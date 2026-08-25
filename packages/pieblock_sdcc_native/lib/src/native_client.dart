import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'bindings.dart';

const _ok = 0;
const _canceled = 5;
const _running = 6;
const _complete = 7;
const _eventAvailable = 8;

String? _nativeString(Pointer<Char> pointer) {
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
    required this.logPath,
    required this.errorCode,
    this.hexPath,
    this.mapPath,
  });
  final bool success;
  final bool canceled;
  final int exitCode;
  final int errorCount;
  final int warningCount;
  final String message;
  final String? hexPath;
  final String? mapPath;
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
    : _bindings = PbSdccBindings(
        library ??
            (Platform.isAndroid
                ? DynamicLibrary.open('libpieblock_sdcc_native.so')
                : throw UnsupportedError('原生 SDCC 仅支持 Android')),
      ) {
    final actual = _bindings.apiVersion();
    if (actual != 5) {
      throw StateError('不兼容的 SDCC FFI ABI：$actual（需要 5）');
    }
  }

  final PbSdccBindings _bindings;
  String get fingerprint => _bindings.fingerprint().cast<Utf8>().toDartString();
  bool get isAvailable => _bindings.isAvailable() != 0;

  NativeSdccOperation start({
    required int operationKind,
    required String workingDirectory,
    required String resourceDirectory,
    required String projectKind,
    String? sourcePath,
    String? objectOutputPath,
    List<String> objectPaths = const [],
    List<String> libraryObjectPaths = const [],
    List<String> arguments = const [],
    String? hexOutputPath,
    String? mapOutputPath,
    required String logOutputPath,
  }) {
    final request = calloc<PbSdccRequest>();
    final operationPointer = calloc<Pointer<Void>>();
    final allocated = <Pointer<Utf8>>[];
    final allocatedArrays = <Pointer<Pointer<Char>>>[];
    Pointer<Char> string(String? value) {
      if (value == null) return Pointer.fromAddress(0);
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
        ..operationKind = operationKind
        ..workingDirectory = string(workingDirectory)
        ..resourceDirectory = string(resourceDirectory)
        ..projectKind = string(projectKind)
        ..sourcePath = string(sourcePath)
        ..objectOutputPath = string(objectOutputPath)
        ..hexOutputPath = string(hexOutputPath)
        ..mapOutputPath = string(mapOutputPath)
        ..logOutputPath = string(logOutputPath);
      request.ref.objectPaths
        ..items = strings(objectPaths)
        ..count = objectPaths.length;
      request.ref.libraryObjectPaths
        ..items = strings(libraryObjectPaths)
        ..count = libraryObjectPaths.length;
      request.ref.arguments
        ..items = strings(arguments)
        ..count = arguments.length;
      final status = _bindings.start(request, operationPointer);
      if (status != _ok) throw StateError('无法启动 Android SDCC 阶段（状态码 $status）');
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
    return _pollOperation(operation);
  }

  NativeSdccOperation _pollOperation(Pointer<Void> operation) {
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
                message: _nativeString(event.ref.message) ?? '',
                fileName: _nativeString(event.ref.fileName),
                current: event.ref.current <= 0 ? null : event.ref.current,
                total: event.ref.total <= 0 ? null : event.ref.total,
              ),
            );
          }
        } finally {
          calloc.free(event);
        }
        final result = calloc<PbSdccResult>();
        try {
          final status = _bindings.result(operation, result);
          if (status == _running) return;
          if (status != _complete) throw StateError('读取 SDCC 阶段结果失败：$status');
          final value = NativeSdccResult(
            success: result.ref.status == _ok,
            canceled: result.ref.status == _canceled,
            exitCode: result.ref.exitCode,
            errorCount: result.ref.errorCount,
            warningCount: result.ref.warningCount,
            message: _nativeString(result.ref.message) ?? '',
            hexPath: _nativeString(result.ref.hexPath),
            mapPath: _nativeString(result.ref.mapPath),
            logPath: _nativeString(result.ref.logPath) ?? '',
            errorCode: _nativeString(result.ref.errorCode) ?? '',
          );
          timer?.cancel();
          await events.close();
          destroy();
          completer.complete(value);
        } finally {
          calloc.free(result);
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
}
