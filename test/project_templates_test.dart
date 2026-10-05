import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pieblock_app/src/project_templates.dart';
import 'package:pieblock_core/pieblock_core.dart';

/// 模板工程是「打开开关就能直接走到烧录」的承诺，所以这里把两件事钉死：
/// 一是模板文件本身必须是当前格式版本能解析的合法项目，二是解析出来的配置
/// 必须零 error。格式版本升级时忘记重存 `assets/templates/`，会在这里失败。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final kind in ProjectKind.values) {
    test('${kind.name} 模板可解析且零 error', () async {
      final raw = await rootBundle.loadString(ProjectTemplates.assetFor(kind));
      final json = jsonDecode(raw);
      expect(json, isA<Map>());
      expect(
        (json as Map)['format_version'],
        ProjectDocument.formatVersion,
        reason: '模板必须与当前项目格式版本一致，否则 fromJson 会直接拒绝',
      );
      final document = ProjectDocument.fromJson(Map<String, Object?>.from(json));
      expect(document.kind, kind);

      final issues = ProjectValidator.validate(document.config);
      expect(
        issues
            .where((issue) => issue.severity == IssueSeverity.error)
            .map((issue) => '${issue.fieldPath}: ${issue.message}')
            .toList(),
        isEmpty,
      );
      final warnings = issues
          .where((issue) => issue.severity == IssueSeverity.warning)
          .map((issue) => '${issue.fieldPath}: ${issue.message}')
          .toList();
      if (kind == ProjectKind.infantry) {
        // 四轮已经占满固定 10000Hz 的 PWMB，拨弹电机作为第 5 路平滑电机只能
        // 落回固定 50Hz 的 PWMA，这条提示在步兵模板里无法避免。
        expect(warnings, hasLength(1));
        expect(warnings.single, startsWith('mechanism.feeder_pin'));
      } else {
        expect(warnings, isEmpty);
      }
    });
  }

  test('模板配置可直接生成固件源码', () async {
    // 校验通过不代表能生成：代码生成器对部分字段还有自己的假设，
    // 模板如果踩到，用户在代码页只会看到一个打不开的页面。
    for (final kind in ProjectKind.values) {
      final config = await const ProjectTemplates().config(kind);
      expect(
        () => CodeGenerator.generate(config),
        returnsNormally,
        reason: '${kind.name} 模板应能直接走到代码页',
      );
    }
  });

  test('config 只取回配置，并拒绝与所选类型不符的模板', () async {
    final config = await const ProjectTemplates().config(ProjectKind.music);
    expect(config, isA<MusicConfig>());
    expect((config as MusicConfig).notes, isNotEmpty);

    // 用调试模板冒充步兵：kind 与 config 不一致会让向导步骤和代码生成都错。
    final debugRaw = await rootBundle.loadString(
      ProjectTemplates.assetFor(ProjectKind.debug),
    );
    await expectLater(
      ProjectTemplates(loader: (_) async => debugRaw).config(
        ProjectKind.infantry,
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      ProjectTemplates(loader: (_) async => '{}').config(ProjectKind.infantry),
      throwsA(isA<FormatException>()),
    );
  });
}
