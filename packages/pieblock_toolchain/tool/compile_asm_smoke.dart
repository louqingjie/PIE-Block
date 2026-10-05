import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_toolchain/pieblock_toolchain.dart';

/// 汇编输出试点的端到端冒烟构建：
/// 用内置样例音乐配置直接生成汇编源码，
/// 走 FirmwareBuilder 的 SDCC 子进程管线完成汇编、链接并产出 HEX。
/// 用法：dart run tool/compile_asm_smoke.dart
Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln('用法：dart run tool/compile_asm_smoke.dart');
    exitCode = 64;
    return;
  }
  final config = sampleMusicConfig();
  final source = CodeGenerator.generate(config, target: OutputTarget.asm);
  final builder = FirmwareBuilder();
  final compilerFingerprint = await builder.resolveCompilerFingerprint(
    CompilerKind.sdcc,
  );
  final operation = builder.start(
    BuildRequest(
      projectKind: config.kind,
      sourceCode: source,
      compiler: CompilerKind.sdcc,
      compilerFingerprint: compilerFingerprint,
      outputTarget: OutputTarget.asm,
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

/// 与 pieblock_core 的 generate_smoke 保持一致的最小音乐配置。
MusicConfig sampleMusicConfig() => MusicConfig(
  notes: const [
    MusicNote(id: 'c4', pitch: 60, startTick: 0, durationTicks: 480),
    MusicNote(id: 'e4', pitch: 64, startTick: 720, durationTicks: 480),
  ],
  tempoEvents: const [
    TempoEvent(tick: 0, microsecondsPerQuarter: 500000),
    TempoEvent(tick: 960, microsecondsPerQuarter: 400000),
  ],
);
