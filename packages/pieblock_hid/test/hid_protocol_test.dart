import 'dart:typed_data';

import 'package:pieblock_hid/pieblock_hid.dart';
import 'package:pieblock_toolchain/pieblock_toolchain.dart';
import 'package:test/test.dart';

class _FakeTransport implements HidTransport {
  int devices = 1;
  bool opened = false;
  bool closed = false;
  final writes = <Uint8List>[];
  final responses = <Uint8List>[];

  @override
  Future<void> cancel() async {}

  @override
  Future<void> close() async => closed = true;

  @override
  Future<int> countDevices() async => devices;

  @override
  Future<bool> open() async => opened = true;

  @override
  Future<Uint8List> read(int timeoutMilliseconds) async =>
      responses.removeAt(0);

  @override
  Future<bool> write(Uint8List report) async {
    writes.add(report);
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
}
