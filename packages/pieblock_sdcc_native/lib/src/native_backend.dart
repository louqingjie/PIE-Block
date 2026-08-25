import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pieblock_toolchain/pieblock_toolchain.dart';

import 'native_client.dart';

class NativeSdccBackend implements SdccCompilerBackend {
  NativeSdccBackend({
    required this.resourceRoot,
    required this.librarySha256,
    required this.androidAbi,
    NativeSdccClient? client,
  }) : _client = client ?? NativeSdccClient();

  final String resourceRoot;
  final String librarySha256;
  final String androidAbi;
  final NativeSdccClient _client;
  NativeSdccOperation? _operation;

  @override
  Future<String> resolveFingerprint() async {
    if (!_client.isAvailable) {
      throw UnsupportedError('此安装包尚未包含可用的 Android SDCC 原生流水线');
    }
    return '${_client.fingerprint};library:$librarySha256;'
        'resource:${p.basename(resourceRoot)};runtime-abi:$androidAbi';
  }

  @override
  Future<CompilerBackendResult> build(
    BuildRequest request,
    String workDirectory,
    BuildEventSink emit,
  ) async {
    if (!_client.isAvailable) {
      return const CompilerBackendResult(
        success: false,
        message: '此安装包尚未包含可用的 Android SDCC 原生流水线',
      );
    }
    final output = Directory(p.join(workDirectory, 'output'));
    await output.create(recursive: true);
    final mainSource = File(p.join(workDirectory, 'main.c'));
    await mainSource.writeAsString(request.sourceCode, flush: true);
    final project = request.projectKind.name;
    final hexPath = p.join(output.path, '$project.hex');
    final mapPath = p.join(output.path, '$project.map');
    final logPath = p.join(output.path, '$project.log');
    final plan = await SdccBuildPlan.prepare(
      resourceRoot: resourceRoot,
      projectName: project,
      mainSourcePath: mainSource.path,
      outputDirectory: output.path,
    );
    final operation = _client.start(
      workingDirectory: workDirectory,
      resourceDirectory: resourceRoot,
      projectKind: project,
      mainSourcePath: mainSource.path,
      interruptHeaderPath: plan.interruptHeaderPath,
      sourcePaths: plan.sourcePaths,
      compileArguments: plan.compileArguments,
      linkArguments: plan.linkArguments,
      hexOutputPath: hexPath,
      mapOutputPath: mapPath,
      logOutputPath: logPath,
    );
    _operation = operation;
    final subscription = operation.events.listen((event) {
      emit(
        switch (event.stage) {
          0 || 1 => BuildStage.preparing,
          2 || 3 => BuildStage.compiling,
          4 => BuildStage.linking,
          _ => BuildStage.done,
        },
        event.message,
        level: switch (event.level) {
          1 => BuildEventLevel.warning,
          2 => BuildEventLevel.error,
          _ => BuildEventLevel.info,
        },
        current: event.current,
        total: event.total,
      );
    });
    try {
      final result = await operation.result;
      return CompilerBackendResult(
        success: result.success && await File(result.hexPath).exists(),
        canceled: result.canceled,
        exitCode: result.exitCode,
        hexPath: result.hexPath,
        mapPath: result.mapPath,
        warningCount: result.warningCount,
        message: result.message,
      );
    } finally {
      await subscription.cancel();
      if (identical(_operation, operation)) _operation = null;
    }
  }

  @override
  void cancel() => _operation?.cancel();
}
