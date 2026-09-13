import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

abstract interface class HidTransport {
  Future<int> countDevices();
  Future<bool> open();
  Future<bool> write(Uint8List report);
  Future<Uint8List> read(int timeoutMilliseconds);
  Future<void> cancel();
  Future<void> close();
}

// 桌面端（Windows/Linux）的 FFI 传输层：库名按平台解析，
// 指向各自的原生实现（同一 C ABI，见 packages/pieblock_hid/src/pieblock_hid.h）。
class NativeHidTransport implements HidTransport {
  NativeHidTransport() : _bindings = _HidBindings.load();

  final _HidBindings _bindings;

  @override
  Future<int> countDevices() async => _bindings.count();

  @override
  Future<bool> open() async => _bindings.open() == 1;

  @override
  Future<bool> write(Uint8List report) async {
    final buffer = calloc<Uint8>(report.length);
    try {
      buffer.asTypedList(report.length).setAll(0, report);
      return _bindings.write(buffer, report.length) == 1;
    } finally {
      calloc.free(buffer);
    }
  }

  @override
  Future<Uint8List> read(int timeoutMilliseconds) async {
    final buffer = calloc<Uint8>(256);
    try {
      final length = _bindings.read(buffer, 256, timeoutMilliseconds);
      return length <= 0
          ? Uint8List(0)
          : Uint8List.fromList(buffer.asTypedList(length));
    } finally {
      calloc.free(buffer);
    }
  }

  @override
  Future<void> cancel() async => _bindings.cancel();

  @override
  Future<void> close() async => _bindings.close();
}

typedef _CountNative = Int32 Function();
typedef _CountDart = int Function();
typedef _OpenNative = Int32 Function();
typedef _OpenDart = int Function();
typedef _WriteNative = Int32 Function(Pointer<Uint8>, Int32);
typedef _WriteDart = int Function(Pointer<Uint8>, int);
typedef _ReadNative = Int32 Function(Pointer<Uint8>, Int32, Int32);
typedef _ReadDart = int Function(Pointer<Uint8>, int, int);
typedef _VoidNative = Void Function();
typedef _VoidDart = void Function();

class _HidBindings {
  _HidBindings(
    this.count,
    this.open,
    this.write,
    this.read,
    this.cancel,
    this.close,
  );

  final _CountDart count;
  final _OpenDart open;
  final _WriteDart write;
  final _ReadDart read;
  final _VoidDart cancel;
  final _VoidDart close;

  factory _HidBindings.load() {
    final String defaultName;
    if (Platform.isWindows) {
      defaultName = 'pieblock_hid.dll';
    } else if (Platform.isLinux) {
      defaultName = 'libpieblock_hid.so';
    } else {
      throw UnsupportedError(
        'USB-HID 烧录不支持当前平台（${Platform.operatingSystem}）',
      );
    }
    final override = Platform.environment['PIEBLOCK_HID_DLL'];
    final library = DynamicLibrary.open(
      override == null || override.isEmpty ? defaultName : override,
    );
    return _HidBindings(
      library.lookupFunction<_CountNative, _CountDart>('pb_hid_count'),
      library.lookupFunction<_OpenNative, _OpenDart>('pb_hid_open'),
      library.lookupFunction<_WriteNative, _WriteDart>('pb_hid_write'),
      library.lookupFunction<_ReadNative, _ReadDart>('pb_hid_read'),
      library.lookupFunction<_VoidNative, _VoidDart>('pb_hid_cancel'),
      library.lookupFunction<_VoidNative, _VoidDart>('pb_hid_close'),
    );
  }
}
