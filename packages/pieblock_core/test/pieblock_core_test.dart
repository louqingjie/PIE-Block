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
}) => InfantryConfig(
  remote: const RemoteConfig(channel: 36, deadzone: 100),
  chassis: completeChassis(shared: shared),
  feederPin: 'P60',
  feederDirection: Direction.forward,
  yawDrive: DriveType.servo,
  yawPin: 'MP74',
  yawDirection: Direction.forward,
  yawMidOffset: 0,
  pitchDrive: DriveType.servo,
  pitchPin: 'MP03',
  pitchDirection: Direction.forward,
  pitchMidOffset: 0,
  arrowBehavior: ArrowBehavior.other,
  feedMode: feedMode,
  triggerKey: 'E',
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
    pinRoles: {for (final pin in expansionPins) pin: PinRole.motor},
    servoMids: const {'MP03': 0, 'MP74': 0},
  ),
  modeCount: 1,
  modes: [EngineerModeConfig(preserveChassis: true)],
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
        pin: PinRole.motor,
    },
    servoMids: const {'P60': 0, 'MP03': 0, 'MP74': 0},
  ),
  modeCount: 4,
  switchStrategy: strategy,
  modeSwitchKey: strategy == SwitchStrategy.cycle ? 'E' : null,
  modeKeys: strategy == SwitchStrategy.direct
      ? const ['E', 'UP', 'DOWN', 'LEFT']
      : null,
  modes: [
    EngineerModeConfig(
      preserveChassis: true,
      actions: [
        ActionMapping(
          key: 'A',
          direction: Direction.forward,
          mode: ControlMode.direct,
          parameter: 30,
          pin: 'P60',
        ),
        ActionMapping(
          key: 'B',
          direction: Direction.reverse,
          mode: ControlMode.incremental,
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

void main() {
  group('项目格式与进度', () {
    test('格式 14 往返并保存向导进度', () {
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
      expect(source.toJson()['format_version'], 14);
      expect(restored.guideProgress.currentStepId, 'controls');
      expect(restored.guideProgress.visitedStepIds, hasLength(3));
      expect((source.toJson()['config']! as Map), isNot(contains('pwm')));
    });

    test('格式 13 直接拒绝', () {
      expect(
        () => ProjectDocument.fromJson({'format_version': 13}),
        throwsFormatException,
      );
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

    test('上游改变后保留非法值并精确报错', () {
      final config = completeInfantry().copyWith(
        yawDrive: DriveType.motor,
        yawPin: 'MP74',
      );
      expect(config.yawPin, 'MP74');
      expect(
        ProjectValidator.validate(config).any(
          (i) =>
              i.severity == IssueSeverity.error &&
              i.fieldPath == 'gimbal.yaw.pin',
        ),
        isTrue,
      );
    });

    test('数字键包含 LC/RC 且排除摇杆轴', () {
      expect(digitalRemoteKeys, containsAll(['E', 'LC', 'RC']));
      expect(digitalRemoteKeys, isNot(contains('LX')));
    });
  });

  group('生成器', () {
    test('完整步兵配置生成且使用按键宏和实际槽位', () {
      final code = CodeGenerator.generate(
        completeInfantry().copyWith(triggerKey: 'LC', frictionKey: 'RC'),
      );
      expect(code, contains('KEY_OFFSET_Rocker11'));
      expect(code, contains('KEY_OFFSET_Rocker21'));
      expect(code, contains('dutyOfMotor[0]'));
      expect(code, contains('FRICTION_START_DUTY 500'));
      expect(code, contains('retry < 20'));
      expect(code, contains('Uart1TxQuery(control_frame_pack[i])'));
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

    test('工程完整配置可以生成', () {
      expect(CodeGenerator.generate(completeEngineer()), contains('RunMode1'));
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

    test('工程四种控制方式、两种切换策略和蜂鸣反馈可生成', () {
      final cycle = advancedEngineer();
      expect(
        ProjectValidator.validate(cycle)
            .where((i) => i.severity == IssueSeverity.error),
        isEmpty,
      );
      final cycleCode = CodeGenerator.generate(cycle);
      expect(cycleCode, contains('ModeSwitchFeedback'));
      expect(cycleCode, contains('PrepareMode'));
      expect(cycleCode, contains('1000L / 180L'));
      expect(cycleCode, contains('/ 2047'));
      expect(cycleCode, contains('Dir_Change_Order'));
      expect(cycleCode, contains('Uart1TxQuery(control_frame_pack[i])'));

      final directCode = CodeGenerator.generate(
        advancedEngineer(strategy: SwitchStrategy.direct, buzzerDisabled: true),
      );
      expect(directCode, contains('modeKeyLast[0]'));
      expect(directCode, isNot(contains('ModeSwitchFeedback')));
      expect(directCode, isNot(contains('Beep(')));
    });
  });
}
