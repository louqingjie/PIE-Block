import 'dart:typed_data';

import 'package:pieblock_hid/pieblock_hid.dart';
import 'package:pieblock_toolchain/pieblock_toolchain.dart';
import 'package:test/test.dart';

class _FakeTransport implements HidTransport {
  int devices = 1;
  bool opened = false;
  bool closed = false;
  final writes = <Uint8List>[];
  final responses = <Uint8List?>[];

  /// 从第 N 份报告起让 write 返回失败（模拟 Linux hidraw 的 OUT URB 忙）。
  int? failWriteFrom;

  /// 每次 write 相对构造时刻的耗时，用于断言帧内报告间隔。
  final Stopwatch clock = Stopwatch()..start();
  final writeTimes = <Duration>[];

  /// 已发出的帧数：每帧首个报告以 `46 B9 6A` 开头（wire[0] 是 report ID）。
  int get frames => writes
      .where(
        (report) =>
            report.length > 3 &&
            report[1] == 0x46 &&
            report[2] == 0xb9 &&
            report[3] == 0x6a,
      )
      .length;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> close() async => closed = true;

  @override
  Future<int> countDevices() async => devices;

  @override
  Future<bool> open() async => opened = true;

  /// 队列里的 `null` 表示设备这次没有回包；队列耗尽同样返回空。
  @override
  Future<Uint8List> read(int timeoutMilliseconds) async =>
      responses.isEmpty ? Uint8List(0) : responses.removeAt(0) ?? Uint8List(0);

  @override
  Future<bool> write(Uint8List report) async {
    writes.add(report);
    writeTimes.add(clock.elapsed);
    final limit = failWriteFrom;
    if (limit != null && writes.length > limit) return false;
    return true;
  }
}

Uint8List _ack(int command, [List<int> rest = const []]) => Uint8List.fromList([
  0x46,
  0xb9,
  0x68,
  0,
  rest.length + 3,
  command,
  ...rest,
  0,
  0,
]);

void main() {
  test('协议帧与冻结的 Godot/Python 向量一致', () {
    expect(
      HidProtocol.buildPacket(const [0x01, 0, 0, 0, 0, 0, 0, 0x80, 0]),
      equals([
        0x46,
        0xb9,
        0x6a,
        0,
        0x0f,
        0x01,
        0,
        0,
        0,
        0,
        0,
        0,
        0x80,
        0,
        0,
        0xfa,
        0x16,
      ]),
    );
    expect(
      HidProtocol.buildPacket(const [0xff]),
      equals([0x46, 0xb9, 0x6a, 0, 7, 0xff, 1, 0x70, 0x16]),
    );
  });

  test('141 字节写帧拆为 65/65/64 字节报告', () {
    final payload = [
      0x32,
      0,
      0,
      0x5a,
      0xa5,
      ...List.generate(128, (index) => index),
    ];
    final reports = HidProtocol.splitReports(HidProtocol.buildPacket(payload));
    expect(reports.map((report) => report.length), [65, 65, 64]);
    expect(reports.first.take(10), [
      0,
      0x46,
      0xb9,
      0x6a,
      0,
      0x8b,
      0x32,
      0,
      0,
      0x5a,
    ]);
  });

  test('FE/FF 地址生成正确命令且同块空白补零', () {
    final blocks = HidProtocol.buildWriteBlocks(
      HexImage({0xfe0000: 1, 0xfe0200: 2, 0xff0000: 3}),
    );
    expect(blocks.map((block) => block.command), [0x32, 0x12, 0x02]);
    expect(blocks.map((block) => block.address), [0, 0x200, 0]);
    expect(blocks.first.data.take(3), [1, 0, 0]);
  });

  test('Fake HID 完成连接、擦除、写入和复位', () async {
    final transport = _FakeTransport();
    transport.responses.addAll([
      _ack(0x01),
      _ack(0x05),
      _ack(0x03),
      _ack(0x02, [0x54]),
      _ack(0x02, [0x54]),
    ]);
    final events = <FlashStage>[];
    final result = await HidFlasher.flashWithTransport(
      HexImage({0xfe0000: 1, 0xff0000: 2}),
      transport,
      (stage, message, {current, total}) => events.add(stage),
    );
    expect(result.success, isTrue);
    expect(
      events,
      containsAllInOrder([
        FlashStage.connecting,
        FlashStage.erasing,
        FlashStage.programming,
        FlashStage.resetting,
        FlashStage.done,
      ]),
    );
    expect(transport.closed, isTrue);
    expect(transport.writes.last.sublist(1, 10), [
      0x46,
      0xb9,
      0x6a,
      0,
      7,
      0xff,
      1,
      0x70,
      0x16,
    ]);
  });

  test('零设备和多设备均拒绝烧录', () async {
    for (final count in [0, 2]) {
      final transport = _FakeTransport()..devices = count;
      final result = await HidFlasher.flashWithTransport(
        HexImage({0xfe0000: 1, 0xff0000: 2}),
        transport,
        (stage, message, {current, total}) {},
      );
      expect(result.success, isFalse);
      expect(transport.writes, isEmpty);
    }
  });

  test('帧内相邻报告按 hidReportGap 留出间隔', () async {
    // 参考实现 pie_block_hid.py 在报告之间保留 1ms，Dart 移植曾丢掉这个间隔。
    expect(hidReportGap, const Duration(milliseconds: 1));
    final transport = _FakeTransport()..responses.add(_ack(0x02, [0x54]));
    const gap = Duration(milliseconds: 25);
    await HidProtocol.expectAck(
      transport,
      [
        0x32,
        0,
        0,
        0x5a,
        0xa5,
        ...List.generate(128, (index) => index),
      ],
      '写入 0x0000',
      command: 0x02,
      reportGap: gap,
    );
    expect(transport.writeTimes, hasLength(3));
    expect(
      transport.writeTimes[1] - transport.writeTimes[0],
      greaterThanOrEqualTo(gap),
    );
    expect(
      transport.writeTimes[2] - transport.writeTimes[1],
      greaterThanOrEqualTo(gap),
    );
  });

  test('写块无响应时自动重发同一块并继续烧录', () async {
    final transport = _FakeTransport();
    transport.responses.addAll([
      _ack(0x01),
      _ack(0x05),
      _ack(0x03),
      _ack(0x02, [0x54]),
      null, // 第一块 0x0080：设备编程 flash 时丢掉了这一帧
      _ack(0x02, [0x54]),
    ]);
    final events = <String>[];
    final result = await HidFlasher.flashWithTransport(
      HexImage({0xfe0000: 1, 0xfe0080: 2}),
      transport,
      (stage, message, {current, total}) => events.add(message),
      reportGap: Duration.zero,
      retryBackoff: Duration.zero,
    );
    expect(result.success, isTrue);
    expect(
      events,
      contains('写入 0x0080 无响应，正在重发（第 2/3 次）'),
    );
    // info + unlock + erase + 块0 + 块1 两次 + 复位 = 7 帧
    expect(transport.frames, 7);
    expect(transport.closed, isTrue);
  });

  test('连续无响应时给出可操作的失败信息且无 Bad state 前缀', () async {
    final transport = _FakeTransport();
    transport.responses.addAll([
      _ack(0x01),
      _ack(0x05),
      _ack(0x03),
      _ack(0x02, [0x54]),
      // 第二块起设备彻底沉默（探活 info 也不会回）
    ]);
    final events = <String>[];
    final result = await HidFlasher.flashWithTransport(
      HexImage({0xfe0000: 1, 0xfe0080: 2}),
      transport,
      (stage, message, {current, total}) => events.add(message),
      reportGap: Duration.zero,
      retryBackoff: Duration.zero,
      probeTimeout: Duration.zero,
    );
    expect(result.success, isFalse);
    expect(result.stage, FlashStage.programming);
    expect(result.message, isNot(contains('Bad state')));
    expect(result.message, contains('第 2/2 块'));
    expect(result.message, contains('0x0080'));
    expect(result.message, contains('断电重新上电'));
    expect(events, contains('第 2/2 块（写入 0x0080）：连续 3 次无响应，烧录中断'));
    expect(events.join('\n'), contains('断电几秒后重新上电'));
    // info + unlock + erase + 块0 + 块1 三次重发 + 探活 info = 8 帧
    expect(transport.frames, 8);
  });

  test('设备仍在 ISP 模式时提示直接重试', () async {
    final transport = _FakeTransport();
    transport.responses.addAll([
      _ack(0x01),
      _ack(0x05),
      _ack(0x03),
      _ack(0x02, [0x54]),
      null,
      null,
      null,
      _ack(0x01), // 探活成功：设备还在 ISP
    ]);
    final events = <String>[];
    final result = await HidFlasher.flashWithTransport(
      HexImage({0xfe0000: 1, 0xfe0080: 2}),
      transport,
      (stage, message, {current, total}) => events.add(message),
      reportGap: Duration.zero,
      retryBackoff: Duration.zero,
      probeTimeout: Duration.zero,
    );
    expect(result.success, isFalse);
    expect(result.message, contains('仍在 ISP 模式'));
    expect(events.join('\n'), contains('直接点「烧录当前固件」重试即可'));
  });

  test('连接/擦除阶段无响应时给出阶段名而非 Bad state', () async {
    final transport = _FakeTransport();
    transport.responses.addAll([_ack(0x01), _ack(0x05)]); // erase 起设备沉默
    final result = await HidFlasher.flashWithTransport(
      HexImage({0xfe0000: 1}),
      transport,
      (stage, message, {current, total}) {},
      reportGap: Duration.zero,
      retryBackoff: Duration.zero,
      probeTimeout: Duration.zero,
    );
    expect(result.success, isFalse);
    expect(result.stage, FlashStage.erasing);
    expect(
      result.message,
      '烧录中断：擦除程序区（erase）无响应，请断电重新上电后重试',
    );
  });

  test('写报告失败时给出块号与断电提示而非裸错误', () async {
    final transport = _FakeTransport();
    transport.responses.addAll([
      _ack(0x01),
      _ack(0x05),
      _ack(0x03),
      _ack(0x02, [0x54]),
    ]);
    // info(1)+unlock(1)+erase(1)+块0(3)=6 份报告成功后，第二块的报告写不进去
    // （等价 Linux hidraw 设备忙时 ::write 返回 -EBUSY）。
    transport.failWriteFrom = 6;
    final events = <String>[];
    final result = await HidFlasher.flashWithTransport(
      HexImage({0xfe0000: 1, 0xfe0080: 2}),
      transport,
      (stage, message, {current, total}) => events.add(message),
      reportGap: Duration.zero,
      retryBackoff: Duration.zero,
      probeTimeout: Duration.zero,
    );
    expect(result.success, isFalse);
    expect(result.stage, FlashStage.programming);
    expect(result.message, contains('第 2/2 块'));
    expect(result.message, contains('写入 0x0080：写入报告失败'));
    expect(result.message, contains('断电重新上电'));
    expect(events.join('\n'), contains('写入中断，烧录中断'));
  });

  test('烧录日志标明生效的帧内报告间隔（便于识别旧构建）', () async {
    final transport = _FakeTransport();
    transport.responses.addAll([
      _ack(0x01),
      _ack(0x05),
      _ack(0x03),
      _ack(0x02, [0x54]),
      _ack(0x02, [0x54]),
    ]);
    final events = <String>[];
    await HidFlasher.flashWithTransport(
      HexImage({0xfe0000: 1, 0xff0000: 2}),
      transport,
      (stage, message, {current, total}) => events.add(message),
    );
    expect(
      events,
      contains('帧内报告间隔 ${hidReportGap.inMilliseconds}ms'),
    );
  });

  test('整条烧录的帧序列（命令 + 地址 + 报告尺寸）与改造前一致', () async {
    // 这条用例锁住跨平台共享的那份字节流：Windows 的 pieblock_hid.dll 与
    // Linux 的 libpieblock_hid.so 收到的报告序列必须完全相同。
    final transport = _FakeTransport();
    transport.responses.addAll([
      _ack(0x01),
      _ack(0x05),
      _ack(0x03),
      _ack(0x02, [0x54]),
      _ack(0x02, [0x54]),
      _ack(0x02, [0x54]),
      _ack(0x02, [0x54]),
    ]);
    final result = await HidFlasher.flashWithTransport(
      HexImage({0xfe0000: 1, 0xfe0080: 2, 0xff0000: 3, 0xff0100: 4}),
      transport,
      (stage, message, {current, total}) {},
      reportGap: Duration.zero,
    );
    expect(result.success, isTrue);
    // 每帧的首个报告：[reportID, 46, b9, 6a, len_hi, len_lo, payload0, ...]，
    // 因此命令在 report[6]，两字节地址在 report[7..8]。
    final heads = transport.writes
        .where(
          (report) =>
              report.length > 9 &&
              report[1] == 0x46 &&
              report[2] == 0xb9 &&
              report[3] == 0x6a,
        )
        .map((report) => (report[6], (report[7] << 8) | report[8]))
        .toList();
    expect(heads.map((head) => head.$1).toList(), [
      0x01, // info
      0x05, // unlock
      0x03, // erase
      0x32, // 用户区首块
      0x12, // 用户区后续块
      0x02, // 0xFF0000 区
      0x02,
      0xff, // 复位
    ]);
    expect(
      heads
          .where((head) => const [0x32, 0x12, 0x02].contains(head.$1))
          .map((head) => head.$2)
          .toList(),
      [0x0000, 0x0080, 0x0000, 0x0100],
    );
    // 报告契约：首字节恒为 report ID 槽 0x00；Windows 侧 pb_hid_write 要求
    // length ≤ OutputReportByteLength（65），Linux 侧固定 64 字节本体。
    expect(transport.writes.every((report) => report[0] == 0), isTrue);
    expect(transport.writes.map((report) => report.length).toSet(), {64, 65});
  });
}
