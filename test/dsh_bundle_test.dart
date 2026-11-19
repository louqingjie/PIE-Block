import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// DSH 插件分发版 Skill 的契约测试：
/// - 插件清单与 patch 保持最小形态（只装 skill，不写用户目录）；
/// - patch 用 DSH_PROFILE_DIR 定位包内技能根（baseUrl 在 host patch 里不可用，已实测）；
/// - 随包的示例工程/文档与仓库源文件保持一致，避免两份漂移；
/// - 技能 frontmatter 与红线不被误删。
const _bundle = 'dsh-bundle/pieblock-dsh-skills';

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '缺少文件：$path');
  return file.readAsStringSync();
}

Map<String, String> _frontmatter(String text) {
  expect(text.startsWith('---\n'), isTrue);
  final end = text.indexOf('\n---', 4);
  expect(end, greaterThan(0));
  final result = <String, String>{};
  for (final line in text.substring(4, end).split('\n')) {
    final index = line.indexOf(':');
    if (index <= 0) continue;
    result[line.substring(0, index).trim()] = line
        .substring(index + 1)
        .trim();
  }
  return result;
}

void main() {
  test('插件清单声明了 bundle patch', () {
    final manifest =
        jsonDecode(_read('$_bundle/package.json')) as Map<String, Object?>;
    expect(manifest['name'], 'pieblock-dsh-skills');
    expect(manifest['private'], isTrue);
    final dsh = manifest['dsh']! as Map<String, Object?>;
    final bundle = dsh['bundle']! as Map<String, Object?>;
    final patch = bundle['patch'] as String;
    expect(File('$_bundle/$patch').existsSync(), isTrue);
    expect(patch, './cordis.patch.yml');
  });

  test('patch 只注册 Host 级 skill provider', () {
    final patch = _read('$_bundle/cordis.patch.yml');
    expect(patch, contains('id: pieblock-skills'));
    expect(patch, contains('@deepseek-ai/dsh-skill-filesystem'));
    expect(patch, contains('providerName: pieblock'));
    expect(patch, contains('includeDefaultRoots: false'));
    expect(patch, contains('bundledSkillDir'));
    // 回归：host patch 里的 !!js 不能依赖 baseUrl（实测会得到不存在的路径）。
    expect(patch, contains('DSH_PROFILE_DIR'));
    final effective = patch
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('#'))
        .join('\n');
    expect(effective, isNot(contains('baseUrl')));
  });

  for (final name in ['pieblock-config', 'pieblock-troubleshooting']) {
    test('$name：frontmatter 与红线完整', () {
      final text = _read('$_bundle/skills/$name/SKILL.md');
      final fields = _frontmatter(text);
      expect(fields['name'], name);
      expect(fields['description'], contains('PIE-Block'));
      expect(text, contains('不直接修改'));
      expect(text, contains('main.c'));
      expect(text, contains('不绕过代码生成器'));
      expect(text, contains('不编译、不烧录'));
      expect(text, contains('propose'));
      expect(text, contains('确认'));
      // 插件版必须能指向随包示例，而不是只认仓库路径。
      expect(text, contains('assets/examples'));
    });
  }

  test('配置 Skill 随包示例与仓库示例逐字节一致', () {
    for (final name in ['omni3', 'mecanum4', 'arm2dof']) {
      final repo = File('book/examples/$name.pieproj').readAsBytesSync();
      final bundled = File(
        '$_bundle/skills/pieblock-config/assets/examples/$name.pieproj',
      ).readAsBytesSync();
      expect(
        bundled,
        repo,
        reason: '$name.pieproj 与 book/examples 不一致，更新示例后要同步插件包',
      );
    }
  });

  test('随包文档与仓库文档逐字节一致', () {
    const docs = [
      'docs/reference/Flutter项目文件格式.md',
      'docs/reference/STC32G固件约束.md',
      'docs/guides/Flutter编译与烧录指南.md',
    ];
    for (final path in docs) {
      final fileName = path.split('/').last;
      final repo = File(path).readAsBytesSync();
      final bundled = File(
        '$_bundle/skills/pieblock-config/assets/docs/$fileName',
      ).readAsBytesSync();
      expect(
        bundled,
        repo,
        reason: '$fileName 与仓库文档不一致，更新文档后要同步插件包',
      );
    }
  });

  test('排障 Skill 保留 @expr 锚点与参考手册', () {
    final anchors = _read(
      '$_bundle/skills/pieblock-troubleshooting/references/parameter-to-code.md',
    );
    expect(anchors, contains('@expr:'));
    expect(
      File(
        '$_bundle/skills/pieblock-troubleshooting/references/bug-report-template.md',
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        '$_bundle/skills/pieblock-config/references/config-recipes.md',
      ).existsSync(),
      isTrue,
    );
  });
}
