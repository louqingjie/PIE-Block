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
  frictionP64MaxDuty: frictionMode == FrictionMode.brushlessEsc ? 800 : null,
  frictionP66MaxDuty: frictionMode == FrictionMode.brushlessEsc ? 700 : null,
  frictionLevelStep: frictionMode == FrictionMode.brushlessEsc ? 10 : null,
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
      value: 800,
    ),
    const DebugTestItem(
      pin: 'P66',
      enabled: true,
      driveType: DebugDriveType.friction,
      direction: Direction.forward,
      value: 600,
    ),
    const DebugTestItem(
      pin: 'MP03',
      enabled: true,
      driveType: DebugDriveType.servo,
      direction: Direction.reverse,
      value: 30,
      durationMs: 4200,
    ),
    for (final pin in debugPins.where(
      (pin) => pin != 'P64' && pin != 'P66' && pin != 'MP03',
    ))
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
    test('格式 16 往返并保存向导进度', () {
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
      expect(source.toJson()['format_version'], 16);
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
      expect(config.tests.first.direction, isNull);
      expect(config.tests[2].durationMs, 4200);
      expect(config.tests.first.toJson(), isNot(contains('direction')));
      expect(config.tests.first.toJson(), isNot(contains('duration_ms')));
      // 调试项目的摩擦轮项直接保存目标占空比，不再有独立的上限字段。
      expect(config.tests.first.value, 800);
      expect(config.tests[1].value, 600);
      expect(config.toJson(), isNot(contains('friction_p64_max_duty')));
      expect(config.toJson(), isNot(contains('friction_p66_max_duty')));

      final legacyFriction = DebugTestItem.fromJson({
        ...config.tests.first.toJson(),
        'direction': Direction.reverse.name,
      });
      expect(legacyFriction.direction, isNull);
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

    test('摩擦轮比例映射律：油门 0% 落在启动占空比，满油落在各自上限', () {
      // 需求里的基准算例：P64 上限 700、P66 上限 800，中油门应得 600 / 650。
      expect(Friction.dutyOfLevel(50, 700), 600);
      expect(Friction.dutyOfLevel(50, 800), 650);
      for (final maxDuty in [700, 800]) {
        expect(Friction.dutyOfLevel(0, maxDuty), Friction.startDuty);
        expect(Friction.dutyOfLevel(100, maxDuty), maxDuty);
        // 映射单调不减，且始终落在 [启动占空比, 满油上限] 区间内。
        var previous = 0;
        for (var level = 0; level <= Friction.levelMax; level++) {
          final duty = Friction.dutyOfLevel(level, maxDuty);
          expect(duty, greaterThanOrEqualTo(previous));
          expect(duty, inInclusiveRange(Friction.startDuty, maxDuty));
          previous = duty;
        }
      }
      // 越界的油门按量程夹紧，不外插。
      expect(Friction.dutyOfLevel(-10, 800), Friction.startDuty);
      expect(Friction.dutyOfLevel(200, 800), 800);
    });

    test('摩擦轮两侧上限各自校验且油门步长限定在量程内', () {
      List<String> messages(InfantryConfig config) =>
          ProjectValidator.validate(config)
              .map((issue) => issue.message)
              .toList();

      expect(
        messages(completeInfantry().copyWith(frictionP64MaxDuty: 750)),
        contains(contains('P64 摩擦轮最大占空比必须是 500–800 内的整百值')),
      );
      expect(
        messages(completeInfantry().copyWith(frictionP66MaxDuty: 900)),
        contains(contains('P66 摩擦轮最大占空比必须在 500–800 之间')),
      );
      expect(
        messages(completeInfantry().copyWith(frictionLevelStep: 0)),
        contains(contains('摩擦轮油门步长必须在 1–100 之间')),
      );
      expect(
        messages(completeInfantry().copyWith(frictionLevelStep: 101)),
        contains(contains('摩擦轮油门步长必须在 1–100 之间')),
      );
      // 两侧上限不同是正常配置，不应产生任何摩擦轮相关问题。
      expect(
        messages(
          completeInfantry().copyWith(
            frictionP64MaxDuty: 700,
            frictionP66MaxDuty: 800,
          ),
        ).where((message) => message.contains('摩擦轮')),
        isEmpty,
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

    test('调试曲线的摩擦轮目标就是配置的占空比', () {
      final code = CodeGenerator.generate(completeDebug());
      expect(code.indexOf('1. P64'), lessThan(code.indexOf('2. P66')));
      expect(code.indexOf('2. P66'), lessThan(code.indexOf('3. MP03')));
      // 每个摩擦轮只设一个目标，值就是测试项里填的占空比（P64 800、P66 600），
      // 不再做「油门 → 满油上限」换算；斜坡到位后停留观察，再设目标 0 停机。
      expect(code, contains('FrictionRampTo(2, 800)'));
      expect(code, contains('FrictionRampTo(2, 0)'));
      expect(code, contains('FrictionRampTo(3, 600)'));
      expect(code, contains('FrictionRampTo(3, 0)'));
      expect(code, isNot(contains('FrictionRampTo(3, 800)')));
      expect(code, contains('Ms_Delay(4200);'));
      expect(code, contains('PWM_SET_Frequency(PWMB_CH4_P03, 50, 0);'));
      expect(code, contains('static void Uart1TxQuery(uint8_t dat)'));
      expect(code, contains('Uart1TxQuery(control_frame_pack[i])'));
      expect(code, isNot(contains('Uart1SendFrameQuery')));
      expect(code, isNot(contains('uint8_t globalInterruptEnabled = EA;')));
      expect(
        code,
        isNot(contains('UART_PutChar(UART_1, control_frame_pack[i])')),
      );
    });

    test('P64/P66 摩擦轮不发方向帧且不要求配置方向', () {
      String generateFor(String pin, {Direction? legacyDirection}) {
        return CodeGenerator.generate(
          DebugConfig(
            tests: [
              DebugTestItem(
                pin: pin,
                enabled: true,
                driveType: DebugDriveType.friction,
                direction: legacyDirection,
                value: pin == 'P64' ? 800 : 700,
              ),
              for (final candidate in debugPins.where((value) => value != pin))
                DebugTestItem(pin: candidate),
            ],
          ),
        );
      }

      // 摩擦轮方向固定，测试不再发送方向帧：设定频率后直接跑斜坡。
      final p64 = generateFor('P64', legacyDirection: Direction.reverse);
      expect(p64, isNot(contains('ExpansionBoradControl(Dir_Change_Order')));
      expect(
        p64.indexOf('ExpansionBoradControl(Init_Order'),
        lessThan(p64.indexOf('FrictionRampTo(2, 800)')),
      );

      final p66 = generateFor('P66');
      expect(p66, isNot(contains('ExpansionBoradControl(Dir_Change_Order')));
      expect(
        p66.indexOf('ExpansionBoradControl(Init_Order'),
        lessThan(p66.indexOf('FrictionRampTo(3, 700)')),
      );
    });

    test('拓展板 Init 只在 PWM 组频率变化时重发', () {
      final code = CodeGenerator.generate(
        DebugConfig(
          tests: [
            const DebugTestItem(
              pin: 'P60',
              enabled: true,
              driveType: DebugDriveType.motor,
              direction: Direction.forward,
              value: 2000,
              durationMs: 3000,
            ),
            const DebugTestItem(
              pin: 'P64',
              enabled: true,
              driveType: DebugDriveType.friction,
              value: 800,
            ),
            const DebugTestItem(
              pin: 'P66',
              enabled: true,
              driveType: DebugDriveType.friction,
              value: 700,
            ),
            for (final pin in debugPins.where(
              (pin) => pin != 'P60' && pin != 'P64' && pin != 'P66',
            ))
              DebugTestItem(pin: pin),
          ],
        ),
      );

      // P60 要 PWMA=10000Hz，换一次；P64 回到 50Hz，再换一次；P66 与 P64
      // 同频不重复。加上循环开头那次复位，共 3 次 Init。
      expect('ExpansionBoradControl(Init_Order, '.allMatches(code).length, 3);
      expect(
        code,
        contains('Init_Order, 10000, 10000, 10000, 10000, 50, 50, 50, 50'),
      );
      expect(code, contains('Init_Order, 50, 50, 50, 50, 50, 50, 50, 50'));
    });

    test('摩擦轮测试先做 500 占空比激活 1000ms 且期间不发蜂鸣', () {
      final code = CodeGenerator.generate(completeDebug());
      expect(code, contains('#define FRICTION_ACTIVATE_MS 1000'));

      // 激活函数本体：给 500 启动占空比 → 静音 → 保持 1000ms；不含 5000
      // 占空比（5000 是蜂鸣器发声用的占空比，出现即表示激活期间会响）。
      final activateBody = code.substring(
        code.indexOf('static void FrictionActivate'),
        code.indexOf('static void FrictionRampTo'),
      );
      expect(activateBody, contains('frictionDuty = FRICTION_START_DUTY;'));
      expect(
        activateBody,
        contains('PWM_SET_Frequency(BUZZER_CH, BUZZER_IDLE_FREQ, 0);'),
      );
      expect(activateBody, isNot(contains('5000')));
      expect(activateBody, contains('Ms_Delay(FRICTION_ACTIVATE_MS);'));

      // 每个摩擦轮测试项都先激活，再爬目标。
      expect(
        code.indexOf('FrictionActivate(2);'),
        lessThan(code.indexOf('FrictionRampTo(2, 800);')),
      );
    });

    test('调试提示音用一条上行音型表示第 N 项', () {
      final code = CodeGenerator.generate(completeDebug());

      // 方案总览注释应描述音型方案，不是旧的「轮廓 + 点数」双通道。
      expect(code, contains('一条上行音型 C6-E6-G6-C7-E7'));

      // 音高全部走宏。
      expect(code, contains('#define CUE_C6 1047'));
      expect(code, contains('#define CUE_G6 1568'));
      expect(code, contains('#define CUE_C7 2093'));
      expect(code, contains('#define CUE_E7 2637'));
      expect(code, contains('#define CUE_G5 784'));
      expect(code, contains('#define CUE_MOTIF_LEN 5'));
      expect(code, contains('#define CUE_SECTION_GAP_MS 300'));
      // 结束区（回落乐句）已删除，它的时值宏不应残留。
      expect(code, isNot(contains('DoneCue')));
      expect(code, isNot(contains('CUE_EVENT_DONE_MS')));
      expect(code, isNot(contains('CUE_EVENT_GAP_MS')));

      // 收尾旋律（《卡农》全部完成音）与它的循环宏已移除：没有「全部完成」这一档。
      expect(code, isNot(contains('AllDoneCue')));
      expect(code, isNot(contains('CUE_ALLDONE_REPEAT_MS')));

      // 全部完成改为《卡农》曲谱后，旧的琶音时值宏应被收敛掉。
      expect(code, isNot(contains('CUE_ALLDONE_NOTE_MS')));
      expect(code, isNot(contains('CUE_ALLDONE_TAIL_MS')));

      // 音型取音高用 switch，避开 SDCC 的数组变址取错字节问题。
      expect(
        code,
        contains('static uint16_t MotifNote(uint8_t index, uint8_t high)'),
      );
      expect(code, contains('case 0: return (uint16_t)(CUE_C6 * octave);'));

      // 开始区已删除：个数本身就是序号，不再先播一遍完整音型。
      // 连同它的时值宏一起收敛掉，避免留下没人用的宏。
      expect(code, isNot(contains('static void ReadyCue')));
      expect(code, isNot(contains('ReadyCue();')));
      expect(code, isNot(contains('CUE_EVENT_NOTE_MS')));
      expect(code, isNot(contains('Beep(MotifNote(i, 0)')));

      // 全部完成是《卡农》：这条收尾旋律已随循环调试一并移除。
      expect(code, isNot(contains('Beep(147, 1333);')));
      expect(code, isNot(contains('Beep(740, 2667);')));

      // 步序用同一套音区进位公式。
      expect(code, contains('#define CUE_ZONE_SPAN 5'));
      expect(code, contains('#define CUE_UNIT_MS 220'));
      expect(code, contains('#define CUE_GAP_MS 140'));
      expect(
        code,
        contains('zone = (uint8_t)((step - 1) / CUE_ZONE_SPAN);'),
      );
      expect(
        code,
        contains('count = (uint8_t)((step - 1) % CUE_ZONE_SPAN + 1);'),
      );

      // 分区停顿只留一处：步序音与随后的测试动作之间。
      expect(
        code,
        contains('        StepCue(1);\n        Ms_Delay(CUE_SECTION_GAP_MS);'),
      );
      expect('Ms_Delay(CUE_SECTION_GAP_MS);'.allMatches(code).length, 3);

      // 每个测试项按顺序播自己的步序码，步号从 1 连续递增。
      expect(code, contains('StepCue(1);'));
      expect(code, contains('StepCue(2);'));
      expect(code, contains('StepCue(3);'));
      expect(
        code.indexOf('StepCue(1);'),
        lessThan(code.indexOf('StepCue(2);')),
      );
      expect(
        code.indexOf('StepCue(2);'),
        lessThan(code.indexOf('StepCue(3);')),
      );

      // 整段序列改为循环执行：测试项只写一遍，全部包在 while (1) 里。
      const loopHead = '\n    while (1)\n    {';
      expect(loopHead.allMatches(code).length, 1);
      expect(code.indexOf(loopHead), lessThan(code.indexOf('StepCue(1);')));
      expect(code, isNot(contains('AllDoneCue')));
      expect(code, isNot(contains('CUE_ALLDONE_REPEAT_MS')));

      // 旧版两个平音常量不应残留。
      expect(code, isNot(contains('BUZZER_FREQ_READY')));
      expect(code, isNot(contains('BUZZER_FREQ_DONE')));
    });

    test('步序用上行音型的前 N 个音表示第 N 项', () {
      // 项 1~5：低音区，音数 = 序号，且正好是上行音型的前 count 个音。
      for (var index = 1; index <= 5; index++) {
        final notes = DebugCues.step(index)
            .where((note) => note.frequencyHz != null)
            .map((note) => note.frequencyHz!)
            .toList();
        expect(notes.length, index, reason: '第 $index 项应有 $index 个音');
        expect(
          notes,
          DebugCues.ascentLow.take(index).toList(),
          reason: '第 $index 项应是上行音型的前 $index 个音',
        );
      }
      // 项 6~10：整体升八度，音数继续按 (N-1)%5+1 走。
      for (var index = 6; index <= 10; index++) {
        final count = (index - 1) % 5 + 1;
        final notes = DebugCues.step(index)
            .where((note) => note.frequencyHz != null)
            .map((note) => note.frequencyHz!)
            .toList();
        expect(notes.length, count);
        expect(
          notes,
          DebugCues.ascentHigh.take(count).toList(),
          reason: '第 $index 项应是高八度音型的前 $count 个音',
        );
      }

      // 越界序号不抛异常，按最后一段处理。
      expect(DebugCues.step(0), isNotEmpty);
      expect(DebugCues.step(-3), isNotEmpty);
      expect(DebugCues.step(99), isNotEmpty);

      // 音型本身单调递增（它只是被 step() 按个数取前缀，不再单独播一遍，
      // 但它仍是整个方案的音高来源，所以这里的顺序性质要守住）。
      for (var i = 1; i < DebugCues.ascentLow.length; i++) {
        expect(DebugCues.ascentLow[i] > DebugCues.ascentLow[i - 1], isTrue,
            reason: '上行音型第 $i 个音应高于前一个');
      }

      // 上行音型的第一个音仍是整条方案的音高基准。
      expect(DebugCues.ascentLow.first, DebugCues.noteC6);
    });

    test('步序提示就是一段上行、内部只有间隔没有停顿', () {
      // 分区停顿（固件里那段）必须明显长于步序音之间的内部间隔。
      expect(DebugCues.sectionGapMs, greaterThan(DebugCues.gapMs * 2));

      for (var index = 1; index <= 10; index++) {
        final count = (index - 1) % 5 + 1;
        final notes = DebugCues.step(index);
        final voiced = notes.where((n) => n.frequencyHz != null).toList();

        expect(voiced.length, count, reason: '第 $index 项应有 $count 个音');
        // 音之间只有间隔；提示里没有额外的段落（既没有前奏，也没有回落）。
        expect(notes.where((n) => n.frequencyHz == null).length, count - 1);
        expect(notes.first.frequencyHz, isNotNull);
        expect(notes.last.frequencyHz, isNotNull);

        // 单调上行。
        for (var i = 1; i < voiced.length; i++) {
          expect(voiced[i].frequencyHz! > voiced[i - 1].frequencyHz!, isTrue,
              reason: '第 $index 项应单调上行');
        }
        // 时值只有两种：单元音与音间间隔。
        expect(voiced.every((n) => n.durationMs == DebugCues.unitMs), isTrue);
        expect(
          notes
              .where((n) => n.frequencyHz == null)
              .every((n) => n.durationMs == DebugCues.gapMs),
          isTrue,
        );
      }

      // 两个音区相差一个八度：十二平均律取整有 ±2Hz 误差。
      for (var i = 0; i < DebugCues.ascentLow.length; i++) {
        expect(
          (DebugCues.ascentHigh[i] - DebugCues.ascentLow[i] * 2).abs(),
          lessThanOrEqualTo(2),
          reason: '音型第 $i 个音的高低八度应相差一倍',
        );
      }
    });

    test('调试序列跑完最后一项后自动回到第 1 项', () {
      final code = CodeGenerator.generate(completeDebug());

      // 测试项只写一遍，整段包在 while (1) 里循环执行；没有收尾旋律。
      // 按「换行 + 缩进 + while (1)」匹配，避开文件头注释里提到的同名文字。
      const loopHead = '\n    while (1)\n    {';
      expect(loopHead.allMatches(code).length, 1);
      expect(code.indexOf(loopHead), lessThan(code.indexOf('StepCue(1);')));
      expect('StepCue(1);'.allMatches(code).length, 1);
      expect('StepCue(3);'.allMatches(code).length, 1);
      // 结束区的回落乐句已删除。
      expect(code, isNot(contains('DoneCue')));
      expect(code, isNot(contains('AllDoneCue')));
      expect(code, isNot(contains('CUE_ALLDONE_REPEAT_MS')));

      // 每轮开头把 PWM 组频率复位到 main 起始的 50Hz：逐项那条 Init 是生成期
      // 按静态顺序算出来的，只有每轮都从这个状态起步，第二轮及以后才继续成立。
      expect(
        code,
        contains(
          'ExpansionBoradControl(Init_Order, 50, 50, 50, 50, 50, 50, 50, 50);'
          '\n        Ms_Delay(20);',
        ),
      );
      expect(
        code.indexOf(
          'ExpansionBoradControl(Init_Order, 50, 50, 50, 50, 50, 50, 50, 50);',
        ),
        lessThan(code.indexOf('StepCue(1);')),
      );

      // 最后一项之后同样留出项间间隔，再八路归零，然后才回到第 1 项。
      final lastGap = code.lastIndexOf('Ms_Delay(TEST_GAP_MS);');
      expect(lastGap, greaterThan(code.indexOf('StepCue(3);')));
      final zeroAt = code.indexOf(
        'ExpansionBoradControl(Duty_Change_Order, 0, 0, 0, 0, 0, 0, 0, 0);',
        lastGap,
      );
      expect(zeroAt, greaterThan(lastGap));
      // 归零就是循环体末尾：其后只有循环体的收尾。
      expect(code.substring(zeroAt), isNot(contains('StepCue(')));
    });

    test('摩擦轮目标占空比限定 500–800，低于 600 只给提醒', () {
      DebugConfig withDuty(int? duty) => DebugConfig(
        tests: [
          DebugTestItem(
            pin: 'P64',
            enabled: true,
            driveType: DebugDriveType.friction,
            value: duty,
          ),
          for (final pin in debugPins.where((pin) => pin != 'P64'))
            DebugTestItem(pin: pin),
        ],
      );
      List<ValidationIssue> issues(int? duty) =>
          ProjectValidator.validate(withDuty(duty));
      List<String> messages(int? duty) =>
          issues(duty).map((issue) => issue.message).toList();

      // 超出 500–800 是错误。
      for (final duty in const [400, 900]) {
        expect(
          messages(duty),
          contains(contains('P64 摩擦轮目标占空比必须在 500–800 之间')),
        );
        expect(
          issues(duty).firstWhere((i) => i.fieldPath == 'tests.0.value').severity,
          IssueSeverity.error,
        );
      }
      // 500 合法但偏低：只给提醒，不是错误。
      final low = issues(500);
      final lowIssue = low.firstWhere((i) => i.fieldPath == 'tests.0.value');
      expect(lowIssue.severity, IssueSeverity.warning);
      expect(lowIssue.message, contains('低于 600'));
      expect(
        low.where(
          (i) => i.fieldPath == 'tests.0.value' && i.severity == IssueSeverity.error,
        ),
        isEmpty,
      );
      // 600 起不再提醒，800 也干净。
      for (final duty in const [600, 800]) {
        expect(
          messages(duty).where((message) => message.contains('摩擦轮')),
          isEmpty,
        );
      }
    });

    test('电机和舵机仍要求配置方向', () {
      final invalid = DebugConfig(
        tests: [
          const DebugTestItem(
            pin: 'P60',
            enabled: true,
            driveType: DebugDriveType.motor,
            value: 1000,
          ),
          for (final pin in debugPins.where((pin) => pin != 'P60'))
            DebugTestItem(pin: pin),
        ],
      );
      expect(
        ProjectValidator.validate(invalid).map((issue) => issue.fieldPath),
        contains('tests.0.direction'),
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
      final source = completeInfantry(frictionMode: FrictionMode.disabled)
          .copyWith(
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
      expect(withoutFriction.frictionP64MaxDuty, enabled.frictionP64MaxDuty);
      expect(withoutFriction.frictionP66MaxDuty, enabled.frictionP66MaxDuty);

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
      expect(restored.frictionP64MaxDuty, enabled.frictionP64MaxDuty);
      expect(restored.frictionP66MaxDuty, enabled.frictionP66MaxDuty);
      expect(restored.frictionLevelStep, enabled.frictionLevelStep);
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
        InfantryPinPlanner.occupantsOf(
          config,
          'P60',
          'gimbal.pitch.1.pin',
        ).single.ownerLabel,
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
        ProjectValidator.validate(blank)
            .where((i) => i.fieldPath.startsWith('gimbal.')),
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
          'turnSpeed = (int)(((int32_t)-valueOfRoker[0][0] * (int32_t)speed) / 2047L);';
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

    test('云台舵机方向反向时对摇杆增量取反', () {
      final forward = CodeGenerator.generate(completeInfantry());
      expect(
        forward,
        contains(
          'yawDuty += (int)((float)valueOfRoker[1][0] * 2.0f / 2047.0f * 5.555556f);',
        ),
      );
      expect(
        forward,
        contains(
          'pitchDuty += (int)((float)valueOfRoker[1][1] * 2.0f / 2047.0f * 5.555556f);',
        ),
      );

      final reversedYaw = CodeGenerator.generate(
        completeInfantry().copyWith(
          yawActuators: const [
            AxisActuator(
              drive: DriveType.servo,
              pin: 'MP74',
              direction: Direction.reverse,
              midOffset: 0,
            ),
          ],
        ),
      );
      expect(
        reversedYaw,
        contains(
          'yawDuty += (int)((float)-valueOfRoker[1][0] * 2.0f / 2047.0f * 5.555556f);',
        ),
      );
      expect(
        reversedYaw,
        isNot(
          contains(
            'yawDuty += (int)((float)valueOfRoker[1][0] * 2.0f / 2047.0f * 5.555556f);',
          ),
        ),
      );

      final reversedPitch = CodeGenerator.generate(
        completeInfantry().copyWith(
          pitchActuators: const [
            AxisActuator(
              drive: DriveType.servo,
              pin: 'MP03',
              direction: Direction.reverse,
              midOffset: 0,
            ),
          ],
        ),
      );
      expect(
        reversedPitch,
        contains(
          'pitchDuty += (int)((float)-valueOfRoker[1][1] * 2.0f / 2047.0f * 5.555556f);',
        ),
      );
      expect(
        reversedPitch,
        isNot(
          contains(
            'pitchDuty += (int)((float)valueOfRoker[1][1] * 2.0f / 2047.0f * 5.555556f);',
          ),
        ),
      );
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
          'baseSpeed = (int)(((int32_t)-valueOfRoker[0][1] * (int32_t)speed) / 2047L);',
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
      expect(code, isNot(contains('FRICTION_ACTIVATE_MS')));
      expect(code, isNot(contains('frictionActivateLoops')));
    });

    test('摩擦轮启停跳过 0~500 无效区间', () {
      final code = CodeGenerator.generate(completeInfantry());
      expect(
        code,
        contains(
          'ExpansionBoradControl(Dir_Change_Order, dutyOfMotor[0]>=0,dutyOfMotor[1]>=0,1,1,',
        ),
      );
      // 启动：低于最低有效占空比时直接跳到 500，不从 0 逐格爬上来
      expect(
        code,
        contains(
          'if (frictionTargetDutyP64 >= FRICTION_START_DUTY && frictionDutyP64 < FRICTION_START_DUTY)',
        ),
      );
      expect(
        code,
        contains(
          'if (frictionTargetDutyP66 >= FRICTION_START_DUTY && frictionDutyP66 < FRICTION_START_DUTY)',
        ),
      );
      // 停机：降到最低有效占空比后直接归零，不在 0~500 之间逐格磨
      expect(
        code,
        contains(
          'if (frictionTargetDutyP64 == 0 && frictionDutyP64 <= FRICTION_START_DUTY)',
        ),
      );
      expect(
        code,
        contains(
          'if (frictionTargetDutyP66 == 0 && frictionDutyP66 <= FRICTION_START_DUTY)',
        ),
      );
      // 旧写法只在 duty 恰好为 0 时跳变，关闭途中重新开启会从 0~500 之间
      // 渐变上去，不应再出现
      expect(code, isNot(contains('frictionStartedThisCycle')));
    });

    test('步兵摩擦轮从静止启动先做 500 占空比激活 1000ms', () {
      final code = CodeGenerator.generate(completeInfantry());
      expect(code, contains('#define FRICTION_ACTIVATE_MS 1000'));
      // 激活按主循环整圈折算：一圈约 FRICTION_LOOP_MS 毫秒，向上取整保证
      // 实际保持时间不会短于 1000ms
      expect(code, contains('#define FRICTION_LOOP_MS 20'));
      expect(
        code,
        contains(
          '#define FRICTION_ACTIVATE_LOOPS ((FRICTION_ACTIVATE_MS + FRICTION_LOOP_MS - 1) / FRICTION_LOOP_MS)',
        ),
      );
      expect(code, contains('uint8_t frictionActivateLoops = 0;'));

      final update = code.substring(
        code.indexOf('void UpdateWeapons'),
        code.indexOf('void main'),
      );
      // 开关键按下且摩擦轮还停在 0 时触发激活
      expect(
        update,
        contains(
          'if (frictionEnabled && frictionDutyP64 == 0\n'
          '        && frictionTargetDutyP64 >= FRICTION_START_DUTY)\n'
          '        frictionActivateLoops = FRICTION_ACTIVATE_LOOPS;',
        ),
      );
      // 关闭摩擦轮时立刻取消激活残留，直接走停机斜坡
      expect(
        update,
        contains('if (!frictionEnabled) frictionActivateLoops = 0;'),
      );

      final activate = update.substring(
        update.indexOf('if (frictionActivateLoops > 0) {'),
        update.indexOf('    } else {'),
      );
      // 激活期间两边都只维持启动占空比，不进 ±1 斜坡
      expect(activate, contains('frictionDutyP64 = FRICTION_START_DUTY;'));
      expect(activate, contains('frictionDutyP66 = FRICTION_START_DUTY;'));
      expect(activate, isNot(contains('FRICTION_STEP_DUTY')));
      // 激活期间不发蜂鸣，与调试工程的摩擦轮测试一致
      expect(activate, isNot(contains('BUZZER')));
      expect(
        code,
        contains(
          'else if (frictionActivateLoops == 0 && (frictionDutyP64 != frictionTargetDutyP64',
        ),
      );
    });

    test('两侧摩擦轮按各自满油上限映射同一油门比例值', () {
      final code = CodeGenerator.generate(
        completeInfantry().copyWith(
          frictionP64MaxDuty: 700,
          frictionP66MaxDuty: 800,
          frictionLevelStep: 10,
        ),
      );
      expect(code, contains('#define FRICTION_MAX_DUTY_P64 700'));
      expect(code, contains('#define FRICTION_MAX_DUTY_P66 800'));
      expect(code, contains('#define FRICTION_LEVEL_MAX 100'));
      expect(code, contains('#define FRICTION_LEVEL_STEP 10'));
      expect(code, contains('uint8_t frictionLevel = 0;'));
      // 比例值换算：duty = 500 + level * (该侧上限 - 500) / 100
      expect(
        code,
        contains(
          '((uint16_t)level * (uint16_t)(maxDuty - FRICTION_START_DUTY)) / FRICTION_LEVEL_MAX',
        ),
      );
      // 油门是唯一控制量，目标占空比每周期重新映射
      expect(
        code,
        contains(
          'frictionTargetDutyP64 = frictionEnabled\n'
          '        ? FrictionDutyOfLevel(frictionLevel, FRICTION_MAX_DUTY_P64) : 0;',
        ),
      );
      expect(
        code,
        contains(
          'frictionTargetDutyP66 = frictionEnabled\n'
          '        ? FrictionDutyOfLevel(frictionLevel, FRICTION_MAX_DUTY_P66) : 0;',
        ),
      );
      // 按键只改油门，不再直接加减占空比真值
      expect(
        code,
        contains('frictionLevel = frictionEnabled ? FRICTION_LEVEL_MAX : 0;'),
      );
      expect(code, isNot(contains('FRICTION_SPEED_STEP')));
      // 两个引脚各自独立输出，不再共用同一个占空比变量
      expect(code, contains('frictionDutyP64,frictionDutyP66'));
      expect(code, isNot(contains('frictionDuty,')));
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
          '    pitchDuty2 += (int)((float)-valueOfRoker[1][1] * 2.0f / 2047.0f * 5.555556f);',
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
      final config = completeInfantry(frictionMode: FrictionMode.disabled)
          .copyWith(pitchActuators: const []);
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
  });
}
