// 开发期基准生成器：把 Dart CLI 的 validate/codegen 输出落成 golden。
//
// 运行：cd tui/parity/tools && dart run bin/export_cli_goldens.dart
//
// 生成 tui/parity/cli/projects/*.pieproj（提交到 git）与
// tui/parity/golden/cli/cli.json：退出码 + stdout + stderr 逐字节快照。
import 'dart:convert';
import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';

void main() {
  final toolsDir = Directory.current.absolute.path;
  final repoRoot = Directory(toolsDir).parent.parent.parent;
  final projectsDir = Directory('${repoRoot.path}${Platform.pathSeparator}tui'
      '${Platform.pathSeparator}parity${Platform.pathSeparator}cli'
      '${Platform.pathSeparator}projects');
  final goldenDir = Directory('${repoRoot.path}${Platform.pathSeparator}tui'
      '${Platform.pathSeparator}parity${Platform.pathSeparator}golden'
      '${Platform.pathSeparator}cli');
  projectsDir.createSync(recursive: true);
  goldenDir.createSync(recursive: true);

  final projects = <({String name, Map<String, Object?> json})>[
    for (final file in _files(repoRoot, 'packages/pieblock_core/test/fixtures'))
      (
        name: file.uri.pathSegments.last.replaceAll('.pieproj', '_fixture'),
        json: _read(file),
      ),
    for (final file in _files(repoRoot, 'assets/templates'))
      (name: '${file.uri.pathSegments.last.split('.').first}_template', json: _read(file)),
    for (final kind in ProjectKind.values)
      (name: '${kind.name}_default', json: ProjectDocument.create(kind).toJson()),
    // 版本不兼容样本：过旧与过新。
    (
      name: 'version_too_old',
      json: {..._read(_firstFixture(repoRoot, 'format17')), 'format_version': 16},
    ),
    (
      name: 'version_too_new',
      json: {..._read(_firstFixture(repoRoot, 'format17')), 'format_version': 24},
    ),
  ];

  final written = <({String name, String relative})>[];
  for (final project in projects) {
    final relative =
        'tui/parity/cli/projects/${project.name}.pieproj';
    final file = File('${repoRoot.path}${Platform.pathSeparator}'
        '${relative.replaceAll('/', Platform.pathSeparator)}');
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(project.json)}\n',
    );
    written.add((name: project.name, relative: relative));
  }

  final cases = <Object?>[];
  for (final project in written) {
    for (final command in ['validate', 'codegen']) {
      final result = Process.runSync(
        Platform.resolvedExecutable,
        ['run', 'packages/pieblock_core/bin/pieblock.dart', command, project.relative],
        workingDirectory: repoRoot.path,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      cases.add({
        'name': '${project.name}_$command',
        'kind': _kindOf(project.relative),
        'command': command,
        'args': [command, project.relative],
        'exitCode': result.exitCode,
        'stdout': result.stdout,
        'stderr': result.stderr,
      });
    }
  }
  // 代码生成失败（配置有 error）：debug 默认工程。
  final target = File('${goldenDir.path}${Platform.pathSeparator}cli.json');
  target.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'cases': cases})}\n',
  );
  stdout.writeln('cli golden: ${target.path}');
}

String _kindOf(String relative) {
  final name = relative.split('/').last;
  if (name.startsWith('infantry')) return 'infantry';
  if (name.startsWith('engineer')) return 'engineer';
  if (name.startsWith('debug')) return 'debug';
  if (name.startsWith('music')) return 'music';
  if (name.contains('infantry')) return 'infantry';
  if (name.contains('engineer')) return 'engineer';
  if (name.contains('debug')) return 'debug';
  if (name.contains('music')) return 'music';
  return 'unknown';
}

File _firstFixture(Directory repoRoot, String prefix) {
  final dir = Directory('${repoRoot.path}${Platform.pathSeparator}'
      'packages${Platform.pathSeparator}pieblock_core${Platform.pathSeparator}test'
      '${Platform.pathSeparator}fixtures');
  final files = dir
      .listSync()
      .whereType<File>()
      .where((file) => file.uri.pathSegments.last.startsWith(prefix))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return files.first;
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
