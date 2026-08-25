import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pieblock_toolchain/pieblock_toolchain.dart';

class AndroidSdccServiceBackend implements SdccCompilerBackend {
  AndroidSdccServiceBackend({
    required this.resourceRoot,
    required this.librarySha256,
    required this.androidAbi,
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _methods = methodChannel ?? const MethodChannel(_methodChannelName),
       _events = eventChannel ?? const EventChannel(_eventChannelName);

  static const _methodChannelName = 'cn.edu.cnu.pieblock/sdcc_compiler';
  static const _eventChannelName = 'cn.edu.cnu.pieblock/sdcc_compiler_events';
  static const protocolVersion = 2;
  static const workerProtocolVersion = 1;

  final String resourceRoot;
  final String librarySha256;
  final String androidAbi;
  final MethodChannel _methods;
  final EventChannel _events;
  String? _activeOperationId;

  @override
  Future<String> resolveFingerprint() async {
    final capabilities = await _methods.invokeMapMethod<Object?, Object?>(
      'probe',
    );
    final actualProtocol = capabilities?['protocolVersion'] as int?;
    if (actualProtocol != protocolVersion) {
      throw StateError(
        '不兼容的 Android 编译服务协议：$actualProtocol（需要 $protocolVersion）',
      );
    }
    if (capabilities?['workerProtocolVersion'] != workerProtocolVersion) {
      throw StateError(
        '不兼容的 Android Worker 协议：${capabilities?['workerProtocolVersion']}'
        '（需要 $workerProtocolVersion）',
      );
    }
    if (capabilities?['apiVersion'] != 5 ||
        capabilities?['available'] != true) {
      throw UnsupportedError('Android SDCC 流水线尚未通过安全门自检');
    }
    final nativeFingerprint = capabilities?['fingerprint'] as String?;
    if (nativeFingerprint == null || nativeFingerprint.isEmpty) {
      throw StateError('Android SDCC 原生指纹为空');
    }
    return '$nativeFingerprint;service:$protocolVersion;worker:$workerProtocolVersion;'
        'library:$librarySha256;'
        'resource:${p.basename(resourceRoot)};runtime-abi:$androidAbi';
  }

  @override
  Future<CompilerBackendResult> build(
    BuildRequest request,
    String workDirectory,
    BuildEventSink emit,
  ) async {
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
    final resultCompleter = Completer<CompilerBackendResult>();
    late final StreamSubscription<Object?> subscription;
    subscription = _events.receiveBroadcastStream().listen(
      (raw) {
        if (raw is! Map) return;
        final event = raw.cast<Object?, Object?>();
        final operationId = event['operationId'] as String?;
        if (_activeOperationId != null && operationId != _activeOperationId) {
          return;
        }
        if (event['type'] == 'event') {
          emit(
            _stage(event['stage'] as int? ?? 0),
            event['message'] as String? ?? '',
            level: _level(event['level'] as int? ?? 0),
            current: event['current'] as int?,
            total: event['total'] as int?,
          );
        } else if (event['type'] == 'result' && !resultCompleter.isCompleted) {
          resultCompleter.complete(
            CompilerBackendResult(
              success: event['success'] == true && File(hexPath).existsSync(),
              canceled: event['canceled'] == true,
              exitCode: event['exitCode'] as int?,
              hexPath: event['hexPath'] as String?,
              mapPath: event['mapPath'] as String?,
              warningCount: event['warningCount'] as int? ?? 0,
              message: event['message'] as String?,
            ),
          );
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!resultCompleter.isCompleted) {
          resultCompleter.complete(
            CompilerBackendResult(success: false, message: '编译器进程异常退出：$error'),
          );
        }
      },
    );
    try {
      _activeOperationId = await _methods.invokeMethod<String>('start', {
        'workingDirectory': workDirectory,
        'resourceDirectory': resourceRoot,
        'projectKind': project,
        'mainSourcePath': mainSource.path,
        'interruptHeaderPath': plan.interruptHeaderPath,
        'sourcePaths': plan.sourcePaths,
        'librarySourcePaths': plan.librarySourcePaths,
        'compileArguments': plan.compileArguments,
        'linkArguments': plan.linkArguments,
        'hexOutputPath': hexPath,
        'mapOutputPath': mapPath,
        'logOutputPath': logPath,
      });
      if (_activeOperationId == null) {
        throw StateError('Android 编译服务没有返回任务 ID');
      }
      return await resultCompleter.future;
    } on PlatformException catch (error) {
      return CompilerBackendResult(
        success: false,
        message: error.message ?? '无法启动 Android 编译服务',
      );
    } finally {
      final operationId = _activeOperationId;
      _activeOperationId = null;
      await subscription.cancel();
      if (operationId != null) {
        await _methods.invokeMethod<void>('acknowledge', {
          'operationId': operationId,
        });
      }
    }
  }

  @override
  void cancel() {
    final operationId = _activeOperationId;
    if (operationId == null) return;
    unawaited(
      _methods.invokeMethod<void>('cancel', {'operationId': operationId}),
    );
  }

  static BuildStage _stage(int value) => switch (value) {
    0 || 1 => BuildStage.preparing,
    2 || 3 => BuildStage.compiling,
    4 => BuildStage.linking,
    _ => BuildStage.done,
  };

  static BuildEventLevel _level(int value) => switch (value) {
    1 => BuildEventLevel.warning,
    2 => BuildEventLevel.error,
    _ => BuildEventLevel.info,
  };
}
