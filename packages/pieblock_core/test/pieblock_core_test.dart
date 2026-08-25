import 'dart:convert';
import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';
import 'package:test/test.dart';

void main() {
  group('项目格式', () {
    test('格式 13 可以往返且步兵不保存 PWM 配置', () {
      final source = ProjectDocument.create('步兵测试', ProjectKind.infantry);
      final decoded = jsonDecode(jsonEncode(source.toJson()));
      final restored = ProjectDocument.fromJson(
        Map<String, Object?>.from(decoded as Map),
      );
      expect(restored.name, source.name);
      expect(restored.kind, ProjectKind.infantry);
      expect(restored.config, isA<InfantryConfig>());
      expect(source.toJson()['format_version'], 13);
      final config = source.toJson()['config']! as Map<String, Object?>;
      expect(config, isNot(contains('pwm')));
      expect(config['buzzer_disabled'], isFalse);
    });
    test(
      '拒绝旧格式',
      () => expect(
        () => ProjectDocument.fromJson({'format_version': 11}),
        throwsFormatException,
      ),
    );
    test('仓库原子保存并打开', () async {
      final dir = await Directory.systemTemp.createTemp('pieblock-core-test-');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}${Platform.pathSeparator}demo.pieproj';
      const repository = ProjectRepository();
      await repository.create(path, '工程测试', ProjectKind.engineer);
      final opened = await repository.open(path);
      expect(opened.kind, ProjectKind.engineer);
      expect(File('$path.tmp').existsSync(), isFalse);
    });
  });

  group('校验与生成', () {
    test('默认配置可以生成', () {
      final infantry = InfantryConfig();
      expect(
        ProjectValidator.validate(infantry)
            .where((i) => i.severity == IssueSeverity.error),
        isEmpty,
      );
      expect(CodeGenerator.generate(infantry), contains('void main(void)'));
      expect(
        CodeGenerator.generate(infantry),
        contains('FRICTION_MAX_DUTY 800'),
      );
    });
    test('拦截通道、IO 和按键冲突', () {
      final base = InfantryConfig();
      final bad = base.copyWith(
        remote: const RemoteConfig(channel: 126),
        chassis: base.chassis.copyWith(leftRear: base.chassis.leftFront),
        triggerKey: 'A',
      );
      final messages = ProjectValidator.validate(bad)
          .map((i) => i.message)
          .join('\n');
      expect(messages, contains('通道号'));
      expect(messages, contains('重复'));
      expect(messages, contains('按键'));
    });
    test('动作稳定 ID 可往返', () {
      final action = ActionMapping(key: 'A');
      expect(ActionMapping.fromJson(action.toJson()).id, action.id);
    });
    test('工程切换键冲突会报错', () {
      final engineer = EngineerConfig(
        modes: [
          EngineerModeConfig(actions: [ActionMapping(key: 'E')]),
        ],
      );
      expect(
        ProjectValidator.validate(engineer)
            .any((i) => i.message.contains('切换键冲突')),
        isTrue,
      );
    });
    test('步兵引脚角色与可选范围按占用动态推导', () {
      final infantry = InfantryConfig();
      final assignments = InfantryPinPlanner.derive(infantry);
      expect(assignments['P64']?.role, PinRole.friction);
      expect(assignments['P66']?.role, PinRole.friction);
      expect(assignments['MP74']?.role, PinRole.servo);
      expect(
        InfantryPinPlanner.allowedPins(infantry, 'mechanism.feeder_pin'),
        contains('P62'),
      );
      expect(
        InfantryPinPlanner.allowedPins(infantry, 'mechanism.feeder_pin'),
        isNot(contains('P64')),
      );
    });
    test('非法步兵引脚返回精确字段路径', () {
      final invalid = InfantryConfig(yawDrive: DriveType.servo, yawPin: 'P74');
      expect(
        ProjectValidator.validate(invalid).any(
          (issue) =>
              issue.severity == IssueSeverity.error &&
              issue.fieldPath == 'gimbal.yaw.pin',
        ),
        isTrue,
      );
    });
    test('数字按键排除摇杆轴并映射 LC RC', () {
      expect(digitalRemoteKeys, containsAll(['E', 'LC', 'RC']));
      expect(digitalRemoteKeys, isNot(contains('LX')));
      final config = InfantryConfig(
        triggerKey: 'LC',
        frictionKey: 'RC',
        frictionUpKey: 'A',
        frictionDownKey: 'B',
      );
      final code = CodeGenerator.generate(config);
      expect(code, contains('KEY_OFFSET_Rocker11'));
      expect(code, contains('KEY_OFFSET_Rocker21'));
    });
    test('生成器按实际配置映射底盘与拨弹槽位', () {
      final base = InfantryConfig();
      final config = base.copyWith(
        chassis: base.chassis.copyWith(
          leftFront: const WheelConfig('P60 P61'),
          leftRear: const WheelConfig('P75 P25'),
          rightFront: const WheelConfig('P76 P26'),
          rightRear: const WheelConfig('P77 P27'),
        ),
        feederPin: 'P62',
      );
      final code = CodeGenerator.generate(config);
      expect(code, contains('dutyOfMotor[0] = baseSpeed - turnSpeed'));
      expect(code, contains('dutyOfMotor[1] = 6000'));
      expect(
        code,
        contains(
          'ExpansionBoradControl(Init_Order, 50, 50, 50, 50, 10000, 10000, 10000, 10000)',
        ),
      );
    });
  });
}
