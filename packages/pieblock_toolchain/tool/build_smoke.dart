import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_toolchain/pieblock_toolchain.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length < 2 || arguments.length > 3) {
    stderr.writeln(
      '用法：dart run tool/build_smoke.dart <infantry|engineer|debug> <main.c> [Keil目录]',
    );
    exitCode = 64;
    return;
  }
  final kind = ProjectKind.values.byName(arguments[0]);
  final builder = FirmwareBuilder();
  final compiler = arguments.length == 3
      ? CompilerKind.keil
      : CompilerKind.sdcc;
  final compilerFingerprint = await builder.resolveCompilerFingerprint(
    compiler,
    keilRoot: arguments.length == 3 ? arguments[2] : null,
  );
  final operation = builder.start(
    BuildRequest(
      projectKind: kind,
      sourceCode: await File(arguments[1]).readAsString(),
      compiler: compiler,
      compilerFingerprint: compilerFingerprint,
      keilRoot: arguments.length == 3 ? arguments[2] : null,
    ),
  );
  operation.events.listen((event) => stdout.writeln(event.message));
  final result = await operation.result;
  if (!result.success) {
    stderr.writeln(result.log);
    exitCode = 1;
    return;
  }
  stdout.writeln('HEX=${result.artifact!.hexPath}');
}
