import 'models.dart';

abstract final class CodeGenerator {
  static String generate(RobotConfig config) => switch (config) {
    InfantryConfig value => _infantry(value),
    EngineerConfig value => _engineer(value),
  };

  static int _dir(Direction value) => value == Direction.forward ? 1 : 0;
  static int _frequency(PwmFrequency value) =>
      value == PwmFrequency.hz50 ? 50 : 10000;
  static int _servoDuty(int? degrees) =>
      (750 + ((degrees ?? 0) * 1000 / 180)).round().clamp(250, 1250);
  static String _key(String key) =>
      'KEY_OFFSET_${key.replaceAll('UP', 'UP').replaceAll('DOWN', 'DOWN').replaceAll('LEFT', 'LEFT').replaceAll('RIGHT', 'RIGHT')}';

  static String _header(RobotConfig c, String title) =>
      '''// $title（由 Pie-Block Flutter 配置器自动生成）
#include "main.h"
#include "MATH.H"

uint8_t Channal = ${c.remote.channel ?? 36};
uint16_t maxSpeed = ${c.chassis.normalSpeed ?? 4000};
uint16_t ultraSpeed = ${c.chassis.sprintSpeed ?? 8000};
uint16_t deadBandOfLeft = ${c.remote.deadzone ?? 10};
uint16_t deadBandOfRight = ${c.remote.deadzone ?? 10};

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

void ExpansionBoradControl(uint8_t command,
    uint16_t p60, uint16_t p62, uint16_t p64, uint16_t p66,
    uint16_t p74, uint16_t p75, uint16_t p76, uint16_t p77)
{
    uint8_t i;
    uint16_t values[8] = {p60,p62,p64,p66,p74,p75,p76,p77};
    control_frame_pack[0] = COMM_HEADER_1;
    control_frame_pack[1] = COMM_HEADER_2;
    control_frame_pack[2] = command;
    for (i = 0; i < 8; i++) {
        control_frame_pack[3 + i * 2] = (uint8_t)(values[i] >> 8);
        control_frame_pack[4 + i * 2] = (uint8_t)(values[i] & 0xff);
    }
    control_frame_pack[19] = COMM_END_1;
    control_frame_pack[20] = COMM_END_2;
    for (i = 0; i < 21; i++) UART_PutChar(UART_1, control_frame_pack[i]);
}

void ReadControllerInputs(void)
{
    valueOfRoker[0][0] = RcRockerValueRead(ROCKER_LEFT_HORIZONTAL);
    valueOfRoker[0][1] = RcRockerValueRead(ROCKER_LEFT_VERTICAL);
    valueOfRoker[1][0] = RcRockerValueRead(ROCKER_RIGHT_HORIZONTAL);
    valueOfRoker[1][1] = RcRockerValueRead(ROCKER_RIGHT_VERTICAL);
}
''';

  static String _chassis(ChassisConfig c) {
    final sprint = c.sprintEnabled
        ? '''
    if (RcKeyValueRead(KEY_OFFSET_Rocker11)) speed = ultraSpeed;
'''
        : '';
    return '''
void CalculateChassis(void)
{
    int speed = maxSpeed;
    int baseSpeed;
    int turnSpeed;$sprint
    baseSpeed = (int)((float)valueOfRoker[0][1] * speed / 2047);
    turnSpeed = (int)((float)valueOfRoker[0][0] * speed / 2047);
    dutyOfMotor[4] = ${_dir(c.leftFront.direction) == 1 ? '' : '-'}baseSpeed ${_dir(c.leftFront.direction) == 1 ? '-' : '+'} turnSpeed;
    dutyOfMotor[5] = ${_dir(c.leftRear.direction) == 1 ? '' : '-'}baseSpeed ${_dir(c.leftRear.direction) == 1 ? '-' : '+'} turnSpeed;
    dutyOfMotor[6] = ${_dir(c.rightFront.direction) == 1 ? '-' : ''}baseSpeed ${_dir(c.rightFront.direction) == 1 ? '-' : '+'} turnSpeed;
    dutyOfMotor[7] = ${_dir(c.rightRear.direction) == 1 ? '-' : ''}baseSpeed ${_dir(c.rightRear.direction) == 1 ? '-' : '+'} turnSpeed;
}
''';
  }

  static String _pwmInit(PwmGroupConfig pwm) {
    final lines = <String>[
      '    ExpansionBoradControl(Init_Order, ${List.filled(4, _frequency(pwm.pwma)).join(', ')}, ${List.filled(4, _frequency(pwm.pwmb)).join(', ')});',
    ];
    for (final pin in mainServoPins) {
      lines.add(
        '    PWM_Init(PWMB_CH${pin == 'MP74' ? '1_P74' : '4_P03'}, 50, ${_servoDuty(pwm.servoMids[pin])});',
      );
    }
    return lines.join('\n');
  }

  static String _infantry(InfantryConfig c) {
    final yawDuty = _servoDuty(c.yawMidOffset),
        pitchDuty = _servoDuty(c.pitchMidOffset);
    return '''${_header(c, '步兵机器人控制代码')}
#define FRICTION_START_DUTY 500
#define FRICTION_MAX_DUTY ${c.frictionMaxDuty ?? 800}
#define FRICTION_SPEED_STEP ${c.frictionStep ?? 100}
uint16_t yawDuty = $yawDuty;
uint16_t pitchDuty = $pitchDuty;
uint16_t frictionDuty = 0;
uint8_t frictionEnabled = 0;

${_chassis(c.chassis)}
void All_Init(void)
{
    Board_Init();
    UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, 230400, TIM1);
    NRF24L01_Init();
${_pwmInit(c.pwm)}
    Ms_Delay(1000);
}

void UpdateGimbal(void)
{
    yawDuty += (int)((float)valueOfRoker[1][0] * 2.0f / 2047.0f * 5.555556f);
    pitchDuty += (int)((float)valueOfRoker[1][1] * 2.0f / 2047.0f * 5.555556f);
    if (yawDuty < 250) yawDuty = 250; if (yawDuty > 1250) yawDuty = 1250;
    if (pitchDuty < 250) pitchDuty = 250; if (pitchDuty > 1250) pitchDuty = 1250;
    ${c.zeroEnabled ? 'if (RcKeyValueRead(KEY_OFFSET_Rocker21)) { yawDuty = $yawDuty; pitchDuty = $pitchDuty; }' : ''}
}

void UpdateWeapons(void)
{
    static uint8_t lastFriction = 0;
    static uint8_t lastTrigger = 0;
    uint8_t friction = RcKeyValueRead(${_key(c.frictionKey)});
    uint8_t trigger = RcKeyValueRead(${_key(c.triggerKey)});
    if (friction && !lastFriction) frictionEnabled = !frictionEnabled;
    if (frictionEnabled && frictionDuty < FRICTION_MAX_DUTY) frictionDuty++;
    if (!frictionEnabled && frictionDuty > 0) frictionDuty--;
    if (trigger && !lastTrigger) {
        dutyOfMotor[0] = ${_dir(c.feederDirection) == 1 ? '' : '-'}${c.triggerSpeed ?? 6000};
        ExpansionBoradControl(Duty_Change_Order, abs(dutyOfMotor[0]), 0, frictionDuty, frictionDuty, 0,0,0,0);
        Ms_Delay(${c.triggerTimeMs ?? 100});
        dutyOfMotor[0] = 0;
    }
    lastFriction = friction;
    lastTrigger = trigger;
}

void main(void)
{
    All_Init();
    while (1) {
        nrf_handler();
        ReadControllerInputs();
        CalculateChassis();
        UpdateGimbal();
        UpdateWeapons();
        ExpansionBoradControl(Dir_Change_Order, 1,1,1,1, dutyOfMotor[4]>=0, dutyOfMotor[5]>=0, dutyOfMotor[6]>=0, dutyOfMotor[7]>=0);
        Ms_Delay(EXPANSION_FRAME_GAP_MS);
        ExpansionBoradControl(Duty_Change_Order, abs(dutyOfMotor[0]),0,frictionDuty,frictionDuty,abs(dutyOfMotor[4]),abs(dutyOfMotor[5]),abs(dutyOfMotor[6]),abs(dutyOfMotor[7]));
        PWM_SET_Frequency(PWMB_CH1_P74, 50, yawDuty);
        PWM_SET_Frequency(PWMB_CH4_P03, 50, pitchDuty);
        Ms_Delay(10);
    }
}
''';
  }

  static String _engineer(EngineerConfig c) {
    final modeFunctions = <String>[], cases = <String>[];
    for (var i = 0; i < c.modeCount; i++) {
      final mode = c.modes[i], body = <String>[];
      if (mode.preserveChassis) body.add('    CalculateChassis();');
      for (final a in mode.actions) {
        final sign = a.direction == Direction.forward ? '' : '-';
        final read = a.key.endsWith('X') || a.key.endsWith('Y')
            ? 'valueOfRoker[${a.key.startsWith('L') ? 0 : 1}][${a.key.endsWith('X') ? 0 : 1}]'
            : 'RcKeyValueRead(${_key(a.key)})';
        final slot = expansionPins.indexOf(a.pin);
        if (slot >= 0) {
          final expression = switch (a.mode) {
            ControlMode.direct => '$sign${a.parameter ?? 0}',
            ControlMode.incremental =>
              'dutyOfMotor[$slot] + $sign${a.parameter ?? 0}',
            ControlMode.speed =>
              '(int)((float)$read * ${a.parameter ?? 0} / 2047)',
            ControlMode.accelerate =>
              'dutyOfMotor[$slot] + (int)((float)$read * ${a.parameter ?? 0} / 2047)',
          };
          body.add('    if ($read) dutyOfMotor[$slot] = $expression;');
        } else {
          body.add(
            '    if ($read) PWM_SET_Frequency(PWMB_CH${a.pin == 'MP74' ? '1_P74' : '4_P03'}, 50, ${_servoDuty(c.pwm.servoMids[a.pin])} + $sign${a.parameter ?? 0});',
          );
        }
      }
      modeFunctions.add('void RunMode${i + 1}(void)\n{\n${body.join('\n')}\n}');
      cases.add('        case ${i + 1}: RunMode${i + 1}(); break;');
    }
    final switchLogic = c.switchStrategy == SwitchStrategy.cycle
        ? '''if (RcKeyValueRead(${_key(c.modeSwitchKey)}) && !lastSwitch) { currentMode++; if (currentMode > ${c.modeCount}) currentMode = 1; }
        lastSwitch = RcKeyValueRead(${_key(c.modeSwitchKey)});'''
        : List.generate(
            c.modeCount,
            (i) =>
                'if (RcKeyValueRead(${_key(c.modeKeys[i])})) currentMode = ${i + 1};',
          ).join('\n        ');
    return '''${_header(c, '工程机器人控制代码')}
uint8_t currentMode = 1;
uint8_t lastSwitch = 0;

${_chassis(c.chassis)}
${modeFunctions.join('\n\n')}

void All_Init(void)
{
    Board_Init();
    UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, 230400, TIM1);
    NRF24L01_Init();
${_pwmInit(c.pwm)}
}

void main(void)
{
    All_Init();
    while (1) {
        nrf_handler();
        ReadControllerInputs();
        $switchLogic
        switch (currentMode) {
${cases.join('\n')}
        }
        ExpansionBoradControl(Duty_Change_Order, abs(dutyOfMotor[0]),abs(dutyOfMotor[1]),abs(dutyOfMotor[2]),abs(dutyOfMotor[3]),abs(dutyOfMotor[4]),abs(dutyOfMotor[5]),abs(dutyOfMotor[6]),abs(dutyOfMotor[7]));
        Ms_Delay(10);
    }
}
''';
  }
}
