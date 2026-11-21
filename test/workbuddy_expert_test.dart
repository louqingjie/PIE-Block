import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// WorkBuddy 专家包（私有专家原型）的契约测试：
/// 结构 / 字段 / 头像尺寸 / 描述字数 / 技能 frontmatter 必须符合开放平台文档，
/// 避免打包后解析失败。
const _root = 'workbuddy-expert/pieblock-expert';

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '缺少文件：$path');
  return file.readAsStringSync();
}

Map<String, String> _frontmatterFields(String text) {
  expect(text.startsWith('---\n'), isTrue);
  final end = text.indexOf('\n---', 4);
  expect(end, greaterThan(0));
  final fields = <String, String>{};
  for (final line in text.substring(4, end).split('\n')) {
    if (line.startsWith(' ')) continue;
    final index = line.indexOf(':');
    if (index <= 0) continue;
    fields[line.substring(0, index).trim()] = line
        .substring(index + 1)
        .trim();
  }
  return fields;
}

void main() {
  late Map<String, Object?> manifest;
  setUpAll(() {
    manifest =
        jsonDecode(_read('$_root/.codebuddy-plugin/plugin.json'))
            as Map<String, Object?>;
  });

  test('plugin.json 必填字段与路径有效', () {
    expect(manifest['name'], 'pieblock-expert');
    expect(manifest['expertType'], 'agent');
    expect(manifest['agentName'], 'pieblock-assistant');
    expect(manifest['categoryId'], '02-Engineering');
    expect(manifest['plugin'], manifest['name']);
    expect(manifest['version'], matches(RegExp(r'^\d+\.\d+\.\d+$')));
    expect((manifest['author']! as Map)['name'], isNotEmpty);

    final agents = (manifest['agents']! as List).cast<String>();
    expect(agents, isNotEmpty);
    for (final agent in agents) {
      expect(File('$_root/$agent').existsSync(), isTrue, reason: agent);
    }

    final skills = (manifest['skills']! as List).cast<String>();
    expect(skills, hasLength(2));
    for (final skill in skills) {
      expect(
        File('$_root/$skill/SKILL.md').existsSync(),
        isTrue,
        reason: skill,
      );
    }
  });

  test('展示字段满足市场规范', () {
    final displayName = manifest['displayName']! as Map;
    final profession = manifest['profession']! as Map;
    final description = manifest['displayDescription']! as Map;
    expect((displayName['zh']! as String).isNotEmpty, isTrue);
    expect((displayName['en']! as String).isNotEmpty, isTrue);
    expect((profession['zh']! as String).isNotEmpty, isTrue);
    expect((profession['en']! as String).isNotEmpty, isTrue);

    // 官方要求中文 40–50 字。
    final zh = description['zh']! as String;
    final cjk = RegExp(r'[\u4e00-\u9fff]').allMatches(zh).length;
    expect(cjk, inInclusiveRange(40, 50), reason: 'displayDescription 中文 $cjk 字');
    expect((description['en']! as String).isNotEmpty, isTrue);

    final defaultPrompt = manifest['defaultInitPrompt']! as Map;
    final quickPrompts = (manifest['quickPrompts']! as List).cast<Map>();
    expect(quickPrompts, hasLength(3));
    expect(defaultPrompt['zh'], quickPrompts.first['zh']);
    expect(defaultPrompt['en'], quickPrompts.first['en']);
    expect((manifest['tags']! as List), hasLength(3));
  });

  test('头像为 512×512 PNG 且不超过 500KB', () {
    final bytes = File('$_root/avatars/expert.png').readAsBytesSync();
    expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    // PNG IHDR：宽高各 4 字节大端，位于第 16、20 字节。
    final width = bytes.buffer.asByteData().getUint32(16);
    final height = bytes.buffer.asByteData().getUint32(20);
    expect(width, 512);
    expect(height, 512);
    expect(bytes.length, lessThan(500 * 1024));
  });

  test('Agent 定义文件包含人设与红线', () {
    final agent = _read('$_root/agents/pieblock-assistant.md');
    final fields = _frontmatterFields(agent);
    expect(fields['name'], 'pieblock-assistant');
    expect(fields['description'], isNotEmpty);
    expect(agent, contains('不直接修改'));
    expect(agent, contains('main.c'));
    expect(agent, contains('不绕过代码生成器'));
    expect(agent, contains('不编译、不烧录'));
    expect(agent, contains('propose'));
    expect(agent, contains('机械培训群'));
  });

  test('两个 Skill 使用 WorkBuddy frontmatter 且保留红线', () {
    const required = [
      'name',
      'display_name',
      'display_name_en',
      'description',
      'description_zh',
      'description_en',
      'version',
      'author',
    ];
    for (final name in ['pieblock-config', 'pieblock-troubleshooting']) {
      final text = _read('$_root/skills/$name/SKILL.md');
      final fields = _frontmatterFields(text);
      for (final key in required) {
        expect(fields[key], isNotNull, reason: '$name 缺少 $key');
      }
      expect(fields['name'], name);
      expect(text, contains('不直接修改'));
      expect(text, contains('不绕过代码生成器'));
      expect(text, contains('gitee.com/louqingjie/pie-block'));
    }
  });

  test('配置 Skill 自带示例与文档', () {
    for (final name in ['omni3', 'mecanum4', 'arm2dof']) {
      expect(
        File(
          '$_root/skills/pieblock-config/assets/examples/$name.pieproj',
        ).existsSync(),
        isTrue,
      );
    }
    expect(
      File(
        '$_root/skills/pieblock-config/assets/docs/Flutter项目文件格式.md',
      ).existsSync(),
      isTrue,
    );
  });
}
