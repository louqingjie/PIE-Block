// 开发期基准生成器：导出表达式解析/求值/C 发射/运行时/试算的 golden。
//
// 运行：cd tui/parity/tools && dart run bin/export_expression_goldens.dart
import 'dart:convert';
import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';

const _scope = <String, ExpressionType>{
  'speed': ExpressionType.integer,
  'ratio': ExpressionType.rational,
};

const _inputs = <String, num>{
  'LX': 120,
  'LY': -30,
  'RX': 0,
  'RY': 45,
  'A': 1,
  'B': 0,
  'UP': 1,
};

const _variableValues = <String, num>{'speed': 50, 'ratio': 0.5};

const _cases = <String>[
  '1+2*3',
  '(1+2)*3',
  '10/3',
  '10/4',
  '10.0/4',
  '7%3',
  '-7%3',
  'LX',
  'LX>100',
  'LX>=100 && A==1',
  '!A',
  '-LX',
  '+LX',
  '1<2.5',
  '1.0==1',
  'min(1,2,3)',
  'max(1.5,2,3)',
  'abs(-5)',
  'abs(-5.5)',
  'sign(LX-100)',
  'sqrt(LX)',
  'atan2(1.0,2.0)',
  'PI',
  'E',
  'PI*2',
  '1e3',
  '1.5e-2',
  'LX?1:2',
  'LX?1:2.5',
  'speed+1',
  'ratio*2',
  'speed>ratio',
  '((LX))',
  'min(LX, LY)',
  'abs(speed)',
  'sqrt(ratio)',
  'min(1,2,3,4,5)',
  '1 + 2 * 3 - 4 / 2',
  '',
  '1+',
  'foo',
  '1/0',
  '1%0',
  '1%2.0',
  'sqrt(-1)',
  'sqrt(-1.0)',
  'atan2(1)',
  'min(1)',
  'unknown(1)',
  '1.2.3',
  '.',
  '1e',
  '1e999',
  '1 & 2',
  '1=2',
  'A B',
  '99999999999999999999',
  '2147483648',
  '@',
  '1 ? 2',
  '1 ? 2 : ',
  '(1+2',
  'min(1,2',
  'min(1,2,)',
  'PI + 中文',
];

const _variableNames = <String>[
  'speed1',
  'a',
  'Abc_123',
  '_x',
  '1x',
  'LX',
  'int',
  'PI',
  'speed-1',
  'abcdefghijklmnopqrstuvwx',
  'abcdefghijklmnopqrstuvwxy',
  '',
  '中文',
  'speed ',
  'speed_',
];

void main() {
  final toolsDir = Directory.current.absolute.path;
  final repoRoot = Directory(toolsDir).parent.parent.parent;
  final outputDir = Directory('${repoRoot.path}${Platform.pathSeparator}tui'
      '${Platform.pathSeparator}parity${Platform.pathSeparator}golden'
      '${Platform.pathSeparator}expression');
  outputDir.createSync(recursive: true);

  final cases = <Object?>[];
  for (final source in _cases) {
    final parsed = ExpressionParser.parse(source, variables: _scope);
    final payload = <String, Object?>{
      'source': source,
      'ok': parsed.ok,
      'diagnostics': [
        for (final diagnostic in parsed.diagnostics)
          {'message': diagnostic.message, 'offset': diagnostic.offset},
      ],
    };
    if (parsed.ok) {
      final emitter = ExpressionEmitter(
        inputCode: (name) => 'INPUT_$name',
        variableCode: (name) => 'VAR_$name',
      );
      payload['type'] = parsed.root!.type.name;
      payload['code'] = emitter.emit(parsed.root!);
      payload['helpers'] = emitter.helpers.toList()..sort();
      payload['eval'] = ExpressionEvaluator.evaluate(
        parsed.root!,
        inputs: _inputs,
        variables: _variableValues,
      ).toString();
    }
    cases.add(payload);
  }

  final runtimeCases = <Object?>[
    for (final helpers in <List<String>>[
      const [],
      const ['div_i', 'mod_i'],
      const ['sqrt_f'],
      const ['atan2_f', 'clamp_i', 'servo_duty'],
      const ['sign_f', 'min_f', 'max_f', 'abs_f', 'clamp_f'],
      const [
        'clamp_i',
        'clamp_f',
        'servo_duty',
        'div_i',
        'mod_i',
        'div_f',
        'abs_i',
        'abs_f',
        'min_i',
        'min_f',
        'max_i',
        'max_f',
        'sign_i',
        'sign_f',
        'sqrt_f',
        'atan2_f',
      ],
    ])
      {
        'helpers': helpers,
        'code': ExpressionRuntime.code(helpers.toSet()),
      },
  ];

  final preview = <Object?>[];
  final template = _loadProject(
    repoRoot,
    'assets/templates/engineer.pieproj',
  );
  final config = template.config as EngineerConfig;
  for (var modeIndex = 0; modeIndex < config.modes.length; modeIndex++) {
    const inputs = <String, num>{
      'LX': 500,
      'LY': -200,
      'RX': 100,
      'RY': 0,
      'A': 1,
      'B': 1,
      'C': 0,
      'D': 0,
      'E': 1,
      'LC': 0,
      'RC': 0,
      'UP': 1,
      'DOWN': 0,
      'LEFT': 0,
      'RIGHT': 1,
    };
    final result = EngineerPreview.evaluateMode(config, modeIndex, inputs);
    final variables = result.variables.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    preview.add({
      'modeIndex': modeIndex,
      'inputs': inputs,
      'variables': {for (final entry in variables) entry.key: entry.value.toString()},
      'rows': [
        for (final row in result.rows)
          {
            'label': row.label,
            'fieldPath': row.fieldPath,
            'value': row.value?.toString(),
            'error': row.error,
          },
      ],
    });
  }

  final golden = <String, Object?>{
    'cases': cases,
    'runtime': runtimeCases,
    'variableNames': [
      for (final name in _variableNames)
        {'name': name, 'valid': isValidVariableName(name)},
    ],
    'engineerPreview': preview,
  };
  final target = File(
    '${outputDir.path}${Platform.pathSeparator}expression.json',
  );
  target.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(golden)}\n',
  );
  stdout.writeln('expression golden: ${target.path}');
}

ProjectDocument _loadProject(Directory repoRoot, String relative) {
  final file = File('${repoRoot.path}${Platform.pathSeparator}'
      '${relative.replaceAll('/', Platform.pathSeparator)}');
  return ProjectDocument.fromJson(
    Map<String, Object?>.from(jsonDecode(file.readAsStringSync()) as Map),
  );
}
