import 'dart:convert';
import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';
import 'package:test/test.dart';

ChassisConfig completeChassis({bool shared = false}) => ChassisConfig(
  leftFront: const WheelConfig('P74 P24', Direction.forward),
  leftRear: WheelConfig(shared ? 'P74 P24' : 'P75 P25', Direction.forward),
  rightFront: const WheelConfig('P76 P26', Direction.reverse),
  rightRear: const WheelConfig('P77 P27', Direction.reverse),
  normalSpeed: 4000,
  sprintSpeed: 8000,
);

InfantryConfig completeInfantry({
  FrictionMode frictionMode = FrictionMode.brushlessEsc,
  FeedMode feedMode = FeedMode.blockingOpenLoop,
  bool shared = false,
  String? reverseFeedKey,
}) => InfantryConfig(
  remote: const RemoteConfig(channel: 36, deadzone: 100),
  chassis: completeChassis(shared: shared),
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
  arrowBehavior: ArrowBehavior.other,
  feedMode: feedMode,
  triggerKey: 'E',
  reverseFeedKey: reverseFeedKey,
  triggerSpeed: 6000,
  triggerTimeMs: feedMode == FeedMode.blockingOpenLoop ? 250 : null,
  frictionMode: frictionMode,
  frictionKey: frictionMode == FrictionMode.brushlessEsc ? 'A' : null,
  frictionUpKey: frictionMode == FrictionMode.brushlessEsc ? 'B' : null,
  frictionDownKey: frictionMode == FrictionMode.brushlessEsc ? 'C' : null,
  frictionMaxDuty: frictionMode == FrictionMode.brushlessEsc ? 800 : null,
  frictionStep: frictionMode == FrictionMode.brushlessEsc ? 100 : null,
);

EngineerConfig completeEngineer() => EngineerConfig(
  remote: const RemoteConfig(channel: 36, deadzone: 100),
  chassis: completeChassis(),
  pwm: PwmGroupConfig(
    pwma: PwmFrequency.hz10000,
    pwmb: PwmFrequency.hz10000,
    pinRoles: {
      for (final pin in expansionPins)
        pin: EngineerPinCapabilities.frictionPins.contains(pin)
            ? PinRole.friction
            : PinRole.motor,
    },
    servoMids: const {'MP03': 0, 'MP74': 0},
  ),
  modeCount: 1,
  modes: [EngineerModeConfig(preserveChassis: true)],
);

DebugConfig completeDebug() => DebugConfig(
  tests: [
    const DebugTestItem(
      pin: 'P64',
      enabled: true,
      driveType: DebugDriveType.friction,
      direction: Direction.forward,
      value: 750,
    ),
    const DebugTestItem(
      pin: 'MP03',
      enabled: true,
      driveType: DebugDriveType.servo,
      direction: Direction.reverse,
      value: 30,
      durationMs: 4200,
    ),
    for (final pin in debugPins.where((pin) => pin != 'P64' && pin != 'MP03'))
      DebugTestItem(pin: pin),
  ],
);

EngineerConfig advancedEngineer({
  SwitchStrategy strategy = SwitchStrategy.cycle,
  bool buzzerDisabled = false,
}) => EngineerConfig(
  remote: const RemoteConfig(channel: 36, deadzone: 100),
  chassis: completeChassis(),
  pwm: PwmGroupConfig(
    pwma: PwmFrequency.hz50,
    pwmb: PwmFrequency.hz10000,
    buzzerDisabled: buzzerDisabled,
    pinRoles: {
      'P60': PinRole.servo,
      for (final pin in expansionPins.where((pin) => pin != 'P60'))
        pin: EngineerPinCapabilities.frictionPins.contains(pin)
            ? PinRole.friction
            : PinRole.motor,
    },
    servoMids: const {'P60': 0, 'MP03': 0, 'MP74': 0},
  ),
  modeCount: 4,
  switchStrategy: strategy,
  modeSwitchKey: strategy == SwitchStrategy.cycle ? 'E' : null,
  modeKeys: strategy == SwitchStrategy.direct
      ? const ['E', '↑', '↓', '←']
      : null,
  modes: [
    EngineerModeConfig(
      preserveChassis: true,
      actions: [
        ActionMapping(
          key: 'A',
          direction: Direction.forward,
          mode: ControlMode.single,
          parameter: 5.5,
          pin: 'P60',
        ),
        ActionMapping(
          key: 'B',
          direction: Direction.reverse,
          mode: ControlMode.continuous,
          parameter: 5,
          pin: 'P60',
        ),
        ActionMapping(
          key: 'C',
          direction: Direction.forward,
          mode: ControlMode.direct,
          parameter: 4000,
          pin: 'P62',
        ),
      ],
    ),
    EngineerModeConfig(
      actions: [
        ActionMapping(
          key: 'RX',
          direction: Direction.forward,
          mode: ControlMode.speed,
          parameter: 5000,
          pin: 'P64',
        ),
        ActionMapping(
          key: 'RY',
          direction: Direction.forward,
          mode: ControlMode.accelerate,
          parameter: 100,
          pin: 'P66',
        ),
      ],
    ),
    EngineerModeConfig(),
    EngineerModeConfig(),
  ],
);

EngineerConfig servoButtonEngineer({
  ControlMode mode = ControlMode.single,
  num parameter = 1.25,
  String key = 'A',
  String pin = 'P60',
  Direction direction = Direction.forward,
}) {
  final source = completeEngineer();
  return source.copyWith(
    pwm: source.pwm.copyWith(
      pinRoles: {...source.pwm.pinRoles, 'P60': PinRole.servo},
      servoMids: {...source.pwm.servoMids, 'P60': 0},
    ),
    modes: [
      EngineerModeConfig(
        preserveChassis: true,
        actions: [
          ActionMapping(
            key: key,
            direction: direction,
            mode: mode,
            parameter: parameter,
            pin: pin,
          ),
        ],
      ),
    ],
  );
}

void main() {
  group('项目格式与进度', () {
    test('格式 15 往返并保存向导进度', () {
      final source = ProjectDocument.create('步兵测试', ProjectKind.infantry)
          .copyWith(
            guideProgress: const GuideProgress(
              currentStepId: 'controls',
              visitedStepIds: ['remote', 'mechanism', 'controls'],
            ),
          );
      final restored = ProjectDocument.fromJson(
        Map<String, Object?>.from(
          jsonDecode(jsonEncode(source.toJson())) as Map,
        ),
      );
      expect(source.toJson()['format_version'], 15);
      expect(restored.guideProgress.currentStepId, 'controls');
      expect(restored.guideProgress.visitedStepIds, hasLength(3));
      expect((source.toJson()['config']! as Map), isNot(contains('pwm')));
    });

    test('云台执行器按数组往返并支持多个执行器', () {
      final source = completeInfantry().copyWith(
        yawActuators: const [
          AxisActuator(
            drive: DriveType.servo,
            pin: 'MP74',
            direction: Direction.forward,
            midOffset: -12,
          ),
          AxisActuator(
            drive: DriveType.servo,
            pin: 'P75',
            direction: Direction.reverse,
            midOffset: 8,
          ),
        ],
        pitchActuators: const [
          AxisActuator(
            drive: DriveType.motor,
            pin: 'P77',
            direction: Direction.reverse,
          ),
        ],
      );
      final json = source.toJson();
      expect(json['yaw'], hasLength(2));
      expect(json['pitch'], hasLength(1));
      final restored = InfantryConfig.fromJson(
        Map<String, Object?>.from(jsonDecode(jsonEncode(json)) as Map),
      );
      expect(restored.yawActuators, hasLength(2));
      expect(restored.yawActuators[1].pin, 'P75');
      expect(restored.yawActuators[1].midOffset, 8);
      expect(restored.pitchActuators.single.drive, DriveType.motor);
      expect(restored.pitchActuators.single.midOffset, isNull);
    });

    test('格式 14 直接拒绝', () {
      expect(
        () => ProjectDocument.fromJson({'format_version': 14}),
        throwsFormatException,
      );
    });

    test('底盘转向反向配置默认关闭且可往返', () {
      expect(ChassisConfig.fromJson(const {}).turnReversed, isFalse);
      final source = completeChassis().copyWith(turnReversed: true);
      final json = source.toJson();
      expect(json['turn_reversed'], isTrue);
      expect(ChassisConfig.fromJson(json).turnReversed, isTrue);
      expect(source.copyWith(turnReversed: false).turnReversed, isFalse);
    });

    test('反向拨弹键默认不使用且可往返', () {
      expect(completeInfantry().toJson()['reverse_feed_key'], isNull);
      final source = completeInfantry(reverseFeedKey: 'D');
      final json = source.toJson();
      expect(json['reverse_feed_key'], 'D');
      expect(InfantryConfig.fromJson(json).reverseFeedKey, 'D');
      expect(source.copyWith(reverseFeedKey: null).reverseFeedKey, isNull);
    });

    test('舵机按键控制方式和小数灵敏度可往返', () {
      final source = ActionMapping(
        id: 'servo-button',
        key: 'A',
        direction: Direction.forward,
        mode: ControlMode.single,
        parameter: 1.25,
        pin: 'P60',
      );
      final restored = ActionMapping.fromJson(
        Map<String, Object?>.from(
          jsonDecode(jsonEncode(source.toJson())) as Map,
        ),
      );
      expect(restored.mode, ControlMode.single);
      expect(restored.parameter, 1.25);
      expect(
        source.copyWith(mode: ControlMode.continuous).mode,
        ControlMode.continuous,
      );

      final legacy = ActionMapping.fromJson({
        ...source.toJson(),
        'mode': ControlMode.direct.name,
        'parameter': 30,
      });
      expect(legacy.mode, ControlMode.direct);
      expect(legacy.parameter, 30);
    });

    test('调试项目顺序与配置可往返', () {
      final source = ProjectDocument.create(
        '调试测试',
        ProjectKind.debug,
      ).copyWith(config: completeDebug());
      final restored = ProjectDocument.fromJson(
        Map<String, Object?>.from(
          jsonDecode(jsonEncode(source.toJson())) as Map,
        ),
      );
      expect(restored.kind, ProjectKind.debug);
      expect(restored.guideProgress.currentStepId, 'tests');
      final config = restored.config as DebugConfig;
      expect(config.tests.first.pin, 'P64');
      expect(config.tests[1].durationMs, 4200);
      expect(config.tests.first.toJson(), isNot(contains('duration_ms')));
    });

    test('新项目必填项为空且不能生成', () {
      final config =
          ProjectDocument.create('空白', ProjectKind.infantry).config
              as InfantryConfig;
      expect(config.remote.channel, isNull);
      expect(config.chassis.leftFront.pin, isNull);
      expect(config.feedMode, isNull);
      expect(config.frictionMode, isNull);
      final engineerJson = ProjectDocument.create(
        '空白工程',
        ProjectKind.engineer,
      ).config.toJson();
      expect((engineerJson['pwm']! as Map)['pwma'], isNull);
      expect(
        ((engineerJson['pwm']! as Map)['pin_roles'] as Map)['P60'],
        isNull,
      );
      expect(
        ProjectValidator.validate(config)
            .where((i) => i.severity == IssueSeverity.error),
        isNotEmpty,
      );
      expect(() => CodeGenerator.generate(config), throwsStateError);
    });

    test('校验项区分未填必填项与已填非法值', () {
      final blankIssues = ProjectValidator.validate(InfantryConfig());
      expect(
        blankIssues.where((issue) => issue.severity == IssueSeverity.error),
        everyElement(
          predicate<ValidationIssue>(
            (issue) => issue.kind == ValidationIssueKind.required,
          ),
        ),
      );

      final invalidIssues = ProjectValidator.validate(
        InfantryConfig(remote: const RemoteConfig(channel: 126)),
      );
      expect(
        invalidIssues
            .singleWhere((issue) => issue.fieldPath == 'remote.channel')
            .kind,
        ValidationIssueKind.invalid,
      );
    });

    test('底盘速度低于建议阈值时给出非阻塞警告', () {
      final low = completeInfantry().copyWith(
        chassis: completeChassis().copyWith(
          normalSpeed: 3999,
          sprintSpeed: 8999,
        ),
      );
      final warnings = ProjectValidator.validate(low)
          .where((issue) => issue.severity == IssueSeverity.warning)
          .map((issue) => issue.message);
      expect(
        warnings,
        containsAll(['普通速度低于 4000，底盘移动速度可能变慢', '冲刺速度低于 9000，底盘移动速度可能变慢']),
      );

      final boundary = low.copyWith(
        chassis: low.chassis.copyWith(normalSpeed: 4000, sprintSpeed: 9000),
      );
      expect(
        ProjectValidator.validate(boundary)
            .where((issue) => issue.message.contains('底盘移动速度可能变慢')),
        isEmpty,
      );

      final invalid = low.copyWith(
        chassis: low.chassis.copyWith(normalSpeed: -1, sprintSpeed: -1),
      );
      expect(
        ProjectValidator.validate(invalid)
            .where((issue) => issue.message.contains('底盘移动速度可能变慢')),
        isEmpty,
      );
    });

    test('摇杆死区大于 500 时给出非阻塞警告', () {
      Iterable<ValidationIssue> deadzoneIssues(int deadzone) =>
          ProjectValidator.validate(
            completeInfantry().copyWith(
              remote: RemoteConfig(channel: 36, deadzone: deadzone),
            ),
          ).where((issue) => issue.fieldPath == 'remote.deadzone');

      expect(deadzoneIssues(500), isEmpty);
      for (final value in [501, 2047]) {
        final warning = deadzoneIssues(value).single;
        expect(warning.severity, IssueSeverity.warning);
        expect(warning.stepId, 'remote');
        expect(warning.message, '摇杆死区大于 500，可能影响操控灵敏度');
      }

      final invalid = deadzoneIssues(2048).single;
      expect(invalid.severity, IssueSeverity.error);
      expect(invalid.message, isNot(contains('可能影响操控灵敏度')));
    });

    test('仓库原子保存并打开', () async {
      final dir = await Directory.systemTemp.createTemp('pieblock-core-test-');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}${Platform.pathSeparator}demo.pieproj';
      const repository = ProjectRepository();
      await repository.create(path, '工程测试', ProjectKind.engineer);
      expect((await repository.open(path)).kind, ProjectKind.engineer);
      expect(File('$path.tmp').existsSync(), isFalse);
    });
  });

  group('工程引脚能力', () {
    test('每组引脚只公开硬件支持的输出角色', () {
      const motorRoles = [
        PinRole.motor,
        PinRole.servo,
        PinRole.jitterMotor,
        PinRole.unused,
      ];
      const frictionRoles = [PinRole.servo, PinRole.friction, PinRole.unused];

      for (final pin in EngineerPinCapabilities.motorPins) {
        expect(EngineerPinCapabilities.allowedRoles(pin), motorRoles);
      }
      for (final pin in EngineerPinCapabilities.frictionPins) {
        expect(EngineerPinCapabilities.allowedRoles(pin), frictionRoles);
      }
      for (final pin in mainServoPins) {
        expect(EngineerPinCapabilities.allowedRoles(pin), const [
          PinRole.servo,
        ]);
      }
      for (final pin in [...expansionPins, ...mainServoPins]) {
        expect(
          EngineerPinCapabilities.supportsRole(pin, PinRole.servo),
          isTrue,
        );
      }
    });

    test('非法角色被保留并产生单一字段错误且阻止生成', () {
      EngineerConfig withRole(String pin, PinRole role) {
        final source = completeEngineer();
        return source.copyWith(
          pwm: source.pwm.copyWith(
            pinRoles: {...source.pwm.pinRoles, pin: role},
          ),
        );
      }

      for (final invalid in [
        ('P64', PinRole.motor),
        ('P66', PinRole.jitterMotor),
        ('P60', PinRole.friction),
        ('P74', PinRole.friction),
      ]) {
        final config = withRole(invalid.$1, invalid.$2);
        final issues = ProjectValidator.validate(config)
            .where((issue) => issue.fieldPath == 'pwm.pin_roles.${invalid.$1}')
            .toList();
        expect(
          issues.where((issue) => issue.severity == IssueSeverity.error),
          hasLength(1),
        );
        expect(
          issues.where((issue) => issue.severity == IssueSeverity.warning),
          isEmpty,
        );
        expect(() => CodeGenerator.generate(config), throwsStateError);
      }

      final invalid = withRole('P64', PinRole.motor);
      final document = ProjectDocument.create(
        '非法工程配置',
        ProjectKind.engineer,
      ).copyWith(config: invalid);
      final restored = ProjectDocument.fromJson(
        Map<String, Object?>.from(
          jsonDecode(jsonEncode(document.toJson())) as Map,
        ),
      );
      expect(
        (restored.config as EngineerConfig).pwm.pinRoles['P64'],
        PinRole.motor,
      );
    });

    test('P64/P66 摩擦轮角色保持合法', () {
      final errors = ProjectValidator.validate(completeEngineer()).where(
        (issue) =>
            issue.severity == IssueSeverity.error &&
            issue.fieldPath.startsWith('pwm.pin_roles.'),
      );
      expect(errors, isEmpty);
    });
  });

  group('工程舵机按键控制', () {
    Iterable<ValidationIssue> parameterIssues(num parameter) =>
        ProjectValidator.validate(servoButtonEngineer(parameter: parameter))
            .where((issue) => issue.fieldPath == 'modes.0.actions.0.parameter');

    test('灵敏度范围、精度和速度警告正确', () {
      expect(parameterIssues(10), isEmpty);
      for (final value in [10.01, 20]) {
        final warning = parameterIssues(value).single;
        expect(warning.severity, IssueSeverity.warning);
        expect(warning.message, '舵机角度变化速度可能过快');
      }
      expect(
        CodeGenerator.generate(servoButtonEngineer(parameter: 10.01)),
        contains('servoButtonRemainder'),
      );

      for (final value in [0, -0.01, 20.01, 1.234]) {
        final issues = parameterIssues(value).toList();
        expect(
          issues.where((issue) => issue.severity == IssueSeverity.error),
          hasLength(1),
        );
        expect(
          issues.where((issue) => issue.severity == IssueSeverity.warning),
          isEmpty,
        );
        expect(
          () => CodeGenerator.generate(servoButtonEngineer(parameter: value)),
          throwsStateError,
        );
      }
    });

    test('数字按键舵机接受直接单次持续且保留非法值', () {
      expect(
        ProjectValidator.validate(
          servoButtonEngineer(mode: ControlMode.direct, parameter: 30),
        ).where((issue) => issue.severity == IssueSeverity.error),
        isEmpty,
      );
      for (final mode in [ControlMode.single, ControlMode.continuous]) {
        expect(
          ProjectValidator.validate(servoButtonEngineer(mode: mode))
              .where((issue) => issue.severity == IssueSeverity.error),
          isEmpty,
        );
      }

      final config = servoButtonEngineer(
        mode: ControlMode.incremental,
        parameter: 5,
      );
      final issue = ProjectValidator.validate(config)
          .singleWhere((issue) => issue.fieldPath == 'modes.0.actions.0.mode');
      expect(issue.severity, IssueSeverity.error);
      expect(config.modes.single.actions.single.mode, ControlMode.incremental);

      expect(
        ProjectValidator.validate(
          servoButtonEngineer(
            mode: ControlMode.direct,
            parameter: 30,
            key: 'RX',
          ),
        ).where((issue) => issue.severity == IssueSeverity.error),
        isEmpty,
      );
    });

    test('直接预设点位使用整数角度范围且不产生灵敏度警告', () {
      for (final value in [0, 90]) {
        final issues = ProjectValidator.validate(
          servoButtonEngineer(mode: ControlMode.direct, parameter: value),
        ).where((issue) => issue.fieldPath == 'modes.0.actions.0.parameter');
        expect(issues, isEmpty);
      }

      for (final value in [-1, 90.01, 91]) {
        final config = servoButtonEngineer(
          mode: ControlMode.direct,
          parameter: value,
        );
        final issues = ProjectValidator.validate(config)
            .where((issue) => issue.fieldPath == 'modes.0.actions.0.parameter')
            .toList();
        expect(
          issues.where((issue) => issue.severity == IssueSeverity.error),
          hasLength(1),
        );
        expect(
          issues.where((issue) => issue.severity == IssueSeverity.warning),
          isEmpty,
        );
        expect(() => CodeGenerator.generate(config), throwsStateError);
      }
    });
  });

  group('调试项目', () {
    test('空序列、非法引脚能力和值会阻止生成', () {
      expect(ProjectValidator.validate(DebugConfig()), isNotEmpty);
      final invalid = DebugConfig(
        tests: [
          const DebugTestItem(
            pin: 'MP03',
            enabled: true,
            driveType: DebugDriveType.motor,
            direction: Direction.forward,
            value: 100,
          ),
          for (final pin in debugPins.where((pin) => pin != 'MP03'))
            DebugTestItem(pin: pin),
        ],
      );
      expect(
        ProjectValidator.validate(invalid).map((issue) => issue.message),
        contains(contains('仅支持舵机')),
      );
      expect(() => CodeGenerator.generate(invalid), throwsStateError);
    });

    test('生成混合测试、非整百摩擦轮曲线和安全完成循环', () {
      final code = CodeGenerator.generate(completeDebug());
      expect(code.indexOf('1. P64'), lessThan(code.indexOf('2. MP03')));
      expect(code, contains('Duty_Change_Order, 0, 0, 750'));
      expect(code, contains('Duty_Change_Order, 0, 0, 700'));
      expect(code, contains('Ms_Delay(4200);'));
      expect(code, contains('PWM_SET_Frequency(PWMB_CH4_P03, 50, 0);'));
      expect(code, contains('Ms_Delay(2000);'));
      expect(code, contains('static void Uart1TxQuery(uint8_t dat)'));
      expect(code, contains('Uart1TxQuery(control_frame_pack[i])'));
      expect(code, isNot(contains('Uart1SendFrameQuery')));
      expect(code, isNot(contains('uint8_t globalInterruptEnabled = EA;')));
      expect(
        code,
        isNot(contains('UART_PutChar(UART_1, control_frame_pack[i])')),
      );
    });
  });

  group('引脚规划与条件校验', () {
    test('空白配置不提前占用任何引脚', () {
      final blank = InfantryConfig();
      expect(InfantryPinPlanner.derive(blank), isEmpty);
      expect(
        InfantryPinPlanner.allowedPins(blank, 'chassis.left_front.pin'),
        contains('P60 P61'),
      );
    });

    test('摩擦轮仅在启用时占用 P64/P66', () {
      expect(
        InfantryPinPlanner.derive(completeInfantry()).keys,
        containsAll(['P64', 'P66']),
      );
      expect(
        InfantryPinPlanner.derive(
          completeInfantry(frictionMode: FrictionMode.disabled),
        ).keys,
        isNot(contains('P64')),
      );
    });

    test('底盘同侧共享合法且摘要合并所有者', () {
      final config = completeInfantry(shared: true);
      expect(
        ProjectValidator.validate(config)
            .where((i) => i.severity == IssueSeverity.error),
        isEmpty,
      );
      expect(
        InfantryPinPlanner.derive(config)['P74']!.ownerLabel,
        contains('左前轮'),
      );
      expect(
        InfantryPinPlanner.derive(config)['P74']!.ownerLabel,
        contains('左后轮'),
      );
    });

    test('反向拨弹键必须避让其他按键和方向键', () {
      bool hasError(InfantryConfig config, String path) =>
          ProjectValidator.validate(config).any(
            (i) => i.severity == IssueSeverity.error && i.fieldPath == path,
          );
      expect(
        hasError(
          completeInfantry(reverseFeedKey: 'D'),
          'controls.reverse_feed_key',
        ),
        isFalse,
      );
      // 与扳机键、摩擦轮开关键重名，或使用摇杆轴
      for (final key in ['E', 'A', 'LX']) {
        expect(
          hasError(
            completeInfantry(reverseFeedKey: key),
            'controls.reverse_feed_key',
          ),
          isTrue,
          reason: '$key 不应被接受',
        );
      }
      // 摩擦轮关闭后 'A' 释放
      expect(
        hasError(
          completeInfantry(
            reverseFeedKey: 'A',
            frictionMode: FrictionMode.disabled,
          ),
          'controls.reverse_feed_key',
        ),
        isFalse,
      );
      // 方向键已用于底盘时不能作为反向拨弹键，用途为“其他”时可用
      expect(
        hasError(
          completeInfantry(reverseFeedKey: '↓')
              .copyWith(arrowBehavior: ArrowBehavior.move),
          'controls.reverse_feed_key',
        ),
        isTrue,
      );
      expect(
        hasError(
          completeInfantry(reverseFeedKey: '↓')
              .copyWith(arrowBehavior: ArrowBehavior.other),
          'controls.reverse_feed_key',
        ),
        isFalse,
      );
    });

    test('上游改变后保留非法值并精确报错', () {
      final config = completeInfantry().copyWith(
        yawActuators: const [
          AxisActuator(
            drive: DriveType.motor,
            pin: 'MP74',
            direction: Direction.forward,
          ),
        ],
      );
      expect(config.yawActuators.single.pin, 'MP74');
      expect(
        ProjectValidator.validate(config).any(
          (i) =>
              i.severity == IssueSeverity.error &&
              i.fieldPath == 'gimbal.yaw.0.pin',
        ),
        isTrue,
      );
    });

    test('占用不会从硬件兼容候选中移除', () {
      final config = completeInfantry(frictionMode: FrictionMode.disabled);
      expect(
        InfantryPinPlanner.allowedPins(config, 'mechanism.feeder_pin'),
        containsAll(['P74', 'P75', 'P76', 'P77']),
      );
    });

    test('拨弹与轮电机交换时规范化复合引脚名称', () {
      final source = completeInfantry(frictionMode: FrictionMode.disabled)
          .copyWith(
            chassis: completeChassis().copyWith(
              leftFront: const WheelConfig('P62 P63', Direction.forward),
            ),
          );
      final plan = InfantryPinPlanner.planReassignment(
        source,
        'mechanism.feeder_pin',
        'P62',
      );

      expect(plan.occupants.single.ownerLabel, '左前轮');
      expect(plan.supports(InfantryPinReassignmentStrategy.swap), isTrue);
      final result = InfantryPinPlanner.applyReassignment(
        source,
        'mechanism.feeder_pin',
        'P62',
        InfantryPinReassignmentStrategy.swap,
      );
      expect(result.feederPin, 'P62');
      expect(result.chassis.leftFront.pin, 'P60 P61');
      expect(
        ProjectValidator.validate(result)
            .where((issue) => issue.message.contains('同时被')),
        isEmpty,
      );
    });

    test('同侧共享占用组可以整体交换或整体解除', () {
      final source = completeInfantry(frictionMode: FrictionMode.disabled)
          .copyWith(
            chassis: completeChassis().copyWith(
              leftFront: const WheelConfig('P62 P63', Direction.forward),
              leftRear: const WheelConfig('P62 P63', Direction.forward),
            ),
          );
      final plan = InfantryPinPlanner.planReassignment(
        source,
        'mechanism.feeder_pin',
        'P62',
      );
      expect(
        plan.occupants.map((occupant) => occupant.ownerLabel),
        containsAll(['左前轮', '左后轮']),
      );

      final swapped = InfantryPinPlanner.applyReassignment(
        source,
        'mechanism.feeder_pin',
        'P62',
        InfantryPinReassignmentStrategy.swap,
      );
      expect(swapped.chassis.leftFront.pin, 'P60 P61');
      expect(swapped.chassis.leftRear.pin, 'P60 P61');

      final takenOver = InfantryPinPlanner.applyReassignment(
        source,
        'mechanism.feeder_pin',
        'P62',
        InfantryPinReassignmentStrategy.takeOver,
      );
      expect(takenOver.feederPin, 'P62');
      expect(takenOver.chassis.leftFront.pin, isNull);
      expect(takenOver.chassis.leftRear.pin, isNull);
      expect(
        ProjectValidator.validate(takenOver).where(
          (issue) =>
              issue.severity == IssueSeverity.error &&
              issue.fieldPath.startsWith('chassis.left_'),
        ),
        hasLength(2),
      );
    });

    test('交换会拒绝不兼容引脚和跨侧共享', () {
      final source = completeInfantry(
        frictionMode: FrictionMode.disabled,
        shared: true,
      );
      final crossSide = InfantryPinPlanner.planReassignment(
        source,
        'chassis.left_front.pin',
        'P76 P26',
      );
      expect(crossSide.supports(InfantryPinReassignmentStrategy.swap), isFalse);
      expect(
        crossSide.supports(InfantryPinReassignmentStrategy.takeOver),
        isTrue,
      );

      final incompatible = InfantryPinPlanner.planReassignment(
        source,
        'gimbal.yaw.0.pin',
        'P60',
      );
      expect(
        incompatible.supports(InfantryPinReassignmentStrategy.swap),
        isFalse,
      );
    });

    test('当前引脚为空时只能抢占，未分配可直接应用', () {
      final source = completeInfantry(
        frictionMode: FrictionMode.disabled,
      ).copyWith(
        yawActuators: const [
          AxisActuator(
            drive: DriveType.servo,
            direction: Direction.forward,
          ),
        ],
      );
      final occupied = InfantryPinPlanner.planReassignment(
        source,
        'gimbal.yaw.0.pin',
        'P60',
      );
      expect(occupied.supports(InfantryPinReassignmentStrategy.swap), isFalse);
      expect(
        occupied.supports(InfantryPinReassignmentStrategy.takeOver),
        isTrue,
      );

      final cleared = InfantryPinPlanner.applyReassignment(
        completeInfantry(),
        'mechanism.feeder_pin',
        null,
        InfantryPinReassignmentStrategy.direct,
      );
      expect(cleared.feederPin, isNull);
    });

    test('固定摩擦轮通过显式事务让出或取得 P64/P66', () {
      final enabled = completeInfantry();
      final takePin = InfantryPinPlanner.planReassignment(
        enabled,
        'mechanism.feeder_pin',
        'P64',
      );
      expect(
        takePin.supports(
          InfantryPinReassignmentStrategy.disableFrictionAndTakeOver,
        ),
        isTrue,
      );
      final withoutFriction = InfantryPinPlanner.applyReassignment(
        enabled,
        'mechanism.feeder_pin',
        'P64',
        InfantryPinReassignmentStrategy.disableFrictionAndTakeOver,
      );
      expect(withoutFriction.frictionMode, FrictionMode.disabled);
      expect(withoutFriction.feederPin, 'P64');
      expect(withoutFriction.frictionMaxDuty, enabled.frictionMaxDuty);

      final enablePlan = InfantryPinPlanner.planFrictionEnablement(
        withoutFriction,
      );
      expect(enablePlan.occupants.single.ownerLabel, '拨弹电机');
      final restored = InfantryPinPlanner.applyFrictionEnablement(
        withoutFriction,
        InfantryPinReassignmentStrategy.enableFrictionAndTakeOver,
      );
      expect(restored.frictionMode, FrictionMode.brushlessEsc);
      expect(restored.feederPin, isNull);
      expect(restored.frictionMaxDuty, enabled.frictionMaxDuty);
    });

    test('同轴多个执行器各自占用引脚并可被抢占', () {
      final config = completeInfantry(frictionMode: FrictionMode.disabled)
          .copyWith(
            pitchActuators: const [
              AxisActuator(
                drive: DriveType.servo,
                pin: 'MP03',
                direction: Direction.forward,
                midOffset: 0,
              ),
              AxisActuator(
                drive: DriveType.servo,
                pin: 'P62',
                direction: Direction.reverse,
                midOffset: 10,
              ),
            ],
          );
      expect(
        InfantryPinPlanner.allowedPins(config, 'gimbal.pitch.1.pin'),
        InfantryPinPlanner.servoPins,
      );
      expect(
        InfantryPinPlanner.allowedPins(
          config.copyWith(
            yawActuators: const [
              AxisActuator(
                drive: DriveType.motor,
                pin: 'P62',
                direction: Direction.forward,
              ),
            ],
          ),
          'gimbal.yaw.0.pin',
        ),
        InfantryPinPlanner.motorPins,
      );
      expect(InfantryPinPlanner.derive(config)['P62']!.ownerLabel, 'Pitch 轴 2');
      expect(
        InfantryPinPlanner.occupantsOf(config, 'P62', 'gimbal.pitch.1.pin'),
        isEmpty,
      );
      expect(
        InfantryPinPlanner.occupantsOf(config, 'P60', 'gimbal.pitch.1.pin')
            .single
            .ownerLabel,
        '拨弹电机',
      );

      final taken = InfantryPinPlanner.applyReassignment(
        config,
        'gimbal.pitch.1.pin',
        'P60',
        InfantryPinReassignmentStrategy.takeOver,
      );
      expect(taken.pitchActuators[1].pin, 'P60');
      expect(taken.pitchActuators.first.pin, 'MP03');
      expect(taken.feederPin, isNull);
    });

    test('执行器逐个校验，空轴不报必填', () {
      final blank = InfantryConfig();
      expect(
        ProjectValidator.validate(
          blank,
        ).where((i) => i.fieldPath.startsWith('gimbal.')),
        isNotEmpty,
      );

      expect(
        ProjectValidator.validate(
          blank.copyWith(yawActuators: const [], pitchActuators: const []),
        ).where((i) => i.fieldPath.startsWith('gimbal.')),
        isEmpty,
      );

      final secondIncomplete =
          completeInfantry(frictionMode: FrictionMode.disabled).copyWith(
            pitchActuators: const [
              AxisActuator(
                drive: DriveType.servo,
                pin: 'MP03',
                direction: Direction.forward,
                midOffset: 0,
              ),
              AxisActuator(drive: DriveType.servo),
            ],
          );
      final missing = ProjectValidator.validate(secondIncomplete)
          .where((i) => i.fieldPath.startsWith('gimbal.pitch.1.'))
          .toList();
      expect(
        missing.map((i) => i.fieldPath),
        containsAll([
          'gimbal.pitch.1.pin',
          'gimbal.pitch.1.direction',
          'gimbal.pitch.1.mid_offset',
        ]),
      );
      expect(
        missing.every((i) => i.kind == ValidationIssueKind.required),
        isTrue,
      );

      final duplicated = secondIncomplete.copyWith(
        pitchActuators: const [
          AxisActuator(
            drive: DriveType.servo,
            pin: 'MP03',
            direction: Direction.forward,
            midOffset: 0,
          ),
          AxisActuator(
            drive: DriveType.servo,
            pin: 'MP03',
            direction: Direction.forward,
            midOffset: 0,
          ),
        ],
      );
      expect(
        ProjectValidator.validate(duplicated)
            .where((i) => i.message.contains('同时被'))
            .map((i) => i.fieldPath)
            .toSet(),
        containsAll(['gimbal.pitch.0.pin', 'gimbal.pitch.1.pin']),
      );
    });

    test('数字键包含 LC/RC 且排除摇杆轴', () {
      expect(digitalRemoteKeys, containsAll(['E', 'LC', 'RC']));
      expect(digitalRemoteKeys, isNot(contains('LX')));
    });
  });

  group('生成器', () {
    test('工程舵机单次持续生成按键沿和定点小数余量', () {
      final source = servoButtonEngineer();
      final config = source.copyWith(
        modeCount: 2,
        switchStrategy: SwitchStrategy.cycle,
        modeSwitchKey: 'E',
        modes: [
          EngineerModeConfig(
            preserveChassis: true,
            actions: [
              ActionMapping(
                key: 'A',
                direction: Direction.forward,
                mode: ControlMode.single,
                parameter: 1.25,
                pin: 'P60',
              ),
              ActionMapping(
                key: 'B',
                direction: Direction.reverse,
                mode: ControlMode.continuous,
                parameter: 0.5,
                pin: 'MP03',
              ),
            ],
          ),
          EngineerModeConfig(
            actions: [
              ActionMapping(
                key: 'C',
                direction: Direction.reverse,
                mode: ControlMode.single,
                parameter: 0.01,
                pin: 'MP74',
              ),
            ],
          ),
        ],
      );
      final code = CodeGenerator.generate(config);

      expect(code, contains('int32_t servoButtonRemainder[3] = {0};'));
      expect(code, contains('uint8_t servoButtonKeyLast[2] = {0};'));
      expect(
        code,
        contains('if (RcKeyValueRead(KEY_OFFSET_A) && !servoButtonKeyLast[0])'),
      );
      expect(
        code,
        contains('servoButtonKeyLast[0] = RcKeyValueRead(KEY_OFFSET_A);'),
      );
      expect(
        code,
        isNot(
          contains('servoButtonKeyLast[1] = RcKeyValueRead(KEY_OFFSET_B);'),
        ),
      );
      expect(code, contains('if (RcKeyValueRead(KEY_OFFSET_B))'));
      expect(code, contains('servoButtonRemainder[0] += 125000L;'));
      expect(code, contains('servoButtonRemainder[1] += -50000L;'));
      expect(code, contains('servoButtonRemainder[2] += -1000L;'));
      expect(code, contains('servoButtonRemainder[0] / 18000L'));
      expect(code, contains('servoButtonRemainder[0] %= 18000L'));
      expect(code, contains('dutyOfMotor[0] += (int)'));
      expect(code, contains('mainServoDuty[0] += (int)'));
      expect(code, contains('servoButtonRemainder[0] = 0;'));
      expect(code, contains('static void SyncServoButtonKeys(uint8_t mode)'));
      expect(code, contains('servoButtonStateMode != currentMode'));
      expect(
        code.indexOf('SyncServoButtonKeys(currentMode);'),
        lessThan(code.indexOf('switch (currentMode)')),
      );
      expect(code, contains('int mainServoDuty[2]'));
    });

    test('工程舵机直接模式生成预设点位上升沿且不使用小数余量', () {
      final source = servoButtonEngineer();
      final config = source.copyWith(
        pwm: source.pwm.copyWith(
          servoMids: {...source.pwm.servoMids, 'P60': 60, 'MP03': -60},
        ),
        modes: [
          EngineerModeConfig(
            preserveChassis: true,
            actions: [
              ActionMapping(
                key: 'A',
                direction: Direction.forward,
                mode: ControlMode.direct,
                parameter: 90,
                pin: 'P60',
              ),
              ActionMapping(
                key: 'B',
                direction: Direction.reverse,
                mode: ControlMode.direct,
                parameter: 90,
                pin: 'MP03',
              ),
            ],
          ),
        ],
      );
      final code = CodeGenerator.generate(config);

      expect(code, isNot(contains('servoButtonRemainder')));
      expect(code, contains('uint8_t servoButtonKeyLast[2] = {0};'));
      expect(
        code,
        contains(
          'if (RcKeyValueRead(KEY_OFFSET_A) && !servoButtonKeyLast[0]) dutyOfMotor[0] = 1250;',
        ),
      );
      expect(
        code,
        contains(
          'if (RcKeyValueRead(KEY_OFFSET_B) && !servoButtonKeyLast[1]) mainServoDuty[0] = 250;',
        ),
      );
      expect(
        code,
        contains('servoButtonKeyLast[0] = RcKeyValueRead(KEY_OFFSET_A);'),
      );
      expect(
        code,
        contains('servoButtonKeyLast[1] = RcKeyValueRead(KEY_OFFSET_B);'),
      );
      expect(code, contains('static void SyncServoButtonKeys(uint8_t mode)'));
      expect(
        code.indexOf('SyncServoButtonKeys(currentMode);'),
        lessThan(code.indexOf('switch (currentMode)')),
      );
    });

    test('底盘转向反向仅在启用时取反 turnSpeed', () {
      final standardConfig = completeInfantry().copyWith(
        arrowBehavior: ArrowBehavior.move,
      );
      final standard = CodeGenerator.generate(standardConfig);
      expect(standard, isNot(contains('turnSpeed = -turnSpeed;')));

      final reversed = CodeGenerator.generate(
        standardConfig.copyWith(
          chassis: standardConfig.chassis.copyWith(turnReversed: true),
        ),
      );
      const calculation =
          'turnSpeed = (int)(((int32_t)valueOfRoker[0][0] * (int32_t)speed) / 2047L);';
      const inversion = 'turnSpeed = -turnSpeed;';
      const firstWheel = 'dutyOfMotor[4] = baseSpeed - turnSpeed;';
      expect(reversed.split(inversion), hasLength(2));
      expect(
        reversed.indexOf(calculation),
        lessThan(reversed.indexOf(inversion)),
      );
      expect(
        reversed.indexOf(inversion),
        lessThan(reversed.indexOf(firstWheel)),
      );
      expect(reversed, contains('valueOfRoker[0][0] = -2047'));
      expect(reversed, contains('valueOfRoker[0][0] = 2047'));
      expect(reversed.replaceFirst('    $inversion\n', ''), standard);
    });

    test('完整步兵配置生成且使用按键宏和实际槽位', () {
      final code = CodeGenerator.generate(
        completeInfantry().copyWith(triggerKey: 'LC', frictionKey: 'RC'),
      );
      expect(code, contains('KEY_OFFSET_Rocker11'));
      expect(code, contains('KEY_OFFSET_Rocker21'));
      expect(code, contains('#include <stdlib.h>'));
      expect(code, isNot(contains('#include "MATH.H"')));
      expect(code, contains('dutyOfMotor[0]'));
      expect(code, contains('FRICTION_START_DUTY 500'));
      expect(code, contains('retry < 20'));
      expect(code, contains('static void Uart1TxQuery(uint8_t dat)'));
      expect(code, contains('Uart1TxQuery(control_frame_pack[i])'));
      expect(code, isNot(contains('Uart1SendFrameQuery')));
      expect(code, isNot(contains('uint8_t globalInterruptEnabled = EA;')));
      expect(
        code,
        contains(
          'baseSpeed = (int)(((int32_t)valueOfRoker[0][1] * (int32_t)speed) / 2047L);',
        ),
      );
      expect(code, isNot(contains('baseSpeed = (int)((float)')));
      expect(code, isNot(contains('turnSpeed = (int)((float)')));
      expect(
        code,
        isNot(contains('UART_PutChar(UART_1, control_frame_pack[i])')),
      );
      expect(code, contains('P2INTE &= ~GPIO_Pin_6'));
      expect(code, contains('StepBegin(0)'));
      expect(code, contains('UpdateBuzzerFeedback'));
      expect(
        'Ms_Delay(EXPANSION_FRAME_GAP_MS);'.allMatches(code).length,
        greaterThanOrEqualTo(2),
      );
    });

    test('禁用摩擦轮后不生成摩擦轮状态机', () {
      final code = CodeGenerator.generate(
        completeInfantry(frictionMode: FrictionMode.disabled),
      );
      expect(code, isNot(contains('FRICTION_START_DUTY')));
    });

    test('摩擦轮启停跳过 0~500 无效区间', () {
      final code = CodeGenerator.generate(completeInfantry());
      // 启动：低于最低有效占空比时直接跳到 500，不从 0 逐格爬上来
      expect(
        code,
        contains(
          'if (frictionTargetDuty >= FRICTION_START_DUTY && frictionDuty < FRICTION_START_DUTY)',
        ),
      );
      // 停机：降到最低有效占空比后直接归零，不在 0~500 之间逐格磨
      expect(
        code,
        contains(
          'if (frictionTargetDuty == 0 && frictionDuty <= FRICTION_START_DUTY)',
        ),
      );
      // 旧写法只在 duty 恰好为 0 时跳变，关闭途中重新开启会从 0~500 之间
      // 渐变上去，不应再出现
      expect(code, isNot(contains('frictionStartedThisCycle')));
    });

    test('未设置反向拨弹键时不生成任何反向逻辑', () {
      final code = CodeGenerator.generate(completeInfantry());
      expect(code, isNot(contains('reverseFeed')));
      expect(code, isNot(contains('reverse_feed')));
    });

    test('反向拨弹键按住持续反转并在松开时归零', () {
      String reverseBranch(String code) => code.substring(
        code.indexOf('    if (reverseFeed) {'),
        code.indexOf('    lastTrigger = trigger;'),
      );
      final blocking = CodeGenerator.generate(
        completeInfantry(reverseFeedKey: 'D'),
      );
      expect(
        blocking,
        contains('uint8_t reverseFeed = RcKeyValueRead(KEY_OFFSET_D);'),
      );
      // 反转占空比与拨弹方向相反：正向拨弹时取负
      expect(reverseBranch(blocking), contains('dutyOfMotor[0] = -6000;'));
      // 松开反向键必须归零，不能停在反转占空比上
      expect(reverseBranch(blocking), contains('dutyOfMotor[0] = 0;'));
      expect(reverseBranch(blocking), contains('Ms_Delay(250)'));

      final visual = CodeGenerator.generate(
        completeInfantry(
          feedMode: FeedMode.visualClosedLoop,
          reverseFeedKey: 'D',
        ),
      );
      expect(reverseBranch(visual), contains('dutyOfMotor[0] = -6000;'));
      expect(
        reverseBranch(visual),
        contains('dutyOfMotor[0] = trigger ? 6000 : 0;'),
      );
      expect(visual, isNot(contains('Ms_Delay(250)')));

      // 拨弹方向本身为反向时，退弹方向翻转为正
      final reversedFeeder = CodeGenerator.generate(
        completeInfantry(reverseFeedKey: 'D')
            .copyWith(feederDirection: Direction.reverse),
      );
      expect(reverseBranch(reversedFeeder), contains('dutyOfMotor[0] = 6000;'));
      expect(
        reverseBranch(reversedFeeder),
        contains('dutyOfMotor[0] = -6000;'),
      );
    });

    test('工程完整配置可以生成', () {
      expect(CodeGenerator.generate(completeEngineer()), contains('RunMode1'));
    });

    test('同轴多个执行器各自生成控制语句', () {
      final config = completeInfantry(frictionMode: FrictionMode.disabled)
          .copyWith(
            zeroEnabled: true,
            pitchActuators: const [
              AxisActuator(
                drive: DriveType.servo,
                pin: 'MP03',
                direction: Direction.forward,
                midOffset: 0,
              ),
              AxisActuator(
                drive: DriveType.servo,
                pin: 'P64',
                direction: Direction.reverse,
                midOffset: 10,
              ),
              AxisActuator(
                drive: DriveType.motor,
                pin: 'P62',
                direction: Direction.forward,
              ),
            ],
          );
      final code = CodeGenerator.generate(config);
      expect(code, contains('uint16_t pitchDuty2 = 806;'));
      expect(
        code,
        contains(
          '    pitchDuty2 += (int)((float)valueOfRoker[1][1] * 2.0f / 2047.0f * 5.555556f);',
        ),
      );
      expect(
        code,
        contains(
          '    if (pitchDuty2 < 473) pitchDuty2 = 473; if (pitchDuty2 > 1139) pitchDuty2 = 1139;',
        ),
      );
      expect(
        code,
        contains(
          '    dutyOfMotor[1] = (int)(((int32_t)valueOfRoker[1][1] * 10000L) / 2047L);',
        ),
      );
      expect(
        code,
        contains(
          'if (RcKeyValueRead(KEY_OFFSET_Rocker21)) { yawDuty = 750; pitchDuty = 750; pitchDuty2 = 806; }',
        ),
      );
      expect(code, contains('static uint16_t lastFeedbackDuty[3] = {0};'));
      expect(code, contains('pitchDuty2,abs(dutyOfMotor[3])'));
    });

    test('空轴不生成占空比变量和控制语句', () {
      final config = completeInfantry(
        frictionMode: FrictionMode.disabled,
      ).copyWith(pitchActuators: const []);
      final code = CodeGenerator.generate(config);
      expect(code, contains('uint16_t yawDuty = 750;'));
      expect(code, isNot(contains('pitchDuty')));
      expect(code, isNot(contains('valueOfRoker[1][1] * 2.0f')));
    });

    test('步兵两种拨弹、方向键、摩擦轮和蜂鸣器条件进入代码', () {
      final visual = CodeGenerator.generate(
        completeInfantry(feedMode: FeedMode.visualClosedLoop)
            .copyWith(arrowBehavior: ArrowBehavior.move, buzzerDisabled: true),
      );
      expect(visual, contains('= trigger ? 6000 : 0'));
      expect(visual, isNot(contains('Ms_Delay(250)')));
      expect(visual, contains('KEY_OFFSET_UP'));
      expect(visual, isNot(contains('Beep(')));

      final sprint = CodeGenerator.generate(
        completeInfantry().copyWith(arrowBehavior: ArrowBehavior.sprint),
      );
      expect(sprint, contains('maxSpeed = ultraSpeed'));
    });

    test('工程六种控制方式、两种切换策略和蜂鸣反馈可生成', () {
      final cycle = advancedEngineer();
      expect(
        ProjectValidator.validate(cycle)
            .where((i) => i.severity == IssueSeverity.error),
        isEmpty,
      );
      final cycleCode = CodeGenerator.generate(cycle);
      expect(cycleCode, contains('ModeSwitchFeedback'));
      expect(cycleCode, contains('PrepareMode'));
      expect(cycleCode, contains('servoButtonRemainder'));
      expect(cycleCode, contains('/ 2047'));
      expect(cycleCode, contains('Dir_Change_Order'));
      expect(cycleCode, contains('static void Uart1TxQuery(uint8_t dat)'));
      expect(cycleCode, contains('Uart1TxQuery(control_frame_pack[i])'));
      expect(cycleCode, isNot(contains('Uart1SendFrameQuery')));
      expect(cycleCode, isNot(contains('baseSpeed = (int)((float)')));
      expect(cycleCode, isNot(contains('turnSpeed = (int)((float)')));
      expect(
        cycleCode,
        isNot(contains('UART_PutChar(UART_1, control_frame_pack[i])')),
      );
      expect(
        cycleCode,
        contains(
          'ExpansionBoradControl(Init_Order, 50, 50, 50, 50, 10000, 10000, 10000, 10000);\n'
          '    Ms_Delay(EXPANSION_FRAME_GAP_MS);',
        ),
      );

      final directCode = CodeGenerator.generate(
        advancedEngineer(strategy: SwitchStrategy.direct, buzzerDisabled: true),
      );
      expect(directCode, contains('modeKeyLast[0]'));
      expect(directCode, isNot(contains('ModeSwitchFeedback')));
      expect(directCode, isNot(contains('Beep(')));
    });

    test('音乐项目请求汇编输出 SDCC as251 源码', () {
      final config = MusicConfig(
        notes: const [
          MusicNote(id: 'c4', pitch: 60, startTick: 0, durationTicks: 480),
          MusicNote(id: 'e4', pitch: 64, startTick: 720, durationTicks: 480),
        ],
        tempoEvents: const [
          TempoEvent(tick: 0, microsecondsPerQuarter: 500000),
          TempoEvent(tick: 960, microsecondsPerQuarter: 400000),
        ],
      );
      expect(CodeGenerator.asmSupported(ProjectKind.music), isTrue);

      final asm = CodeGenerator.generate(config, target: OutputTarget.asm);
      // 复位向量、程序入口与栈底标记：与 SDCC 生成的主模块骨架一致。
      expect(asm, contains('__interrupt_vect:'));
      expect(asm, contains('__sdcc_program_startup:'));
      expect(asm, contains('__start__stack:'));
      // 库函数 extern 与调用约定（下划线前缀、ecall 调用）。
      expect(asm, contains('.globl\t_Board_Init'));
      expect(asm, contains('.globl\t_Ms_Delay'));
      expect(asm, contains('.globl\t_PWM_Init'));
      expect(asm, contains('.globl\t_PWM_SET_Frequency'));
      expect(asm, contains('ecall\t_Ms_Delay'));
      expect(asm, contains('ecall\t_PWM_SET_Frequency'));
      expect(asm, contains('mov\tdpl, #(PWMB_CH3_P33)'));
      // 与 C 版一一对应的函数骨架。
      expect(asm, contains('_Music_Wait:'));
      expect(asm, contains('_Music_Stop:'));
      expect(asm, contains('_Music_PlaySegment:'));
      expect(asm, contains('_Music_PlayOnce:'));
      expect(asm, contains('_All_Init:'));
      expect(asm, contains('_main:'));
      // 频率表：音符 69（A4）= 440 Hz = 0x01B8，大端存放。
      expect(asm, contains('#0x01, #0xb8'));
      // 段表：C4 500ms、休止 250ms、E4 500ms → 共 3 段。
      expect(asm, contains('MUSIC_SEGMENT_COUNT = 3'));
      expect(asm, contains('_musicSegmentDurations:'));
      expect(asm, contains('_musicSegmentNotes:'));
      expect(asm, contains('休止'));
      // Channal 由 All_Init 显式写入，等价 C 版静态初始化。
      expect(asm, contains('mov\ta, #0x24'));
    });

    test('非音乐项目请求汇编输出抛出 UnsupportedError', () {
      expect(CodeGenerator.asmSupported(ProjectKind.infantry), isFalse);
      expect(CodeGenerator.asmSupported(ProjectKind.engineer), isFalse);
      expect(CodeGenerator.asmSupported(ProjectKind.debug), isFalse);
      expect(
        () => CodeGenerator.generate(
          completeInfantry(),
          target: OutputTarget.asm,
        ),
        throwsUnsupportedError,
      );
    });
  });
}
