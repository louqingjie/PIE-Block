import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Agent Skill 是发给外部 AI 阅读的规程文件：名字、描述、红线与链接一旦失效，
/// AI 就会按错误的规程操作。这里把这些契约锁进测试。
const _skills = <String, String>{
  'pieblock-config': 'skills/pieblock-config',
  'pieblock-troubleshooting': 'skills/pieblock-troubleshooting',
};

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '缺少文件：$path');
  return file.readAsStringSync();
}

Map<String, String> _frontmatter(String path, String text) {
  expect(
    text.startsWith('---\n'),
    isTrue,
    reason: '$path 必须以 YAML frontmatter 开头',
  );
  final end = text.indexOf('\n---', 4);
  expect(end, greaterThan(0), reason: '$path 的 frontmatter 没有结束标记');
  final header = text.substring(4, end);
  final result = <String, String>{};
  for (final line in header.split('\n')) {
    final index = line.indexOf(':');
    if (index <= 0) continue;
    result[line.substring(0, index).trim()] = line.substring(index + 1).trim();
  }
  return result;
}

/// 收集 Markdown 里的本地链接（跳过 http(s)、锚点、mailto）。
List<String> _localLinks(String path) {
  final text = File(path).readAsStringSync();
  final links = <String>[];
  for (final match in RegExp(r'\]\(([^)]+)\)').allMatches(text)) {
    var target = match.group(1)!.trim();
    if (target.startsWith('<') || target.startsWith('#')) continue;
    if (target.startsWith('http://') ||
        target.startsWith('https://') ||
        target.startsWith('mailto:')) {
      continue;
    }
    target = target.split('#').first;
    if (target.isEmpty) continue;
    if (target.contains('%')) {
      target = Uri.decodeComponent(target);
    }
    links.add(p.normalize(p.join(p.dirname(path), target)));
  }
  return links;
}

void main() {
  group('Skill frontmatter', () {
    for (final entry in _skills.entries) {
      test('${entry.key}：name/description 合法', () {
        final path = '${entry.value}/SKILL.md';
        final fields = _frontmatter(path, _read(path));
        expect(fields['name'], entry.key);
        final description = fields['description'] ?? '';
        expect(description, contains('PIE-Block'));
        expect(description.length, lessThan(1024));
      });
    }
  });

  group('红线', () {
    for (final entry in _skills.entries) {
      test('${entry.key}：包含不可绕过的红线', () {
        final text = _read('${entry.value}/SKILL.md');
        // 三条最关键的禁令：不手改生成代码、不绕过生成器、不编译烧录。
        expect(text, contains('不直接修改'));
        expect(text, contains('main.c'));
        expect(text, contains('不绕过代码生成器'));
        expect(text, contains('不编译、不烧录'));
        // 提案-确认链路与用户确认。
        expect(text, contains('propose'));
        expect(text, contains('确认'));
      });
    }
  });

  test('参考文件都真实存在', () {
    const referenced = [
      'book/examples/omni3.pieproj',
      'book/examples/mecanum4.pieproj',
      'book/examples/arm2dof.pieproj',
      'book/examples/debug-checklist.pieproj',
      'book/examples/music-twinkle.pieproj',
      'book/chapters/ch05.tex',
      'book/chapters/concise/ch05.tex',
      'assets/templates/infantry.pieproj',
      'assets/templates/engineer.pieproj',
      'docs/reference/Flutter项目文件格式.md',
      'docs/reference/STC32G固件约束.md',
      'docs/guides/PIE-Block命令行工具.md',
      'docs/guides/Flutter编译与烧录指南.md',
      'docs/playbook',
      'packages/pieblock_core/lib/src/code_generator.dart',
      'packages/pieblock_core/lib/src/expression.dart',
      'packages/pieblock_core/lib/src/models.dart',
      'packages/pieblock_core/lib/src/validator.dart',
    ];
    for (final path in referenced) {
      expect(
        File(path).existsSync() || Directory(path).existsSync(),
        isTrue,
        reason: 'Skill 引用的路径不存在：$path',
      );
    }
  });

  test('Skill 与用户指南里的本地 Markdown 链接都能解析', () {
    final files = <String>[
      for (final entry in _skills.entries) ...[
        '${entry.value}/SKILL.md',
        '${entry.value}/references/questionnaire.md',
        '${entry.value}/references/config-recipes.md',
        '${entry.value}/references/workflow.md',
        '${entry.value}/references/parameter-to-code.md',
        '${entry.value}/references/bug-report-template.md',
      ],
      'docs/guides/AI-Skills使用指南.md',
      'docs/guides/PIE-Block命令行工具.md',
    ];
    for (final file in files) {
      if (!File(file).existsSync()) continue;
      for (final target in _localLinks(file)) {
        expect(
          File(target).existsSync() || Directory(target).existsSync(),
          isTrue,
          reason: '$file 里的链接指向不存在的路径：$target',
        );
      }
    }
  });

  test('使用指南与 CLI 指南互相链接到 Skill', () {
    final guide = _read('docs/guides/AI-Skills使用指南.md');
    expect(guide, contains('pieblock-config'));
    expect(guide, contains('pieblock-troubleshooting'));
    expect(guide, contains('main.c'));

    final cli = _read('docs/guides/PIE-Block命令行工具.md');
    expect(cli, contains('skills/'));
    expect(cli, contains('AI-Skills使用指南.md'));
  });

  test('排障手册保留了 @expr 锚点，配置手册保留能力矩阵', () {
    expect(
      _read('skills/pieblock-troubleshooting/references/parameter-to-code.md'),
      contains('@expr:'),
    );
    expect(
      _read('skills/pieblock-config/references/config-recipes.md'),
      contains('能力矩阵'),
    );
  });

  test('排障反馈走团队飞书群，不要求学生自己开 GitHub Issue', () {
    final skill = _read('skills/pieblock-troubleshooting/SKILL.md');
    expect(skill, contains('机械培训群'));
    expect(skill, contains('不要用飞书私聊'));
    expect(skill, isNot(contains('建议用户在 GitHub Issues 提交')));

    final template = _read(
      'skills/pieblock-troubleshooting/references/bug-report-template.md',
    );
    expect(template, contains('机械培训群'));
    expect(template, contains('不要私聊'));
    expect(template, contains('不需要脱敏'));
    expect(template, isNot(contains('脱敏后')));
    expect(template, isNot(contains('提交 Issue 前')));

    expect(_read('docs/guides/AI-Skills使用指南.md'), contains('机械培训群'));
  });
}
