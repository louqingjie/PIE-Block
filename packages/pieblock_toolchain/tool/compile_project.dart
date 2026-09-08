import 'dart:async';
import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_toolchain/pieblock_toolchain.dart';

/// 离线 SDCC 编译端到端验证工具。
///
/// 用法: dart run tool/compile_project.dart <kind>
///   kind: infantry | engineer | debug | music
///
/// 用 ProjectDocument.create 的新工程默认配置作为确定性输入（与新建工程
/// 向导产物一致），生成代码后走完整 FirmwareBuilder 流程编译，
/// 输出 HEX 路径与 SHA256，用于跨平台产物对比。
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('用法: dart run tool/compile_project.dart <kind>');
    stderr.writeln('  kind: infantry | engineer | debug | music');
    exitCode = 2;
    return;
  }
  final kind = ProjectKind.values.where((value) => value.name == args[0]).firstOrNull;
  if (kind == null) {
    stderr.writeln('未知工程类型: ${args[0]}');
    exitCode = 2;
    return;
  }

  final work = await Directory.systemTemp.createTemp('pieblock_verify_');
  try {
    final builder = FirmwareBuilder(
      artifacts: BuildArtifactRepository(
        root: Directory.fromUri(work.uri.resolve('artifacts')).path,
      ),
      runtimeRoot: Directory.fromUri(work.uri.resolve('runtime')).path,
      workRoot: Directory.fromUri(work.uri.resolve('builds')).path,
    );
    final document = ProjectDocument.create('verify', kind);
    // 新建工程不预填必填配置。为使代码生成可用，补上与向导最小操作等价的
    // 确定性内容：调试工程启用第一个调试项；音乐工程添加单个音符。
    final config = switch (document.config) {
      final DebugConfig debug => debug.copyWith(
        tests: [
          debug.tests.first.copyWith(
            enabled: true,
            driveType: DebugDriveType.servo,
            direction: Direction.forward,
            value: 45,
          ),
          ...debug.tests.skip(1),
        ],
      ),
      final MusicConfig music => music.copyWith(
        notes: [
          MusicNote(id: 'verify', pitch: 60, startTick: 0, durationTicks: 480),
        ],
      ),
      _ => document.config,
    };
    final code = CodeGenerator.generate(config);
    final compilerFingerprint = await builder.resolveCompilerFingerprint(
      CompilerKind.sdcc,
    );
    final request = BuildRequest(
      projectKind: kind,
      sourceCode: code,
      compiler: CompilerKind.sdcc,
      compilerFingerprint: compilerFingerprint,
    );
    final operation = builder.start(request);
    final subscription = operation.events.listen(
      (event) => stdout.writeln('[${event.stage.name}] ${event.message}'),
      onError: (Object error) => stderr.writeln('$error'),
    );
    final result = await operation.result;
    await subscription.cancel();
    if (!result.success) {
      stderr.writeln(result.log);
      stderr.writeln('编译失败（exitCode=${result.exitCode}）');
      exitCode = 1;
      return;
    }
    final artifact = result.artifact!;
    stdout.writeln('kind        = ${kind.name}');
    stdout.writeln('byte_count  = ${artifact.byteCount}');
    stdout.writeln('warnings    = ${artifact.warningCount}');
    stdout.writeln('hex_sha256  = ${artifact.hexSha256}');
    stdout.writeln('hex_path    = ${artifact.hexPath}');
  } finally {
    await work.delete(recursive: true);
  }
}
