import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'bindings.dart';

const _ok = 0;
const _canceled = 5;
const _running = 6;
const _complete = 7;
const _eventAvailable = 8;

String? _optionalNativeString(Pointer<Char> pointer) {
  if (pointer.address == 0) return null;
  final value = pointer.cast<Utf8>().toDartString();
  return value.isEmpty ? null : value;
}

class NativeSdccEvent {
  const NativeSdccEvent({
    required this.stage,
    required this.level,
    required this.message,
    this.fileName,
    this.current,
    this.total,
  });

  final int stage;
  final int level;
  final String message;
  final String? fileName;
  final int? current;
  final int? total;
}

class NativeSdccResult {
  const NativeSdccResult({
    required this.success,
    required this.canceled,
    required this.exitCode,
    required this.errorCount,
    required this.warningCount,
    required this.message,
    required this.hexPath,
    required this.mapPath,
    required this.logPath,
    required this.errorCode,
  });

  final bool success;
  final bool canceled;
  final int exitCode;
  final int errorCount;
  final int warningCount;
  final String message;
  final String hexPath;
  final String mapPath;
  final String logPath;
  final String errorCode;
}

class NativeSdccOperation {
  NativeSdccOperation._(this.events, this.result, this._cancel);

  final Stream<NativeSdccEvent> events;
  final Future<NativeSdccResult> result;
  final void Function() _cancel;

  void cancel() => _cancel();
}

class NativeSdccClient {
  NativeSdccClient({DynamicLibrary? library})
    : _usesInjectedLibrary = library != null,
      _bindings = PbSdccBindings(
        library ??
            (Platform.isAndroid
                ? DynamicLibrary.open('libpieblock_sdcc_native.so')
                : throw UnsupportedError('原生 SDCC 仅支持 Android')),
      ) {
    final actual = _bindings.apiVersion();
    if (actual != 3) {
      throw StateError('不兼容的 SDCC FFI ABI：$actual（需要 3）');
    }
  }

  final PbSdccBindings _bindings;
  final bool _usesInjectedLibrary;

  String get fingerprint => _bindings.fingerprint().cast<Utf8>().toDartString();

  bool get isAvailable => _bindings.isAvailable() != 0;

  NativeSdccOperation start({
    required String workingDirectory,
    required String resourceDirectory,
    required String projectKind,
    required String mainSourcePath,
    List<String> sourcePaths = const [],
    List<String> compileArguments = const [],
    List<String> linkArguments = const [],
    required String hexOutputPath,
    required String mapOutputPath,
    required String logOutputPath,
  }) {
    if (!_usesInjectedLibrary && Platform.isAndroid) {
      return _startInIsolate({
        'workingDirectory': workingDirectory,
        'resourceDirectory': resourceDirectory,
        'projectKind': projectKind,
        'mainSourcePath': mainSourcePath,
        'sourcePaths': sourcePaths,
        'compileArguments': compileArguments,
        'linkArguments': linkArguments,
        'hexOutputPath': hexOutputPath,
        'mapOutputPath': mapOutputPath,
        'logOutputPath': logOutputPath,
      });
    }
    return _startDirect(
      workingDirectory: workingDirectory,
      resourceDirectory: resourceDirectory,
      projectKind: projectKind,
      mainSourcePath: mainSourcePath,
      sourcePaths: sourcePaths,
      compileArguments: compileArguments,
      linkArguments: linkArguments,
      hexOutputPath: hexOutputPath,
      mapOutputPath: mapOutputPath,
      logOutputPath: logOutputPath,
    );
  }

  NativeSdccOperation _startDirect({
    required String workingDirectory,
    required String resourceDirectory,
    required String projectKind,
    required String mainSourcePath,
    List<String> sourcePaths = const [],
    List<String> compileArguments = const [],
    List<String> linkArguments = const [],
    required String hexOutputPath,
    required String mapOutputPath,
    required String logOutputPath,
  }) {
    final request = calloc<PbSdccRequest>();
    final operationPointer = calloc<Pointer<Void>>();
    final allocated = <Pointer<Utf8>>[];
    final allocatedArrays = <Pointer<Pointer<Char>>>[];
    Pointer<Char> string(String value) {
      final pointer = value.toNativeUtf8();
      allocated.add(pointer);
      return pointer.cast();
    }

    Pointer<Pointer<Char>> strings(List<String> values) {
      if (values.isEmpty) return Pointer.fromAddress(0);
      final pointers = calloc<Pointer<Char>>(values.length);
      allocatedArrays.add(pointers);
      for (var index = 0; index < values.length; index++) {
        pointers[index] = string(values[index]);
      }
      return pointers;
    }

    try {
      request.ref
        ..workingDirectory = string(workingDirectory)
        ..resourceDirectory = string(resourceDirectory)
        ..projectKind = string(projectKind)
        ..mainSourcePath = string(mainSourcePath)
        ..hexOutputPath = string(hexOutputPath)
        ..mapOutputPath = string(mapOutputPath)
        ..logOutputPath = string(logOutputPath);
      request.ref.sourcePaths
        ..items = strings(sourcePaths)
        ..count = sourcePaths.length;
      request.ref.compileArguments
        ..items = strings(compileArguments)
        ..count = compileArguments.length;
      request.ref.linkArguments
        ..items = strings(linkArguments)
        ..count = linkArguments.length;
      final status = _bindings.start(request, operationPointer);
      if (status != _ok) {
        throw StateError('无法启动 Android SDCC 构建（状态码 $status）');
      }
    } finally {
      for (final pointer in allocated) {
        calloc.free(pointer);
      }
      for (final pointers in allocatedArrays) {
        calloc.free(pointers);
      }
      calloc.free(request);
    }

    final operation = operationPointer.value;
    calloc.free(operationPointer);
    final events = StreamController<NativeSdccEvent>.broadcast();
    final completer = Completer<NativeSdccResult>();
    Timer? timer;
    var destroyed = false;
    var polling = false;

    void destroy() {
      if (destroyed) return;
      destroyed = true;
      _bindings.destroy(operation);
    }

    Future<void> poll() async {
      if (destroyed || polling) return;
      polling = true;
      try {
        final event = calloc<PbSdccEvent>();
        try {
          while (_bindings.poll(operation, event) == _eventAvailable) {
            events.add(
              NativeSdccEvent(
                stage: event.ref.stage,
                level: event.ref.level,
                message: event.ref.message.cast<Utf8>().toDartString(),
                fileName: _optionalNativeString(event.ref.fileName),
                current: event.ref.current <= 0 ? null : event.ref.current,
                total: event.ref.total <= 0 ? null : event.ref.total,
              ),
            );
          }
        } finally {
          calloc.free(event);
        }
        final nativeResult = calloc<PbSdccResult>();
        try {
          final status = _bindings.result(operation, nativeResult);
          if (status == _running) return;
          if (status != _complete) {
            throw StateError('读取 Android SDCC 结果失败（状态码 $status）');
          }
          final value = NativeSdccResult(
            success: nativeResult.ref.status == _ok,
            canceled: nativeResult.ref.status == _canceled,
            exitCode: nativeResult.ref.exitCode,
            errorCount: nativeResult.ref.errorCount,
            warningCount: nativeResult.ref.warningCount,
            message: nativeResult.ref.message.cast<Utf8>().toDartString(),
            hexPath: nativeResult.ref.hexPath.cast<Utf8>().toDartString(),
            mapPath: nativeResult.ref.mapPath.cast<Utf8>().toDartString(),
            logPath: nativeResult.ref.logPath.cast<Utf8>().toDartString(),
            errorCode: nativeResult.ref.errorCode.cast<Utf8>().toDartString(),
          );
          timer?.cancel();
          await events.close();
          destroy();
          if (!completer.isCompleted) completer.complete(value);
        } finally {
          calloc.free(nativeResult);
        }
      } catch (error, stack) {
        timer?.cancel();
        if (!events.isClosed) await events.close();
        destroy();
        if (!completer.isCompleted) completer.completeError(error, stack);
      } finally {
        polling = false;
      }
    }

    timer = Timer.periodic(
      const Duration(milliseconds: 20),
      (_) => unawaited(poll()),
    );
    unawaited(poll());
    return NativeSdccOperation._(events.stream, completer.future, () {
      if (!destroyed) _bindings.cancel(operation);
    });
  }

  NativeSdccOperation _startInIsolate(Map<String, Object> request) {
    final events = StreamController<NativeSdccEvent>.broadcast();
    final completer = Completer<NativeSdccResult>();
    final messages = ReceivePort();
    SendPort? controlPort;
    var cancelRequested = false;
    var closed = false;

    Future<void> close() async {
      if (closed) return;
      closed = true;
      messages.close();
      if (!events.isClosed) await events.close();
    }

    messages.listen((message) {
      if (message is! Map) return;
      switch (message['type']) {
        case 'ready':
          controlPort = message['port'] as SendPort;
          if (cancelRequested) controlPort!.send('cancel');
        case 'event':
          events.add(
            NativeSdccEvent(
              stage: message['stage'] as int,
              level: message['level'] as int,
              message: message['message'] as String,
              fileName: message['fileName'] as String?,
              current: message['current'] as int?,
              total: message['total'] as int?,
            ),
          );
        case 'result':
          final result = NativeSdccResult(
            success: message['success'] as bool,
            canceled: message['canceled'] as bool,
            exitCode: message['exitCode'] as int,
            errorCount: message['errorCount'] as int,
            warningCount: message['warningCount'] as int,
            message: message['message'] as String,
            hexPath: message['hexPath'] as String,
            mapPath: message['mapPath'] as String,
            logPath: message['logPath'] as String,
            errorCode: message['errorCode'] as String,
          );
          if (!completer.isCompleted) completer.complete(result);
          unawaited(close());
        case 'error':
          if (!completer.isCompleted) {
            completer.completeError(StateError(message['message'] as String));
          }
          unawaited(close());
      }
    });
    unawaited(
      Isolate.spawn(_nativeSdccWorker, <Object>[
        messages.sendPort,
        request,
      ], debugName: 'PIE-Block SDCC').then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          if (!completer.isCompleted) completer.completeError(error, stack);
          unawaited(close());
        },
      ),
    );
    return NativeSdccOperation._(events.stream, completer.future, () {
      cancelRequested = true;
      controlPort?.send('cancel');
    });
  }
}

Future<void> _nativeSdccWorker(List<Object> arguments) async {
  final parent = arguments[0] as SendPort;
  final values = (arguments[1] as Map).cast<String, Object>();
  final control = ReceivePort();
  Pointer<Void>? operation;
  var canceled = false;
  try {
    final bindings = PbSdccBindings(
      DynamicLibrary.open('libpieblock_sdcc_native.so'),
    );
    control.listen((message) {
      if (message == 'cancel') {
        canceled = true;
        final current = operation;
        if (current != null) bindings.cancel(current);
      }
    });
    parent.send(<String, Object>{'type': 'ready', 'port': control.sendPort});
    final request = calloc<PbSdccRequest>();
    final operationPointer = calloc<Pointer<Void>>();
    final allocated = <Pointer<Utf8>>[];
    final allocatedArrays = <Pointer<Pointer<Char>>>[];
    Pointer<Char> string(String value) {
      final pointer = value.toNativeUtf8();
      allocated.add(pointer);
      return pointer.cast();
    }

    Pointer<Pointer<Char>> strings(List<String> values) {
      if (values.isEmpty) return Pointer.fromAddress(0);
      final pointers = calloc<Pointer<Char>>(values.length);
      allocatedArrays.add(pointers);
      for (var index = 0; index < values.length; index++) {
        pointers[index] = string(values[index]);
      }
      return pointers;
    }

    try {
      request.ref
        ..workingDirectory = string(values['workingDirectory']! as String)
        ..resourceDirectory = string(values['resourceDirectory']! as String)
        ..projectKind = string(values['projectKind']! as String)
        ..mainSourcePath = string(values['mainSourcePath']! as String)
        ..hexOutputPath = string(values['hexOutputPath']! as String)
        ..mapOutputPath = string(values['mapOutputPath']! as String)
        ..logOutputPath = string(values['logOutputPath']! as String);
      final sourcePaths = (values['sourcePaths']! as List).cast<String>();
      final compileArguments = (values['compileArguments']! as List)
          .cast<String>();
      final linkArguments = (values['linkArguments']! as List).cast<String>();
      request.ref.sourcePaths
        ..items = strings(sourcePaths)
        ..count = sourcePaths.length;
      request.ref.compileArguments
        ..items = strings(compileArguments)
        ..count = compileArguments.length;
      request.ref.linkArguments
        ..items = strings(linkArguments)
        ..count = linkArguments.length;
      final status = bindings.start(request, operationPointer);
      if (status != _ok) {
        throw StateError('无法启动 Android SDCC 构建（状态码 $status）');
      }
      operation = operationPointer.value;
      if (canceled) bindings.cancel(operation);
    } finally {
      for (final pointer in allocated) {
        calloc.free(pointer);
      }
      for (final pointers in allocatedArrays) {
        calloc.free(pointers);
      }
      calloc.free(request);
      calloc.free(operationPointer);
    }

    while (true) {
      final event = calloc<PbSdccEvent>();
      try {
        while (bindings.poll(operation, event) == _eventAvailable) {
          parent.send(<String, Object?>{
            'type': 'event',
            'stage': event.ref.stage,
            'level': event.ref.level,
            'message': event.ref.message.cast<Utf8>().toDartString(),
            'fileName': _optionalNativeString(event.ref.fileName),
            'current': event.ref.current <= 0 ? null : event.ref.current,
            'total': event.ref.total <= 0 ? null : event.ref.total,
          });
        }
      } finally {
        calloc.free(event);
      }
      final result = calloc<PbSdccResult>();
      try {
        final status = bindings.result(operation, result);
        if (status == _complete) {
          parent.send(<String, Object>{
            'type': 'result',
            'success': result.ref.status == _ok,
            'canceled': result.ref.status == _canceled,
            'exitCode': result.ref.exitCode,
            'errorCount': result.ref.errorCount,
            'warningCount': result.ref.warningCount,
            'message': result.ref.message.cast<Utf8>().toDartString(),
            'hexPath': result.ref.hexPath.cast<Utf8>().toDartString(),
            'mapPath': result.ref.mapPath.cast<Utf8>().toDartString(),
            'logPath': result.ref.logPath.cast<Utf8>().toDartString(),
            'errorCode': result.ref.errorCode.cast<Utf8>().toDartString(),
          });
          return;
        }
        if (status != _running) {
          throw StateError('读取 Android SDCC 结果失败（状态码 $status）');
        }
      } finally {
        calloc.free(result);
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  } catch (error) {
    parent.send(<String, Object>{'type': 'error', 'message': '$error'});
  } finally {
    control.close();
    final current = operation;
    if (current != null) {
      final bindings = PbSdccBindings(
        DynamicLibrary.open('libpieblock_sdcc_native.so'),
      );
      bindings.destroy(current);
    }
  }
}
