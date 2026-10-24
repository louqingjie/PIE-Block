// 用内置 SDCC 真实编译教材示例工程，产出 HEX 与 main.rst 列表文件，
// 供第 9 章「编译、烧录与联机调试」引用真实产物（字节数、警告数、
// HEX 记录与列表文件摘录都来自这里）。
//
// 用法（仓库根目录）：
//
//     dart run tool/build_book_firmware.dart
//
// 产物写入 build/book_firmware/<示例名>/：
//   firmware.hex   链接后的 Intel HEX
//   main.rst       SDCC 汇编列表文件
//   build.json     摘要（字节数、警告数、SHA-256）

import 'dart:convert';
import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_toolchain/pieblock_toolchain.dart';

const _examples = <String>['infantry-standard', 'debug-checklist'];

String _abs(String path) =>
    path.startsWith('/') ? path : '${Directory.current.path}/$path';

Future<void> main() async {
  final outRoot = Directory('build/book_firmware');
  outRoot.createSync(recursive: true);

  var failed = false;
  for (final name in _examples) {
    stdout.writeln('== $name');
    final doc = ProjectDocument.fromJson(
      Map<String, Object?>.from(
        jsonDecode(File('book/examples/$name.pieproj').readAsStringSync()) as Map,
      ),
    );
    final source = CodeGenerator.generate(doc.config);
    final builder = FirmwareBuilder(
      artifacts: BuildArtifactRepository(root: _abs('build/book_firmware/artifacts')),
      runtimeRoot: _abs('build/book_firmware/runtime'),
      workRoot: _abs('build/book_firmware/work'),
    );
    final fingerprint = await builder.resolveCompilerFingerprint(
      CompilerKind.sdcc,
    );
    final operation = builder.start(
      BuildRequest(
        projectKind: doc.kind,
        sourceCode: source,
        compiler: CompilerKind.sdcc,
        compilerFingerprint: fingerprint,
      ),
    );
    operation.events.listen(
      (event) => stdout.writeln('  [${event.stage.name}] ${event.message}'),
      onError: (Object _) {},
    );
    final result = await operation.result;
    final artifact = result.artifact;
    if (!result.success || artifact == null) {
      stderr.writeln('  编译失败：\n${result.log}');
      failed = true;
      continue;
    }
    final dir = Directory('build/book_firmware/$name');
    dir.createSync(recursive: true);
    final hex = File(artifact.hexPath);
    final listing = result.listing;
    final hexCopy = File('${dir.path}/firmware.hex');
    hexCopy.parent.createSync(recursive: true);
    hexCopy.writeAsBytesSync(hex.readAsBytesSync(), flush: true);
    if (listing != null) {
      File('${dir.path}/main.rst').writeAsStringSync(listing);
    }
    File('${dir.path}/build.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'hex': hexCopy.path,
        'hexBytes': artifact.byteCount,
        'hexSha256': artifact.hexSha256,
        'warnings': artifact.warningCount,
        'builtAt': artifact.builtAt.toIso8601String(),
        'listing': listing == null ? null : '${dir.path}/main.rst',
      }),
    );
    stdout.writeln(
      '  完成：${artifact.byteCount} 字节，${artifact.warningCount} 条警告，'
      'HEX=${hexCopy.path}',
    );
  }
  if (failed) exitCode = 1;
}
