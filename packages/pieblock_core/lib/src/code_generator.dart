import 'dart:math' as math;

import 'models.dart';
import 'music.dart';
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
    uint16_t values[8];
    values[0] = p60; values[1] = p62; values[2] = p64; values[3] = p66;
    values[4] = p74; values[5] = p75; values[6] = p76; values[7] = p77;
    control_frame_pack[0] = COMM_HEADER_1;
    control_frame_pack[1] = COMM_HEADER_2;
    control_frame_pack[2] = command;
    for (i = 0; i < 8; i++) {
        control_frame_pack[3 + i * 2] = (uint8_t)(values[i] >> 8);
        control_frame_pack[4 + i * 2] = (uint8_t)(values[i] & 0xff);
    }
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
    baseSpeed = (int)(((int32_t)valueOfRoker[0][1] * (int32_t)speed) / 2047L);
    turnSpeed = (int)(((int32_t)valueOfRoker[0][0] * (int32_t)speed) / 2047L);
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
    final yawDuty = _servoDuty(c.yawMidOffset),
        pitchDuty = _servoDuty(c.pitchMidOffset),
        feederSlot = _slot(c.feederPin);
    String axisUpdate({required bool yaw}) {
      final drive = yaw ? c.yawDrive : c.pitchDrive,
          pin = yaw ? c.yawPin : c.pitchPin,
          direction = yaw ? c.yawDirection : c.pitchDirection,
          rocker = yaw ? 'valueOfRoker[1][0]' : 'valueOfRoker[1][1]',
          variable = yaw ? 'yawDuty' : 'pitchDuty';
      if (drive == DriveType.servo) {
        final home = yaw ? yawDuty : pitchDuty;
        final low = (home - 333).clamp(250, 1250);
        final high = (home + 333).clamp(250, 1250);
        return '''    $variable += (int)((float)$rocker * 2.0f / 2047.0f * 5.555556f);
    if ($variable < $low) $variable = $low; if ($variable > $high) $variable = $high;''';
      }
      final sign = direction == Direction.forward ? '' : '-';
      return '    dutyOfMotor[${_slot(pin)}] = $sign(int)(((int32_t)$rocker * 10000L) / 2047L);';
    }

    String dutyValue(int index) {
      if (frictionEnabled && (index == 2 || index == 3)) {
        return 'frictionDuty';
      }
      if (c.yawDrive == DriveType.servo && _slot(c.yawPin) == index) {
        return 'yawDuty';
      }
      if (c.pitchDrive == DriveType.servo && _slot(c.pitchPin) == index) {
        return 'pitchDuty';
      }
      return 'abs(dutyOfMotor[$index])';
    }

    String directionValue(int index) {
      if (frictionEnabled && (index == 2 || index == 3) ||
          c.yawDrive == DriveType.servo && _slot(c.yawPin) == index ||
          c.pitchDrive == DriveType.servo && _slot(c.pitchPin) == index) {
        return '1';
      }
      return 'dutyOfMotor[$index]>=0';
    }

    final dutyArgs = List.generate(8, dutyValue).join(','),
        directionArgs = List.generate(8, directionValue).join(','),
        mainServoInit = <String>[],
        mainServoUpdates = <String>[];
    if (c.yawDrive == DriveType.servo && mainServoPins.contains(c.yawPin)) {
      final channel = c.yawPin == 'MP74' ? '1_P74' : '4_P03';
      mainServoInit.add('    PWM_Init(PWMB_CH$channel, 50, $yawDuty);');
      mainServoUpdates.add(
        '        PWM_SET_Frequency(PWMB_CH$channel, 50, yawDuty);',
      );
    }
    if (c.pitchDrive == DriveType.servo && mainServoPins.contains(c.pitchPin)) {
      final channel = c.pitchPin == 'MP74' ? '1_P74' : '4_P03';
      mainServoInit.add('    PWM_Init(PWMB_CH$channel, 50, $pitchDuty);');
      mainServoUpdates.add(
        '        PWM_SET_Frequency(PWMB_CH$channel, 50, pitchDuty);',
      );
    }
    final frictionDefines = frictionEnabled
        ? '''#define FRICTION_START_DUTY 500
#define FRICTION_STEP_DUTY 1
#define FRICTION_MAX_DUTY ${c.frictionMaxDuty!}
#define FRICTION_SPEED_STEP ${c.frictionStep!}
'''
        : '';
    final frictionGlobals = frictionEnabled
        ? '''uint16_t frictionDuty = 0;
uint16_t frictionTargetDuty = 0;
uint8_t frictionEnabled = 0;
'''
        : '';
    final frictionUpdate = frictionEnabled
        ? '''    static uint8_t lastFriction = 0;
    static uint8_t lastFrictionUp = 0;
    static uint8_t lastFrictionDown = 0;
    uint8_t friction = RcKeyValueRead(${_key(c.frictionKey!)});
    uint8_t frictionUp = RcKeyValueRead(${_key(c.frictionUpKey!)});
    uint8_t frictionDown = RcKeyValueRead(${_key(c.frictionDownKey!)});
    if (friction && !lastFriction) {
        frictionEnabled = !frictionEnabled;
        frictionTargetDuty = frictionEnabled ? FRICTION_MAX_DUTY : 0;
    }
    if (frictionEnabled && frictionUp && !lastFrictionUp && !frictionDown) {
        frictionTargetDuty += FRICTION_SPEED_STEP;
        if (frictionTargetDuty > FRICTION_MAX_DUTY) frictionTargetDuty = FRICTION_MAX_DUTY;
    }
    if (frictionEnabled && frictionDown && !lastFrictionDown && !frictionUp) {
        if (frictionTargetDuty > FRICTION_START_DUTY + FRICTION_SPEED_STEP)
            frictionTargetDuty -= FRICTION_SPEED_STEP;
        else frictionTargetDuty = FRICTION_START_DUTY;
    }
    /* 指南：启停时 0~5% 区间可以跳过（电机 5% 才起转），
       因此 frictionDuty 只取 0 或 500~上限，中间的 0~500 一律跳变。 */
    if (frictionTargetDuty >= FRICTION_START_DUTY && frictionDuty < FRICTION_START_DUTY)
        frictionDuty = FRICTION_START_DUTY;
    else if (frictionDuty < frictionTargetDuty)
        frictionDuty += FRICTION_STEP_DUTY;
    else if (frictionDuty > frictionTargetDuty) {
        if (frictionTargetDuty == 0 && frictionDuty <= FRICTION_START_DUTY)
            frictionDuty = 0;
        else
            frictionDuty -= FRICTION_STEP_DUTY;
    }
    lastFriction = friction;
    lastFrictionUp = frictionUp;
    lastFrictionDown = frictionDown;
'''
        : '';
    final feedUpdate = c.feedMode == FeedMode.visualClosedLoop
        ? '''    dutyOfMotor[$feederSlot] = trigger ? ${_dir(c.feederDirection!) == 1 ? '' : '-'}${c.triggerSpeed!} : 0;
'''
        : '''    if (trigger && !lastTrigger) {
        dutyOfMotor[$feederSlot] = ${_dir(c.feederDirection!) == 1 ? '' : '-'}${c.triggerSpeed!};
        ExpansionBoradControl(Duty_Change_Order, $dutyArgs);
        Ms_Delay(${c.triggerTimeMs!});
        dutyOfMotor[$feederSlot] = 0;
    }
''';
    final arrowUpdate = switch (c.arrowBehavior) {
      ArrowBehavior.move =>
        '''        if (RcKeyValueRead(KEY_OFFSET_UP)) valueOfRoker[0][1] = 2047;
        if (RcKeyValueRead(KEY_OFFSET_DOWN)) valueOfRoker[0][1] = -2047;
        if (RcKeyValueRead(KEY_OFFSET_LEFT)) valueOfRoker[0][0] = -2047;
        if (RcKeyValueRead(KEY_OFFSET_RIGHT)) valueOfRoker[0][0] = 2047;
''',
      ArrowBehavior.sprint =>
        '''        maxSpeed = ${c.chassis.normalSpeed!};
        if (RcKeyValueRead(KEY_OFFSET_UP)) { valueOfRoker[0][1] = 2047; maxSpeed = ultraSpeed; }
        if (RcKeyValueRead(KEY_OFFSET_DOWN)) { valueOfRoker[0][1] = -2047; maxSpeed = ultraSpeed; }
        if (RcKeyValueRead(KEY_OFFSET_LEFT)) { valueOfRoker[0][0] = -2047; maxSpeed = ultraSpeed; }
        if (RcKeyValueRead(KEY_OFFSET_RIGHT)) { valueOfRoker[0][0] = 2047; maxSpeed = ultraSpeed; }
''',
      ArrowBehavior.other => '',
      null => '',
    };
    final servoDuties = <String>[
      if (c.yawDrive == DriveType.servo) 'yawDuty',
      if (c.pitchDrive == DriveType.servo) 'pitchDuty',
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
${frictionEnabled ? '    else if (frictionDuty != frictionTargetDuty) PWM_SET_Frequency(BUZZER_CH, frictionDuty, 5000);' : ''}
    else PWM_SET_Frequency(BUZZER_CH, 500, 0);
}
''';
    return '''${_header(c, '步兵机器人控制代码', c.buzzerDisabled)}
$frictionDefines
uint16_t yawDuty = $yawDuty;
uint16_t pitchDuty = $pitchDuty;
$frictionGlobals
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
${axisUpdate(yaw: true)}
${axisUpdate(yaw: false)}
    ${c.zeroEnabled ? 'if (RcKeyValueRead(KEY_OFFSET_Rocker21)) { yawDuty = $yawDuty; pitchDuty = $pitchDuty; }' : ''}
}

void UpdateWeapons(void)
{
    static uint8_t lastTrigger = 0;
    uint8_t trigger = RcKeyValueRead(${_key(c.triggerKey!)});
$frictionUpdate$feedUpdate
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
        final isServoButton = digitalRemoteKeys.contains(action.key) &&
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
                final edgeIndex =
                    servoButtonEdgeIndexes['$i:$actionIndex']!;
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
    final servoButtonDeclarations = '''${servoButtonRemainderActions.isEmpty ? '' : 'int32_t servoButtonRemainder[${servoButtonRemainderActions.length}] = {0};'}
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
                lines.add(
                  '            servoButtonKeyLast[$index] = RcKeyValueRead(${_key(entry.action.key!)});',
                );
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
    for (var index = 0; index < active.length; index++) {
      final item = active[index];
      final direction = item.direction == Direction.forward ? 1 : 0;
      final slot = expansionPins.indexOf(item.pin);
      final lines = <String>[
        '    /* ${index + 1}. ${item.pin} ${item.driveType!.name} */',
        '    Beep(BUZZER_FREQ_READY, 200);',
        '    Ms_Delay(200);',
      ];
      if (slot < 0) {
        final channel = item.pin == 'MP74' ? 'PWMB_CH1_P74' : 'PWMB_CH4_P03';
        final angle = direction == 1 ? item.value! : -item.value!;
        lines
          ..add('    PWM_Init($channel, 50, ${_servoDuty(angle)});')
          ..add('    Ms_Delay(${item.durationMs});')
          ..add('    PWM_SET_Frequency($channel, 50, 0);');
      } else if (item.driveType == DebugDriveType.friction) {
        final up = <int>[500];
        while (up.last < item.value!) {
          up.add((up.last + 100).clamp(500, item.value!));
        }
        final curve = <int>[...up, ...up.reversed.skip(1), 0];
        lines
          ..add(
            '    ExpansionBoradControl(Init_Order, ${initValues(slot, 50)});',
          )
          ..add('    Ms_Delay(1000);');
        for (final duty in curve) {
          lines
            ..add(
              '    ExpansionBoradControl(Duty_Change_Order, ${values(slot, duty)});',
            )
            ..add('    Ms_Delay(FRICTION_STEP_MS);');
        }
      } else {
        final servo = item.driveType == DebugDriveType.servo;
        final duty = servo
            ? _servoDuty(direction == 1 ? item.value! : -item.value!)
            : item.value!;
        lines
          ..add(
            '    ExpansionBoradControl(Init_Order, ${initValues(slot, servo ? 50 : 10000)});',
          )
          ..add('    Ms_Delay(20);');
        if (!servo) {
          lines
            ..add(
              '    ExpansionBoradControl(Dir_Change_Order, ${values(slot, direction)});',
            )
            ..add('    Ms_Delay(5);');
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
      lines.add('    Beep(BUZZER_FREQ_DONE, 200);');
      if (index < active.length - 1) lines.add('    Ms_Delay(TEST_GAP_MS);');
      commands.add(lines.join('\n'));
    }

    return '''// 调试测试代码（由 PIE-Block Flutter 配置器自动生成）
#include "main.h"

uint8_t Channal = 36;
#define BUZZER_CH PWMA_CH4N_P33
#define BUZZER_FREQ_READY 500
#define BUZZER_FREQ_DONE 700
#define TEST_GAP_MS 1000
#define FRICTION_STEP_MS 1500
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
    PWM_SET_Frequency(BUZZER_CH, frequency, 5000);
    Ms_Delay(duration);
    PWM_SET_Frequency(BUZZER_CH, frequency, 0);
}

static void ExpansionBoradControl(uint8_t command,
    uint16_t p60, uint16_t p62, uint16_t p64, uint16_t p66,
    uint16_t p74, uint16_t p75, uint16_t p76, uint16_t p77)
{
    uint8_t i;
    uint16_t values[8];
    values[0] = p60; values[1] = p62; values[2] = p64; values[3] = p66;
    values[4] = p74; values[5] = p75; values[6] = p76; values[7] = p77;
    control_frame_pack[0] = COMM_HEADER_1;
    control_frame_pack[1] = COMM_HEADER_2;
    control_frame_pack[2] = command;
    for (i = 0; i < 8; i++) {
        control_frame_pack[3 + i * 2] = (uint8_t)(values[i] >> 8);
        control_frame_pack[4 + i * 2] = (uint8_t)(values[i] & 0xff);
    }
    control_frame_pack[19] = COMM_END_1;
    control_frame_pack[20] = COMM_END_2;
    for (i = 0; i < 21; i++) {
        Uart1TxQuery(control_frame_pack[i]);
    }
}

void main(void)
{
    Board_Init();
    UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, 230400, TIM1);
    PWM_Init(BUZZER_CH, BUZZER_FREQ_READY, 0);
    ExpansionBoradControl(Init_Order, 50, 50, 50, 50, 50, 50, 50, 50);
    Ms_Delay(20);

${commands.join('\n\n')}

    ExpansionBoradControl(Duty_Change_Order, 0, 0, 0, 0, 0, 0, 0, 0);
    while (1) {
        Beep(BUZZER_FREQ_DONE, 500);
        Ms_Delay(2000);
    }
}
''';
  }

  static String _music(MusicConfig config) {
    final segments = MusicTimeline.segments(config);
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
    return '''// MIDI 单音音乐代码（由 PIE-Block Flutter 配置器自动生成）
#include "main.h"

// 步兵 Keil 模板仍链接 nrf24l01.c，保留其所需的通道符号。
uint8_t Channal = 36;
#define MUSIC_BUZZER_CH PWMB_CH3_P33
#define MUSIC_DUTY_ON 5000
#define MUSIC_DUTY_OFF 0

typedef struct
{
    uint32_t duration_ms;
    uint8_t note;
} MusicSegment;

static const uint16_t musicFrequencies[128] =
{
${frequencyRows.join('\n')}
};

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

static void Music_Stop(void)
{
    PWM_SET_Frequency(MUSIC_BUZZER_CH, 1000, MUSIC_DUTY_OFF);
}

static void Music_PlaySegment(const MusicSegment *segment)
{
    if (segment->note == 0)
        Music_Stop();
    else
        PWM_SET_Frequency(MUSIC_BUZZER_CH,
            musicFrequencies[segment->note], MUSIC_DUTY_ON);
    Music_Wait(segment->duration_ms);
}

static void Music_PlayOnce(void)
{
    uint16_t i;
    for (i = 0; i < MUSIC_SEGMENT_COUNT; i++)
        Music_PlaySegment(&musicSegments[i]);
    Music_Stop();
}

static void All_Init(void)
{
    Board_Init();
    PWM_Init(MUSIC_BUZZER_CH, 1000, MUSIC_DUTY_OFF);
    Music_Stop();
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
