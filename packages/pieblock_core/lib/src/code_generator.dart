import 'dart:math' as math;

import 'debug_cues.dart';
import 'models.dart';
import 'music.dart';
import 'staff_firmware_c.dart';
import 'staff_notation.dart';
import 'validator.dart';

abstract final class CodeGenerator {
  static String generate(ProjectConfig config) {
    final errors = ProjectValidator.validate(config)
        .where((issue) => issue.severity == IssueSeverity.error);
    if (errors.isNotEmpty) {
      throw StateError('配置尚未完成，不能生成代码：${errors.first.message}');
    }
    return switch (config) {
      InfantryConfig value => _infantry(value),
      EngineerConfig value => _engineer(value),
      DebugConfig value => _debug(value),
      MusicConfig value => _music(value),
    };
  }

  static int _dir(Direction value) => value == Direction.forward ? 1 : 0;
  static int _frequency(PwmFrequency value) =>
      value == PwmFrequency.hz50 ? 50 : 10000;
  static int _servoDuty(int? degrees) =>
      (750 + ((degrees ?? 0) * 1000 / 180)).round().clamp(250, 1250);
  static String _key(String key) => switch (key) {
    'E' => 'KEY_OFFSET_1',
    'LC' => 'KEY_OFFSET_Rocker11',
    'RC' => 'KEY_OFFSET_Rocker21',
    '↑' => 'KEY_OFFSET_UP',
    '↓' => 'KEY_OFFSET_DOWN',
    '←' => 'KEY_OFFSET_LEFT',
    '→' => 'KEY_OFFSET_RIGHT',
    _ => 'KEY_OFFSET_$key',
  };
  static int _slot(String? pin) =>
      expansionPins.indexOf(InfantryPinPlanner.normalizePin(pin));

  static const String _uart1TxQuery = '''
static void Uart1TxQuery(uint8_t dat)
{
    uint8_t uart1InterruptEnabled = ES;

    ES = 0;
    TI = 0;
    SBUF = dat;
    while (!TI) ;
    TI = 0;
    ES = uart1InterruptEnabled;
}
''';

  static String _runtimeSafety(bool buzzerEnabled) =>
      '''
static void remoteControlInitWithTimeout(void)
{
    uint8_t retry;
    for (retry = 0; retry < 20; retry++) {
        if (NRF24L01_Init()) { Ms_Delay(200); return; }
        Ms_Delay(10);
    }
}

$_uart1TxQuery
#define LED_PORT GPIO_P3
#define LED1_PIN GPIO_Pin_5
#define LED2_PIN GPIO_Pin_6
#define LED3_PIN GPIO_Pin_7
${buzzerEnabled ? '#define BUZZER_CH PWMA_CH4N_P33' : ''}
static void LedShow(uint8_t show)
{
    GPIO_Write_Bit(LED_PORT, LED1_PIN, (show & 0x01) ? 0 : 1);
    GPIO_Write_Bit(LED_PORT, LED2_PIN, (show & 0x02) ? 0 : 1);
    GPIO_Write_Bit(LED_PORT, LED3_PIN, (show & 0x04) ? 0 : 1);
}
static void StepBegin(uint8_t step) { LedShow(step & 0x07); }
${buzzerEnabled ? '''static void Beep(uint16_t freq, uint16_t ms)
{
    PWM_SET_Frequency(BUZZER_CH, freq, 5000);
    Ms_Delay(ms);
    PWM_SET_Frequency(BUZZER_CH, freq, 0);
}
static void StepDone(uint8_t step) { Beep(500 + (uint16_t)(step % 8) * 60, 60); }
''' : 'static void StepDone(uint8_t step) { (void)step; }'}
''';

  static String _header(RobotConfig c, String title, bool buzzerDisabled) =>
      '''// $title（由 PIE-Block Flutter 配置器自动生成）
#include "main.h"
#include <stdlib.h>

uint8_t Channal = ${c.remote.channel!};
uint16_t maxSpeed = ${c.chassis.normalSpeed!};
uint16_t ultraSpeed = ${c.chassis.sprintSpeed ?? c.chassis.normalSpeed!};
uint16_t deadBandOfLeft = ${c.remote.deadzone!};
uint16_t deadBandOfRight = ${c.remote.deadzone!};

#define COMM_HEADER_1 0xAB
#define COMM_HEADER_2 0xBC
#define COMM_END_1 0xCD
#define COMM_END_2 0xDE
#define Init_Order 0xAA
#define Duty_Change_Order 0xBB
#define Freq_Change_Order 0xCC
#define Dir_Change_Order 0xDD
#define EXPANSION_FRAME_GAP_MS 5

uint8_t valueOfKey[3][4];
int valueOfRoker[2][2];
int dutyOfMotor[8];
uint8_t control_frame_pack[21];

${_runtimeSafety(!buzzerDisabled)}

void ExpansionBoradControl(uint8_t command,
    uint16_t p60, uint16_t p62, uint16_t p64, uint16_t p66,
    uint16_t p74, uint16_t p75, uint16_t p76, uint16_t p77)
{
    uint8_t i;
    control_frame_pack[0] = COMM_HEADER_1;
    control_frame_pack[1] = COMM_HEADER_2;
    control_frame_pack[2] = command;
    /* 逐字展开落帧，与《RM电控指南》的参考实现一致：SDCC 对
       "values[] 数组 + 3+i*2 变址" 的写法会取错字节（低字节位置被写成高字节，
       即 10000 发成 0x2727、500 发成 0x0101），这里直接从形参取高/低字节。 */
    control_frame_pack[3] = (uint8_t)((p60 >> 8) & 0xFF);
    control_frame_pack[4] = (uint8_t)(p60 & 0xFF);
    control_frame_pack[5] = (uint8_t)((p62 >> 8) & 0xFF);
    control_frame_pack[6] = (uint8_t)(p62 & 0xFF);
    control_frame_pack[7] = (uint8_t)((p64 >> 8) & 0xFF);
    control_frame_pack[8] = (uint8_t)(p64 & 0xFF);
    control_frame_pack[9] = (uint8_t)((p66 >> 8) & 0xFF);
    control_frame_pack[10] = (uint8_t)(p66 & 0xFF);
    control_frame_pack[11] = (uint8_t)((p74 >> 8) & 0xFF);
    control_frame_pack[12] = (uint8_t)(p74 & 0xFF);
    control_frame_pack[13] = (uint8_t)((p75 >> 8) & 0xFF);
    control_frame_pack[14] = (uint8_t)(p75 & 0xFF);
    control_frame_pack[15] = (uint8_t)((p76 >> 8) & 0xFF);
    control_frame_pack[16] = (uint8_t)(p76 & 0xFF);
    control_frame_pack[17] = (uint8_t)((p77 >> 8) & 0xFF);
    control_frame_pack[18] = (uint8_t)(p77 & 0xFF);
    control_frame_pack[19] = COMM_END_1;
    control_frame_pack[20] = COMM_END_2;
    for (i = 0; i < 21; i++) {
        Uart1TxQuery(control_frame_pack[i]);
    }
}

void ReadControllerInputs(void)
{
    valueOfRoker[0][0] = RcRockerValueRead(ROCKER_LEFT_HORIZONTAL);
    valueOfRoker[0][1] = RcRockerValueRead(ROCKER_LEFT_VERTICAL);
    valueOfRoker[1][0] = RcRockerValueRead(ROCKER_RIGHT_HORIZONTAL);
    valueOfRoker[1][1] = RcRockerValueRead(ROCKER_RIGHT_VERTICAL);
    if (abs(valueOfRoker[0][0]) <= deadBandOfLeft) valueOfRoker[0][0] = 0;
    if (abs(valueOfRoker[0][1]) <= deadBandOfLeft) valueOfRoker[0][1] = 0;
    if (abs(valueOfRoker[1][0]) <= deadBandOfRight) valueOfRoker[1][0] = 0;
    if (abs(valueOfRoker[1][1]) <= deadBandOfRight) valueOfRoker[1][1] = 0;
}
''';

  static String _chassis(ChassisConfig c) {
    final sprint = c.sprintEnabled
        ? '''
    if (RcKeyValueRead(KEY_OFFSET_Rocker11)) speed = ultraSpeed;
'''
        : '';
    final turnReverse = c.turnReversed ? '    turnSpeed = -turnSpeed;\n' : '';
    return '''
void CalculateChassis(void)
{
    int speed = maxSpeed;
    int baseSpeed;
    int turnSpeed;$sprint
    baseSpeed = (int)(((int32_t)-valueOfRoker[0][1] * (int32_t)speed) / 2047L);
    turnSpeed = (int)(((int32_t)-valueOfRoker[0][0] * (int32_t)speed) / 2047L);
$turnReverse    dutyOfMotor[${_slot(c.leftFront.pin)}] = ${_dir(c.leftFront.direction!) == 1 ? '' : '-'}baseSpeed ${_dir(c.leftFront.direction!) == 1 ? '-' : '+'} turnSpeed;
    dutyOfMotor[${_slot(c.leftRear.pin)}] = ${_dir(c.leftRear.direction!) == 1 ? '' : '-'}baseSpeed ${_dir(c.leftRear.direction!) == 1 ? '-' : '+'} turnSpeed;
    dutyOfMotor[${_slot(c.rightFront.pin)}] = ${_dir(c.rightFront.direction!) == 1 ? '-' : ''}baseSpeed ${_dir(c.rightFront.direction!) == 1 ? '-' : '+'} turnSpeed;
    dutyOfMotor[${_slot(c.rightRear.pin)}] = ${_dir(c.rightRear.direction!) == 1 ? '-' : ''}baseSpeed ${_dir(c.rightRear.direction!) == 1 ? '-' : '+'} turnSpeed;
}
''';
  }

  static String _pwmInit(PwmGroupConfig pwm, Set<String> usedPins) {
    final lines = <String>[
      '    ExpansionBoradControl(Init_Order, ${List.filled(4, _frequency(pwm.pwma!)).join(', ')}, ${List.filled(4, _frequency(pwm.pwmb!)).join(', ')});',
    ];
    for (final pin in mainServoPins) {
      if (!usedPins.contains(pin)) continue;
      lines.add(
        '    PWM_Init(PWMB_CH${pin == 'MP74' ? '1_P74' : '4_P03'}, 50, ${_servoDuty(pwm.servoMids[pin])});',
      );
    }
    return lines.join('\n');
  }

  static String _infantry(InfantryConfig c) {
    final frictionEnabled = c.frictionMode == FrictionMode.brushlessEsc;
    final feederSlot = _slot(c.feederPin);
    // 云台按「先 Yaw 后 Pitch、轴内按配置顺序」生成。
    const yawAndPitch = [true, false];
    AxisActuator? actuatorAt({required bool yaw, required int index}) =>
        index < c.actuators(yaw).length ? c.actuators(yaw)[index] : null;
    // 每轴首个执行器沿用 yawDuty / pitchDuty，其余执行器依次为 yawDuty2、pitchDuty2……
    String dutyName({required bool yaw, required int index}) =>
        '${yaw ? 'yaw' : 'pitch'}Duty${index == 0 ? '' : index + 1}';
    final servoActuators = <({bool yaw, int index})>[
      for (final yaw in yawAndPitch)
        for (var index = 0; index < c.actuators(yaw).length; index += 1)
          if (c.actuators(yaw)[index].drive == DriveType.servo)
            (yaw: yaw, index: index),
    ];
    final dutyVariables = <({String name, int home})>[
      for (final yaw in yawAndPitch)
        if (c.actuators(yaw).isNotEmpty) ...[
          (
            name: dutyName(yaw: yaw, index: 0),
            home: _servoDuty(actuatorAt(yaw: yaw, index: 0)?.midOffset),
          ),
          for (final item in servoActuators)
            if (item.yaw == yaw && item.index > 0)
              (
                name: dutyName(yaw: item.yaw, index: item.index),
                home: _servoDuty(
                  actuatorAt(yaw: item.yaw, index: item.index)!.midOffset,
                ),
              ),
        ],
    ];
    String actuatorUpdate({required bool yaw, required int index}) {
      final actuator = actuatorAt(yaw: yaw, index: index)!;
      final rocker = yaw ? 'valueOfRoker[1][0]' : 'valueOfRoker[1][1]';
      if (actuator.drive == DriveType.servo) {
        final variable = dutyName(yaw: yaw, index: index);
        final home = _servoDuty(actuator.midOffset);
        final low = (home - 333).clamp(250, 1250);
        final high = (home + 333).clamp(250, 1250);
        final sign = actuator.direction == Direction.forward ? '' : '-';
        return '''    $variable += (int)((float)$sign$rocker * 2.0f / 2047.0f * 5.555556f);
    if ($variable < $low) $variable = $low; if ($variable > $high) $variable = $high;''';
      }
      final sign = actuator.direction == Direction.forward ? '' : '-';
      return '    dutyOfMotor[${_slot(actuator.pin)}] = $sign(int)(((int32_t)$rocker * 10000L) / 2047L);';
    }

    final gimbalBlocks = <String>[
      for (final yaw in yawAndPitch)
        for (var index = 0; index < c.actuators(yaw).length; index += 1)
          actuatorUpdate(yaw: yaw, index: index),
    ];
    final dutyDeclarations = dutyVariables
        .map((item) => 'uint16_t ${item.name} = ${item.home};')
        .join('\n');
    final dutyResets = dutyVariables
        .map((item) => '${item.name} = ${item.home};')
        .join(' ');

    String dutyValue(int index) {
      if (frictionEnabled) {
        if (index == _slot('P64')) return 'frictionDutyP64';
        if (index == _slot('P66')) return 'frictionDutyP66';
      }
      for (final item in servoActuators) {
        if (_slot(actuatorAt(yaw: item.yaw, index: item.index)!.pin) == index) {
          return dutyName(yaw: item.yaw, index: item.index);
        }
      }
      return 'abs(dutyOfMotor[$index])';
    }

    String directionValue(int index) {
      if (frictionEnabled && (index == _slot('P64') || index == _slot('P66'))) {
        return '1';
      }
      for (final item in servoActuators) {
        if (_slot(actuatorAt(yaw: item.yaw, index: item.index)!.pin) == index) {
          return '1';
        }
      }
      return 'dutyOfMotor[$index]>=0';
    }

    final dutyArgs = List.generate(8, dutyValue).join(','),
        directionArgs = List.generate(8, directionValue).join(','),
        mainServoInit = <String>[],
        mainServoUpdates = <String>[];
    for (final item in servoActuators) {
      final actuator = actuatorAt(yaw: item.yaw, index: item.index)!;
      if (!mainServoPins.contains(actuator.pin)) continue;
      final channel = actuator.pin == 'MP74' ? '1_P74' : '4_P03';
      final duty = dutyName(yaw: item.yaw, index: item.index);
      mainServoInit.add(
        '    PWM_Init(PWMB_CH$channel, 50, ${_servoDuty(actuator.midOffset)});',
      );
      mainServoUpdates.add(
        '        PWM_SET_Frequency(PWMB_CH$channel, 50, $duty);',
      );
    }
    final frictionDefines = frictionEnabled
        ? '''#define FRICTION_START_DUTY ${Friction.startDuty}
#define FRICTION_STEP_DUTY 1
#define FRICTION_LEVEL_MAX ${Friction.levelMax}
#define FRICTION_MAX_DUTY_P64 ${c.frictionP64MaxDuty!}
#define FRICTION_MAX_DUTY_P66 ${c.frictionP66MaxDuty!}
#define FRICTION_LEVEL_STEP ${c.frictionLevelStep!}
/* 主循环一圈约 FRICTION_LOOP_MS 毫秒（Ms_Delay(10) 加两次 5ms 帧间隔），
   电调激活按整圈数折算，实际保持时间不会短于 FRICTION_ACTIVATE_MS。 */
#define FRICTION_LOOP_MS 20
#define FRICTION_ACTIVATE_MS 1000
#define FRICTION_ACTIVATE_LOOPS ((FRICTION_ACTIVATE_MS + FRICTION_LOOP_MS - 1) / FRICTION_LOOP_MS)
'''
        : '';
    final frictionGlobals = frictionEnabled
        ? '''uint8_t frictionLevel = 0;
uint16_t frictionDutyP64 = 0;
uint16_t frictionDutyP66 = 0;
uint16_t frictionTargetDutyP64 = 0;
uint16_t frictionTargetDutyP66 = 0;
uint8_t frictionEnabled = 0;
uint8_t frictionActivateLoops = 0;
'''
        : '';
    // 比例值是唯一控制量：油门 duty = 500 + 油门/100 * (该侧上限 - 500)。
    // P64/P66 各自用自己的上限做线性映射，补偿两侧机械差异带来的转速差。
    final frictionHelpers = frictionEnabled
        ? '''static uint16_t FrictionDutyOfLevel(uint8_t level, uint16_t maxDuty) {
    return (uint16_t)(FRICTION_START_DUTY
        + ((uint16_t)level * (uint16_t)(maxDuty - FRICTION_START_DUTY)) / FRICTION_LEVEL_MAX);
}
'''
        : '';
    String frictionRamp(String pin) => [
      '    if (frictionTargetDuty$pin >= FRICTION_START_DUTY && frictionDuty$pin < FRICTION_START_DUTY)',
      '        frictionDuty$pin = FRICTION_START_DUTY;',
      '    else if (frictionDuty$pin < frictionTargetDuty$pin)',
      '        frictionDuty$pin += FRICTION_STEP_DUTY;',
      '    else if (frictionDuty$pin > frictionTargetDuty$pin) {',
      '        if (frictionTargetDuty$pin == 0 && frictionDuty$pin <= FRICTION_START_DUTY)',
      '            frictionDuty$pin = 0;',
      '        else',
      '            frictionDuty$pin -= FRICTION_STEP_DUTY;',
      '    }',
    ].join('\n');
    final frictionUpdate = frictionEnabled
        ? '''    static uint8_t lastFriction = 0;
    static uint8_t lastFrictionUp = 0;
    static uint8_t lastFrictionDown = 0;
    uint8_t friction = RcKeyValueRead(${_key(c.frictionKey!)});
    uint8_t frictionUp = RcKeyValueRead(${_key(c.frictionUpKey!)});
    uint8_t frictionDown = RcKeyValueRead(${_key(c.frictionDownKey!)});
    if (friction && !lastFriction) {
        frictionEnabled = !frictionEnabled;
        frictionLevel = frictionEnabled ? FRICTION_LEVEL_MAX : 0;
        /* 关闭时立刻取消激活残留，马上走停机斜坡，不停在启动占空比上。 */
        if (!frictionEnabled) frictionActivateLoops = 0;
    }
    if (frictionEnabled && frictionUp && !lastFrictionUp && !frictionDown) {
        if (frictionLevel < FRICTION_LEVEL_MAX - FRICTION_LEVEL_STEP)
            frictionLevel += FRICTION_LEVEL_STEP;
        else frictionLevel = FRICTION_LEVEL_MAX;
    }
    if (frictionEnabled && frictionDown && !lastFrictionDown && !frictionUp) {
        if (frictionLevel > FRICTION_LEVEL_STEP)
            frictionLevel -= FRICTION_LEVEL_STEP;
        else frictionLevel = 0;
    }
    /* 目标占空比每周期由油门重新映射，避免按键跳档后残留旧目标。 */
    frictionTargetDutyP64 = frictionEnabled
        ? FrictionDutyOfLevel(frictionLevel, FRICTION_MAX_DUTY_P64) : 0;
    frictionTargetDutyP66 = frictionEnabled
        ? FrictionDutyOfLevel(frictionLevel, FRICTION_MAX_DUTY_P66) : 0;
    /* 电调激活：摩擦轮从静止（占空比 0）启动时，先保持 FRICTION_START_DUTY
       启动占空比 FRICTION_ACTIVATE_MS，让电调完成激活后再爬坡，
       与调试工程的摩擦轮测试同一套激活流程。 */
    if (frictionEnabled && frictionDutyP64 == 0
        && frictionTargetDutyP64 >= FRICTION_START_DUTY)
        frictionActivateLoops = FRICTION_ACTIVATE_LOOPS;
    if (frictionActivateLoops > 0) {
        frictionActivateLoops--;
        frictionDutyP64 = FRICTION_START_DUTY;
        frictionDutyP66 = FRICTION_START_DUTY;
    } else {
        /* 指南：启停时 0~5% 区间可以跳过（电机 5% 才起转），
           因此输出只取 0 或 500~各自上限，中间的 0~500 一律跳变。
           斜坡跑在占空比上（两侧各自 ±1 duty/周期）， duty 变化率不超过 50/s。 */
${frictionRamp('P64')}
${frictionRamp('P66')}
    }
    lastFriction = friction;
    lastFrictionUp = frictionUp;
    lastFrictionDown = frictionDown;
'''
        : '';
    final feedSign = _dir(c.feederDirection!) == 1 ? '' : '-',
        reverseFeedSign = _dir(c.feederDirection!) == 1 ? '-' : '';
    final forwardFeedUpdate = c.feedMode == FeedMode.visualClosedLoop
        ? '''    dutyOfMotor[$feederSlot] = trigger ? $feedSign${c.triggerSpeed!} : 0;
'''
        : '''    if (trigger && !lastTrigger) {
        dutyOfMotor[$feederSlot] = $feedSign${c.triggerSpeed!};
        ExpansionBoradControl(Duty_Change_Order, $dutyArgs);
        Ms_Delay(${c.triggerTimeMs!});
        dutyOfMotor[$feederSlot] = 0;
    }
''';
    // 反向拨弹键优先于扳机：按住期间持续反转，松开立即归零。
    // 归零不能只写在扳机分支里，否则松开反向键后占空比会一直保持反转值。
    final reverseFeedUpdate = c.feedMode == FeedMode.visualClosedLoop
        ? '''    if (reverseFeed) {
        dutyOfMotor[$feederSlot] = $reverseFeedSign${c.triggerSpeed!};
    } else {
        dutyOfMotor[$feederSlot] = trigger ? $feedSign${c.triggerSpeed!} : 0;
    }
'''
        : '''    if (reverseFeed) {
        dutyOfMotor[$feederSlot] = $reverseFeedSign${c.triggerSpeed!};
    } else {
        if (trigger && !lastTrigger) {
            dutyOfMotor[$feederSlot] = $feedSign${c.triggerSpeed!};
            ExpansionBoradControl(Duty_Change_Order, $dutyArgs);
            Ms_Delay(${c.triggerTimeMs!});
        }
        dutyOfMotor[$feederSlot] = 0;
    }
''';
    final feedUpdate = c.reverseFeedKey == null
        ? forwardFeedUpdate
        : reverseFeedUpdate;
    final reverseFeedDeclaration = c.reverseFeedKey == null
        ? ''
        : '    uint8_t reverseFeed = RcKeyValueRead(${_key(c.reverseFeedKey!)});\n';
    final arrowUpdate = switch (c.arrowBehavior) {
      ArrowBehavior.move =>
        '''        if (RcKeyValueRead(KEY_OFFSET_UP)) valueOfRoker[0][1] = -2047;
        if (RcKeyValueRead(KEY_OFFSET_DOWN)) valueOfRoker[0][1] = 2047;
        if (RcKeyValueRead(KEY_OFFSET_LEFT)) valueOfRoker[0][0] = 2047;
        if (RcKeyValueRead(KEY_OFFSET_RIGHT)) valueOfRoker[0][0] = -2047;
''',
      ArrowBehavior.sprint =>
        '''        maxSpeed = ${c.chassis.normalSpeed!};
        if (RcKeyValueRead(KEY_OFFSET_UP)) { valueOfRoker[0][1] = -2047; maxSpeed = ultraSpeed; }
        if (RcKeyValueRead(KEY_OFFSET_DOWN)) { valueOfRoker[0][1] = 2047; maxSpeed = ultraSpeed; }
        if (RcKeyValueRead(KEY_OFFSET_LEFT)) { valueOfRoker[0][0] = 2047; maxSpeed = ultraSpeed; }
        if (RcKeyValueRead(KEY_OFFSET_RIGHT)) { valueOfRoker[0][0] = -2047; maxSpeed = ultraSpeed; }
''',
      ArrowBehavior.other => '',
      null => '',
    };
    final servoDuties = <String>[
      for (final item in servoActuators)
        dutyName(yaw: item.yaw, index: item.index),
    ];
    final feedbackChecks = <String>[];
    for (var index = 0; index < servoDuties.length; index++) {
      final duty = servoDuties[index];
      feedbackChecks.add(
        '    if (feedbackInitialized && $duty != lastFeedbackDuty[$index]) { changed = 1; feedbackDuty = $duty; }\n'
        '    lastFeedbackDuty[$index] = $duty;',
      );
    }
    final buzzerFeedback =
        c.buzzerDisabled || (servoDuties.isEmpty && !frictionEnabled)
        ? ''
        : '''static uint8_t feedbackInitialized = 0;
static uint16_t lastFeedbackDuty[${servoDuties.isEmpty ? 1 : servoDuties.length}] = {0};
static void UpdateBuzzerFeedback(void)
{
    uint8_t changed = 0;
    uint16_t feedbackDuty = 0;
${feedbackChecks.join('\n')}
    if (!feedbackInitialized) { feedbackInitialized = 1; changed = 0; }
    if (changed) PWM_SET_Frequency(BUZZER_CH, feedbackDuty, 5000);
${frictionEnabled ? '    else if (frictionActivateLoops == 0 && (frictionDutyP64 != frictionTargetDutyP64 || frictionDutyP66 != frictionTargetDutyP66)) PWM_SET_Frequency(BUZZER_CH, frictionDutyP64, 5000);' : ''}
    else PWM_SET_Frequency(BUZZER_CH, 500, 0);
}
''';
    return '''${_header(c, '步兵机器人控制代码', c.buzzerDisabled)}
$frictionDefines
$dutyDeclarations
$frictionGlobals
$frictionHelpers
$buzzerFeedback

${_chassis(c.chassis)}
void All_Init(void)
{
    StepBegin(0);
    Board_Init();
    StepDone(0);
    StepBegin(1);
    UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, 230400, TIM1);
    StepDone(1);
    GPIO_Init(LED_PORT, (GPIO_Pin_enum)(LED1_PIN | LED2_PIN | LED3_PIN), GPIO_OUT_PP);
${c.buzzerDisabled ? '' : '    PWM_Init(BUZZER_CH, 500, 0);'}
    StepBegin(3);
    EA = 0;
    remoteControlInitWithTimeout();
    P2INTE &= ~GPIO_Pin_6;
    EA = 1;
    StepDone(3);
    ExpansionBoradControl(Init_Order, 50, 50, 50, 50, 10000, 10000, 10000, 10000);
${mainServoInit.join('\n')}
    Ms_Delay(1000);
${c.buzzerDisabled ? '' : '''    Beep(523, 120);
    Beep(659, 120);
    Beep(784, 120);
    Beep(1047, 240);'''}
}

void UpdateGimbal(void)
{
${gimbalBlocks.join('\n')}
    ${c.zeroEnabled ? 'if (RcKeyValueRead(KEY_OFFSET_Rocker21)) { $dutyResets }' : ''}
}

void UpdateWeapons(void)
{
    static uint8_t lastTrigger = 0;
    uint8_t trigger = RcKeyValueRead(${_key(c.triggerKey!)});
$reverseFeedDeclaration$frictionUpdate$feedUpdate
    lastTrigger = trigger;
}

void main(void)
{
    All_Init();
    while (1) {
        nrf_handler(); // 轮询 NRF 接收（P2.6 中断已关）
        ReadControllerInputs();
$arrowUpdate
        CalculateChassis();
        UpdateGimbal();
        UpdateWeapons();
        ExpansionBoradControl(Dir_Change_Order, $directionArgs);
        Ms_Delay(EXPANSION_FRAME_GAP_MS);
        ExpansionBoradControl(Duty_Change_Order, $dutyArgs);
        Ms_Delay(EXPANSION_FRAME_GAP_MS);
${mainServoUpdates.join('\n')}
${buzzerFeedback.isEmpty ? '' : '        UpdateBuzzerFeedback();'}
        Ms_Delay(10);
    }
}
''';
  }

  static String _engineer(EngineerConfig c) {
    final modeFunctions = <String>[], cases = <String>[];
    final servoButtonRemainderIndexes = <String, int>{};
    final servoButtonRemainderActions =
        <({int modeIndex, int actionIndex, ActionMapping action})>[];
    final servoButtonEdgeIndexes = <String, int>{};
    final servoButtonEdgeActions =
        <({int modeIndex, int actionIndex, ActionMapping action})>[];
    for (var modeIndex = 0; modeIndex < c.modeCount!; modeIndex++) {
      final actions = c.modes[modeIndex].actions;
      for (var actionIndex = 0; actionIndex < actions.length; actionIndex++) {
        final action = actions[actionIndex];
        final isServoButton =
            digitalRemoteKeys.contains(action.key) &&
            (mainServoPins.contains(action.pin) ||
                c.pwm.pinRoles[action.pin] == PinRole.servo);
        if (!isServoButton) continue;
        if (action.mode == ControlMode.single ||
            action.mode == ControlMode.continuous) {
          servoButtonRemainderIndexes['$modeIndex:$actionIndex'] =
              servoButtonRemainderActions.length;
          servoButtonRemainderActions.add((
            modeIndex: modeIndex,
            actionIndex: actionIndex,
            action: action,
          ));
        }
        if (action.mode == ControlMode.direct ||
            action.mode == ControlMode.single) {
          servoButtonEdgeIndexes['$modeIndex:$actionIndex'] =
              servoButtonEdgeActions.length;
          servoButtonEdgeActions.add((
            modeIndex: modeIndex,
            actionIndex: actionIndex,
            action: action,
          ));
        }
      }
    }
    final usedPins = <String>{
      for (final mode in c.modes.take(c.modeCount!))
        for (final action in mode.actions)
          if (action.pin != null) action.pin!,
    };
    for (var i = 0; i < c.modeCount!; i++) {
      final mode = c.modes[i], body = <String>[];
      if (mode.preserveChassis) body.add('    CalculateChassis();');
      for (
        var actionIndex = 0;
        actionIndex < mode.actions.length;
        actionIndex++
      ) {
        final a = mode.actions[actionIndex];
        final sign = a.direction == Direction.forward ? '' : '-';
        final isAxis = a.key!.endsWith('X') || a.key!.endsWith('Y');
        final read = isAxis
            ? 'valueOfRoker[${a.key!.startsWith('L') ? 0 : 1}][${a.key!.endsWith('X') ? 0 : 1}]'
            : 'RcKeyValueRead(${_key(a.key!)})';
        final slot = expansionPins.indexOf(a.pin!);
        final role = slot >= 0 ? c.pwm.pinRoles[a.pin!] : PinRole.servo;
        if (slot >= 0) {
          if (role == PinRole.servo) {
            final home = _servoDuty(c.pwm.servoMids[a.pin!]);
            if (!isAxis) {
              if (a.mode == ControlMode.direct) {
                final edgeIndex = servoButtonEdgeIndexes['$i:$actionIndex']!;
                final signedAngle =
                    (a.direction == Direction.forward ? 1 : -1) *
                    a.parameter!.toInt();
                final target = _servoDuty(
                  (c.pwm.servoMids[a.pin!] ?? 0) + signedAngle,
                );
                body.add(
                  '    if ($read && !servoButtonKeyLast[$edgeIndex]) dutyOfMotor[$slot] = $target;',
                );
                body.add('    servoButtonKeyLast[$edgeIndex] = $read;');
                continue;
              }
              final remainderIndex =
                  servoButtonRemainderIndexes['$i:$actionIndex']!;
              final sensitivityHundredths = (a.parameter!.toDouble() * 100)
                  .round();
              final signedNumerator =
                  (a.direction == Direction.forward ? 1 : -1) *
                  sensitivityHundredths *
                  1000;
              final edgeIndex = a.mode == ControlMode.single
                  ? servoButtonEdgeIndexes['$i:$actionIndex']!
                  : null;
              final condition = a.mode == ControlMode.single
                  ? '$read && !servoButtonKeyLast[$edgeIndex]'
                  : read;
              body.add(
                '    if ($condition) {\n'
                '        servoButtonRemainder[$remainderIndex] += ${signedNumerator}L;\n'
                '        dutyOfMotor[$slot] += (int)(servoButtonRemainder[$remainderIndex] / 18000L);\n'
                '        servoButtonRemainder[$remainderIndex] %= 18000L;\n'
                '    }',
              );
              if (a.mode == ControlMode.single) {
                body.add('    servoButtonKeyLast[$edgeIndex] = $read;');
              }
              body.add(
                '    if (dutyOfMotor[$slot] < 250) { dutyOfMotor[$slot] = 250; servoButtonRemainder[$remainderIndex] = 0; } '
                'else if (dutyOfMotor[$slot] > 1250) { dutyOfMotor[$slot] = 1250; servoButtonRemainder[$remainderIndex] = 0; }',
              );
              continue;
            }
            final parameter = a.parameter!.toInt();
            final delta =
                '$sign(int)((float)$read * $parameter * 1000.0f / 180.0f / 2047.0f)';
            if (a.mode == ControlMode.direct) {
              body.add('    dutyOfMotor[$slot] = $home + $delta;');
            } else {
              body.add('    dutyOfMotor[$slot] += $delta;');
            }
            body.add(
              '    if (dutyOfMotor[$slot] < 250) dutyOfMotor[$slot] = 250; else if (dutyOfMotor[$slot] > 1250) dutyOfMotor[$slot] = 1250;',
            );
          } else if (a.mode == ControlMode.direct) {
            body.add(
              '    dutyOfMotor[$slot] = $read ? $sign${a.parameter!.toInt()} : 0;',
            );
          } else if (a.mode == ControlMode.speed) {
            body.add(
              '    dutyOfMotor[$slot] = (int)(((int32_t)$read * ${a.parameter!.toInt()}L) / 2047L);',
            );
          } else {
            body.add(
              '    dutyOfMotor[$slot] += (int)(((int32_t)$read * ${a.parameter!.toInt()}L) / 2047L);',
            );
          }
        } else {
          final mainIndex = a.pin == 'MP74' ? 1 : 0;
          final home = _servoDuty(c.pwm.servoMids[a.pin!]);
          if (!isAxis) {
            if (a.mode == ControlMode.direct) {
              final edgeIndex = servoButtonEdgeIndexes['$i:$actionIndex']!;
              final signedAngle =
                  (a.direction == Direction.forward ? 1 : -1) *
                  a.parameter!.toInt();
              final target = _servoDuty(
                (c.pwm.servoMids[a.pin!] ?? 0) + signedAngle,
              );
              body.add(
                '    if ($read && !servoButtonKeyLast[$edgeIndex]) mainServoDuty[$mainIndex] = $target;',
              );
              body.add('    servoButtonKeyLast[$edgeIndex] = $read;');
              continue;
            }
            final remainderIndex =
                servoButtonRemainderIndexes['$i:$actionIndex']!;
            final sensitivityHundredths = (a.parameter!.toDouble() * 100)
                .round();
            final signedNumerator =
                (a.direction == Direction.forward ? 1 : -1) *
                sensitivityHundredths *
                1000;
            final edgeIndex = a.mode == ControlMode.single
                ? servoButtonEdgeIndexes['$i:$actionIndex']!
                : null;
            final condition = a.mode == ControlMode.single
                ? '$read && !servoButtonKeyLast[$edgeIndex]'
                : read;
            body.add(
              '    if ($condition) {\n'
              '        servoButtonRemainder[$remainderIndex] += ${signedNumerator}L;\n'
              '        mainServoDuty[$mainIndex] += (int)(servoButtonRemainder[$remainderIndex] / 18000L);\n'
              '        servoButtonRemainder[$remainderIndex] %= 18000L;\n'
              '    }',
            );
            if (a.mode == ControlMode.single) {
              body.add('    servoButtonKeyLast[$edgeIndex] = $read;');
            }
            body.add(
              '    if (mainServoDuty[$mainIndex] < 250) { mainServoDuty[$mainIndex] = 250; servoButtonRemainder[$remainderIndex] = 0; } '
              'else if (mainServoDuty[$mainIndex] > 1250) { mainServoDuty[$mainIndex] = 1250; servoButtonRemainder[$remainderIndex] = 0; }',
            );
            continue;
          }
          final parameter = a.parameter!.toInt();
          final delta =
              '$sign(int)((float)$read * $parameter * 1000.0f / 180.0f / 2047.0f)';
          if (a.mode == ControlMode.direct) {
            body.add('    mainServoDuty[$mainIndex] = $home + $delta;');
          } else {
            body.add('    mainServoDuty[$mainIndex] += $delta;');
          }
          body.add(
            '    if (mainServoDuty[$mainIndex] < 250) mainServoDuty[$mainIndex] = 250; else if (mainServoDuty[$mainIndex] > 1250) mainServoDuty[$mainIndex] = 1250;',
          );
        }
      }
      modeFunctions.add('void RunMode${i + 1}(void)\n{\n${body.join('\n')}\n}');
      cases.add('        case ${i + 1}: RunMode${i + 1}(); break;');
    }
    final feedbackEnabled = c.modeCount! > 1 && !c.pwm.buzzerDisabled;
    final chassisSlots = {
      _slot(c.chassis.leftFront.pin),
      _slot(c.chassis.leftRear.pin),
      _slot(c.chassis.rightFront.pin),
      _slot(c.chassis.rightRear.pin),
    };
    final prepareCases = <String>[];
    for (var i = 0; i < c.modeCount!; i++) {
      final mapped = c.modes[i].actions
          .map((action) => expansionPins.indexOf(action.pin ?? ''))
          .where((slot) => slot >= 0)
          .toSet();
      final lines = <String>[];
      for (var slot = 0; slot < expansionPins.length; slot++) {
        if (!chassisSlots.contains(slot) &&
            !mapped.contains(slot) &&
            (c.pwm.pinRoles[expansionPins[slot]] == PinRole.motor ||
                c.pwm.pinRoles[expansionPins[slot]] == PinRole.friction ||
                c.pwm.pinRoles[expansionPins[slot]] == PinRole.jitterMotor)) {
          lines.add('            dutyOfMotor[$slot] = 0;');
        }
      }
      prepareCases.add(
        '        case ${i + 1}:\n${lines.join('\n')}\n            break;',
      );
    }
    final prepareMode =
        '''static void PrepareMode(uint8_t mode)
{
    switch (mode) {
${prepareCases.join('\n')}
    }
}
''';
    final servoButtonDeclarations =
        '''${servoButtonRemainderActions.isEmpty ? '' : 'int32_t servoButtonRemainder[${servoButtonRemainderActions.length}] = {0};'}
${servoButtonEdgeActions.isEmpty ? '' : 'uint8_t servoButtonKeyLast[${servoButtonEdgeActions.length}] = {0};'}''';
    final servoButtonSync = servoButtonEdgeActions.isEmpty
        ? ''
        : '''uint8_t servoButtonStateMode = 0;
static void SyncServoButtonKeys(uint8_t mode)
{
    switch (mode) {
${List.generate(c.modeCount!, (modeIndex) {
            final lines = <String>[];
            for (var index = 0; index < servoButtonEdgeActions.length; index++) {
              final entry = servoButtonEdgeActions[index];
              if (entry.modeIndex == modeIndex) {
                lines.add('            servoButtonKeyLast[$index] = RcKeyValueRead(${_key(entry.action.key!)});');
              }
            }
            return lines.isEmpty ? '' : '        case ${modeIndex + 1}:\n${lines.join('\n')}\n            break;';
          }).where((value) => value.isNotEmpty).join('\n')}
    }
}
''';
    final feedback = feedbackEnabled
        ? '''static void ModeSwitchFeedback(uint8_t mode)
{
    Beep(523, 500);
    Ms_Delay(200);
    if (mode >= 1) { Beep(659, 200); if (mode > 1) Ms_Delay(200); }
    if (mode >= 2) { Beep(784, 200); if (mode > 2) Ms_Delay(200); }
    if (mode >= 3) { Beep(1047, 200); if (mode > 3) Ms_Delay(200); }
    if (mode >= 4) Beep(1319, 200);
}
'''
        : '';
    final servoExpressions = <String>[
      for (final pin in usedPins)
        if (expansionPins.contains(pin) && c.pwm.pinRoles[pin] == PinRole.servo)
          'dutyOfMotor[${expansionPins.indexOf(pin)}]',
      if (usedPins.contains('MP03')) 'mainServoDuty[0]',
      if (usedPins.contains('MP74')) 'mainServoDuty[1]',
    ];
    final engineerFeedbackChecks = <String>[];
    for (var index = 0; index < servoExpressions.length; index++) {
      final expression = servoExpressions[index];
      engineerFeedbackChecks.add(
        '    if (servoFeedbackInitialized && $expression != lastServoFeedback[$index]) { changed = 1; feedbackDuty = $expression; }\n'
        '    lastServoFeedback[$index] = $expression;',
      );
    }
    final engineerFeedback = c.pwm.buzzerDisabled || servoExpressions.isEmpty
        ? ''
        : '''static uint8_t servoFeedbackInitialized = 0;
static uint16_t lastServoFeedback[${servoExpressions.length}] = {0};
static void UpdateServoFeedback(void)
{
    uint8_t changed = 0;
    uint16_t feedbackDuty = 0;
${engineerFeedbackChecks.join('\n')}
    if (!servoFeedbackInitialized) { servoFeedbackInitialized = 1; changed = 0; }
    if (changed) PWM_SET_Frequency(BUZZER_CH, feedbackDuty, 5000);
    else PWM_SET_Frequency(BUZZER_CH, 500, 0);
}
''';
    final transitionCall =
        ' PrepareMode(currentMode);${feedbackEnabled ? ' ModeSwitchFeedback(currentMode);' : ''}';
    final switchLogic = c.modeCount == 1
        ? '// 单模式，无需切换'
        : c.switchStrategy == SwitchStrategy.cycle
        ? '''if (RcKeyValueRead(${_key(c.modeSwitchKey!)}) && !lastSwitch) { currentMode++; if (currentMode > ${c.modeCount}) currentMode = 1;$transitionCall }
        lastSwitch = RcKeyValueRead(${_key(c.modeSwitchKey!)});'''
        : List.generate(
            c.modeCount!,
            (i) =>
                '''if (RcKeyValueRead(${_key(c.modeKeys[i]!)}) && !modeKeyLast[$i]) { currentMode = ${i + 1};$transitionCall }
        modeKeyLast[$i] = RcKeyValueRead(${_key(c.modeKeys[i]!)});''',
          ).join('\n        ');
    final directionArgs = List.generate(8, (slot) {
      final role = c.pwm.pinRoles[expansionPins[slot]];
      return role == PinRole.servo ? '1' : 'dutyOfMotor[$slot]>=0';
    }).join(',');
    return '''${_header(c, '工程机器人控制代码', c.pwm.buzzerDisabled)}
uint8_t currentMode = 1;
uint8_t lastSwitch = 0;
uint8_t modeKeyLast[4] = {0};
int mainServoDuty[2] = {${_servoDuty(c.pwm.servoMids['MP03'])}, ${_servoDuty(c.pwm.servoMids['MP74'])}};
$servoButtonDeclarations
$feedback
$prepareMode
$servoButtonSync
$engineerFeedback

${_chassis(c.chassis)}
${modeFunctions.join('\n\n')}

void All_Init(void)
{
    StepBegin(0);
    Board_Init();
    StepDone(0);
    StepBegin(1);
    UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, 230400, TIM1);
    StepDone(1);
    GPIO_Init(LED_PORT, (GPIO_Pin_enum)(LED1_PIN | LED2_PIN | LED3_PIN), GPIO_OUT_PP);
${c.pwm.buzzerDisabled ? '' : '    PWM_Init(BUZZER_CH, 500, 0);'}
    StepBegin(3);
    EA = 0;
    remoteControlInitWithTimeout();
    P2INTE &= ~GPIO_Pin_6;
    EA = 1;
    StepDone(3);
${_pwmInit(c.pwm, usedPins)}
    Ms_Delay(EXPANSION_FRAME_GAP_MS);
${usedPins.where(expansionPins.contains).where((pin) => c.pwm.pinRoles[pin] == PinRole.servo).map((pin) => '    dutyOfMotor[${expansionPins.indexOf(pin)}] = ${_servoDuty(c.pwm.servoMids[pin])};').join('\n')}
    PrepareMode(1);
${c.pwm.buzzerDisabled ? '' : '''    Beep(523, 120);
    Beep(659, 120);
    Beep(784, 120);
    Beep(1047, 240);'''}
}

void main(void)
{
    All_Init();
    while (1) {
        nrf_handler(); // 轮询 NRF 接收（P2.6 中断已关）
        ReadControllerInputs();
        $switchLogic
${servoButtonEdgeActions.isEmpty ? '' : '''        if (servoButtonStateMode != currentMode) {
            SyncServoButtonKeys(currentMode);
            servoButtonStateMode = currentMode;
        }'''}
        switch (currentMode) {
${cases.join('\n')}
        }
        ExpansionBoradControl(Dir_Change_Order, $directionArgs);
        Ms_Delay(EXPANSION_FRAME_GAP_MS);
        ExpansionBoradControl(Duty_Change_Order, abs(dutyOfMotor[0]),abs(dutyOfMotor[1]),abs(dutyOfMotor[2]),abs(dutyOfMotor[3]),abs(dutyOfMotor[4]),abs(dutyOfMotor[5]),abs(dutyOfMotor[6]),abs(dutyOfMotor[7]));
        Ms_Delay(EXPANSION_FRAME_GAP_MS);
${usedPins.contains('MP03') ? '        PWM_SET_Frequency(PWMB_CH4_P03, 50, mainServoDuty[0]);' : ''}
${usedPins.contains('MP74') ? '        PWM_SET_Frequency(PWMB_CH1_P74, 50, mainServoDuty[1]);' : ''}
${engineerFeedback.isEmpty ? '' : '        UpdateServoFeedback();'}
        Ms_Delay(10);
    }
}
''';
  }

  static String _debug(DebugConfig config) {
    String values(int slot, int value) => List.generate(
      8,
      (index) => index == slot ? value.toString() : '0',
    ).join(', ');

    String initValues(int slot, int frequency) {
      final result = List.filled(8, 50);
      final start = slot < 4 ? 0 : 4;
      for (var index = start; index < start + 4; index++) {
        result[index] = frequency;
      }
      return result.join(', ');
    }

    final commands = <String>[];
    final active = config.tests.where((item) => item.enabled).toList();
    // 提示音时值统一从 DebugCues 取，避免固件与 UI 试听两处定义漂移。
    final unitMs = DebugCues.unitMs;
    final gapMs = DebugCues.gapMs;
    final sectionGapMs = DebugCues.sectionGapMs;
    // 拓展板 Init 只用来设定 PWM 组频率（PWMA：P60/P62/P64/P66，PWMB：P74~P77）：
    // 电机 10000Hz，舵机与摩擦轮 50Hz。main() 起始已把两组初始化为 50Hz，
    // 之后只有测试项所需的组频率与当前不同时才重发 Init，不再逐个测试项重复初始化。
    final groupFrequencies = <int>[50, 50];
    for (var index = 0; index < active.length; index++) {
      final item = active[index];
      final direction = item.direction == Direction.forward ? 1 : 0;
      final slot = expansionPins.indexOf(item.pin);
      final friction = item.driveType == DebugDriveType.friction;
      final frequency = friction || item.driveType == DebugDriveType.servo
          ? 50
          : 10000;
      var needInit = false;
      if (slot >= 0) {
        final desired = slot < 4 ? <int>[frequency, 50] : <int>[50, frequency];
        needInit =
            groupFrequencies[0] != desired[0] ||
            groupFrequencies[1] != desired[1];
        if (needInit) {
          groupFrequencies[0] = desired[0];
          groupFrequencies[1] = desired[1];
        }
      }
      final lines = <String>[
        '    /* ${index + 1}. ${item.pin} ${item.driveType!.name} */',
        // 直接播「上行前 N 个音」——个数即序号，不需要先播完整音型做前奏。
        '    StepCue(${index + 1});',
        // 步序区和测试动作之间要有停顿：否则第一声会被动作噪音盖掉，
        // 也让「上行 N 音」和随后的回落分开成两句。
        '    Ms_Delay(CUE_SECTION_GAP_MS);',
        if (needInit)
          '    ExpansionBoradControl(Init_Order, ${initValues(slot, frequency)});',
      ];
      if (slot < 0) {
        final channel = item.pin == 'MP74' ? 'PWMB_CH1_P74' : 'PWMB_CH4_P03';
        final angle = direction == 1 ? item.value! : -item.value!;
        lines
          ..add('    PWM_Init($channel, 50, ${_servoDuty(angle)});')
          ..add('    Ms_Delay(${item.durationMs});')
          ..add('    PWM_SET_Frequency($channel, 50, 0);');
      } else if (friction) {
        // 摩擦轮方向固定，测试期间不发送方向帧；只设一个目标：
        // 测试项里配的就是**目标占空比**本身（500~800），不再经过油门换算，
        // 斜坡逐周期逼近到目标即“斜坡结束”；停留观察后再设目标 0 停机。
        final targetDuty = item.value!;
        lines
          ..add('    Ms_Delay(1000);')
          ..add('    FrictionActivate($slot);')
          ..add('    FrictionRampTo($slot, $targetDuty);')
          ..add('    Ms_Delay(FRICTION_STEP_MS);')
          ..add('    FrictionRampTo($slot, 0);');
      } else {
        final servo = item.driveType == DebugDriveType.servo;
        final duty = servo
            ? _servoDuty(direction == 1 ? item.value! : -item.value!)
            : item.value!;
        if (needInit) lines.add('    Ms_Delay(20);');
        if (!servo) {
          lines
            ..add(
              '    ExpansionBoradControl(Dir_Change_Order, ${values(slot, direction)});',
            )
            ..add('    Ms_Delay(EXPANSION_FRAME_GAP_MS);');
        }
        lines
          ..add(
            '    ExpansionBoradControl(Duty_Change_Order, ${values(slot, duty)});',
          )
          ..add('    Ms_Delay(${item.durationMs});')
          ..add(
            '    ExpansionBoradControl(Duty_Change_Order, ${values(slot, 0)});',
          );
      }
      // 每个测试项之后都留同样的间隔（含最后一项）：最后一项之后的这一秒
      // 就是循环边界，让「回到第 1 项」和普通的项间切换听感一致。
      lines.add('    Ms_Delay(TEST_GAP_MS);');
      commands.add(lines.join('\n'));
    }

    // 测试项整体缩进一层：它们已经是 while (1) 循环体的一部分。
    final loopBody = commands
        .map(
          (command) =>
              command.split('\n').map((line) => '    $line').join('\n'),
        )
        .join('\n\n');

    return '''// 调试测试代码（由 PIE-Block Flutter 配置器自动生成）
#include "main.h"

/* 提示音方案（详见 docs/design/调试模式提示音方案.md）：
   步序用一条上行音型 C6-E6-G6-C7-E7 的前 N 个音表示第 N 项
   （个数即序号，不单独播一遍完整音型做前奏，也没有结束区的回落乐句）。
   音区（八度）负责进位：项 1~5 低八度，项 6 起高八度。
   整段测试序列放在 while (1) 里循环执行：跑完最后一项自动回到第 1 项，
   没有「全部完成」的收尾旋律。 */
uint8_t Channal = 36;
#define BUZZER_CH PWMA_CH4N_P33
#define BUZZER_DUTY_ON 5000
/* 静音占位频率：占空比为 0，频率取值不影响是否有声 */
#define BUZZER_IDLE_FREQ 500
/* 音高：十二平均律，A4 = 440Hz */
#define CUE_C5 ${DebugCues.noteC5}
#define CUE_E5 ${DebugCues.noteE5}
#define CUE_G5 ${DebugCues.noteG5}
#define CUE_C6 ${DebugCues.noteC6}
#define CUE_E6 ${DebugCues.noteE6}
#define CUE_G6 ${DebugCues.noteG6}
#define CUE_C7 ${DebugCues.noteC7}
#define CUE_E7 ${DebugCues.noteE7}
/* 上行音型：C6-E6-G6-C7-E7。步序用它的前 N 个音表示第 N 项（个数即序号），
   音型本身不单独播放。 */
#define CUE_MOTIF_LEN ${DebugCues.zoneSpan}
/* 步序码：八度音区进位（项 1~5 低八度，项 6 起高八度） */
#define CUE_ZONE_SPAN ${DebugCues.zoneSpan}
#define CUE_UNIT_MS $unitMs
#define CUE_GAP_MS $gapMs
/* 分区停顿：步序音与随后的测试动作之间的静默，
   必须明显长于 CUE_GAP_MS，否则动作噪音会盖掉步序音。 */
#define CUE_SECTION_GAP_MS $sectionGapMs
/* 项间与循环边界的静默：跑完最后一项后同样等这么久再回到第 1 项。 */
#define TEST_GAP_MS 1000
#define FRICTION_STEP_MS 1500
#define FRICTION_START_DUTY 500
#define FRICTION_STEP_DUTY 1
#define FRICTION_RAMP_CYCLE_MS 20
#define FRICTION_ACTIVATE_MS 1000
#define EXPANSION_FRAME_GAP_MS 5
#define COMM_HEADER_1 0xAB
#define COMM_HEADER_2 0xBC
#define COMM_END_1 0xCD
#define COMM_END_2 0xDE
#define Init_Order 0xAA
#define Duty_Change_Order 0xBB
#define Dir_Change_Order 0xDD

static uint8_t control_frame_pack[21];

$_uart1TxQuery
static void Beep(uint16_t frequency, uint16_t duration)
{
    PWM_SET_Frequency(BUZZER_CH, frequency, BUZZER_DUTY_ON);
    Ms_Delay(duration);
    PWM_SET_Frequency(BUZZER_CH, frequency, 0);
}

/* 上行音型第 index 个音（index 从 0 开始），high 为真时整体升八度。
   用 switch 而不是数组变址：SDCC 对 "数组 + 变址" 的写法有已知取错字节的
   问题（见 ExpansionBoradControl 里的注释），能避开就避开。 */
static uint16_t MotifNote(uint8_t index, uint8_t high)
{
    uint16_t octave = high ? 2 : 1;

    switch (index)
    {
    case 0: return (uint16_t)(CUE_C6 * octave);
    case 1: return (uint16_t)(CUE_E6 * octave);
    case 2: return (uint16_t)(CUE_G6 * octave);
    case 3: return (uint16_t)(CUE_C7 * octave);
    default: return (uint16_t)(CUE_E7 * octave);
    }
}

/* 步序提示：用上行音型的前 count 个音表示第 count 项——**个数即序号**，
   所以不需要先播一遍完整音型做前奏，也没有结束区的回落乐句。
   音区（八度）负责进位：项 1~5 用低八度那组，项 6 起换高八度那组。 */
static void StepCue(uint8_t step)
{
    uint8_t zone;
    uint8_t count;
    uint8_t i;

    zone = (uint8_t)((step - 1) / CUE_ZONE_SPAN);
    count = (uint8_t)((step - 1) % CUE_ZONE_SPAN + 1);
    for (i = 0; i < count; i++)
    {
        Beep(MotifNote(i, zone), CUE_UNIT_MS);
        if (i + 1 < count)
            Ms_Delay(CUE_GAP_MS);
    }
}

static void ExpansionBoradControl(uint8_t command,
    uint16_t p60, uint16_t p62, uint16_t p64, uint16_t p66,
    uint16_t p74, uint16_t p75, uint16_t p76, uint16_t p77)
{
    uint8_t i;
    control_frame_pack[0] = COMM_HEADER_1;
    control_frame_pack[1] = COMM_HEADER_2;
    control_frame_pack[2] = command;
    /* 逐字展开落帧，与《RM电控指南》的参考实现一致：SDCC 对
       "values[] 数组 + 3+i*2 变址" 的写法会取错字节（低字节位置被写成高字节，
       即 10000 发成 0x2727、500 发成 0x0101），这里直接从形参取高/低字节。 */
    control_frame_pack[3] = (uint8_t)((p60 >> 8) & 0xFF);
    control_frame_pack[4] = (uint8_t)(p60 & 0xFF);
    control_frame_pack[5] = (uint8_t)((p62 >> 8) & 0xFF);
    control_frame_pack[6] = (uint8_t)(p62 & 0xFF);
    control_frame_pack[7] = (uint8_t)((p64 >> 8) & 0xFF);
    control_frame_pack[8] = (uint8_t)(p64 & 0xFF);
    control_frame_pack[9] = (uint8_t)((p66 >> 8) & 0xFF);
    control_frame_pack[10] = (uint8_t)(p66 & 0xFF);
    control_frame_pack[11] = (uint8_t)((p74 >> 8) & 0xFF);
    control_frame_pack[12] = (uint8_t)(p74 & 0xFF);
    control_frame_pack[13] = (uint8_t)((p75 >> 8) & 0xFF);
    control_frame_pack[14] = (uint8_t)(p75 & 0xFF);
    control_frame_pack[15] = (uint8_t)((p76 >> 8) & 0xFF);
    control_frame_pack[16] = (uint8_t)(p76 & 0xFF);
    control_frame_pack[17] = (uint8_t)((p77 >> 8) & 0xFF);
    control_frame_pack[18] = (uint8_t)(p77 & 0xFF);
    control_frame_pack[19] = COMM_END_1;
    control_frame_pack[20] = COMM_END_2;
    for (i = 0; i < 21; i++) {
        Uart1TxQuery(control_frame_pack[i]);
    }
}

static uint16_t frictionDuty = 0;

/* 只改当前测试那个脚的占空比，其余脚维持 0。按脚展开写，避免 SDCC 在
   "values[] + 变址" 上取错字节。 */
static void FrictionSendDuty(uint8_t slot, uint16_t duty)
{
    switch (slot) {
    case 0: ExpansionBoradControl(Duty_Change_Order, duty, 0, 0, 0, 0, 0, 0, 0); break;
    case 1: ExpansionBoradControl(Duty_Change_Order, 0, duty, 0, 0, 0, 0, 0, 0); break;
    case 2: ExpansionBoradControl(Duty_Change_Order, 0, 0, duty, 0, 0, 0, 0, 0); break;
    case 3: ExpansionBoradControl(Duty_Change_Order, 0, 0, 0, duty, 0, 0, 0, 0); break;
    case 4: ExpansionBoradControl(Duty_Change_Order, 0, 0, 0, 0, duty, 0, 0, 0); break;
    case 5: ExpansionBoradControl(Duty_Change_Order, 0, 0, 0, 0, 0, duty, 0, 0); break;
    case 6: ExpansionBoradControl(Duty_Change_Order, 0, 0, 0, 0, 0, 0, duty, 0); break;
    default: ExpansionBoradControl(Duty_Change_Order, 0, 0, 0, 0, 0, 0, 0, duty); break;
    }
}

/* 摩擦轮激活：给 500 启动占空比并保持 FRICTION_ACTIVATE_MS 让电调完成激活；
   这段激活时间不发蜂鸣。 */
static void FrictionActivate(uint8_t slot)
{
    frictionDuty = FRICTION_START_DUTY;
    FrictionSendDuty(slot, frictionDuty);
    PWM_SET_Frequency(BUZZER_CH, BUZZER_IDLE_FREQ, 0);
    Ms_Delay(FRICTION_ACTIVATE_MS);
}

/* 摩擦轮斜坡控制与步兵项目同律：静止先跳到启动占空比，其余每周期
   ±FRICTION_STEP_DUTY 渐变；目标为 0 且已降到启动占空比及以下直接停机。
   渐变期间蜂鸣频率等于当前占空比，启动爬升即为上行扫频。 */
static void FrictionRampTo(uint8_t slot, uint16_t target)
{
    while (frictionDuty != target) {
        if (target >= FRICTION_START_DUTY && frictionDuty < FRICTION_START_DUTY)
            frictionDuty = FRICTION_START_DUTY;
        else if (frictionDuty < target)
            frictionDuty += FRICTION_STEP_DUTY;
        else if (target == 0 && frictionDuty <= FRICTION_START_DUTY)
            frictionDuty = 0;
        else
            frictionDuty -= FRICTION_STEP_DUTY;
        FrictionSendDuty(slot, frictionDuty);
        if (frictionDuty)
            PWM_SET_Frequency(BUZZER_CH, frictionDuty, 5000);
        else
            PWM_SET_Frequency(BUZZER_CH, BUZZER_IDLE_FREQ, 0);
        Ms_Delay(FRICTION_RAMP_CYCLE_MS);
    }
}

void main(void)
{
    Board_Init();
    UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, 230400, TIM1);
    PWM_Init(BUZZER_CH, BUZZER_IDLE_FREQ, 0);

    /* 整段测试序列循环执行：跑完最后一项自动回到第 1 项。 */
    while (1)
    {
        /* 每轮开头先把两组 PWM 复位到 main 起始的 50Hz。逐项那条 Init 是
           生成期按「上一项之后」的静态状态决定要不要发的，只有每轮都从
           同一个状态起步，这条静态判断在第二轮及以后才继续成立。 */
        ExpansionBoradControl(Init_Order, 50, 50, 50, 50, 50, 50, 50, 50);
        Ms_Delay(20);

$loopBody

        /* 一轮结束：八路输出全部归零，随后回到第 1 项。 */
        ExpansionBoradControl(Duty_Change_Order, 0, 0, 0, 0, 0, 0, 0, 0);
    }
}
''';
  }

  static String _music(MusicConfig config) {
    final segments = MusicTimeline.segments(config);
    final staffSong = buildStaffSong(config);
    final frequencies = List.generate(128, (note) {
      if (note == 0) return 1000;
      return (440 * math.pow(2, (note - 69) / 12)).round();
    });
    final frequencyRows = <String>[];
    for (var row = 0; row < 16; row++) {
      frequencyRows.add(
        '    ${frequencies.skip(row * 8).take(8).join(', ')}${row < 15 ? ',' : ''}',
      );
    }
    final segmentRows = segments
        .map(
          (segment) => '    {${segment.durationMs}UL, ${segment.pitch ?? 0}},',
        )
        .join('\n');
    final staffTables = emitStaffFirmwareTables(staffSong, prefix: 'staff');
    return '''// MIDI 单音音乐代码（由 PIE-Block Flutter 配置器自动生成）
// SDCC 构建额外带 128x64 五线谱滚动显示；Keil 构建保持只播放。
#include "main.h"

// 步兵 Keil 模板仍链接 nrf24l01.c，保留其所需的通道符号。
uint8_t Channal = 36;
#define MUSIC_BUZZER_CH PWMB_CH3_P33
#define MUSIC_DUTY_ON 5000
#define MUSIC_DUTY_OFF 0

static const uint16_t musicFrequencies[128] =
{
${frequencyRows.join('\n')}
};

static void Music_Stop(void)
{
    PWM_SET_Frequency(MUSIC_BUZZER_CH, 1000, MUSIC_DUTY_OFF);
}

#if defined(__SDCC)
/* 五线谱显示：事件/调号/拍号/字形点阵全部由配置预计算，渲染在固件里完成。 */
#include "OLED_Staff.h"
#include "MusicClock.h"

$staffTables

static void Music_PlayOnce(void)
{
    uint16_t i;
    MusicClock_Reset();
    for (i = 0; i < STAFF_EVENT_COUNT; i++)
    {
        MusicClock_WaitDeadline();
        if (staffPitches[i] == 0)
            Music_Stop();
        else
            PWM_SET_Frequency(MUSIC_BUZZER_CH,
                musicFrequencies[staffPitches[i]], MUSIC_DUTY_ON);
        OLEDStaff_Show(&staffSong, i);
        MusicClock_Advance(staffDurationsMs[i]);
    }
    MusicClock_WaitDeadline();
    Music_Stop();
}
#else
/* Keil 构建：没有 OLED 五线谱显示，保持原来的蜂鸣器播放行为。 */
typedef struct
{
    uint32_t duration_ms;
    uint8_t note;
} MusicSegment;

static const MusicSegment musicSegments[${segments.length}] =
{
$segmentRows
};
#define MUSIC_SEGMENT_COUNT ${segments.length}

static void Music_Wait(uint32_t duration_ms)
{
    while (duration_ms > 65535UL)
    {
        Ms_Delay((uint16_t)65535);
        duration_ms -= 65535UL;
    }
    if (duration_ms > 0UL)
        Ms_Delay((uint16_t)duration_ms);
}

static void Music_PlayOnce(void)
{
    uint16_t i;
    for (i = 0; i < MUSIC_SEGMENT_COUNT; i++)
    {
        if (musicSegments[i].note == 0)
            Music_Stop();
        else
            PWM_SET_Frequency(MUSIC_BUZZER_CH,
                musicFrequencies[musicSegments[i].note], MUSIC_DUTY_ON);
        Music_Wait(musicSegments[i].duration_ms);
    }
    Music_Stop();
}
#endif

static void All_Init(void)
{
    Board_Init();
    PWM_Init(MUSIC_BUZZER_CH, 1000, MUSIC_DUTY_OFF);
    Music_Stop();
#if defined(__SDCC)
    MusicClock_Init();
    OLEDStaff_Init();
#endif
}

void main(void)
{
    All_Init();
    while (1)
        Music_PlayOnce();
}
''';
  }
}
