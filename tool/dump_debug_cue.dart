// 离线验证辅助：把调试项目生成的两份 C 固件落到 tmp/cue_verify，供 SDCC 编译检查。
// 用法：dart run tool/dump_debug_cue.dart
import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';

DebugConfig _debugConfig() => DebugConfig(
  tests: [
    const DebugTestItem(
      pin: 'P64',
      enabled: true,
      driveType: DebugDriveType.friction,
      direction: Direction.forward,
      value: 100,
    ),
    const DebugTestItem(
      pin: 'P66',
      enabled: true,
      driveType: DebugDriveType.friction,
      direction: Direction.forward,
      value: 50,
    ),
    const DebugTestItem(
      pin: 'MP03',
      enabled: true,
      driveType: DebugDriveType.servo,
      direction: Direction.reverse,
      value: 30,
      durationMs: 4200,
    ),
    for (final pin in debugPins.where(
      (pin) => pin != 'P64' && pin != 'P66' && pin != 'MP03',
    ))
      DebugTestItem(pin: pin),
  ],
  frictionP64MaxDuty: 800,
  frictionP66MaxDuty: 700,
);

void main() {
  for (final style in DebugCueStyle.values) {
    final code = CodeGenerator.generate(
      _debugConfig().copyWith(cueStyle: style),
    );
    final file = File('tmp/cue_verify/debug_${style.name}.c');
    file.writeAsStringSync(code);
    stdout.writeln('${file.path} ${code.length} 字节');
  }
}
