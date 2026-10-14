import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';

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
    : _transportFactory = transport ?? NativeHidTransport.new;

  /// 写块无响应时的最大尝试次数。设备在编程 flash 时会丢弃紧跟 ACK 的下一帧
  /// （实测首块 0x0000 正常、第二块 0x0080 完全无响应），按地址原样重发同一块
  /// 是幂等的，能直接救回中断的烧录。
  static const defaultWriteAttempts = 3;

  /// 重发前的退避：给设备留出完成 flash 编程的时间。
  static const defaultRetryBackoff = Duration(milliseconds: 50);

  /// 失败后探活（`info`）的超时。
  static const defaultProbeTimeout = Duration(milliseconds: 800);

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
          message: _errorText(error),
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
      const message = 'HEX 已丢失或内容发生变化，请重新编译';
      emit(FlashStage.preparing, message);
      throw StateError(message);
    }
    final validation = await IntelHexValidator.validateApplication(path);
    if (!validation.ok) {
      emit(FlashStage.preparing, validation.message);
      throw StateError(validation.message);
    }
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

  /// 桌面 isolate 烧录路径使用的传输层：协议层与原生层都是跨平台同一套，
  /// 仅库名/设备枚举由原生实现按平台处理。
  static HidTransport desktopTransport() => NativeHidTransport();

  static void _cancelNative() {
    if (!Platform.isWindows && !Platform.isLinux) return;
    try {
      final transport = desktopTransport();
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
      result = await _runFlash(path, expected, desktopTransport(), event);
    } catch (error) {
      result = FlashResult(
        success: false,
        stage: FlashStage.preparing,
        message: _errorText(error),
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
    void Function(FlashStage, String, {int? current, int? total}) onEvent, {
    Duration? reportGap,
    int writeAttempts = defaultWriteAttempts,
    Duration retryBackoff = defaultRetryBackoff,
    Duration probeTimeout = defaultProbeTimeout,
  }) async {
    // 节奏用参考实现的 1ms（见 protocol.dart 的 hidReportGap）。曾经有过一段
    // 「Linux 放大到 20ms」的保守值，后来定位到真正的坑是 Linux 原生层剥掉了
    // report ID 槽（docs/pitfall/HID烧录写块无响应.md 第五轮）；写法修好后实测
    // 1ms 在同一块板子上写完 414 块只用 5.66 秒，20ms 纯属多余。
    final gap = reportGap ?? hidReportGap;
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
    var blockIndex = -1;
    var blockTotal = 0;
    try {
      onEvent(FlashStage.connecting, '正在连接主控板引导程序…');
      // 把生效的节奏写进日志：排查时一眼就能看出跑的是不是带节流修复的构建。
      onEvent(FlashStage.connecting, '帧内报告间隔 ${gap.inMilliseconds}ms');
      await HidProtocol.expectAck(
        transport,
        const [0x01, 0, 0, 0, 0, 0, 0, 0x80, 0],
        'info',
        command: 0x01,
        reportGap: gap,
      );
      await HidProtocol.expectAck(
        transport,
        const [0x05, 0, 0, 0x5a, 0xa5],
        'unlock',
        command: 0x05,
        reportGap: gap,
      );
      activeStage = FlashStage.erasing;
      onEvent(activeStage, '正在擦除主控板程序区…');
      await HidProtocol.expectAck(
        transport,
        const [0x03, 0, 0, 0x5a, 0xa5],
        'erase',
        command: 0x03,
        reportGap: gap,
      );
      final blocks = HidProtocol.buildWriteBlocks(image);
      blockTotal = blocks.length;
      activeStage = FlashStage.programming;
      for (var index = 0; index < blocks.length; index++) {
        blockIndex = index;
        final block = blocks[index];
        final label =
            '写入 0x${block.address.toRadixString(16).padLeft(4, '0')}';
        final payload = <int>[
          block.command,
          (block.address >> 8) & 0xff,
          block.address & 0xff,
          0x5a,
          0xa5,
          ...block.data,
        ];
        Uint8List? response;
        for (var attempt = 1; ; attempt++) {
          try {
            response = await HidProtocol.expectAck(
              transport,
              payload,
              label,
              command: 0x02,
              reportGap: gap,
            );
            break;
          } on HidNoResponseException {
            if (attempt >= writeAttempts) rethrow;
            onEvent(
              activeStage,
              '$label 无响应，正在重发（第 ${attempt + 1}/$writeAttempts 次）',
            );
            await Future<void>.delayed(retryBackoff);
          }
        }
        if (response.length < 7 || response[6] != 0x54) {
          throw StateError('$label 未确认成功');
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
      // 写块阶段（以及连接/擦除阶段的设备静默）统一走探活 + 操作指引：
      // 在 Linux 上写报告本身也可能失败（hidraw 的 OUT URB 忙），只报
      // 「写入报告失败」用户看不懂下一步该做什么。
      if (error is HidNoResponseException || blockIndex >= 0) {
        return _reportInterruption(
          error,
          transport,
          activeStage,
          blockIndex: blockIndex,
          blockTotal: blockTotal,
          writeAttempts: writeAttempts,
          probeTimeout: probeTimeout,
          onEvent: onEvent,
        );
      }
      final message = _errorText(error);
      onEvent(activeStage, message);
      return FlashResult(success: false, stage: activeStage, message: message);
    } finally {
      await transport.close();
    }
  }

  /// 烧录中断的收尾：先用只读的 `info` 探活，再按「仍在 ISP 模式」与
  /// 「已退出/掉线」两种情况给出不同的操作指引。状态栏只有一行，完整指引写进
  /// 日志区。
  static Future<FlashResult> _reportInterruption(
    Object error,
    HidTransport transport,
    FlashStage stage, {
    required int blockIndex,
    required int blockTotal,
    required int writeAttempts,
    required Duration probeTimeout,
    required void Function(FlashStage, String, {int? current, int? total})
    onEvent,
  }) async {
    final noResponse = error is HidNoResponseException;
    final label = error is HidNoResponseException
        ? error.label
        : _errorText(error);
    final where = blockIndex < 0
        ? '${_stageText(stage)}（$label）'
        : '第 ${blockIndex + 1}/$blockTotal 块（$label）';
    onEvent(
      stage,
      '$where：${noResponse ? '连续 $writeAttempts 次无响应' : '写入中断'}，烧录中断',
    );
    final alive = await _probeAlive(transport, probeTimeout);
    final reason = noResponse ? '无响应' : '';
    if (alive) {
      onEvent(
        stage,
        '主控板仍在 ISP 模式：直接点「烧录当前固件」重试即可，无需重新编译。',
      );
      return FlashResult(
        success: false,
        stage: stage,
        message: '烧录中断：$where$reason，设备仍在 ISP 模式，可直接重试',
      );
    }
    onEvent(
      stage,
      '主控板已无响应：请关闭四个开关，给主控板断电几秒后重新上电，'
      '再点「烧录当前固件」用同一份固件重试，无需重新编译。',
    );
    return FlashResult(
      success: false,
      stage: stage,
      message: '烧录中断：$where$reason，请断电重新上电后重试',
    );
  }

  /// 写块失败后的探活：`info` 是只读命令，能在不改变设备状态的前提下判断
  /// 主控板是否还停在 ISP 模式。
  static Future<bool> _probeAlive(
    HidTransport transport,
    Duration timeout,
  ) async {
    try {
      await HidProtocol.expectAck(
        transport,
        const [0x01, 0, 0, 0, 0, 0, 0, 0x80, 0],
        'info',
        command: 0x01,
        timeoutMilliseconds: timeout.inMilliseconds,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 界面可见的失败文案：StateError 只取 message，避免状态栏出现
  /// `Bad state: ` 这类 Dart 运行时前缀。
  static String _errorText(Object error) =>
      error is StateError ? error.message.toString() : error.toString();

  static String _stageText(FlashStage stage) => switch (stage) {
    FlashStage.connecting => '连接引导程序',
    FlashStage.erasing => '擦除程序区',
    FlashStage.programming => '写入固件',
    FlashStage.resetting => '复位主控板',
    FlashStage.preparing => '校验固件',
    FlashStage.done => '烧录',
    FlashStage.canceled => '烧录',
  };
}
