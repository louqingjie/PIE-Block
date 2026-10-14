// 打印某个 HEX 的 ISP 烧录计划，用于跨实现/跨抓包对拍：
//
//   dart run tool/dump_block_plan.dart firmware.hex
//
// 输出每行 `<索引> <命令> <ISP地址> <128 字节块数据的 sha1>`，与
// stc32g/toolchain/stcflash/linux_hidraw_flash.py --dry-run 的输出逐行可比；
// 真机抓包时也可用它核对「某一块实际发出去的字节」。
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:pieblock_hid/pieblock_hid.dart';
import 'package:pieblock_toolchain/pieblock_toolchain.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('用法: dart run tool/dump_block_plan.dart <firmware.hex>');
    exitCode = 64;
    return;
  }
  final validation = await IntelHexValidator.validateApplication(
    arguments.single,
  );
  if (!validation.ok) {
    stderr.writeln(validation.message);
    exitCode = 1;
    return;
  }
  final blocks = HidProtocol.buildWriteBlocks(validation.image!);
  for (var index = 0; index < blocks.length; index++) {
    final block = blocks[index];
    final command = block.command.toRadixString(16).padLeft(2, '0');
    final address = block.address.toRadixString(16).padLeft(4, '0');
    stdout.writeln('$index $command $address ${sha1.convert(block.data)}');
  }
  stdout.writeln('# 共 ${blocks.length} 块');
}
