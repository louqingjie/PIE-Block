import 'dart:convert';
import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';
import 'package:test/test.dart';

void main() {
  group('项目格式', () {
    test('格式 12 可以往返', () {
      final source = ProjectDocument.create('步兵测试', ProjectKind.infantry);
      final decoded = jsonDecode(jsonEncode(source.toJson()));
      final restored = ProjectDocument.fromJson(
        Map<String, Object?>.from(decoded as Map),
      );
      expect(restored.name, source.name);
      expect(restored.kind, ProjectKind.infantry);
      expect(restored.config, isA<InfantryConfig>());
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
  });
}
