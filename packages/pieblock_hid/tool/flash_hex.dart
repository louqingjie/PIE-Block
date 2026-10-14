// 用应用内同一条 Dart 链路（HidProtocol + HidFlasher + 原生 hidraw 传输层）
// 烧录一份 HEX：不启动 GUI 也能在真机上验证应用本身的烧录路径。
//
//   dart run tool/flash_hex.dart <firmware.hex> [--report-gap-ms N]
//
// 不传 --report-gap-ms 时用 HidFlasher.defaultReportGap（Linux 20ms、其它平台
// 1ms），与向导页「烧录当前固件」完全一致；日志里的「帧内报告间隔」会标出实际
// 生效的值。会擦除程序区，运行前必须先把主控板断电重新上电进入 ISP。
import 'dart:io';

import 'package:pieblock_hid/pieblock_hid.dart';
import 'package:pieblock_toolchain/pieblock_toolchain.dart';

Future<void> main(List<String> arguments) async {
  final parsed = _parse(arguments);
  if (parsed == null) {
    exitCode = 64;
    return;
  }
  final validation = await IntelHexValidator.validateApplication(parsed.hex);
  if (!validation.ok) {
    stderr.writeln(validation.message);
    exitCode = 1;
    return;
  }
  final stopwatch = Stopwatch()..start();
  String stamp() => '${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)}s';
  final HidTransport transport;
  try {
    transport = HidFlasher.desktopTransport();
  } catch (error) {
    stderr.writeln('无法加载原生传输层：$error');
    stderr.writeln('开发机请指向已构建的库，例如：');
    stderr.writeln(
      '  PIEBLOCK_HID_DLL=build/linux/x64/debug/bundle/lib/libpieblock_hid.so \\\n'
      '    dart run tool/flash_hex.dart <firmware.hex>',
    );
    exitCode = 2;
    return;
  }
  final result = await HidFlasher.flashWithTransport(
    validation.image!,
    transport,
    (stage, message, {current, total}) {
      if (current == null || total == null) {
        stdout.writeln('[${stamp().padLeft(7)}] $message');
      } else if (current % 25 == 0 || current == total) {
        final perBlock = stopwatch.elapsedMilliseconds / current;
        stdout.writeln(
          '[${stamp().padLeft(7)}] $current/$total $message（${perBlock.toStringAsFixed(0)}ms/块）',
        );
      }
    },
    reportGap: parsed.reportGap,
  );
  stdout.writeln(
    '${result.success ? '成功' : '失败'}（${result.stage.name}）：${result.message}'
    ' 用时 ${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)}s',
  );
  exitCode = result.success ? 0 : 3;
}

({String hex, Duration? reportGap})? _parse(List<String> arguments) {
  String? hex;
  Duration? reportGap;
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument == '--report-gap-ms') {
      if (index + 1 >= arguments.length) {
        stderr.writeln('--report-gap-ms 需要一个毫秒数');
        return null;
      }
      reportGap = Duration(milliseconds: int.parse(arguments[++index]));
    } else if (argument == '--help' || argument == '-h') {
      stdout.writeln(
        '用法: dart run tool/flash_hex.dart <firmware.hex> [--report-gap-ms N]',
      );
      return null;
    } else if (hex == null) {
      hex = argument;
    } else {
      stderr.writeln('多余的参数：$argument');
      return null;
    }
  }
  if (hex == null) {
    stderr.writeln(
      '用法: dart run tool/flash_hex.dart <firmware.hex> [--report-gap-ms N]',
    );
    return null;
  }
  return (hex: hex, reportGap: reportGap);
}
