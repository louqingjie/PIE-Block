/// 生成 `assets/templates/*.pieproj` 四份模板工程。
///
/// 模板必须能通过 `ProjectValidator` 的零 error 校验，否则新手一打开开关
/// 就会看到满屏红字，与「预填好」的意图相反。用构造函数而不是手写 JSON 来
/// 定义内容，是为了让引脚冲突、频率匹配这类约束在改数值时立刻被校验器发现。
///
/// 用法：`dart run tool/generate_project_templates.dart`
library;

import 'dart:convert';
import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';

const _outputDir = 'assets/templates';

void main() {
  final templates = <ProjectDocument>[
    _document(ProjectKind.infantry, _infantry()),
    _document(ProjectKind.engineer, _engineer()),
    _document(ProjectKind.debug, _debug()),
    _document(ProjectKind.music, _music()),
  ];
  var failed = false;
  final dir = Directory(_outputDir);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  for (final document in templates) {
    final issues = ProjectValidator.validate(document.config);
    final errors = issues
        .where((issue) => issue.severity == IssueSeverity.error)
        .toList();
    final warnings = issues
        .where((issue) => issue.severity == IssueSeverity.warning)
        .toList();
    stdout.writeln(
      '${document.kind.name}: ${errors.length} error, ${warnings.length} warning',
    );
    for (final issue in issues) {
      final mark = issue.severity == IssueSeverity.error ? 'ERROR' : 'warn ';
      stdout.writeln('  [$mark] ${issue.fieldPath}: ${issue.message}');
    }
    if (errors.isNotEmpty) {
      failed = true;
      continue;
    }
    final encoded = const JsonEncoder.withIndent('  ')
        .convert(document.toJson());
    File('$_outputDir/${document.kind.name}.pieproj')
        .writeAsStringSync('$encoded\n');
  }
  if (failed) {
    stderr.writeln('模板存在 error，未写入任何文件。');
    exitCode = 1;
  }
}

/// 时间戳固定，避免每次生成都产生无关 diff。
ProjectDocument _document(ProjectKind kind, ProjectConfig config) {
  final createdAt = DateTime.utc(2026, 1, 1);
  return ProjectDocument(
    name: '模板工程',
    kind: kind,
    createdAt: createdAt,
    updatedAt: createdAt,
    config: config,
    guideProgress: GuideProgress.initial(kind),
  );
}

const _remote = RemoteConfig(channel: 36, deadzone: 100);

/// 四轮占满 PWMB（步兵固定 10000Hz），这样轮电机不会落进 PWMA 触发警告。
const _chassis = ChassisConfig(
  leftFront: WheelConfig('P74 P24', Direction.forward),
  leftRear: WheelConfig('P75 P25', Direction.forward),
  rightFront: WheelConfig('P76 P26', Direction.reverse),
  rightRear: WheelConfig('P77 P27', Direction.reverse),
  normalSpeed: 6000,
  sprintEnabled: false,
  turnReversed: false,
);

ProjectConfig _infantry() {
  return InfantryConfig(
    remote: _remote,
    chassis: _chassis,
    // 拨弹电机是第 5 路平滑电机，PWMB 已被四轮占满，只能落回固定 50Hz 的
    // PWMA，因此这条「电机可能一卡一卡」的提示在步兵模板里无法避免。
    feederPin: 'P60',
    feederDirection: Direction.forward,
    yawActuators: const [
      AxisActuator(
        drive: DriveType.servo,
        pin: 'MP74',
        direction: Direction.forward,
        midOffset: 0,
        minLimit: -60,
        maxLimit: 60,
      ),
    ],
    pitchActuators: const [
      AxisActuator(
        drive: DriveType.servo,
        pin: 'MP03',
        direction: Direction.forward,
        midOffset: 0,
        minLimit: -60,
        maxLimit: 60,
      ),
    ],
    arrowBehavior: ArrowBehavior.move,
    feedMode: FeedMode.blockingOpenLoop,
    triggerKey: 'E',
    reverseFeedKey: 'D',
    triggerSpeed: 6000,
    triggerTimeMs: 250,
    frictionMode: FrictionMode.brushlessEsc,
    frictionKey: 'A',
    frictionUpKey: 'B',
    frictionDownKey: 'C',
    frictionP64MaxDuty: 700,
    frictionP66MaxDuty: 800,
    frictionLevelStep: 10,
  );
}

ProjectConfig _engineer() {
  // PWMA 只放舵机与摩擦轮（期望 50Hz）、PWMB 只放平滑电机（期望 10000Hz），
  // 两组频率与角色逐一对齐，才不会产生「角色与所在 PWM 组频率不匹配」提示。
  final roles = <String, PinRole>{
    'P60': PinRole.servo,
    'P62': PinRole.servo,
    'P64': PinRole.friction,
    'P66': PinRole.friction,
    'P74': PinRole.motor,
    'P75': PinRole.motor,
    'P76': PinRole.motor,
    'P77': PinRole.motor,
  };
  return EngineerConfig(
    remote: _remote,
    chassis: const ChassisConfig(
      leftFront: WheelConfig('P74 P24', Direction.forward),
      leftRear: WheelConfig('P75 P25', Direction.forward),
      rightFront: WheelConfig('P76 P26', Direction.reverse),
      rightRear: WheelConfig('P77 P27', Direction.reverse),
      normalSpeed: 5000,
      sprintEnabled: false,
      turnReversed: false,
    ),
    pwm: PwmGroupConfig(
      pwma: PwmFrequency.hz50,
      pwmb: PwmFrequency.hz10000,
      pinRoles: roles,
      servoMids: const {'P60': 0, 'P62': 0, 'MP03': 0, 'MP74': 0},
      frictionMaxDuties: const {'P64': 700, 'P66': 800},
    ),
    modeCount: 2,
    switchStrategy: SwitchStrategy.cycle,
    modeSwitchKey: 'E',
    modes: [
      EngineerModeConfig(
        id: 'template-mode-1',
        preserveChassis: true,
        actions: [
          ActionMapping(
            id: 'template-1-1',
            key: 'A',
            direction: Direction.forward,
            mode: ControlMode.single,
            parameter: 5,
            pin: 'P60',
          ),
          ActionMapping(
            id: 'template-1-2',
            key: 'B',
            direction: Direction.forward,
            mode: ControlMode.continuous,
            parameter: 3,
            pin: 'P62',
          ),
          // 摩擦轮用专用语义：启停按一次切到目标油门、再按一次停止；
          // P64/P66 共享同一油门，各自按满油上限映射占空比。
          ActionMapping(
            id: 'template-1-3',
            key: 'C',
            mode: ControlMode.frictionToggle,
            parameter: 100,
            pin: 'P64',
          ),
          ActionMapping(
            id: 'template-1-4',
            key: 'D',
            direction: Direction.reverse,
            mode: ControlMode.frictionStep,
            parameter: 10,
            pin: 'P66',
          ),
        ],
      ),
      EngineerModeConfig(
        id: 'template-mode-2',
        preserveChassis: false,
        actions: [
          ActionMapping(
            id: 'template-2-1',
            key: 'LX',
            direction: Direction.forward,
            mode: ControlMode.incremental,
            parameter: 20,
            pin: 'P60',
          ),
          ActionMapping(
            id: 'template-2-2',
            key: 'RY',
            mode: ControlMode.frictionAxis,
            parameter: 50,
            pin: 'P64',
          ),
          ActionMapping(
            id: 'template-2-3',
            key: 'D',
            direction: Direction.reverse,
            mode: ControlMode.direct,
            parameter: 45,
            pin: 'P62',
          ),
        ],
      ),
    ],
  );
}

ProjectConfig _debug() {
  DebugTestItem motor(String pin) => DebugTestItem(
    pin: pin,
    enabled: true,
    driveType: DebugDriveType.motor,
    direction: Direction.forward,
    value: 5000,
    durationMs: 3000,
  );
  return DebugConfig(
    tests: [
      motor('P60'),
      motor('P62'),
      const DebugTestItem(
        pin: 'P64',
        enabled: true,
        driveType: DebugDriveType.friction,
        value: 700,
      ),
      const DebugTestItem(
        pin: 'P66',
        enabled: true,
        driveType: DebugDriveType.friction,
        value: 700,
      ),
      motor('P74'),
      motor('P75'),
      motor('P76'),
      motor('P77'),
      const DebugTestItem(
        pin: 'MP03',
        enabled: true,
        driveType: DebugDriveType.servo,
        direction: Direction.forward,
        value: 45,
        durationMs: 3000,
      ),
      const DebugTestItem(
        pin: 'MP74',
        enabled: true,
        driveType: DebugDriveType.servo,
        direction: Direction.forward,
        value: 45,
        durationMs: 3000,
      ),
    ],
  );
}

/// 《小星星》首句，够短、一听就认得，且每个音符起始 tick 互不相同。
ProjectConfig _music() {
  const melody = <int>[60, 60, 67, 67, 69, 69, 67, 65, 65, 64, 64, 62, 62, 60];
  const durations = <int>[
    480, 480, 480, 480, 480, 480, 960, //
    480, 480, 480, 480, 480, 480, 960,
  ];
  var tick = 0;
  final notes = <MusicNote>[];
  for (var index = 0; index < melody.length; index += 1) {
    notes.add(
      MusicNote(
        id: 'n${index + 1}',
        pitch: melody[index],
        startTick: tick,
        durationTicks: durations[index],
      ),
    );
    tick += durations[index];
  }
  return MusicConfig(
    ticksPerQuarter: 480,
    keySignatureFifths: 0,
    trackName: '一闪一闪亮晶晶',
    notes: notes,
    // 这两个键必须显式给出：fromJson 在键缺失时传空列表而不是 null，
    // 会绕过构造函数默认值，直接报「事件必须从 tick 0 开始」。
    tempoEvents: const [TempoEvent(tick: 0, microsecondsPerQuarter: 500000)],
    timeSignatureEvents: const [
      TimeSignatureEvent(tick: 0, numerator: 4, denominator: 4),
    ],
  );
}
