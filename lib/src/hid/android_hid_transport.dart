import 'package:flutter/services.dart';
import 'package:pieblock_hid/pieblock_hid.dart';

/// Android USB-HID 传输：通过平台通道 [channel] 与 Kotlin `UsbHidBridge`
/// （UsbManager + HidDevice）交互。
///
/// 协议层完全复用 pieblock_hid（帧/块/ACK 与 Windows 一致），本类只承担
/// 传输语义：一次写一个 64 字节报告（含前导 0x00 report-id 原样透传），
/// 读输入报告超时返回空。
class AndroidHidTransport implements HidTransport {
  AndroidHidTransport({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('cn.edu.cnu.pieblock/hid');

  final MethodChannel _channel;

  @override
  Future<int> countDevices() async {
    try {
      final devices = await _channel.invokeListMethod<Object?>('list');
      return devices?.length ?? 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<bool> open() async {
    // 桥接层返回状态：ok / app_mode / no_device / permission_denied /
    // busy / failed。app_mode 表示板子在运行用户程序，需重新上电进 ISP。
    final status = await _channel.invokeMethod<String>('open') ?? 'failed';
    switch (status) {
      case 'ok':
        return true;
      case 'app_mode':
        throw StateError(
          '主控板正在运行用户程序（听到奏乐就是它），未进入 ISP 模式：'
          '请给主控板断电几秒后重新上电，重新插拔 OTG 后立即烧录',
        );
      default:
        return false;
    }
  }

  @override
  Future<bool> write(Uint8List report) async =>
      await _channel.invokeMethod<bool>('write', report) ?? false;

  @override
  Future<Uint8List> read(int timeoutMilliseconds) async {
    final data = await _channel.invokeMethod<Uint8List>(
      'read',
      timeoutMilliseconds,
    );
    return data ?? Uint8List(0);
  }

  @override
  Future<void> cancel() => _channel.invokeMethod<void>('cancel');

  @override
  Future<void> close() => _channel.invokeMethod<void>('close');
}
