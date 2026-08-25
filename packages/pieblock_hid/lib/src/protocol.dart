import 'dart:typed_data';

import 'package:pieblock_toolchain/pieblock_toolchain.dart';

import 'transport.dart';

const hidVid = 0x34bf;
const hidPid = 0x1001;
const flashBlockSize = 128;
const _codeBase = 0xfe0000;
const _highBase = 0xff0000;

class FlashBlock {
  const FlashBlock({
    required this.address,
    required this.command,
    required this.data,
  });
  final int address;
  final int command;
  final Uint8List data;
}

abstract final class HidProtocol {
  static Uint8List buildPacket(List<int> payload) {
    final packet = <int>[0x46, 0xb9, 0x6a];
    final totalLength = payload.length + 6;
    packet.addAll([(totalLength >> 8) & 0xff, totalLength & 0xff, ...payload]);
    var checksum = 0;
    for (var index = 2; index < packet.length; index++) {
      checksum = (checksum + packet[index]) & 0xffff;
    }
    packet.addAll([(checksum >> 8) & 0xff, checksum & 0xff, 0x16]);
    return Uint8List.fromList(packet);
  }

  static List<Uint8List> splitReports(Uint8List packet) {
    final reports = <Uint8List>[];
    for (var offset = 0; offset < packet.length; offset += 64) {
      final end = (offset + 64).clamp(0, packet.length);
      final wire = <int>[0, ...packet.sublist(offset, end)];
      while (wire.length < 64) {
        wire.add(0);
      }
      reports.add(Uint8List.fromList(wire));
    }
    return reports;
  }

  static List<FlashBlock> buildWriteBlocks(HexImage image) {
    final user = <int, Uint8List>{};
    final high = <int, Uint8List>{};
    for (final entry in image.bytes.entries) {
      final base = entry.key < _highBase ? _codeBase : _highBase;
      final target = entry.key < _highBase ? user : high;
      final relative = entry.key - base;
      if (relative < 0 || relative >= 0x10000) {
        throw FormatException(
          'HEX 地址 0x${entry.key.toRadixString(16)} 无法映射到 ISP',
        );
      }
      final block = relative ~/ flashBlockSize;
      target.putIfAbsent(
        block,
        () => Uint8List(flashBlockSize),
      )[relative % flashBlockSize] = entry.value;
    }
    final blocks = <FlashBlock>[];
    final userKeys = user.keys.toList()..sort();
    for (var index = 0; index < userKeys.length; index++) {
      final key = userKeys[index];
      blocks.add(
        FlashBlock(
          address: key * flashBlockSize,
          command: index == 0 ? 0x32 : 0x12,
          data: user[key]!,
        ),
      );
    }
    final highKeys = high.keys.toList()..sort();
    for (final key in highKeys) {
      blocks.add(
        FlashBlock(
          address: key * flashBlockSize,
          command: 0x02,
          data: high[key]!,
        ),
      );
    }
    return blocks;
  }

  static Uint8List expectAck(
    HidTransport transport,
    List<int> payload,
    String label, {
    int commandOffset = 0,
    required int command,
    int timeoutMilliseconds = 3000,
  }) {
    final packet = buildPacket(payload);
    for (final report in splitReports(packet)) {
      if (!transport.write(report)) throw StateError('$label：写入报告失败');
    }
    final response = transport.read(timeoutMilliseconds);
    if (response.isEmpty) throw StateError('$label：设备无响应');
    if (response.length < 6 ||
        response[0] != 0x46 ||
        response[1] != 0xb9 ||
        response[2] != 0x68) {
      throw StateError('$label：响应帧头异常');
    }
    if (response[5 + commandOffset] != command) {
      throw StateError('$label：响应命令异常');
    }
    return response;
  }
}
