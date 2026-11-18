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
    _Case('engineer_bad_pwm',
        _mutateRobot(_loadProject(repoRoot, 'assets/templates/engineer.pieproj'), (config) {
      final pwm = config['pwm']! as Map<String, Object?>;
      (pwm['pin_roles']! as Map<String, Object?>)['P60'] = 'motor';
      (pwm['pin_roles']! as Map<String, Object?>)['MP03'] = 'motor';
      (pwm['servo_mids']! as Map<String, Object?>)['P62'] = 200;
      config['mode_switch_key'] = 'ZZ';
      (config['chassis']! as Map<String, Object?>)
        ..['sprint_enabled'] = true
        ..['sprint_speed'] = 9000;
    })),
    _Case('engineer_bad_modes',
        _mutateRobot(_loadProject(repoRoot, 'assets/templates/engineer.pieproj'), (config) {
      config['switch_strategy'] = 'direct';
      config['mode_keys'] = ['E', 'LC'];
      (config['chassis']! as Map<String, Object?>)
        ..['sprint_enabled'] = true
        ..['sprint_speed'] = 9000;
      final mode = ((config['modes']! as List<Object?>)[1]!)
          as Map<String, Object?>;
      final actions = mode['actions']! as List<Object?>;
      actions.addAll([
        {
          'input_kind': 'remote',
          'key': 'ZZ',
          'output_kind': 'pin',
          'pin': 'P99',
          'mode': 'direct',
          'parameter': 500,
        },
        {
          'input_kind': 'remote',
          'key': 'D',
          'output_kind': 'pin',
          'pin': 'P60',
          'mode': 'direct',
          'parameter': 10,
        },
        {
          'input_kind': 'unspecified',
          'key': 'B',
          'output_kind': 'pin',
          'pin': 'P60',
          'expression': '1+',
          'mode': 'direct',
          'parameter': 1,
        },
        {
          'input_kind': 'unspecified',
          'output_kind': 'integer',
          'variable': 'bad name',
          'expression': '1.5',
        },
        {
          'input_kind': 'unspecified',
          'output_kind': 'integer',
          'variable': 'dup',
          'expression': '1',
        },
        {
          'input_kind': 'unspecified',
          'output_kind': 'integer',
          'variable': 'dup',
          'expression': '2',
        },
      ]);
      mode['action_tables'] = [
        {
          'key': 'E',
          'prev_key': 'E',
          'steps': 3,
          'wrap': false,
          'rows': [
            {
              'pin': 'P62',
              'values': [10, 20],
            },
          ],
        },
      ];
    })),
    _Case('engineer_variable_types',
        _mutateRobot(_loadProject(repoRoot, 'assets/templates/engineer.pieproj'), (config) {
      final modes = config['modes']! as List<Object?>;
      (modes[0]! as Map<String, Object?>)['actions'] = [
        ...(modes[0]! as Map<String, Object?>)['actions']! as List<Object?>,
        {
          'input_kind': 'unspecified',
          'output_kind': 'integer',
          'variable': 'shared',
          'expression': '1',
        },
      ];
      (modes[1]! as Map<String, Object?>)['actions'] = [
        ...(modes[1]! as Map<String, Object?>)['actions']! as List<Object?>,
        {
          'input_kind': 'unspecified',
          'output_kind': 'rational',
          'variable': 'shared',
          'expression': '1.5',
        },
      ];
    })),
    _Case('music_default', _defaultDocument(ProjectKind.music)),
    _Case('music_template', _loadProject(repoRoot, 'assets/templates/music.pieproj')),
    _Case('music_bad_notes', _mutateRobot(_defaultDocument(ProjectKind.music), (config) {
      config['notes'] = [
        {'id': '', 'pitch': 300, 'start_tick': -1, 'duration_ticks': 0},
        {'id': 'a', 'pitch': 60, 'start_tick': 0, 'duration_ticks': 100},
        {'id': 'a', 'pitch': 61, 'start_tick': 50, 'duration_ticks': 100},
      ];
    })),
    _Case('music_bad_events', _mutateRobot(_defaultDocument(ProjectKind.music), (config) {
      config['key_signature_fifths'] = 8;
      config['ticks_per_quarter'] = 0;
      config['tempo_events'] = [
        {'tick': 10, 'microseconds_per_quarter': 0},
      ];
      config['time_signature_events'] = [
        {'tick': 0, 'numerator': 0, 'denominator': 3},
      ];
    })),
    _Case('music_long', _mutateRobot(_defaultDocument(ProjectKind.music), (config) {
      config['notes'] = [
        {
          'id': 'long',
          'pitch': 60,
          'start_tick': 0,
          'duration_ticks': 2000000,
        },
      ];
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
