// 生成代码运行时验证工具（发布前逻辑核对用）。
//
// 三个阶段：
//  1. 排列组合：枚举步兵/工程合法配置的一维变体与随机全组合，生成 C 源码，
//     做结构性断言（括号平衡、槽位索引、变量名唯一性、表达式标记路径）。
//  2. 编译冒烟：对每个生成的源文件用 gcc -fsyntax-only 做编译级检查
//     （桩头文件 tool/runtime_stub/main.h）。
//  3. 运行时执行：把生成的代码与虚拟时钟 harness 一起编译成可执行文件，
//     用脚本化遥控输入驱动，解码扩展板帧并断言时序/占空比语义。
//
// 用法：cd packages/pieblock_core && dart run tool/verify_runtime.dart
// 依赖：gcc。无 gcc 时阶段 2/3 自动跳过并给出提示。
import 'dart:io';
import 'dart:math' as math;

import 'package:pieblock_core/pieblock_core.dart';

// ---------------------------------------------------------------------------
// 公共构件
// ---------------------------------------------------------------------------

const _gcc = 'gcc';

final _workRoot = Directory.current.uri.resolve('tool/.verify_runtime/');

/// 输入事件：[时刻 ms, 输入名, 值]。输入名为 LX/LY/RX/RY 或数字键。
/// 摇杆轴用 0–3；数字键用 16 + 桩头文件里的 KEY_OFFSET 枚举值，避免与轴撞号。
typedef InputEvent = (int atMs, String input, int value);

int _inputId(String input) => switch (input) {
  'LX' => 0,
  'LY' => 1,
  'RX' => 2,
  'RY' => 3,
  'E' => 16 + 1,
  '↑' => 16 + 2,
  '↓' => 16 + 3,
  '←' => 16 + 4,
  '→' => 16 + 5,
  'A' => 16 + 6,
  'B' => 16 + 7,
  'C' => 16 + 8,
  'D' => 16 + 9,
  'LC' => 16 + 10,
  'RC' => 16 + 11,
  _ => throw ArgumentError('未知输入 $input'),
};

class FrameLine {
  FrameLine(this.ms, this.cmd, this.duties);
  final int ms;
  final int cmd; // 0xAA Init / 0xBB Duty / 0xDD Dir
  final List<int> duties;
}

class PwmLine {
  PwmLine(this.ms, this.channel, this.freq, this.duty);
  final int ms, channel, freq, duty;
}

class RunLog {
  RunLog(this.frames, this.pwm, this.endMs);
  final List<FrameLine> frames;
  final List<PwmLine> pwm;
  final int endMs;

  List<FrameLine> dutyFrames() =>
      frames.where((f) => f.cmd == 0xBB).toList(growable: false);
  List<FrameLine> dirFrames() =>
      frames.where((f) => f.cmd == 0xDD).toList(growable: false);
  List<PwmLine> pwmChannel(int channel) =>
      pwm.where((p) => p.channel == channel).toList(growable: false);
}

/// 用正则把生成代码里的 Uart1TxQuery（轮询等待硬件 TI）替换成直接记帧的实现，
/// 否则脱离硬件会在 while (!TI) 上死等；同时把 `void main(void)` 改名为
/// robot_main 交给 harness 驱动。替换前断言原文逐字节匹配模板。
String prepareSource(String source) {
  final pattern = RegExp(
    r'static void Uart1TxQuery\(uint8_t dat\)\n\{\n(?:[^\n]*\n)*?\}',
  );
  final matches = pattern.allMatches(source).toList();
  if (matches.length != 1) {
    throw StateError('Uart1TxQuery 替换点异常：匹配到 ${matches.length} 处');
  }
  final mainCount = 'void main(void)'.allMatches(source).length;
  if (mainCount != 1) {
    throw StateError('main 定义匹配异常：$mainCount 处');
  }
  return source
      .replaceFirst(
        pattern,
        'static void Uart1TxQuery(uint8_t dat)\n'
        '{\n'
        '    extern void pb_log_byte(uint8_t);\n'
        '    pb_log_byte(dat);\n'
        '}',
      )
      .replaceFirst('void main(void)', 'void robot_main(void)');
}

String harnessSource(int limitMs, List<InputEvent> events) {
  final eventRows = events
      .map((e) => '    {${e.$1}ULL, ${_inputId(e.$2)}, ${e.$3}},')
      .join('\n');
  return '''
#include "main.h"
#include <setjmp.h>
#include <stdio.h>

static unsigned long long g_ms = 0;
static unsigned long long g_limit = ${limitMs}ULL;
static jmp_buf g_bail;

typedef struct { unsigned long long at; int id; int value; } PbEvent;
static const PbEvent g_events[] = {
$eventRows
};
static const int g_eventCount = (int)(sizeof(g_events) / sizeof(g_events[0]));
static int g_eventIdx = 0;
static int g_rocker[4] = {0, 0, 0, 0};
static int g_key[16] = {0};

static void PbPump(void)
{
    while (g_eventIdx < g_eventCount && g_events[g_eventIdx].at <= g_ms) {
        const PbEvent *e = &g_events[g_eventIdx++];
        if (e->id < 4) g_rocker[e->id] = e->value;
        else g_key[e->id - 16] = e->value;
    }
}

void Ms_Delay(uint32_t ms)
{
    g_ms += ms;
    PbPump();
    if (g_ms >= g_limit) longjmp(g_bail, 1);
}

uint8_t NRF24L01_Init(void) { return 1; }
void Board_Init(void) {}
void UART_Init(int id, int rx, int tx, int baud, int tim)
{ (void)id; (void)rx; (void)tx; (void)baud; (void)tim; }
void GPIO_Init(GPIO_Port_enum port, GPIO_Pin_enum pins, int mode)
{ (void)port; (void)pins; (void)mode; }
void GPIO_Write_Bit(GPIO_Port_enum port, GPIO_Pin_enum pin, int value)
{ (void)port; (void)pin; (void)value; }

static uint8_t g_frame[21];
static int g_frameLen = 0;
volatile unsigned char EA = 0, P2INTE = 0;
void pb_log_byte(uint8_t dat)
{
    int i;
    g_frame[g_frameLen++] = dat;
    if (g_frameLen < 21) return;
    g_frameLen = 0;
    if (g_frame[0] != 0xAB || g_frame[1] != 0xBC) return;
    printf("F %llu %u", g_ms, (unsigned)g_frame[2]);
    for (i = 0; i < 8; i++)
        printf(" %u", (unsigned)((g_frame[3 + i * 2] << 8) | g_frame[4 + i * 2]));
    printf("\\n");
}

void PWM_Init(int channel, int frequency, int duty)
{ PbPump(); printf("P %llu %d %d %d\\n", g_ms, channel, frequency, duty); }
void PWM_SET_Frequency(int channel, int frequency, int duty)
{ PbPump(); printf("P %llu %d %d %d\\n", g_ms, channel, frequency, duty); }

uint8_t RcKeyValueRead(int key) { PbPump(); return (uint8_t)(g_key[key] != 0); }
int RcRockerValueRead(int rocker) { PbPump(); return g_rocker[rocker]; }
void nrf_handler(void) {}

int main(void)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    PbPump();
    if (setjmp(g_bail) == 0) robot_main();
    printf("E %llu\\n", g_ms);
    return 0;
}
''';
}

RunLog parseLog(String stdoutText) {
  final frames = <FrameLine>[], pwm = <PwmLine>[];
  var endMs = 0;
  for (final line in stdoutText.split('\n')) {
    if (line.isEmpty) continue;
    final parts = line.trim().split(RegExp(r'\s+'));
    switch (parts[0]) {
      case 'F':
        frames.add(FrameLine(
          int.parse(parts[1]),
          int.parse(parts[2]),
          [for (var i = 0; i < 8; i++) int.parse(parts[3 + i])],
        ));
      case 'P':
        pwm.add(PwmLine(
          int.parse(parts[1]),
          int.parse(parts[2]),
          int.parse(parts[3]),
          int.parse(parts[4]),
        ));
      case 'E':
        endMs = int.parse(parts[1]);
    }
  }
  return RunLog(frames, pwm, endMs);
}

bool hasGcc() =>
    Process.runSync('which', [_gcc]).exitCode == 0 &&
    Process.runSync(_gcc, ['--version']).exitCode == 0;

// ---------------------------------------------------------------------------
// 结构性检查（纯 Dart，无编译器依赖）
// ---------------------------------------------------------------------------

List<String> structuralIssues(String name, String source) {
  final issues = <String>[];
  final pairs = {'{': '}', '(': ')', '[': ']'};
  final stack = <_Tok>[];
  final tokenizer = RegExp(r'[{}\[\]()]|/\*[\s\S]*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|[\s\S]');
  for (final match in tokenizer.allMatches(source)) {
    final token = match.group(0)!;
    final line = source.substring(0, match.start).split('\n').length;
    if (pairs.containsKey(token)) {
      stack.add(_Tok(token, line));
    } else if (pairs.containsValue(token)) {
      if (stack.isEmpty || pairs[stack.last.token] != token) {
        issues.add('$name: 多余的 $token @行$line');
        break;
      }
      stack.removeLast();
    }
  }
  if (stack.isNotEmpty) {
    issues.add('$name: 未闭合的 ${stack.last.token} @行${stack.last.line}');
  }
  // 数组声明 `int dutyOfMotor[8];`/`int mainServoDuty[2];` 之外，索引必须落在范围内。
  for (final match
      in RegExp(r'(?<!int )dutyOfMotor\[(\-?\d+)\]').allMatches(source)) {
    final index = int.parse(match.group(1)!);
    if (index < 0 || index > 7) {
      issues.add('$name: dutyOfMotor[$index] 越界');
    }
  }
  for (final match
      in RegExp(r'(?<!int )mainServoDuty\[(\-?\d+)\]').allMatches(source)) {
    final index = int.parse(match.group(1)!);
    if (index < 0 || index > 1) {
      issues.add('$name: mainServoDuty[$index] 越界');
    }
  }
  // 全局变量声明唯一性（表达式行变量）。
  final declared = <String>{};
  for (final match in RegExp(
    r'^(?:static\s+)?(?:int32_t|float|uint16_t|uint8_t|int)\s+(pbv_\w+)',
    multiLine: true,
  ).allMatches(source)) {
    if (!declared.add(match.group(1)!)) {
      issues.add('$name: 全局变量 ${match.group(1)} 重复声明');
    }
  }
  for (final match in RegExp(r'/\*@expr:([^*]+)\*/').allMatches(source)) {
    final path = match.group(1)!;
    if (!path.startsWith(RegExp(r'modes\.\d+\.actions\.\d+\.expression'))) {
      issues.add('$name: 表达式标记路径异常 $path');
    }
  }
  return issues;
}

class _Tok {
  _Tok(this.token, this.line);
  final String token;
  final int line;
}

// ---------------------------------------------------------------------------
// 配置构件
// ---------------------------------------------------------------------------

ChassisConfig chassis({bool sprint = false, bool turnReversed = false}) =>
    ChassisConfig(
      leftFront: const WheelConfig('P74 P24', Direction.forward),
      leftRear: const WheelConfig('P75 P25', Direction.forward),
      rightFront: const WheelConfig('P76 P26', Direction.reverse),
      rightRear: const WheelConfig('P77 P27', Direction.reverse),
      normalSpeed: 6000,
      sprintSpeed: 9000,
      sprintEnabled: sprint,
      turnReversed: turnReversed,
    );

InfantryConfig infantryBase({
  FeedMode feedMode = FeedMode.visualClosedLoop,
  FrictionMode frictionMode = FrictionMode.brushlessEsc,
  ArrowBehavior arrow = ArrowBehavior.other,
  String? reverseKey,
  bool zero = false,
  bool buzzer = true,
  List<AxisActuator> yaw = const [
    AxisActuator(
      drive: DriveType.servo,
      pin: 'MP74',
      direction: Direction.forward,
      midOffset: 0,
    ),
  ],
  List<AxisActuator> pitch = const [
    AxisActuator(
      drive: DriveType.servo,
      pin: 'MP03',
      direction: Direction.forward,
      midOffset: 0,
    ),
  ],
  ChassisConfig? chassisConfig,
  String frictionKey = 'A',
  String frictionUpKey = 'B',
  String frictionDownKey = 'C',
  String triggerKey = 'E',
  int triggerTimeMs = 250,
  String feederPin = 'P60',
}) => InfantryConfig(
  remote: const RemoteConfig(channel: 36, deadzone: 100),
  chassis: chassisConfig ?? chassis(),
  feederPin: feederPin,
  feederDirection: Direction.forward,
  yawActuators: yaw,
  pitchActuators: pitch,
  arrowBehavior: arrow,
  feedMode: feedMode,
  triggerKey: triggerKey,
  reverseFeedKey: reverseKey,
  triggerSpeed: 3000,
  triggerTimeMs: triggerTimeMs,
  frictionMode: frictionMode,
  frictionKey: frictionKey,
  frictionUpKey: frictionUpKey,
  frictionDownKey: frictionDownKey,
  frictionP64MaxDuty: 800,
  frictionP66MaxDuty: 700,
  frictionLevelStep: 10,
  zeroEnabled: zero,
  buzzerDisabled: !buzzer,
);

EngineerConfig engineerBase({
  bool chassisEnabled = true,
  int modeCount = 1,
  SwitchStrategy? strategy,
  String? switchKey,
  List<String?>? modeKeys,
  List<EngineerModeConfig>? modes,
  Map<String, PinRole>? roles,
  Map<String, int>? servoMids,
  Map<String, int>? frictionMax,
  bool buzzer = true,
  PwmFrequency pwma = PwmFrequency.hz50,
  PwmFrequency pwmb = PwmFrequency.hz10000,
}) {
  final defaultRoles = <String, PinRole>{
    for (final pin in expansionPins)
      pin: switch (pin) {
        'P60' => PinRole.servo,
        'P62' => PinRole.servo,
        'P64' || 'P66' => PinRole.friction,
        _ => PinRole.motor,
      },
  };
  return EngineerConfig(
    remote: const RemoteConfig(channel: 36, deadzone: 100),
    chassis: chassisEnabled
        ? chassis()
        : ChassisConfig.defaults().copyWith(enabled: false),
    pwm: PwmGroupConfig(
      pwma: pwma,
      pwmb: pwmb,
      buzzerDisabled: !buzzer,
      pinRoles: roles ?? defaultRoles,
      servoMids: servoMids ??
          const {'P60': 0, 'P62': 0, 'MP03': 0, 'MP74': 0},
      frictionMaxDuties: frictionMax ?? const {'P64': 800, 'P66': 700},
    ),
    modeCount: modeCount,
    switchStrategy: strategy,
    modeSwitchKey: switchKey,
    modeKeys: modeKeys ?? const [null, null, null, null],
    modes: modes ?? [EngineerModeConfig(preserveChassis: true)],
  );
}

ActionMapping action(
  String? key, {
  String? pin,
  Direction? direction,
  ControlMode? mode,
  num? parameter,
  ActionInputKind inputKind = ActionInputKind.remote,
  ActionOutputKind outputKind = ActionOutputKind.pin,
  String? variable,
  String? expression,
}) => ActionMapping(
  inputKind: inputKind,
  key: key,
  outputKind: outputKind,
  pin: pin,
  variableName: variable,
  expression: expression,
  direction: direction,
  mode: mode,
  parameter: parameter,
);

// ---------------------------------------------------------------------------
// 阶段 1+2：排列组合与编译冒烟
// ---------------------------------------------------------------------------

typedef ConfigVariant = (String, ProjectConfig);

List<(String, ProjectConfig)> infantryVariants() {
  final base = infantryBase();
  final variants = <(String, ProjectConfig)>[('inf-base', base)];
  void add(String name, InfantryConfig config) =>
      variants.add(('inf-$name', config));

  for (final mode in FeedMode.values) {
    add('feed-${mode.name}', infantryBase(feedMode: mode));
  }
  for (final mode in FrictionMode.values) {
    add('friction-${mode.name}', infantryBase(frictionMode: mode));
  }
  for (final arrow in ArrowBehavior.values) {
    add('arrow-${arrow.name}', infantryBase(arrow: arrow));
  }
  add('reverse-key', infantryBase(reverseKey: 'D'));
  add('zero-on', infantryBase(zero: true));
  add('buzzer-off', infantryBase(buzzer: false));
  add('gimbal-empty', infantryBase(yaw: const [], pitch: const []));
  add(
    'gimbal-motor',
    infantryBase(
      frictionMode: FrictionMode.disabled,
      yaw: const [
        AxisActuator(drive: DriveType.motor, pin: 'P62', direction: Direction.forward),
      ],
      pitch: const [
        AxisActuator(drive: DriveType.motor, pin: 'P64', direction: Direction.reverse),
      ],
    ),
  );
  add(
    'gimbal-multi',
    infantryBase(
      yaw: const [
        AxisActuator(drive: DriveType.servo, pin: 'MP74', direction: Direction.forward, midOffset: 10),
        AxisActuator(drive: DriveType.servo, pin: 'P66', direction: Direction.reverse, midOffset: -20),
      ],
      pitch: const [
        AxisActuator(drive: DriveType.servo, pin: 'P64', direction: Direction.forward, midOffset: 5),
      ],
      frictionMode: FrictionMode.disabled,
    ),
  );
  add('chassis-sprint', infantryBase(chassisConfig: chassis(sprint: true)));
  add('chassis-turnrev', infantryBase(chassisConfig: chassis(turnReversed: true)));
  add(
    'chassis-shared',
    infantryBase(
      feederPin: 'P62',
      chassisConfig: const ChassisConfig(
        leftFront: WheelConfig('P60 P61', Direction.forward),
        leftRear: WheelConfig('P60 P61', Direction.forward),
        rightFront: WheelConfig('P74 P24', Direction.reverse),
        rightRear: WheelConfig('P75 P25', Direction.reverse),
        normalSpeed: 6000,
        sprintSpeed: 9000,
      ),
    ),
  );
  add('keys-mixed',
      infantryBase(triggerKey: '↑', frictionKey: '↓', frictionUpKey: '←', frictionDownKey: '→', arrow: ArrowBehavior.other, reverseKey: 'RC'));
  return variants;
}

List<(String, ProjectConfig)> engineerVariants() {
  final variants = <(String, ProjectConfig)>[('eng-base', engineerBase())];
  void add(String name, EngineerConfig config) =>
      variants.add(('eng-$name', config));

  // 每种控制方式 × 输入类型（按键/轴）× 角色的代表组合。
  ActionMapping axisAction(String key, String pin, ControlMode mode,
          Direction? dir, num param) =>
      action(key, pin: pin, direction: dir, mode: mode, parameter: param);
  ActionMapping buttonAction(String key, String pin, ControlMode mode,
          Direction? dir, num param) =>
      action(key, pin: pin, direction: dir, mode: mode, parameter: param);

  // 舵机 + 轴：direct / incremental
  add(
    'servo-axis',
    engineerBase(
      modes: [
        EngineerModeConfig(preserveChassis: true, actions: [
          axisAction('RX', 'P60', ControlMode.direct, Direction.forward, 30),
          axisAction('RY', 'P62', ControlMode.incremental, Direction.reverse, 15),
        ]),
      ],
    ),
  );
  // 舵机 + 按键：direct / single / continuous
  add(
    'servo-button',
    engineerBase(
      modes: [
        EngineerModeConfig(preserveChassis: true, actions: [
          buttonAction('A', 'P60', ControlMode.direct, Direction.forward, 45),
          buttonAction('B', 'P62', ControlMode.single, Direction.forward, 1.25),
          buttonAction('C', 'MP03', ControlMode.continuous, Direction.reverse, 0.5),
        ]),
      ],
    ),
  );
  // 电机 + 轴：speed / accelerate；电机 + 按键：direct
  // 底盘默认占 P74~P77，电机动作放 PWMA 组的 P60/P62（pwma 提到 10000Hz）。
  add(
    'motor-actions',
    engineerBase(
      pwma: PwmFrequency.hz10000,
      roles: {
        for (final pin in expansionPins)
          pin: switch (pin) {
            'P60' || 'P62' => PinRole.motor,
            'P64' || 'P66' => PinRole.unused,
            _ => PinRole.motor,
          },
      },
      modes: [
        EngineerModeConfig(preserveChassis: false, actions: [
          axisAction('RX', 'P60', ControlMode.speed, Direction.forward, 8000),
          axisAction('RY', 'P62', ControlMode.accelerate, Direction.reverse, 2000),
          buttonAction('A', 'P60', ControlMode.direct, Direction.forward, 5000),
        ]),
      ],
    ),
  );
  // 抖动电机
  add(
    'jitter-motor',
    engineerBase(
      roles: {
        for (final pin in expansionPins)
          pin: switch (pin) {
            'P60' => PinRole.jitterMotor,
            'P64' || 'P66' => PinRole.friction,
            'P62' => PinRole.servo,
            _ => PinRole.motor,
          },
      },
      pwma: PwmFrequency.hz10000,
      modes: [
        EngineerModeConfig(preserveChassis: true, actions: [
          axisAction('RX', 'P60', ControlMode.speed, Direction.forward, 4000),
          buttonAction('A', 'P60', ControlMode.direct, Direction.reverse, 3000),
        ]),
      ],
    ),
  );
  // 摩擦轮四种方式
  add(
    'friction-all',
    engineerBase(
      modes: [
        EngineerModeConfig(preserveChassis: true, actions: [
          buttonAction('A', 'P64', ControlMode.frictionToggle, null, 100),
          buttonAction('B', 'P64', ControlMode.frictionStep, Direction.forward, 30),
          buttonAction('C', 'P64', ControlMode.frictionContinuous, Direction.reverse, 10),
          axisAction('RX', 'P64', ControlMode.frictionAxis, null, 20),
        ]),
      ],
    ),
  );
  // 摩擦轮旧控制方式（仅警告）
  add(
    'friction-legacy',
    engineerBase(
      modes: [
        EngineerModeConfig(preserveChassis: true, actions: [
          axisAction('RX', 'P64', ControlMode.speed, Direction.forward, 8000),
        ]),
      ],
    ),
  );
  // 模式数量 × 切换策略
  for (final count in [1, 2, 3, 4]) {
    for (final strategy in SwitchStrategy.values) {
      final modes = [
        for (var i = 0; i < count; i++)
          EngineerModeConfig(
            preserveChassis: i == 0,
            actions: [
              // E 不在 direct 策略的模式键（A–D）里，也不与 cycle 的 E 冲突：
              // cycle 策略下 E 是切换键，动作键改用 LC 避让。
              buttonAction(
                strategy == SwitchStrategy.cycle ? 'LC' : 'E',
                'P60',
                ControlMode.direct,
                Direction.forward,
                10 * (i + 1),
              ),
            ],
          ),
      ];
      add(
        'modes-$count-${strategy.name}',
        engineerBase(
          modeCount: count,
          strategy: strategy,
          switchKey: strategy == SwitchStrategy.cycle ? 'E' : null,
          modeKeys: strategy == SwitchStrategy.direct
              ? ['A', 'B', 'C', 'D'].take(count).toList()
              : null,
          modes: modes,
        ),
      );
    }
  }
  // 底盘关闭 + 释放引脚动作
  add(
    'chassis-off',
    engineerBase(
      chassisEnabled: false,
      roles: {
        for (final pin in expansionPins)
          pin: pin == 'P60' || pin == 'P62'
              ? PinRole.servo
              : EngineerPinCapabilities.frictionPins.contains(pin)
              ? PinRole.friction
              : PinRole.motor,
      },
      modes: [
        EngineerModeConfig(actions: [
          buttonAction('A', 'P74', ControlMode.direct, Direction.forward, 6000),
          axisAction('RX', 'P75', ControlMode.speed, Direction.forward, 7000),
        ]),
      ],
    ),
  );
  // 变量与表达式
  add(
    'expressions',
    engineerBase(
      modeCount: 2,
      strategy: SwitchStrategy.cycle,
      switchKey: 'E',
      modes: [
        // 变量行也占用 LX/LY，保留底盘的模式不允许，因此两模式都不保留。
        EngineerModeConfig(preserveChassis: false, actions: [
          action('LX', outputKind: ActionOutputKind.integer, variable: 'speed'),
          action(null,
              inputKind: ActionInputKind.unspecified,
              outputKind: ActionOutputKind.pin,
              pin: 'P60',
              expression: 'speed * 2'),
          action(null,
              inputKind: ActionInputKind.unspecified,
              outputKind: ActionOutputKind.rational,
              variable: 'angle',
              expression: 'min(atan2(RY, 2047) * 57.0, 30.0)'),
          action(null,
              inputKind: ActionInputKind.unspecified,
              outputKind: ActionOutputKind.pin,
              pin: 'MP03',
              expression: 'angle - 10'),
        ]),
        EngineerModeConfig(preserveChassis: false, actions: [
          action(null,
              inputKind: ActionInputKind.unspecified,
              outputKind: ActionOutputKind.integer,
              variable: 'speed',
              expression: 'abs(LY) % 100'),
          action(null,
              inputKind: ActionInputKind.unspecified,
              outputKind: ActionOutputKind.pin,
              pin: 'P62',
              expression: 'sign(speed) * 3000 + 100'),
        ]),
      ],
    ),
  );
  add('buzzer-off', engineerBase(buzzer: false));
  add('servo-mids', engineerBase(servoMids: const {'P60': 30, 'P62': -45, 'MP03': 90, 'MP74': -90}));
  return variants;
}

/// 随机全组合采样：把一维变体的维度做随机组合，覆盖交叉情况。
/// 随机配置本身必须合法——这里刻意按校验器规则构造，保证采样到的是
/// 「允许的配置组合」而不是非法输入。
List<(String, ProjectConfig)> randomSamples(int count, int seed) {
  final random = math.Random(seed);
  final samples = <(String, ProjectConfig)>[];
  for (var i = 0; i < count; i++) {
    if (random.nextBool()) {
      // 步兵随机
      final friction = random.nextBool();
      final gimbalMotor = !friction && random.nextBool();
      final config = infantryBase(
        feedMode: random.nextBool() ? FeedMode.visualClosedLoop : FeedMode.blockingOpenLoop,
        frictionMode: friction ? FrictionMode.brushlessEsc : FrictionMode.disabled,
        arrow: ArrowBehavior.values[random.nextInt(ArrowBehavior.values.length)],
        reverseKey: random.nextBool() ? 'D' : null,
        zero: random.nextBool(),
        buzzer: random.nextBool(),
        triggerTimeMs: 100 + random.nextInt(400),
        yaw: gimbalMotor
            ? const [
                AxisActuator(drive: DriveType.motor, pin: 'P62', direction: Direction.forward),
              ]
            : [
                const AxisActuator(drive: DriveType.servo, pin: 'MP74', direction: Direction.forward, midOffset: 0),
                if (!friction && random.nextBool())
                  const AxisActuator(drive: DriveType.servo, pin: 'P66', direction: Direction.reverse, midOffset: 10),
              ],
        pitch: gimbalMotor
            ? const [
                AxisActuator(drive: DriveType.motor, pin: 'P64', direction: Direction.reverse),
              ]
            : (random.nextBool() && !friction
                ? const [
                    AxisActuator(drive: DriveType.servo, pin: 'P64', direction: Direction.forward, midOffset: -5),
                  ]
                : const []),
        chassisConfig: random.nextBool()
            ? chassis(sprint: random.nextBool(), turnReversed: random.nextBool())
            : null,
      );
      samples.add(('inf-rand$i', config));
    } else {
      // 工程随机：随机模式数、角色矩阵、动作行
      final modeCount = 1 + random.nextInt(4);
      final chassisEnabled = random.nextBool();
      final chassisUsed = chassisEnabled
          ? {'P74', 'P75', 'P76', 'P77'}
          : <String>{};
      final frictionControl = random.nextBool();
      final roles = <String, PinRole>{
        for (final pin in expansionPins)
          pin: switch (pin) {
            'P64' || 'P66' when frictionControl => PinRole.friction,
            _ when chassisUsed.contains(pin) => PinRole.motor,
            _ => PinRole.values[random.nextInt(PinRole.values.length)],
          },
      };
      // 角色必须落在硬件能力内；底盘脚强制电机。
      final fixedRoles = <String, PinRole>{
        for (final pin in expansionPins)
          pin: chassisUsed.contains(pin)
              ? PinRole.motor
              : EngineerPinCapabilities.allowedRoles(pin).contains(roles[pin])
              ? roles[pin]!
              : EngineerPinCapabilities.allowedRoles(pin).first,
      };
      final servoMids = <String, int>{
        for (final pin in fixedRoles.keys)
          if (fixedRoles[pin] == PinRole.servo) pin: 0,
        'MP03': 0,
        'MP74': 0,
      };
      final strategy = SwitchStrategy.values[random.nextInt(2)];
      final modes = <EngineerModeConfig>[];
      for (var m = 0; m < modeCount; m++) {
        final preserve = chassisEnabled && random.nextBool();
        final actions = <ActionMapping>[];
        // 模式切换键（cycle 用 E，direct 用 A-D）不能被动作占用。
        final switchKeys = modeCount > 1
            ? (strategy == SwitchStrategy.cycle
                  ? <String>{'E'}
                  : <String>{'A', 'B', 'C', 'D'})
            : <String>{};
        final freeKeys = digitalRemoteKeys
            .where((k) => !switchKeys.contains(k))
            .toList(growable: false);
        for (var a = 0; a < 1 + random.nextInt(3); a++) {
          // 动作不能落在底盘脚，也不能用保留模式下的 LX/LY 或切换键
          final candidates = expansionPins
              .where((pin) => !chassisUsed.contains(pin))
              .toList();
          final pin = candidates[random.nextInt(candidates.length)];
          final role = fixedRoles[pin]!;
          final axis = random.nextBool();
          final input = axis
              ? axisRemoteInputs[random.nextInt(4)]
              : freeKeys[random.nextInt(freeKeys.length)];
          if (preserve && (input == 'LX' || input == 'LY')) continue;
          final ControlMode mode;
          if (role == PinRole.friction) {
            if (!frictionControl) {
              mode = axis ? ControlMode.speed : ControlMode.direct;
            } else {
              mode = axis
                  ? ControlMode.frictionAxis
                  : ControlMode.frictionToggle;
            }
          } else if (role == PinRole.servo) {
            // 注意 ControlMode 枚举顺序是 direct/incremental/speed/...，
            // 按键只允许 direct/single/continuous，轴只允许 direct/incremental。
            mode = axis
                ? (random.nextBool() ? ControlMode.direct : ControlMode.incremental)
                : [ControlMode.direct, ControlMode.single, ControlMode.continuous][
                    random.nextInt(3)];
          } else if (role == PinRole.motor || role == PinRole.jitterMotor) {
            mode = axis
                ? (random.nextBool() ? ControlMode.speed : ControlMode.accelerate)
                : ControlMode.direct;
          } else {
            continue;
          }
          final frictionMode = mode == ControlMode.frictionToggle ||
              mode == ControlMode.frictionAxis;
          final num parameter = switch (mode) {
            ControlMode.direct =>
              role == PinRole.servo ? random.nextInt(91) : random.nextInt(10001),
            ControlMode.incremental => random.nextInt(91),
            ControlMode.speed ||
            ControlMode.accelerate => random.nextInt(10001),
            ControlMode.single ||
            ControlMode.continuous => (random.nextInt(150) + 50) / 100.0,
            _ => 1 + random.nextInt(100), // 摩擦轮四种
          };
          actions.add(action(input,
              pin: pin,
              direction: frictionMode ? null : Direction.values[random.nextInt(2)],
              mode: mode,
              parameter: parameter));
        }
        modes.add(EngineerModeConfig(preserveChassis: preserve, actions: actions));
      }
      // PWMA 频率：摩擦轮控制必须 50Hz；否则按 P60~P66 的角色需要取多数。
      final pwmaPins = ['P60', 'P62', 'P64', 'P66'];
      final needs50 = frictionControl ||
          pwmaPins.any((p) => fixedRoles[p] == PinRole.servo);
      final needs10000 = pwmaPins.any(
        (p) =>
            fixedRoles[p] == PinRole.motor || fixedRoles[p] == PinRole.jitterMotor,
      );
      final pwma = needs50 || !needs10000
          ? PwmFrequency.hz50
          : PwmFrequency.hz10000;
      samples.add((
        'eng-rand$i',
        engineerBase(
          chassisEnabled: chassisEnabled,
          modeCount: modeCount,
          strategy: modeCount > 1 ? strategy : null,
          switchKey: modeCount > 1 && strategy == SwitchStrategy.cycle ? 'E' : null,
          modeKeys: modeCount > 1 && strategy == SwitchStrategy.direct
              ? ['A', 'B', 'C', 'D'].take(modeCount).toList()
              : null,
          roles: fixedRoles,
          servoMids: servoMids,
          modes: modes,
          pwma: pwma,
        ),
      ));
    }
  }
  return samples;
}

// ---------------------------------------------------------------------------
// 阶段 3：运行时执行场景
// ---------------------------------------------------------------------------

class Scenario {
  Scenario(this.name, this.config, this.limitMs, this.events,
      this.assertions);
  final String name;
  final ProjectConfig config;
  final int limitMs;
  final List<InputEvent> events;
  final List<String> Function(RunLog log) assertions;
}

/// 摩擦轮斜坡不变量断言（步兵与工程共用）：激活 1s@500、±1/周期斜坡、
/// 0~500 区间跳变、上限保护。
List<String> _frictionInvariants(RunLog log, int p64Max, int p66Max) {
  final failures = <String>[];
  final duties = log
      .dutyFrames()
      .map((f) => (f.ms, f.duties[2], f.duties[3]))
      .toList();
  if (duties.isEmpty) {
    return ['没有占空比帧'];
  }
  for (final (ms, p64, p66) in duties) {
    for (final (value, max, label) in [(p64, p64Max, 'P64'), (p66, p66Max, 'P66')]) {
      if (value != 0 && (value < 500 || value > max)) {
        failures.add('$label duty=$value 超出 {0}∪[500,$max] @$ms ms');
      }
    }
  }
  // 相邻帧变化量：斜坡 ±1/周期，只允许 0→500（激活）与 500→0（停机）跳变
  for (var i = 1; i < duties.length; i++) {
    final prev = duties[i - 1], cur = duties[i];
    final values = [
      (from: prev.$2, to: cur.$2, label: 'P64'),
      (from: prev.$3, to: cur.$3, label: 'P66'),
    ];
    for (final v in values) {
      if ((v.to - v.from).abs() > 1) {
        final allowedJump =
            (v.from == 0 && v.to == 500) || (v.from == 500 && v.to == 0);
        if (!allowedJump) {
          failures.add('${v.label} duty ${v.from}→${v.to} 跳变 @${cur.$1}ms');
        }
      }
    }
  }
  return failures;
}

List<Scenario> scenarios() {
  final scenarios = <Scenario>[];

  // --- 步兵：摩擦轮启停/斜坡/档位 ---
  scenarios.add(Scenario(
    'inf-friction-ramp',
    infantryBase(),
    32000,
    [
      (2000, 'A', 1), (2120, 'A', 0), // 开：激活 1s@500 后斜坡到 800/700
      (12000, 'A', 1), (12120, 'A', 0), // 关：斜坡降到 500 后跳 0
      (20000, 'A', 1), (20120, 'A', 0), // 再开
      (25000, 'C', 1), (25120, 'C', 0), // 减档 -10 → 90 → 目标 770/670
    ],
    (log) {
      final failures = _frictionInvariants(log, 800, 700);
      final duty = log.dutyFrames();
      // 开启后 500 激活保持约 1s
      final firstOn = duty
          .where((f) => f.ms >= 2000 && f.ms < 12000 && f.duties[2] == 500)
          .toList();
      if (firstOn.isEmpty) {
        failures.add('没有观察到 500 启动占空比激活');
      } else {
        final span = firstOn.last.ms - firstOn.first.ms;
        if (span < 950) failures.add('激活保持仅 ${span}ms < 950ms');
      }
      // 第一段到达各自上限
      final seg1 = duty.where((f) => f.ms >= 2000 && f.ms < 11000).toList();
      final max64 = seg1.map((f) => f.duties[2]).reduce(math.max);
      final max66 = seg1.map((f) => f.duties[3]).reduce(math.max);
      if (max64 != 800) failures.add('P64 未到达 800（max=$max64）');
      if (max66 != 700) failures.add('P66 未到达 700（max=$max66）');
      // 关闭斜坡：800→500 每 20ms -1（约 6s），之后跳 0；19000 前必须停机
      final offWindow = duty.where((f) => f.ms > 19000 && f.ms < 19500);
      if (offWindow.any((f) => f.duties[2] != 0)) {
        failures.add('关闭后 P64 未停机');
      }
      // 再开后 C 减档：目标 90% → P64 770 / P66 680
      final settled = duty.where((f) => f.ms >= 29000).toList();
      if (settled.isEmpty || settled.last.duties[2] != 770) {
        failures.add('减档后 P64 目标 ${settled.isEmpty ? "?" : settled.last.duties[2]} ≠ 770');
      }
      if (settled.isEmpty || settled.last.duties[3] != 680) {
        failures.add('减档后 P66 目标 ${settled.isEmpty ? "?" : settled.last.duties[3]} ≠ 680');
      }
      return failures;
    },
  ));

  // --- 步兵：阻塞单发 ---
  scenarios.add(Scenario(
    'inf-feed-blocking',
    infantryBase(
      feedMode: FeedMode.blockingOpenLoop,
      frictionMode: FrictionMode.disabled,
      triggerTimeMs: 250,
    ),
    12000,
    [
      (3000, 'E', 1), (3080, 'E', 0),
      (6000, 'E', 1), (6080, 'E', 0),
    ],
    (log) {
      final failures = <String>[];
      final duty = log.dutyFrames();
      final dir = log.dirFrames();
      final pulses = duty
          .where((f) => f.duties[0] == 3000)
          .map((f) => f.ms)
          .toList();
      if (pulses.length < 2) {
        failures.add('阻塞单发没有发出占空比 3000 的帧（${pulses.length} 次）');
      }
      for (final pulse in pulses) {
        // 脉冲后 ~250ms 内底盘帧停摆（阻塞）
        final during = duty.where((f) => f.ms > pulse && f.ms < pulse + 240);
        if (during.isNotEmpty) {
          failures.add('阻塞期间仍在发帧 @${during.first.ms}ms');
        }
        final after = duty.where((f) => f.ms >= pulse + 240).toList();
        if (after.isEmpty || after.first.duties[0] != 0) {
          failures.add('单发结束后未归零');
        } else {
          // 归零前必须有 Dir 帧先于 Duty 帧（生成代码的补偿发送）
          final dirBefore = dir.where((d) => d.ms > pulse && d.ms <= after.first.ms);
          if (dirBefore.isEmpty) {
            failures.add('脉冲期间没有补发方向帧');
          }
        }
      }
      return failures;
    },
  ));

  // --- 步兵：视觉闭环 + 反向拨弹 ---
  scenarios.add(Scenario(
    'inf-feed-reverse',
    infantryBase(feedMode: FeedMode.visualClosedLoop, reverseKey: 'D', frictionMode: FrictionMode.disabled),
    12000,
    [
      (3000, 'D', 1), (5000, 'D', 0),
      (6000, 'E', 1), (7000, 'E', 0),
    ],
    (log) {
      final failures = <String>[];
      final duty = log.dutyFrames();
      final dir = log.dirFrames();
      final reverseWindow = duty.where((f) => f.ms >= 3200 && f.ms < 4900).toList();
      if (reverseWindow.isEmpty || reverseWindow.any((f) => f.duties[0] != 3000)) {
        failures.add('反向拨弹期间占空比异常');
      }
      final reverseDir = dir.where((f) => f.ms >= 3200 && f.ms < 4900);
      if (reverseDir.isEmpty || reverseDir.any((d) => d.duties[0] != 0)) {
        failures.add('反向拨弹期间方向位应为 0');
      }
      final trigWindow = duty.where((f) => f.ms >= 6200 && f.ms < 6900).toList();
      if (trigWindow.isEmpty || trigWindow.any((f) => f.duties[0] != 3000)) {
        failures.add('扳机期间占空比异常');
      }
      final trigDir = dir.where((f) => f.ms >= 6200 && f.ms < 6900);
      if (trigDir.isEmpty || trigDir.any((d) => d.duties[0] != 1)) {
        failures.add('扳机期间方向位应为 1');
      }
      final idle = duty.where((f) => f.ms >= 7200);
      if (idle.any((f) => f.duties[0] != 0)) {
        failures.add('松开后未归零');
      }
      return failures;
    },
  ));

  // --- 步兵：底盘混控 + 冲刺 + 转向 ---
  // 生成公式：左侧正转 `base - turn`、左侧反转 `-base + turn`、
  // 右侧正转 `-base - turn`、右侧反转 `base + turn`。
  scenarios.add(Scenario(
    'inf-chassis',
    infantryBase(
      frictionMode: FrictionMode.disabled,
      chassisConfig: chassis(sprint: true),
    ),
    15000,
    [
      (3000, 'LY', -2047), // 前进
      (6000, 'LX', 1024), // 前进 + 转向
      (9000, 'LC', 1), // 冲刺（左摇杆按下）
      (11000, 'LC', 0), (11000, 'LX', 0), (11000, 'LY', 0),
    ],
    (log) {
      final failures = <String>[];
      final duty = log.dutyFrames();
      final stages = <(int, int, int, int)>[
        (3200, 5900, 6000, 0),
        (6200, 8900, 6000, 1024),
        (9200, 10900, 9000, 1024),
      ];
      for (final (from, to, speed, lx) in stages) {
        final window = duty
            .where((f) => f.ms >= from && f.ms < to)
            .toList();
        if (window.isEmpty) {
          failures.add('$from-$to ms 无帧');
          continue;
        }
        final base = speed; // LY 满杆
        final turn = -(lx * speed) ~/ 2047;
        final expect = [
          base - turn, // 左前（正转）
          base - turn, // 左后（正转）
          base + turn, // 右前（反转）
          base + turn, // 右后（反转）
        ].map((v) => v.abs()).toList();
        // 取该阶段最后一帧对比
        final last = window.last;
        final actual = [last.duties[4], last.duties[5], last.duties[6], last.duties[7]];
        for (var i = 0; i < 4; i++) {
          if ((actual[i] - expect[i]).abs() > 3) {
            failures.add('$from-$to ms 轮$i 占空比 ${actual[i]} ≠ ${expect[i]}');
          }
        }
      }
      // 冲刺（LC）应把速度从 6000 提到 9000：对比阶段 2/3 的左前轮
      final s2 = duty.where((f) => f.ms >= 6200 && f.ms < 8900).toList();
      final s3 = duty.where((f) => f.ms >= 9200 && f.ms < 10900).toList();
      if (s2.isNotEmpty && s3.isNotEmpty && s3.last.duties[4] <= s2.last.duties[4]) {
        failures.add('LC 冲刺未提升速度');
      }
      return failures;
    },
  ));

  // --- 步兵：云台舵机行程与归零 ---
  scenarios.add(Scenario(
    'inf-gimbal',
    infantryBase(zero: true, frictionMode: FrictionMode.disabled),
    15000,
    [
      (3000, 'RX', 2047), // yaw 右打满 → yawDuty 上行到 1250
      (7000, 'RX', -2047), // 下行到 250
      (11000, 'RX', 0), (11000, 'RC', 1), // 归零
      (11500, 'RC', 0),
    ],
    (log) {
      final failures = <String>[];
      final yaw = log.pwmChannel(202).where((p) => p.ms > 2500).toList();
      if (yaw.isEmpty) {
        failures.add('没有主控板舵机 PWM 输出');
        return failures;
      }
      final maxYaw = yaw.map((p) => p.duty).reduce(math.max);
      final minYaw = yaw.map((p) => p.duty).reduce(math.min);
      if (maxYaw != 1250) failures.add('yaw 未到 1250（$maxYaw）');
      if (minYaw != 250) failures.add('yaw 未到 250（$minYaw）');
      final zeroed = yaw.where((p) => p.ms > 11200);
      if (zeroed.isEmpty || zeroed.last.duty != 750) {
        failures.add('归零后未回到 750');
      }
      // pitch 不动
      final pitch = log.pwmChannel(201).where((p) => p.ms > 2500);
      if (pitch.any((p) => p.duty != 750)) failures.add('pitch 不应动作');
      return failures;
    },
  ));

  // --- 步兵：方向键移动/冲刺 ---
  scenarios.add(Scenario(
    'inf-arrow-sprint',
    infantryBase(
      arrow: ArrowBehavior.sprint,
      frictionMode: FrictionMode.disabled,
    ),
    12000,
    [
      (3000, '↑', 1), (5000, '↑', 0),
    ],
    (log) {
      final failures = <String>[];
      final duty = log.dutyFrames();
      final window = duty.where((f) => f.ms >= 3200 && f.ms < 4900).toList();
      if (window.isEmpty) {
        failures.add('方向键期间无帧');
      } else {
        final last = window.last;
        // 冲刺：ultraSpeed=9000 满杆前进 → 左轮 9000、右轮 -9000（方向位区分）
        if (last.duties[4] != 9000 || last.duties[6] != 9000) {
          failures.add('冲刺速度未生效：duty=${last.duties[4]}/${last.duties[6]}');
        }
      }
      return failures;
    },
  ));

  // --- 工程：摩擦轮启停 + 单次降档 ---
  scenarios.add(Scenario(
    'eng-friction',
    engineerBase(
      modes: [
        EngineerModeConfig(preserveChassis: true, actions: [
          action('A', pin: 'P64', mode: ControlMode.frictionToggle, parameter: 100),
          action('B', pin: 'P64', mode: ControlMode.frictionStep, direction: Direction.reverse, parameter: 30),
        ]),
      ],
    ),
    30000,
    [
      (2000, 'A', 1), (2120, 'A', 0), // 开 → 油门 100
      (14000, 'B', 1), (14120, 'B', 0), // 降 30 → 70（目标 710，约 1.8s 斜坡到位）
      (16000, 'B', 1), (16120, 'B', 0), // 再降 30 → 40（目标 620，约 1.8s 斜坡到位）
      (22000, 'A', 1), (22120, 'A', 0), // 关
    ],
    (log) {
      final failures = _frictionInvariants(log, 800, 700);
      final duty = log.dutyFrames();
      final max64 = duty.map((f) => f.duties[2]).reduce(math.max);
      final max66 = duty.map((f) => f.duties[3]).reduce(math.max);
      if (max64 != 800) failures.add('P64 未到 800（$max64）');
      if (max66 != 700) failures.add('P66 未到 700（$max66）');
      // B 两次后目标 40% → 500+40*3=620（17900ms 左右斜坡到位）
      final settled = duty.where((f) => f.ms > 18500 && f.ms < 19000).toList();
      if (settled.isEmpty || settled.last.duties[2] != 620) {
        failures.add('两次降档后目标占空比 ${settled.isEmpty ? "?" : settled.last.duties[2]} ≠ 620');
      }
      final off = duty.where((f) => f.ms > 26000);
      if (off.any((f) => f.duties[2] != 0)) failures.add('关闭后未停机');
      return failures;
    },
  ));

  // --- 工程：模式切换后未保留底盘的占空比残留（安全隐患探针） ---
  scenarios.add(Scenario(
    'eng-chassis-residual',
    engineerBase(
      modeCount: 2,
      strategy: SwitchStrategy.cycle,
      switchKey: 'E',
      modes: [
        EngineerModeConfig(preserveChassis: true, actions: [
          action('A', pin: 'P60', mode: ControlMode.direct, direction: Direction.forward, parameter: 45),
        ]),
        EngineerModeConfig(preserveChassis: false, actions: const []),
      ],
    ),
    15000,
    [
      (3000, 'LY', -2047), // 前进
      (6000, 'E', 1), (6120, 'E', 0), // 切到模式 2（不保留底盘）
    ],
    (log) {
      final failures = <String>[];
      final duty = log.dutyFrames();
      final before = duty.where((f) => f.ms >= 3200 && f.ms < 5900).toList();
      if (before.isEmpty || before.last.duties[4] != 6000) {
        failures.add('切换前底盘占空比异常');
      }
      final after = duty.where((f) => f.ms > 9000).toList();
      if (after.isEmpty) {
        failures.add('切换后无帧');
      } else if (after.any((f) => f.duties[4] != 0)) {
        failures.add(
          '【残留占空比】切到不保留底盘的模式后底盘仍在输出 '
          '${after.first.duties[4]}（设计要求归零）',
        );
      }
      return failures;
    },
  ));

  // --- 工程：电机增速无钳位（溢出探针） ---
  scenarios.add(Scenario(
    'eng-motor-accelerate',
    engineerBase(
      chassisEnabled: false,
      pwma: PwmFrequency.hz10000,
      roles: {
        for (final pin in expansionPins)
          pin: (pin == 'P64' || pin == 'P66') ? PinRole.unused : PinRole.motor,
      },
      modes: [
        EngineerModeConfig(actions: [
          action('LX', pin: 'P60', mode: ControlMode.accelerate, direction: Direction.forward, parameter: 10000),
        ]),
      ],
    ),
    12000,
    [
      (3000, 'LX', 2047),
      (6000, 'LX', 0),
    ],
    (log) {
      final failures = <String>[];
      final duty = log.dutyFrames().where((f) => f.ms > 3200);
      final maxDuty = duty.isEmpty ? 0 : duty.map((f) => f.duties[0]).reduce(math.max);
      if (maxDuty > 10000) {
        failures.add('【增速溢出】占空比 $maxDuty > 10000，无钳位累加'
            '（目标机 int 为 16 位，持续打杆会回绕换向）');
      }
      return failures;
    },
  ));

  // --- 工程：舵机增量 + 单次（含小数余量进位） ---
  scenarios.add(Scenario(
    'eng-servo',
    engineerBase(
      modes: [
        EngineerModeConfig(preserveChassis: true, actions: [
          action('RX', pin: 'P60', mode: ControlMode.incremental, direction: Direction.forward, parameter: 30),
          action('B', pin: 'P62', mode: ControlMode.single, direction: Direction.forward, parameter: 1.25),
        ]),
      ],
    ),
    20000,
    [
      (3000, 'RX', 2047), (5000, 'RX', -2047), (9000, 'RX', 0),
      (11000, 'B', 1), (11200, 'B', 0),
      (12000, 'B', 1), (12200, 'B', 0),
      (13000, 'B', 1), (13200, 'B', 0),
    ],
    (log) {
      final failures = <String>[];
      final duty = log.dutyFrames();
      final p60 = duty.map((f) => (f.ms, f.duties[0])).toList();
      final maxP60 = p60.map((e) => e.$2).reduce(math.max);
      final minP60 = p60.map((e) => e.$2).reduce(math.min);
      if (maxP60 != 1250) failures.add('增量上行未钳位 1250（$maxP60）');
      if (minP60 != 250) failures.add('增量下行未钳位 250（$minP60）');
      // 单次灵敏度 1.25°：3 次共 20.83 duty → 整数累进 6+7+7=20
      final before = duty.lastWhere((f) => f.ms < 11000).duties[1];
      final after = duty.lastWhere((f) => f.ms > 13300).duties[1];
      if (after - before != 20) {
        failures.add('单次 1.25°×3 的余量进位 ${after - before} ≠ 20');
      }
      return failures;
    },
  ));

  // --- 工程：表达式行 ---
  scenarios.add(Scenario(
    'eng-expression',
    engineerBase(
      chassisEnabled: false,
      pwma: PwmFrequency.hz10000,
      roles: {
        for (final pin in expansionPins)
          pin: (pin == 'P64' || pin == 'P66') ? PinRole.unused : PinRole.motor,
      },
      modes: [
        EngineerModeConfig(actions: [
          action('LX', outputKind: ActionOutputKind.integer, variable: 'speed'),
          action(null,
              inputKind: ActionInputKind.unspecified,
              outputKind: ActionOutputKind.pin,
              pin: 'P60',
              expression: 'speed * 2'),
          action(null,
              inputKind: ActionInputKind.unspecified,
              outputKind: ActionOutputKind.pin,
              pin: 'P62',
              expression: 'min(LY, 3000)'),
        ]),
      ],
    ),
    12000,
    [
      (3000, 'LX', 1024), (3000, 'LY', 4000),
      (6000, 'LX', -2047), (6000, 'LY', 1000),
    ],
    (log) {
      final failures = <String>[];
      final duty = log.dutyFrames();
      final s1 = duty.where((f) => f.ms >= 3200 && f.ms < 5900).toList();
      if (s1.isEmpty || s1.last.duties[0] != 2048) {
        failures.add('表达式 speed*2 输出 ${s1.isEmpty ? "?" : s1.last.duties[0]} ≠ 2048');
      }
      if (s1.isEmpty || s1.last.duties[1] != 3000) {
        failures.add('表达式 min(LY,3000) 未钳位 3000');
      }
      final s2 = duty.where((f) => f.ms >= 6200).toList();
      if (s2.isEmpty || s2.last.duties[0] != 4094) {
        failures.add('表达式 speed*2 负向 ${s2.isEmpty ? "?" : s2.last.duties[0]} ≠ 4094');
      }
      if (s2.isEmpty || s2.last.duties[1] != 1000) {
        failures.add('表达式 min(LY,3000) 正常路径 ${s2.isEmpty ? "?" : s2.last.duties[1]} ≠ 1000');
      }
      return failures;
    },
  ));

  // --- 工程：一一对应切换 + 未映射电机归零 ---
  scenarios.add(Scenario(
    'eng-mode-direct',
    engineerBase(
      modeCount: 2,
      strategy: SwitchStrategy.direct,
      modeKeys: ['A', 'B'],
      modes: [
        EngineerModeConfig(preserveChassis: true, actions: [
          action('C', pin: 'P60', mode: ControlMode.direct, direction: Direction.forward, parameter: 80),
        ]),
        EngineerModeConfig(preserveChassis: true, actions: const []),
      ],
    ),
    15000,
    [
      (3000, 'C', 1), // 模式 1 按住 → 舵机 80° → duty 1194
      (6000, 'C', 0), (6000, 'B', 1), (6120, 'B', 0), // 切模式 2：未映射电机归零
    ],
    (log) {
      final failures = <String>[];
      final duty = log.dutyFrames();
      final on = duty.where((f) => f.ms >= 3200 && f.ms < 5900).toList();
      if (on.isEmpty || on.any((f) => f.duties[0] != 1194)) {
        failures.add('模式 1 期间占空比异常（80° → 1194）');
      }
      final off = duty.where((f) => f.ms > 8500).toList();
      // P60 是舵机角色：切到未映射模式时按设计（R7）保持最后位置 1194，
      // 电机/摩擦轮才归零。这里同时验证「舵机保持」这一设计行为。
      if (off.isEmpty) {
        failures.add('切换后无帧');
      } else if (off.any((f) => f.duties[0] != 1194)) {
        failures.add('切换后舵机应保持 1194（得到 ${off.first.duties[0]}）');
      }
      return failures;
    },
  ));

  return scenarios;
}

// ---------------------------------------------------------------------------
// 主流程
// ---------------------------------------------------------------------------

/// 验证工作目录下的子目录（创建并返回），供 CLI 与 dart test 复用。
Future<Directory> verifyWorkRoot(String sub) async {
  final dir = Directory(_workRoot.toFilePath() + sub);
  await dir.create(recursive: true);
  return dir;
}

/// 桩头文件目录（gcc -I 用）。
String stubIncludeDir() =>
    Directory.current.uri.resolve('tool/runtime_stub/').toFilePath();

/// 单个场景的执行结果。
class ScenarioSummary {
  ScenarioSummary(this.failures, this.dutyFrames, this.endMs);
  final List<String> failures;
  final int dutyFrames;
  final int endMs;
}

/// 编译并执行一个场景：生成 → gcc 编译 → 虚拟时钟驱动 → 断言。
/// [buildDir] 为编译产物目录（见 [verifyWorkRoot]）。
Future<ScenarioSummary> runScenario(
  Scenario scenario, [
  Directory? buildDir,
]) async {
  final dir = buildDir ?? await verifyWorkRoot('bin/');
  final validation = ProjectValidator.validate(scenario.config)
      .where((i) => i.severity == IssueSeverity.error)
      .toList();
  if (validation.isNotEmpty) {
    return ScenarioSummary(
      ['场景配置非法：${validation.first.message}'],
      0,
      0,
    );
  }
  final source = CodeGenerator.generate(scenario.config);
  final tag = scenario.name;
  final genFile = File('${dir.path}$tag-gen.c');
  final harnessFile = File('${dir.path}$tag-harness.c');
  await genFile.writeAsString(prepareSource(source));
  await harnessFile.writeAsString(harnessSource(scenario.limitMs, scenario.events));
  final exe = '${dir.path}$tag';
  final compile = Process.runSync(_gcc, [
    '-std=c99',
    '-O0',
    '-w',
    '-I',
    stubIncludeDir(),
    genFile.path,
    harnessFile.path,
    '-lm',
    '-o',
    exe,
  ]);
  if (compile.exitCode != 0) {
    return ScenarioSummary(['编译失败：${compile.stderr}'], 0, 0);
  }
  final run = Process.runSync(exe, []);
  if (run.exitCode != 0) {
    return ScenarioSummary(
      ['运行退出码 ${run.exitCode}：${run.stderr}'],
      0,
      0,
    );
  }
  final log = parseLog(run.stdout as String);
  return ScenarioSummary(
    scenario.assertions(log),
    log.dutyFrames().length,
    log.endMs,
  );
}

Future<int> main(List<String> args) async {
  final onlyStructural = args.contains('--structural');
  final gccAvailable = hasGcc();
  if (!gccAvailable && !onlyStructural) {
    stderr.writeln('警告：未找到 gcc，跳过编译与执行阶段');
  }
  await Directory(_workRoot.toFilePath()).create(recursive: true);

  var failed = 0;
  final variants = [
    ...infantryVariants(),
    ...engineerVariants(),
    ...randomSamples(160, 20261024),
  ];

  print('== 阶段 1：排列组合结构与生成检查（${variants.length} 个配置）==');
  final sources = <String, String>{};
  for (final (name, config) in variants) {
    final validation = ProjectValidator.validate(config)
        .where((i) => i.severity == IssueSeverity.error)
        .toList();
    if (validation.isNotEmpty) {
      print('FAIL $name: 配置应合法却有错误：${validation.first.message}');
      if (args.contains('--debug') && config is EngineerConfig) {
        final c = config;
        for (var m = 0; m < (c.modeCount ?? 0); m++) {
          for (var a = 0; a < c.modes[m].actions.length; a++) {
            final act = c.modes[m].actions[a];
            print(
              '  debug mode$m#$a: key=${act.key} pin=${act.pin} '
              'dir=${act.direction?.name} mode=${act.mode?.name} '
              'param=${act.parameter} role=${act.pin == null ? "?" : c.pwm.pinRoles[act.pin!]?.name}',
            );
          }
        }
      }
      failed++;
      continue;
    }
    try {
      final source = CodeGenerator.generate(config);
      sources[name] = source;
      final issues = structuralIssues(name, source);
      if (issues.isNotEmpty) {
        for (final issue in issues) {
          print('FAIL $issue');
          failed++;
        }
      }
    } on StateError catch (e) {
      print('FAIL $name: 生成失败 $e');
      failed++;
    }
  }
  print('结构检查完成，${sources.length} 个配置成功生成');

  if (gccAvailable && !onlyStructural) {
    print('== 阶段 2：gcc 语法冒烟 ==');
    final genDir = await verifyWorkRoot('gen/');
    for (final entry in sources.entries) {
      final file = File('${genDir.path}${entry.key}.c');
      await file.writeAsString(prepareSource(entry.value));
      final result = Process.runSync(_gcc, [
        '-std=c99',
        '-fsyntax-only',
        '-w',
        '-I',
        stubIncludeDir(),
        file.path,
      ]);
      if (result.exitCode != 0) {
        print('FAIL 编译 ${entry.key}:\n${result.stderr}');
        failed++;
      }
    }
    print('编译冒烟完成');

    print('== 阶段 3：运行时执行场景 ==');
    final buildDir = await verifyWorkRoot('bin/');
    for (final scenario in scenarios()) {
      final summary = await runScenario(scenario, buildDir);
      if (summary.failures.isEmpty) {
        print(
          'PASS ${scenario.name}'
          '（${summary.dutyFrames} 帧，虚拟时长 ${summary.endMs}ms）',
        );
      } else {
        for (final failure in summary.failures) {
          print('FAIL ${scenario.name}: $failure');
          failed++;
        }
      }
    }
  }

  print(failed == 0 ? '\n全部验证通过' : '\n共 $failed 项失败');
  return failed == 0 ? 0 : 1;
}
