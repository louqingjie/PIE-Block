// 开发期基准生成器：用现有 Dart 实现把 fixture/模板迁移到当前格式，
// 输出给 Rust 侧对拍的 golden。发布产物不依赖 Dart。
//
// 运行：cd tui/parity/tools && dart pub get && dart run bin/export_model_goldens.dart
import 'dart:convert';
import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';

void main() {
  final toolsDir = Directory.current.absolute.path;
  final repoRoot = Directory(toolsDir).parent.parent.parent;
  final outputDir = Directory('${repoRoot.path}${Platform.pathSeparator}tui'
      '${Platform.pathSeparator}parity${Platform.pathSeparator}golden'
      '${Platform.pathSeparator}model');
  outputDir.createSync(recursive: true);

  final sources = <File>[
    ..._files(repoRoot, 'packages/pieblock_core/test/fixtures', '.pieproj'),
    ..._files(repoRoot, 'assets/templates', '.pieproj'),
  ];

  for (final file in sources) {
    final relative = file.path.substring(repoRoot.path.length + 1);
    final raw = jsonDecode(file.readAsStringSync());
    final document = ProjectDocument.fromJson(
      Map<String, Object?>.from(raw as Map),
    );
    final golden = <String, Object?>{
      'source': relative.replaceAll('\\', '/'),
      'kind': document.kind.name,
      'sourceFormatVersion': document.sourceFormatVersion,
      'document': document.toJson(),
    };
    final name = file.uri.pathSegments.last;
    final target = File(
      '${outputDir.path}${Platform.pathSeparator}${name.replaceAll('.pieproj', '.json')}',
    );
    target.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(golden)}\n',
    );
    stdout.writeln('golden: ${target.path}');
  }
}

Iterable<File> _files(Directory root, String relativeDir, String suffix) {
  final dir = Directory('${root.path}${Platform.pathSeparator}'
      '${relativeDir.replaceAll('/', Platform.pathSeparator)}');
  return dir
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith(suffix))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}
