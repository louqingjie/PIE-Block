// 开发期基准生成器：导出 C 代码生成 golden（含校验未通过时的错误文案）。
//
// 运行：cd tui/parity/tools && dart run bin/export_codegen_goldens.dart
import 'dart:convert';
import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';

void main() {
  final toolsDir = Directory.current.absolute.path;
  final repoRoot = Directory(toolsDir).parent.parent.parent;
  final outputDir = Directory('${repoRoot.path}${Platform.pathSeparator}tui'
      '${Platform.pathSeparator}parity${Platform.pathSeparator}golden'
      '${Platform.pathSeparator}codegen');
  outputDir.createSync(recursive: true);

  final sources = <({String name, Map<String, Object?> json})>[
    for (final file in _files(repoRoot, 'packages/pieblock_core/test/fixtures'))
      (
        name: file.uri.pathSegments.last.replaceAll('.pieproj', '_fixture'),
        json: _read(file),
      ),
    for (final file in _files(repoRoot, 'assets/templates'))
      (name: '${file.uri.pathSegments.last.split('.').first}_template', json: _read(file)),
    for (final kind in ProjectKind.values)
      (name: '${kind.name}_default', json: ProjectDocument.create(kind).toJson()),
  ];

  final cases = <Object?>[];
  for (final item in sources) {
    final document = ProjectDocument.fromJson(item.json);
    final errors = ProjectValidator.validate(
      document.config,
    ).where((issue) => issue.severity == IssueSeverity.error);
    final payload = <String, Object?>{
      'name': item.name,
      'kind': document.kind.name,
      'sourceFormatVersion': document.sourceFormatVersion,
      'document': document.toJson(),
    };
    if (errors.isNotEmpty) {
      payload['error'] = '配置尚未完成，不能生成代码：${errors.first.message}';
    } else {
      final program = CodeGenerator.generateProgram(document.config);
      payload['source'] = program.source;
      payload['expressionLineFields'] = {
        for (final entry in program.expressionLineFields.entries)
          entry.key.toString(): entry.value,
      };
    }
    cases.add(payload);
  }

  final target = File(
    '${outputDir.path}${Platform.pathSeparator}codegen.json',
  );
  target.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'cases': cases})}\n',
  );
  stdout.writeln('codegen golden: ${target.path}');
}

Map<String, Object?> _read(File file) =>
    Map<String, Object?>.from(jsonDecode(file.readAsStringSync()) as Map);

Iterable<File> _files(Directory root, String relativeDir) {
  final dir = Directory('${root.path}${Platform.pathSeparator}'
      '${relativeDir.replaceAll('/', Platform.pathSeparator)}');
  return dir
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.pieproj'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}
