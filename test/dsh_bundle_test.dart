import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// DSH 插件分发版 Skill 的契约测试：
/// - 插件是可发布的 npm 包：manifest、locale、icon、patch 形态正确；
/// - 插件只注册 skill（index.js 调用 ctx.skills.register），不写用户目录；
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
  test('插件清单是可发布的 npm 包', () {
    final manifest =
        jsonDecode(_read('$_bundle/package.json')) as Map<String, Object?>;
    expect(manifest['name'], 'pieblock-dsh-skills');
    expect(manifest['description'], contains('PIE-Block'));
    expect(manifest['private'], isNull, reason: '发布包不能声明 private');
    expect(manifest['type'], 'module');
    final dsh = manifest['dsh']! as Map<String, Object?>;
    final bundle = dsh['bundle']! as Map<String, Object?>;
    expect(bundle['patch'], './cordis.patch.yml');
    final exports = manifest['exports']! as Map<String, Object?>;
    expect(exports['.'], './index.js');
    expect(exports['./locale/*.json'], './locale/*.json');
    expect(exports['./icon'], './icon.svg');
    final files = (manifest['files']! as List<Object?>).cast<String>();
    for (final required in [
      'index.js',
      'cordis.patch.yml',
      'icon.svg',
      'skills',
    ]) {
      expect(files, contains(required), reason: 'files 缺少 $required');
    }
    expect(manifest['keywords'], contains('dsh-plugin'));
    expect(manifest['repository'], isNotNull);
  });

  test('插件只注册 skill，不写用户技能目录', () {
    final patch = _read('$_bundle/cordis.patch.yml');
    final effective = patch
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('#'))
        .join('\n');
    expect(effective, contains('id: pieblock-skills'));
    expect(effective, contains('name: pieblock-dsh-skills'));
    expect(effective, isNot(contains('skill-filesystem')));
    expect(effective, isNot(contains('bundledSkillDir')));

    final index = _read('$_bundle/index.js');
    expect(index, contains('ctx.skills.register'));
    expect(index, contains('resourceBase'));
    expect(index, contains('pieblock-config'));
    expect(index, contains('pieblock-troubleshooting'));
    // 插件只读包内文件并注册技能，不向用户技能目录写文件。
    expect(index, isNot(contains('writeFile')));
    expect(index, isNot(contains('mkdir')));
  });

  test('locale 提供中英文标题与说明', () {
    for (final language in ['en', 'zh']) {
      final locale =
          jsonDecode(_read('$_bundle/locale/$language.json'))
              as Map<String, Object?>;
      final meta = locale['meta']! as Map<String, Object?>;
      expect(meta['title'], isA<String>());
      expect(meta['description'], isA<String>());
      expect((meta['title']! as String).isNotEmpty, isTrue);
      expect((meta['description']! as String).isNotEmpty, isTrue);
    }
  });

  test('图标是 36x36 的独立 SVG', () {
    final icon = _read('$_bundle/icon.svg');
    expect(icon, contains('<svg'));
    expect(icon, contains('viewBox="0 0 36 36"'));
    expect(icon, isNot(contains('<text')));
    expect(icon, isNot(contains('<script')));
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

  test('随包排障 Skill 与仓库一致：反馈走飞书群而不是 GitHub Issue', () {
    final skill = _read(
      '$_bundle/skills/pieblock-troubleshooting/SKILL.md',
    );
    expect(skill, contains('机械培训群'));
    expect(skill, contains('不要用飞书私聊'));
    expect(skill, isNot(contains('建议用户在 GitHub Issues 提交')));
    final template = _read(
      '$_bundle/skills/pieblock-troubleshooting/references/bug-report-template.md',
    );
    expect(template, contains('机械培训群'));
    expect(template, contains('不要私聊'));
    expect(template, contains('不需要脱敏'));
    final canonical = _read('skills/pieblock-troubleshooting/SKILL.md');
    expect(canonical, contains('机械培训群'));
  });
}
