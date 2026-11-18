/// Windows 用户环境变量读写（HKCU\Environment）。
///
/// 只做一件小事：读/写当前用户的 `Path`，然后广播 WM_SETTINGCHANGE 让新开的
/// 进程看到变化。写 HKCU 不需要管理员权限；值类型保持调用方给的类型，避免把
/// `%VAR%` 展开写死。
///
/// 非 Windows 平台直接返回空值，调用方不需要再判断平台。
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'user_path_value.dart';

class UserPath {
  const UserPath._();

  static const int _hkcu = 0x80000001;
  static const int _keyRead = 0x20019;
  static const int _keyWrite = 0x20006;
  static const int _regExpandSz = 2;
  static const int _errorFileNotFound = 2;

  static final DynamicLibrary _advapi32 = DynamicLibrary.open('advapi32.dll');
  static final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');

  static final _regOpenKeyExW = _advapi32
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<Utf16>, Uint32, Uint32, Pointer<IntPtr>),
        int Function(int, Pointer<Utf16>, int, int, Pointer<IntPtr>)
      >('RegOpenKeyExW');

  static final _regQueryValueExW = _advapi32
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Utf16>,
          Pointer<Uint32>,
          Pointer<Uint32>,
          Pointer<Uint8>,
          Pointer<Uint32>,
        ),
        int Function(
          int,
          Pointer<Utf16>,
          Pointer<Uint32>,
          Pointer<Uint32>,
          Pointer<Uint8>,
          Pointer<Uint32>,
        )
      >('RegQueryValueExW');

  static final _regSetValueExW = _advapi32
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Utf16>,
          Uint32,
          Uint32,
          Pointer<Uint8>,
          Uint32,
        ),
        int Function(int, Pointer<Utf16>, int, int, Pointer<Uint8>, int)
      >('RegSetValueExW');

  static final _regCloseKey = _advapi32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('RegCloseKey');

  static final _sendMessageTimeoutW = _user32
      .lookupFunction<
        IntPtr Function(
          IntPtr,
          Uint32,
          IntPtr,
          Pointer<Utf16>,
          Uint32,
          Uint32,
          Pointer<IntPtr>,
        ),
        int Function(int, int, int, Pointer<Utf16>, int, int, Pointer<IntPtr>)
      >('SendMessageTimeoutW');

  /// 读取一个字符串值；值不存在时返回空字符串与 REG_EXPAND_SZ。
  ///
  /// 打开键失败（极少见）时返回 null，调用方应放弃本次修改。
  static UserPathValue? read({
    String subKey = 'Environment',
    String valueName = 'Path',
  }) {
    if (!Platform.isWindows) return null;

    final key = calloc<IntPtr>();
    final subKeyPtr = subKey.toNativeUtf16();
    final namePtr = valueName.toNativeUtf16();
    final type = calloc<Uint32>();
    final size = calloc<Uint32>();
    try {
      final opened = _regOpenKeyExW(
        _hkcu,
        subKeyPtr,
        0,
        _keyRead | _keyWrite,
        key,
      );
      if (opened != 0) return null;
      try {
        var status = _regQueryValueExW(
          key.value,
          namePtr,
          nullptr,
          type,
          nullptr,
          size,
        );
        if (status == _errorFileNotFound) {
          return const UserPathValue('', _regExpandSz);
        }
        if (status != 0) return null;

        // 多分配两个字节：即使系统没有写入结尾 NUL，也能安全地读出字符串。
        final data = calloc<Uint8>(size.value + 2);
        try {
          status = _regQueryValueExW(
            key.value,
            namePtr,
            nullptr,
            type,
            data,
            size,
          );
          if (status != 0) return null;
          return UserPathValue(
            data.cast<Utf16>().toDartString(),
            type.value == _regExpandSz ? _regExpandSz : 1,
          );
        } finally {
          calloc.free(data);
        }
      } finally {
        _regCloseKey(key.value);
      }
    } finally {
      calloc.free(key);
      calloc.free(subKeyPtr);
      calloc.free(namePtr);
      calloc.free(type);
      calloc.free(size);
    }
  }

  /// 写回字符串值；成功返回 true。键必须已存在（`Environment` 总是存在）。
  static bool write(
    String value, {
    int type = _regExpandSz,
    String subKey = 'Environment',
    String valueName = 'Path',
  }) {
    if (!Platform.isWindows) return false;

    final key = calloc<IntPtr>();
    final subKeyPtr = subKey.toNativeUtf16();
    final namePtr = valueName.toNativeUtf16();
    final dataPtr = value.toNativeUtf16();
    try {
      final opened = _regOpenKeyExW(
        _hkcu,
        subKeyPtr,
        0,
        _keyRead | _keyWrite,
        key,
      );
      if (opened != 0) return false;
      try {
        return _regSetValueExW(
              key.value,
              namePtr,
              0,
              type,
              dataPtr.cast<Uint8>(),
              (value.length + 1) * 2,
            ) ==
            0;
      } finally {
        _regCloseKey(key.value);
      }
    } finally {
      calloc.free(key);
      calloc.free(subKeyPtr);
      calloc.free(namePtr);
      calloc.free(dataPtr);
    }
  }

  /// 广播 `WM_SETTINGCHANGE`，让新开的进程看到新的 PATH。
  ///
  /// 已经启动的终端不会更新，必须重开；这里忽略返回值，广播失败不影响写入。
  static void notifyEnvironmentChanged() {
    if (!Platform.isWindows) return;

    final parameter = 'Environment'.toNativeUtf16();
    final result = calloc<IntPtr>();
    try {
      // HWND_BROADCAST = 0xFFFF, WM_SETTINGCHANGE = 0x001A,
      // SMTO_ABORTIFHUNG = 0x0002, 超时 2 秒。
      _sendMessageTimeoutW(0xFFFF, 0x001A, 0, parameter, 0x0002, 2000, result);
    } finally {
      calloc.free(parameter);
      calloc.free(result);
    }
  }
}
