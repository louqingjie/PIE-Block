import 'dart:convert';
import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_mcp/pieblock_mcp.dart';
import 'package:test/test.dart';

Map<String, Object?> defaultJson(ProjectKind kind) =>
    ProjectDocument.create(kind).config.toJson();

Map<String, Object?> _actuator() => {
  'drive': 'servo',
  'pin': 'MP03',
  'direction': 'forward',
  'mid_offset': 0,
  'min_limit': -45,
  'max_limit': 45,
};

Map<String, Object?> _mode() => {
  'id': 'm1',
  'preserve_chassis': true,
  'actions': [
    {
      'id': 'a1',
      'input_kind': 'remote',
      'key': 'A',
      'output_kind': 'pin',
      'pin': 'P60',
      'mode': 'direct',
      'parameter': 1,
    },
  ],
  'action_tables': [
    {
      'id': 't1',
      'key': 'B',
      'prev_key': 'C',
      'steps': 2,
      'wrap': true,
      'rows': [
        {
          'pin': 'P60',
          'values': [1, 2],
        },
      ],
    },
  ],
};

/// 默认配置里有几个数组是空的，目录自检需要至少一个元素才能展开路径。
Map<String, Object?> richShape(ProjectKind kind) {
  final json = defaultJson(kind);
  switch (kind) {
    case ProjectKind.infantry:
      json['yaw'] = [_actuator()];
      json['pitch'] = [_actuator()];
    case ProjectKind.engineer:
      json['modes'] = [_mode()];
    case ProjectKind.debug:
      // 默认就有十个固定引脚的测试项，不用补。
      break;
    case ProjectKind.music:
      json['notes'] = [
        {'id': 'n1', 'pitch': 60, 'start_tick': 0, 'duration_ticks': 480},
      ];
  }
  // 再走一次项目模型，补全 `toJson` 会写出的 null 键。
  return decodeConfig(kind.name, json).toJson();
}

/// 把目录里的 `*` / `[*]` 展开成当前 JSON 里真实存在的路径。
List<String> expandPaths(
  Object? node,
  List<String> parts,
  String prefix,
) {
  if (parts.isEmpty) return [prefix];
  final raw = parts.first;
  final rest = parts.sublist(1);
  final open = raw.indexOf('[');
  final name = open < 0 ? raw : raw.substring(0, open);
  final index = open < 0 ? null : raw.substring(open + 1, raw.length - 1);

  if (name == '*') {
    if (node is! Map) return const [];
    return [
      for (final entry in node.entries)
        ...expandPaths(
          entry.value,
          rest,
          prefix.isEmpty ? entry.key.toString() : '$prefix.${entry.key}',
        ),
    ];
  }
  if (node is! Map || !node.containsKey(name)) return const [];
  final child = node[name];
  final base = prefix.isEmpty ? name : '$prefix.$name';
  if (index == null) return expandPaths(child, rest, base);
  if (child is! List) return const [];
  if (index == '*') {
    return [
      for (var i = 0; i < child.length; i += 1)
        ...expandPaths(child[i], rest, '$base[$i]'),
    ];
  }
  final at = int.tryParse(index);
  if (at == null || at < 0 || at >= child.length) return const [];
  return expandPaths(child[at], rest, '$base[$at]');
}

void main() {
  final shapes = {
    for (final kind in ProjectKind.values) kind: richShape(kind),
  };

  group('字段目录自检', () {
    test('每条目录项都能在默认配置里找到真实路径', () {
      final missing = <String>[];
      for (final spec in McpFieldCatalog.specs) {
        final hit = shapes.values.any(
          (config) => expandPaths(config, spec.pattern.split('.'), '').isNotEmpty,
        );
        if (!hit) missing.add(spec.pattern);
      }
      expect(missing, isEmpty, reason: '这些目录项在默认配置里找不到：$missing');
    });

    test('具体路径都能反查回目录', () {
      final unresolved = <String>[];
      for (final spec in McpFieldCatalog.specs) {
        for (final config in shapes.values) {
          for (final path in expandPaths(config, spec.pattern.split('.'), '')) {
            if (McpFieldCatalog.lookup(path) == null) unresolved.add(path);
          }
        }
      }
      expect(unresolved, isEmpty, reason: '反查失败的路径：$unresolved');
    });

    test('数组下标会被归一化后命中', () {
      expect(McpFieldCatalog.lookup('yaw[0].pin')?.label, '云台偏航引脚');
      expect(McpFieldCatalog.lookup('yaw[7].pin'), isNotNull);
      expect(McpFieldCatalog.normalize('modes[12].actions[3].key'),
          'modes[*].actions[*].key');
    });

    test('引脚键这类字面键也能命中', () {
      expect(McpFieldCatalog.lookup('pwm.pin_roles.P64')?.label, '引脚输出角色');
      expect(McpFieldCatalog.lookup('pwm.servo_mids.MP03')?.label, '舵机中位');
    });

    test('id 字段一律只读', () {
      final writableIds = [
        for (final spec in McpFieldCatalog.specs)
          if (spec.pattern.endsWith('.id') && spec.writable) spec.pattern,
      ];
      expect(writableIds, isEmpty);
    });

    test('步骤 id 都在已知集合内', () {
      const knownSteps = {
        'remote',
        'mechanism',
        'controls',
        'pwm',
        'strategy',
        'mappings',
        'tests',
        'music',
      };
      final unknown = {
        for (final spec in McpFieldCatalog.specs)
          if (!knownSteps.contains(spec.stepId)) spec.stepId,
      };
      expect(unknown, isEmpty);
    });
  });

  group('校验路径覆盖', () {
    test('fixtures 出现的每个校验路径都能映射到目录', () {
      final dir = Directory('../pieblock_core/test/fixtures');
      expect(dir.existsSync(), isTrue, reason: '找不到 fixtures：${dir.absolute.path}');
      final missing = <String>{};
      for (final file in dir.listSync().whereType<File>()) {
        if (!file.path.endsWith('.pieproj')) continue;
        final document = ProjectDocument.fromJson(
          Map<String, Object?>.from(
            jsonDecode(file.readAsStringSync()) as Map,
          ),
        );
        for (final issue in ProjectValidator.validate(document.config)) {
          if (McpFieldCatalog.lookupIssue(issue.fieldPath) == null) {
            missing.add('${issue.fieldPath}（${issue.stepId}）');
          }
        }
      }
      expect(missing, isEmpty, reason: '未覆盖的校验路径：$missing');
    });

    test('默认配置的校验路径也能映射', () {
      final missing = <String>{};
      for (final kind in ProjectKind.values) {
        final config = ProjectDocument.create(kind).config;
        for (final issue in ProjectValidator.validate(config)) {
          if (McpFieldCatalog.lookupIssue(issue.fieldPath) == null) {
            missing.add('${kind.name}: ${issue.fieldPath}');
          }
        }
      }
      expect(missing, isEmpty, reason: '未覆盖的校验路径：$missing');
    });
  });
}
