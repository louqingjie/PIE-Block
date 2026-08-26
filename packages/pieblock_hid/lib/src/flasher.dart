import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:pieblock_toolchain/pieblock_toolchain.dart';

import 'protocol.dart';
import 'transport.dart';

enum FlashStage {
  preparing,
  connecting,
  erasing,
  programming,
  resetting,
  done,
  canceled,
}

class FlashEvent {
  const FlashEvent(this.stage, this.message, {this.current, this.total});
  final FlashStage stage;
  final String message;
  final int? current;
  final int? total;
}

class FlashResult {
  const FlashResult({
    required this.success,
    required this.stage,
    required this.message,
    this.canceled = false,
  });
  final bool success;
  final FlashStage stage;
  final String message;
  final bool canceled;
}

class FlashOperation {
  FlashOperation(this.events, this.result, this._cancel);
  final Stream<FlashEvent> events;
  final Future<FlashResult> result;
  final void Function() _cancel;
  void cancel() => _cancel();
}

class HidFlasher {
  HidFlasher({HidTransport Function()? transport, this.useIsolate = true})
    : _transportFactory = transport ?? WindowsHidTransport.new;

  final HidTransport Function() _transportFactory;
  final bool useIsolate;
  HidTransport? _activeTransport;

  Future<int> detectDeviceCount() async {
    try {
      return await _transportFactory().countDevices();
    } catch (_) {
      return 0;
    }
  }

  FlashOperation start({
    required String hexPath,
    required String expectedSha256,
  }) {
    if (useIsolate) return _startInIsolate(hexPath, expectedSha256);
    return _startInMainIsolate(hexPath, expectedSha256);
  }

  FlashOperation _startInIsolate(String hexPath, String expectedSha256) {
    final events = StreamController<FlashEvent>.broadcast();
    final result = Completer<FlashResult>();
    Isolate? worker;
    var completed = false;
    final receive = ReceivePort();
    receive.listen((message) {
      if (message is Map && message['type'] == 'event') {
        events.add(
          FlashEvent(
            FlashStage.values.byName(message['stage'] as String),
            message['message'] as String,
            current: message['current'] as int?,
            total: message['total'] as int?,
          ),
        );
      } else if (message is Map && message['type'] == 'result' && !completed) {
        completed = true;
        final value = FlashResult(
          success: message['success'] as bool,
          stage: FlashStage.values.byName(message['stage'] as String),
          message: message['message'] as String,
          canceled: message['canceled'] as bool? ?? false,
        );
        result.complete(value);
        unawaited(events.close());
        receive.close();
      }
    });
    unawaited(
      Isolate.spawn(_worker, {
        'send': receive.sendPort,
        'hex': hexPath,
        'sha': expectedSha256,
      }).then<void>((value) => worker = value).catchError((Object error) {
        if (!completed) {
          completed = true;
          result.complete(
            FlashResult(
              success: false,
              stage: FlashStage.preparing,
              message: '无法启动烧录任务：$error',
            ),
          );
          unawaited(events.close());
          receive.close();
        }
      }),
    );
    final timeout = Timer(const Duration(seconds: 90), () {
      if (!completed) {
        _cancelNative();
        worker?.kill(priority: Isolate.immediate);
        completed = true;
        result.complete(
          const FlashResult(
            success: false,
            stage: FlashStage.canceled,
            message: '烧录超过 90 秒，已自动取消',
            canceled: true,
          ),
        );
        unawaited(events.close());
        receive.close();
      }
    });
    result.future.whenComplete(timeout.cancel);
    return FlashOperation(events.stream, result.future, () {
      if (completed) return;
      _cancelNative();
      worker?.kill(priority: Isolate.immediate);
      completed = true;
      result.complete(
        const FlashResult(
          success: false,
          stage: FlashStage.canceled,
          message: '已取消烧录',
          canceled: true,
        ),
      );
      unawaited(events.close());
      receive.close();
    });
  }

  FlashOperation _startInMainIsolate(String hexPath, String expectedSha256) {
    final events = StreamController<FlashEvent>.broadcast();
    final result = Completer<FlashResult>();
    var completed = false;
    final transport = _transportFactory();
    _activeTransport = transport;
    void emit(FlashStage stage, String message, {int? current, int? total}) {
      if (completed) return;
      events.add(FlashEvent(stage, message, current: current, total: total));
    }

    unawaited(() async {
      FlashResult value;
      try {
        value = await _runFlash(hexPath, expectedSha256, transport, emit);
      } catch (error) {
        value = FlashResult(
          success: false,
          stage: FlashStage.preparing,
          message: '$error',
        );
      } finally {
        await transport.close();
      }
      if (!completed) {
        completed = true;
        result.complete(value);
        unawaited(events.close());
      }
    }());

    void finishCanceled(String message) {
      if (completed) return;
      completed = true;
      _cancelActive();
      result.complete(
        FlashResult(
          success: false,
          stage: FlashStage.canceled,
          message: message,
          canceled: true,
        ),
      );
      unawaited(events.close());
    }

    final timeout = Timer(const Duration(seconds: 90), () {
      finishCanceled('烧录超过 90 秒，已自动取消');
    });
    result.future.whenComplete(timeout.cancel);
    return FlashOperation(events.stream, result.future, () {
      finishCanceled('已取消烧录');
    });
  }

  void _cancelActive() {
    final transport = _activeTransport;
    if (transport != null) {
      unawaited(
        transport.cancel().then<void>((_) => transport.close()).catchError((
          Object _,
        ) {
          try {
            transport.close();
          } catch (_) {}
        }),
      );
      return;
    }
    _cancelNative();
  }

  static Future<FlashResult> _runFlash(
    String path,
    String expected,
    HidTransport transport,
    void Function(FlashStage, String, {int? current, int? total}) emit,
  ) async {
    final file = File(path);
    emit(FlashStage.preparing, '正在校验待烧录固件…');
    if (!await file.exists() || await _normalizedHexSha(file) != expected) {
      throw StateError('HEX 已丢失或内容发生变化，请重新编译');
    }
    final validation = await IntelHexValidator.validateApplication(path);
    if (!validation.ok) throw StateError(validation.message);
    return flashWithTransport(validation.image!, transport, emit);
  }

  /// 黄金哈希采用 LF 规范化内容（与 pieblock_toolchain 的 BuildArtifact
  /// 定义一致）：Intel HEX 为纯文本，Windows 以 CRLF 写出、Android 以 LF
  /// 写出，统一去除 CRLF 后计算 SHA-256。
  static Future<String> _normalizedHexSha(File file) async {
    final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
    return sha256
        .convert(utf8.encode(text.replaceAll('\r\n', '\n')))
        .toString();
  }

  static void _cancelNative() {
    if (!Platform.isWindows) return;
    try {
      final transport = WindowsHidTransport();
      transport.cancel();
      transport.close();
    } catch (_) {}
  }

  static Future<void> _worker(Map<Object?, Object?> args) async {
    final send = args['send']! as SendPort;
    final path = args['hex']! as String;
    final expected = args['sha']! as String;
    void event(FlashStage stage, String message, {int? current, int? total}) =>
        send.send({
          'type': 'event',
          'stage': stage.name,
          'message': message,
          'current': current,
          'total': total,
        });
    FlashResult result;
    try {
      result = await _runFlash(path, expected, WindowsHidTransport(), event);
    } catch (error) {
      result = FlashResult(
        success: false,
        stage: FlashStage.preparing,
        message: '$error',
      );
    }
    send.send({
      'type': 'result',
      'success': result.success,
      'stage': result.stage.name,
      'message': result.message,
      'canceled': result.canceled,
    });
  }

  static Future<FlashResult> flashWithTransport(
    HexImage image,
    HidTransport transport,
    void Function(FlashStage, String, {int? current, int? total}) onEvent,
  ) async {
    final deviceCount = await transport.countDevices();
    if (deviceCount != 1) {
      return FlashResult(
        success: false,
        stage: FlashStage.connecting,
        message: deviceCount == 0 ? '未找到处于 ISP 模式的主控板' : '检测到多块主控板，请只连接一块',
      );
    }
    if (!await transport.open()) {
      return const FlashResult(
        success: false,
        stage: FlashStage.connecting,
        message: '无法打开 USB-HID 设备',
      );
    }
    var activeStage = FlashStage.connecting;
    try {
      onEvent(FlashStage.connecting, '正在连接主控板引导程序…');
      await HidProtocol.expectAck(
        transport,
        const [0x01, 0, 0, 0, 0, 0, 0, 0x80, 0],
        'info',
        command: 0x01,
      );
      await HidProtocol.expectAck(
        transport,
        const [0x05, 0, 0, 0x5a, 0xa5],
        'unlock',
        command: 0x05,
      );
      activeStage = FlashStage.erasing;
      onEvent(activeStage, '正在擦除主控板程序区…');
      await HidProtocol.expectAck(
        transport,
        const [0x03, 0, 0, 0x5a, 0xa5],
        'erase',
        command: 0x03,
      );
      final blocks = HidProtocol.buildWriteBlocks(image);
      activeStage = FlashStage.programming;
      for (var index = 0; index < blocks.length; index++) {
        final block = blocks[index];
        final response = await HidProtocol.expectAck(
          transport,
          [
            block.command,
            (block.address >> 8) & 0xff,
            block.address & 0xff,
            0x5a,
            0xa5,
            ...block.data,
          ],
          '写入 0x${block.address.toRadixString(16).padLeft(4, '0')}',
          command: 0x02,
        );
        if (response.length < 7 || response[6] != 0x54) {
          throw StateError('写入 0x${block.address.toRadixString(16)} 未确认成功');
        }
        onEvent(
          activeStage,
          '正在写入固件 ${index + 1}/${blocks.length}',
          current: index + 1,
          total: blocks.length,
        );
      }
      activeStage = FlashStage.resetting;
      onEvent(activeStage, '写入完成，正在复位主控板…');
      for (final report in HidProtocol.splitReports(
        HidProtocol.buildPacket(const [0xff]),
      )) {
        await transport.write(report);
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      onEvent(FlashStage.done, '烧录完成，主控板已运行新程序');
      return const FlashResult(
        success: true,
        stage: FlashStage.done,
        message: '烧录完成',
      );
    } catch (error) {
      return FlashResult(success: false, stage: activeStage, message: '$error');
    } finally {
      await transport.close();
    }
  }
}
