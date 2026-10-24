import 'package:pieblock_core/pieblock_core.dart';
import 'package:test/test.dart';

/// 发布前逻辑核对沉淀的回归测试：
/// - 生成器两处安全修复（底盘残留占空比归零、电机增速钳位）
/// - 校验器新增的「被允许但会出现问题」组合拦截（LC/RC 固定键冲突、
///   冲刺方向键未配冲刺速度、变量名首尾空格）
ChassisConfig _chassis({bool sprint = false}) => ChassisConfig(
  leftFront: const WheelConfig('P74 P24', Direction.forward),
  leftRear: const WheelConfig('P75 P25', Direction.forward),
  rightFront: const WheelConfig('P76 P26', Direction.reverse),
  rightRear: const WheelConfig('P77 P27', Direction.reverse),
  normalSpeed: 6000,
  sprintSpeed: 9000,
  sprintEnabled: sprint,
);

InfantryConfig _infantry({
  bool sprint = false,
  bool zero = false,
  ArrowBehavior arrow = ArrowBehavior.other,
  String? frictionKey = 'A',
  String? triggerKey = 'E',
  int? sprintSpeed = 9000,
}) => InfantryConfig(
  remote: const RemoteConfig(channel: 36, deadzone: 100),
  chassis: _chassis(sprint: sprint).copyWith(sprintSpeed: sprintSpeed),
  feederPin: 'P60',
  feederDirection: Direction.forward,
  yawActuators: const [
    AxisActuator(
      drive: DriveType.servo,
      pin: 'MP74',
      direction: Direction.forward,
      midOffset: 0,
    ),
  ],
  pitchActuators: const [
    AxisActuator(
      drive: DriveType.servo,
      pin: 'MP03',
      direction: Direction.forward,
      midOffset: 0,
    ),
  ],
  arrowBehavior: arrow,
  feedMode: FeedMode.visualClosedLoop,
  triggerKey: triggerKey,
  triggerSpeed: 3000,
  frictionMode: FrictionMode.brushlessEsc,
  frictionKey: frictionKey,
  frictionUpKey: 'B',
  frictionDownKey: 'C',
  frictionP64MaxDuty: 800,
  frictionP66MaxDuty: 700,
  frictionLevelStep: 10,
  zeroEnabled: zero,
);

EngineerConfig _engineer({
  bool chassisEnabled = true,
  bool sprint = false,
  List<EngineerModeConfig>? modes,
  int modeCount = 1,
  SwitchStrategy? strategy,
  String? switchKey,
  List<String?>? modeKeys,
}) => EngineerConfig(
  remote: const RemoteConfig(channel: 36, deadzone: 100),
  chassis: (chassisEnabled ? _chassis(sprint: sprint) : ChassisConfig.defaults())
      .copyWith(enabled: chassisEnabled),
  pwm: PwmGroupConfig(
    pwma: PwmFrequency.hz50,
    pwmb: PwmFrequency.hz10000,
    pinRoles: {
      for (final pin in expansionPins)
        pin: switch (pin) {
          'P60' || 'P62' => PinRole.servo,
          'P64' || 'P66' => PinRole.friction,
          _ => PinRole.motor,
        },
    },
    servoMids: const {'P60': 0, 'P62': 0, 'MP03': 0, 'MP74': 0},
    frictionMaxDuties: const {'P64': 800, 'P66': 700},
  ),
  modeCount: modeCount,
  switchStrategy: strategy,
  modeSwitchKey: switchKey,
  modeKeys: modeKeys ?? const [null, null, null, null],
  modes:
      modes ??
      [
        EngineerModeConfig(
          preserveChassis: true,
          actions: [
            ActionMapping(
              key: 'A',
              pin: 'P60',
              direction: Direction.forward,
              mode: ControlMode.direct,
              parameter: 45,
            ),
          ],
        ),
      ],
);

List<String> _errors(ProjectConfig config) => ProjectValidator.validate(config)
    .where((issue) => issue.severity == IssueSeverity.error)
    .map((issue) => issue.message)
    .toList();

void main() {
  // 提取生成的 PrepareMode 函数体（到函数末尾的列 0 闭括号）。
  String prepareModeSource(String source) {
    final start = source.indexOf('static void PrepareMode');
    expect(start, greaterThanOrEqualTo(0), reason: '生成代码应包含 PrepareMode');
    final end = source.indexOf('\n}\n', start);
    return source.substring(start, end);
  }

  group('生成器安全修复（发布前逻辑核对）', () {
    test('不保留底盘的模式在 PrepareMode 中把底盘槽归零', () {
      final source = CodeGenerator.generate(
        _engineer(
          modeCount: 2,
          strategy: SwitchStrategy.cycle,
          switchKey: 'E',
          modes: [
            EngineerModeConfig(preserveChassis: true, actions: const []),
            EngineerModeConfig(preserveChassis: false, actions: const []),
          ],
        ),
      );
      final prepare = prepareModeSource(source);
      // 模式 1（保留底盘）：底盘槽 4~7 不归零；模式 2（不保留）：归零。
      final case1 = prepare.substring(prepare.indexOf('case 1:'), prepare.indexOf('case 2:'));
      final case2 = prepare.substring(prepare.indexOf('case 2:'));
      expect(case1.contains('dutyOfMotor[4] = 0;'), isFalse);
      expect(case2.contains('dutyOfMotor[4] = 0;'), isTrue);
      expect(case2.contains('dutyOfMotor[7] = 0;'), isTrue);
    });

    test('保留底盘的模式仍不归零底盘槽', () {
      final source = CodeGenerator.generate(
        _engineer(
          modeCount: 2,
          strategy: SwitchStrategy.cycle,
          switchKey: 'E',
          modes: [
            EngineerModeConfig(preserveChassis: true, actions: const []),
            EngineerModeConfig(preserveChassis: true, actions: const []),
          ],
        ),
      );
      expect(prepareModeSource(source).contains('dutyOfMotor[4] = 0;'), isFalse);
    });

    test('电机增速模式生成 ±10000 钳位', () {
      final source = CodeGenerator.generate(
        _engineer(
          chassisEnabled: false,
          modes: [
            EngineerModeConfig(
              actions: [
                ActionMapping(
                  key: 'LX',
                  pin: 'P60',
                  direction: Direction.forward,
                  mode: ControlMode.accelerate,
                  parameter: 10000,
                ),
              ],
            ),
          ],
        ).copyWith(
          pwm: PwmGroupConfig(
            pwma: PwmFrequency.hz10000,
            pwmb: PwmFrequency.hz10000,
            pinRoles: {
              for (final pin in expansionPins)
                pin: (pin == 'P64' || pin == 'P66')
                    ? PinRole.unused
                    : PinRole.motor,
            },
            servoMids: const {'MP03': 0, 'MP74': 0},
          ),
        ),
      );
      expect(
        source,
        contains('if (dutyOfMotor[0] > 10000) dutyOfMotor[0] = 10000; '
            'else if (dutyOfMotor[0] < -10000) dutyOfMotor[0] = -10000;'),
      );
    });

    test('电机速度模式不受钳位影响（比例直写）', () {
      final source = CodeGenerator.generate(
        _engineer(
          chassisEnabled: false,
          modes: [
            EngineerModeConfig(
              actions: [
                ActionMapping(
                  key: 'LX',
                  pin: 'P60',
                  direction: Direction.forward,
                  mode: ControlMode.speed,
                  parameter: 8000,
                ),
              ],
            ),
          ],
        ).copyWith(
          pwm: PwmGroupConfig(
            pwma: PwmFrequency.hz10000,
            pwmb: PwmFrequency.hz10000,
            pinRoles: {
              for (final pin in expansionPins)
                pin: (pin == 'P64' || pin == 'P66')
                    ? PinRole.unused
                    : PinRole.motor,
            },
            servoMids: const {'MP03': 0, 'MP74': 0},
          ),
        ),
      );
      expect(
        source,
        contains('dutyOfMotor[0] = (int)(((int32_t)valueOfRoker[0][0] * 8000L) / 2047L);'),
      );
      expect(source, isNot(contains('> 10000) dutyOfMotor[0] = 10000;')));
    });
  });

  group('LC/RC 固定键冲突校验', () {
    test('步兵：启用冲刺时动作键不能是 LC', () {
      final errors = _errors(_infantry(sprint: true, frictionKey: 'LC'));
      expect(errors.any((e) => e.contains('LC 已用于底盘冲刺')), isTrue);
    });

    test('步兵：启用云台归中时扳机键不能是 RC', () {
      final errors = _errors(_infantry(zero: true, triggerKey: 'RC'));
      expect(errors.any((e) => e.contains('RC 已用于云台归中')), isTrue);
    });

    test('步兵：未启用冲刺/归中时 LC/RC 可自由使用', () {
      final errors = _errors(_infantry(frictionKey: 'LC', triggerKey: 'RC'));
      expect(
        errors.any((e) => e.contains('已用于底盘冲刺') || e.contains('已用于云台归中')),
        isFalse,
      );
    });

    test('工程：启用冲刺时模式切换键不能是 LC', () {
      final errors = _errors(
        _engineer(
          sprint: true,
          modeCount: 2,
          strategy: SwitchStrategy.cycle,
          switchKey: 'LC',
          modes: [
            EngineerModeConfig(preserveChassis: true, actions: const []),
            EngineerModeConfig(preserveChassis: false, actions: const []),
          ],
        ),
      );
      expect(errors.any((e) => e.contains('LC 已用于底盘冲刺')), isTrue);
    });

    test('工程：启用冲刺时动作输入不能是 LC', () {
      final errors = _errors(
        _engineer(
          sprint: true,
          modes: [
            EngineerModeConfig(
              preserveChassis: true,
              actions: [
                ActionMapping(
                  key: 'LC',
                  pin: 'P60',
                  direction: Direction.forward,
                  mode: ControlMode.direct,
                  parameter: 45,
                ),
              ],
            ),
          ],
        ),
      );
      expect(errors.any((e) => e.contains('LC 已用于底盘冲刺')), isTrue);
    });

    test('工程：未启用底盘（或冲刺）时 LC 不受限', () {
      final errors = _errors(
        _engineer(
          chassisEnabled: false,
          modes: [
            EngineerModeConfig(
              actions: [
                ActionMapping(
                  key: 'LC',
                  pin: 'P60',
                  direction: Direction.forward,
                  mode: ControlMode.direct,
                  parameter: 45,
                ),
              ],
            ),
          ],
        ),
      );
      expect(errors, isEmpty);
    });
  });

  group('冲刺方向键必须有冲刺速度', () {
    test('方向键=冲刺且未填冲刺速度时报错', () {
      final errors = _errors(
        _infantry(arrow: ArrowBehavior.sprint, sprintSpeed: null),
      );
      expect(errors.any((e) => e.contains('必须填写冲刺速度')), isTrue);
    });

    test('方向键=冲刺且已填冲刺速度时通过', () {
      final errors = _errors(_infantry(arrow: ArrowBehavior.sprint));
      expect(errors, isEmpty);
    });

    test('方向键=移动时不需要冲刺速度', () {
      final errors = _errors(
        _infantry(arrow: ArrowBehavior.move, sprintSpeed: null),
      );
      expect(errors.any((e) => e.contains('冲刺速度')), isFalse);
    });
  });

  group('变量名首尾空格', () {
    EngineerConfig configWithName(String name) => _engineer(
      chassisEnabled: false,
      modes: [
        EngineerModeConfig(
          actions: [
            ActionMapping(
              inputKind: ActionInputKind.unspecified,
              outputKind: ActionOutputKind.integer,
              variableName: name,
              expression: 'LX * 2',
            ),
            ActionMapping(
              inputKind: ActionInputKind.unspecified,
              outputKind: ActionOutputKind.pin,
              pin: 'P60',
              expression: 'v * 3',
            ),
          ],
        ),
      ],
    ).copyWith(
      pwm: PwmGroupConfig(
        pwma: PwmFrequency.hz10000,
        pwmb: PwmFrequency.hz10000,
        pinRoles: {
          for (final pin in expansionPins)
            pin: (pin == 'P64' || pin == 'P66') ? PinRole.unused : PinRole.motor,
        },
        servoMids: const {'MP03': 0, 'MP74': 0},
      ),
    );

    test('首尾空格的变量名被拒绝', () {
      expect(
        _errors(configWithName(' v')).any((e) => e.contains('首尾不能有空格')),
        isTrue,
      );
      expect(
        _errors(configWithName('v ')).any((e) => e.contains('首尾不能有空格')),
        isTrue,
      );
    });

    test('首尾空格的变量名被拒绝且阻止生成', () {
      expect(
        _errors(configWithName(' v')).any((e) => e.contains('首尾不能有空格')),
        isTrue,
      );
      expect(
        _errors(configWithName('v ')).any((e) => e.contains('首尾不能有空格')),
        isTrue,
      );
      // 生成入口同样拦下（不会拼出 pbv_ v 这类非法 C 标识符）。
      expect(
        () => CodeGenerator.generate(configWithName(' v ')),
        throwsStateError,
      );
    });
  });
}
