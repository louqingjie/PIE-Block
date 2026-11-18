// 开发期基准生成器：导出校验器 golden。
//
// 运行：cd tui/parity/tools && dart run bin/export_validation_goldens.dart
//
// 输出到 tui/parity/golden/validation/：
// - kind=debug 的用例对比**完整** issues（Rust 侧已移植 debug 校验）；
// - kind=infantry/engineer 的用例额外给 remoteIssues（stepId=remote），
//   Rust 侧在移植完步兵/工程专属规则前先对拍公共机器人规则。
import 'dart:convert';
import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';

void main() {
  final toolsDir = Directory.current.absolute.path;
  final repoRoot = Directory(toolsDir).parent.parent.parent;
  final outputDir = Directory(
    '${repoRoot.path}${Platform.pathSeparator}tui${Platform.pathSeparator}parity'
    '${Platform.pathSeparator}golden${Platform.pathSeparator}validation',
  );
  outputDir.createSync(recursive: true);

  final cases = <_Case>[
    _Case('debug_default', _defaultDocument(ProjectKind.debug)),
    _Case('debug_template', _loadProject(repoRoot, 'assets/templates/debug.pieproj')),
    _Case(
      'debug_format18_fixture',
      _loadProject(repoRoot, 'packages/pieblock_core/test/fixtures/format18_debug.pieproj'),
    ),
    _Case('debug_bad_motor_value', _mutateDebug(_defaultDocument(ProjectKind.debug), (config) {
      final tests = config['tests']! as List<Object?>;
      (tests[0]! as Map<String, Object?>)
        ..['enabled'] = true
        ..['drive_type'] = 'motor'
        ..['value'] = 20000
        ..['duration_ms'] = 500;
    })),
    _Case('debug_special_pins', _mutateDebug(_defaultDocument(ProjectKind.debug), (config) {
      final tests = config['tests']! as List<Object?>;
      (tests[8]! as Map<String, Object?>) // MP03
        ..['enabled'] = true
        ..['drive_type'] = 'motor'
        ..['value'] = 10;
      (tests[9]! as Map<String, Object?>) // MP74
        ..['enabled'] = true
        ..['drive_type'] = 'friction'
        ..['value'] = 600;
      (tests[2]! as Map<String, Object?>) // P64
        ..['enabled'] = true
        ..['drive_type'] = 'friction'
        ..['value'] = 400;
    })),
    _Case('debug_missing_pin', _mutateDebug(_defaultDocument(ProjectKind.debug), (config) {
      (config['tests']! as List<Object?>).removeAt(0); // 去掉 P60
      final tests = config['tests']! as List<Object?>;
      (tests[0]! as Map<String, Object?>)
        ..['enabled'] = true
        ..['drive_type'] = 'motor'
        ..['value'] = 100;
    })),
    _Case('debug_unknown_pin', _mutateDebug(_defaultDocument(ProjectKind.debug), (config) {
      (config['tests']! as List<Object?>).add({
        'pin': 'P99',
        'enabled': true,
        'drive_type': 'servo',
        'value': 0,
        'duration_ms': 3000,
      });
    })),
    _Case('debug_invalid_drive', _mutateDebug(_defaultDocument(ProjectKind.debug), (config) {
      final tests = config['tests']! as List<Object?>;
      (tests[0]! as Map<String, Object?>)
        ..['enabled'] = true
        ..remove('drive_type');
    })),
    _Case('infantry_default', _defaultDocument(ProjectKind.infantry)),
    _Case('infantry_template', _loadProject(repoRoot, 'assets/templates/infantry.pieproj')),
    _Case(
      'infantry_format22_fixture',
      _loadProject(repoRoot, 'packages/pieblock_core/test/fixtures/format22_infantry.pieproj'),
    ),
    _Case('infantry_bad_fields', _mutateRobot(_defaultDocument(ProjectKind.infantry), (config) {
      (config['remote']! as Map<String, Object?>)
        ..['channel'] = 200
        ..['deadzone'] = 3000;
      final chassis = config['chassis']! as Map<String, Object?>;
      chassis['normal_speed'] = 3000;
      chassis['sprint_speed'] = 2000;
      chassis['sprint_enabled'] = true;
      chassis['turn_sensitivity'] = 250;
    })),
    _Case('infantry_chassis_conflicts', _mutateRobot(_defaultDocument(ProjectKind.infantry), (config) {
      final chassis = config['chassis']! as Map<String, Object?>;
      (chassis['left_front']! as Map<String, Object?>)
        ..['pin'] = 'P60 P61'
        ..['direction'] = 'forward';
      (chassis['left_rear']! as Map<String, Object?>)
        ..['pin'] = 'P60 P61'
        ..['direction'] = 'reverse';
      (chassis['right_front']! as Map<String, Object?>)
        ..['pin'] = 'P60 P61'
        ..['direction'] = 'forward';
    })),
    _Case('engineer_default', _defaultDocument(ProjectKind.engineer)),
    _Case('engineer_template', _loadProject(repoRoot, 'assets/templates/engineer.pieproj')),
    _Case('engineer_chassis_disabled',
        _mutateRobot(_defaultDocument(ProjectKind.engineer), (config) {
      (config['chassis']! as Map<String, Object?>)['enabled'] = false;
    })),
  ];

  for (final item in cases) {
    final document = ProjectDocument.fromJson(item.document);
    final issues = ProjectValidator.validate(document.config);
    final payload = <String, Object?>{
      'name': item.name,
      'kind': document.kind.name,
      'document': document.toJson(),
      'issues': [for (final issue in issues) _issueJson(issue)],
      if (document.kind != ProjectKind.debug)
        'remoteIssues': [
          for (final issue in issues.where((issue) => issue.stepId == 'remote'))
            _issueJson(issue),
        ],
    };
    final target = File(
      '${outputDir.path}${Platform.pathSeparator}${item.name}.json',
    );
    target.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(payload)}\n');
    stdout.writeln('validation golden: ${target.path} (${issues.length} issues)');
  }
}

Map<String, Object?> _issueJson(ValidationIssue issue) => {
      'severity': issue.severity.name,
      'kind': issue.kind.name,
      'fieldPath': issue.fieldPath,
      'message': issue.message,
      'stepId': issue.stepId,
    };

Map<String, Object?> _loadProject(Directory repoRoot, String relative) {
  final file = File(
    '${repoRoot.path}${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}',
  );
  return Map<String, Object?>.from(
    jsonDecode(file.readAsStringSync()) as Map,
  );
}

Map<String, Object?> _defaultDocument(ProjectKind kind) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(ProjectDocument.create(kind).toJson())) as Map);

Map<String, Object?> _mutateDebug(
  Map<String, Object?> document,
  void Function(Map<String, Object?> config) mutate,
) {
  final copy = _clone(document);
  mutate(copy['config']! as Map<String, Object?>);
  return ProjectDocument.fromJson(copy).toJson();
}

Map<String, Object?> _mutateRobot(
  Map<String, Object?> document,
  void Function(Map<String, Object?> config) mutate,
) {
  final copy = _clone(document);
  mutate(copy['config']! as Map<String, Object?>);
  return ProjectDocument.fromJson(copy).toJson();
}

Map<String, Object?> _clone(Map<String, Object?> value) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);

class _Case {
  _Case(this.name, this.document);
  final String name;
  final Map<String, Object?> document;
}
