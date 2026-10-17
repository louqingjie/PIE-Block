// 把音乐工程（.pieproj 或单份 MusicConfig JSON）生成成固件 main.c，便于本地构建验证。
//
// 应用内“编译/烧录”走 FirmwareBuilder 的同一套 CodeGenerator，本工具只是把
// 生成结果落盘，供 stc32g_sdcc/build.ps1 直接编译（例如更新
// stc32g_sdcc/projects/BUZZER_MUSIC_GENERATED/src/main.c）。
//
// 用法：
//   dart run tool/generate_firmware_main.dart \
//     --project assets/templates/music.pieproj \
//     --out stc32g_sdcc/projects/BUZZER_MUSIC_GENERATED/src/main.c
//
// 可选 --key-fifths N 覆盖调号（调试五线谱用，不写回工程）。

import 'dart:convert';
import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';

void main(List<String> args) {
  String? projectPath;
  String? outputPath;
  int? keyFifthsOverride;
  for (var i = 0; i < args.length; i++) {
    String value() {
      if (i + 1 >= args.length) {
        throw ArgumentError('参数 ${args[i]} 缺少取值');
      }
      return args[++i];
    }

    switch (args[i]) {
      case '--project':
        projectPath = value();
      case '--out':
        outputPath = value();
      case '--key-fifths':
        keyFifthsOverride = int.parse(value());
      case '--help':
      case '-h':
        stdout.writeln('''
用法：dart run tool/generate_firmware_main.dart --project <path> --out <main.c>
  --project <path>   .pieproj 工程或 MusicConfig JSON
  --out <path>       输出的 main.c 路径
  --key-fifths <n>   覆盖调号（-7..7，仅本次生成）''');
        return;
      default:
        throw ArgumentError('未知参数 ${args[i]}');
    }
  }
  if (projectPath == null || outputPath == null) {
    stderr.writeln('缺少 --project 或 --out，见 --help。');
    exitCode = 64;
    return;
  }
  final raw = File(projectPath).readAsStringSync();
  final json = jsonDecode(raw);
  if (json is! Map) throw const FormatException('工程/配置不是 JSON 对象');
  final map = Map<String, Object?>.from(json);
  MusicConfig config;
  if (map.containsKey('format_version')) {
    final document = ProjectDocument.fromJson(map);
    final value = document.config;
    if (value is! MusicConfig) {
      throw const FormatException('不是音乐工程');
    }
    config = value;
  } else {
    config = MusicConfig.fromJson(map);
  }
  if (keyFifthsOverride != null) {
    config = config.copyWith(
      keySignatureFifths: keyFifthsOverride.clamp(-7, 7).toInt(),
    );
  }
  final code = CodeGenerator.generate(config);
  final file = File(outputPath);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(code);
  final song = buildStaffSong(config);
  stdout.writeln(
    '已生成 $outputPath：${code.length} 字符，'
    '${song.events.length} 个显示事件，调号 ${song.keyFifths}，'
    '拍号 ${song.timeNumerator}/${song.timeDenominator}',
  );
}
