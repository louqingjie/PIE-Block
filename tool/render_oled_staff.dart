// OLED 五线谱渲染模拟器 CLI（128×64 单色，SSD1306 页格式）。
//
// 用途：在真机固件之前，先按精确的 128×64、1bit 像素栅格渲染滚动五线谱，
// 输出放大的 PNG 供评审：
//   - 左端固定：谱号（高/低音，自动切换）+ 调号 + 拍号；
//   - 右侧滚动：按 tick 比例排布音符，每唱完一个音符整幅左移一个步进；
//   - 当前音符上方用 1px 三角标记。
//
// 渲染逻辑与固件/主机对拍完全同源：
//   - 乐理/事件：pieblock_core 的 buildStaffSong；
//   - 字形点阵：pieblock_core 的 staff_glyphs；
//   - 整数版面：pieblock_core 的 staff_layout（StaffRender.c 照抄同一组公式）。
// 帧缓冲为 8 页 × 128 列，buf[page*128+x] 的 bit0 是该页最上一行。
//
// 用法：
//   dart run tool/render_oled_staff.dart --demo twinkle --out tmp/staff_preview
//   dart run tool/render_oled_staff.dart --demo wide --key G
//   dart run tool/render_oled_staff.dart --project path/to/music.pieproj
//   dart run tool/render_oled_staff.dart --self-check
//
// 参数见 --help。可复用的渲染器在 `tool/staff_render.dart`，主机对拍 fixture
// 生成器在 `tool/emit_staff_fixtures.dart`。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pieblock_core/pieblock_core.dart';

import 'oled_staff_spec.dart';
import 'staff_render.dart';

// 兼容旧测试/旧脚本的 import 路径：渲染器与画布工具从本文件仍然可见。
export 'oled_staff_spec.dart';
export 'staff_render.dart';

// ---------------------------------------------------------------------------
// CLI 参数
// ---------------------------------------------------------------------------

class CliOptions {
  const CliOptions({
    required this.demo,
    required this.projectPath,
    required this.configPath,
    required this.render,
    required this.outDir,
    required this.detailIndex,
    required this.selfCheck,
    required this.emitSpec,
  });

  final String? demo;
  final String? projectPath;
  final String? configPath;
  final RenderOptions render;
  final String outDir;
  final int? detailIndex;
  final bool selfCheck;
  final bool emitSpec;
}

CliOptions parseArgs(List<String> args) {
  String? demo;
  String? projectPath;
  String? configPath;
  String? key;
  var clef = 'auto';
  var maxFrames = 0;
  var outDir = 'tmp/staff_preview';
  int? detailIndex;
  var selfCheck = false;
  var emitSpec = false;

  /// 版面参数已固化为固件同源的整数常量；这里保留参数名但只接受标准值，
  /// 避免预览用了一套与固件不一致的比例。
  void fixed(String flag, int actual, int expected) {
    if (actual != expected) {
      throw ArgumentError(
        '$flag 固定为 $expected（与 staff_layout.dart / 固件同源，不能覆盖）',
      );
    }
  }

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    String value() {
      if (i + 1 >= args.length) {
        throw ArgumentError('参数 $arg 缺少取值');
      }
      return args[++i];
    }

    switch (arg) {
      case '--demo':
        demo = value();
      case '--project':
        projectPath = value();
      case '--config':
        configPath = value();
      case '--key':
        key = value();
      case '--clef':
        clef = value();
      case '--space':
        final space = int.parse(value());
        fixed('--space', space, staffSpace);
      case '--px-per-quarter':
        final px = int.parse(value());
        fixed('--px-per-quarter', px, staffPxPerQuarter);
      case '--min-note-gap':
        final gap = int.parse(value());
        fixed('--min-note-gap', gap, staffMinNoteGap);
      case '--cursor':
        final cursor = double.parse(value());
        if ((cursor - 0.30).abs() > 1e-9) {
          throw ArgumentError(
            '--cursor 固定为 0.30（与 staff_layout.dart / 固件同源，不能覆盖）',
          );
        }
      case '--frames':
        maxFrames = int.parse(value());
      case '--detail-index':
        detailIndex = int.parse(value());
      case '--out':
        outDir = value();
      case '--self-check':
        selfCheck = true;
      case '--emit-spec':
        emitSpec = true;
      case '--help':
      case '-h':
        printUsage();
        exit(0);
      default:
        throw ArgumentError('未知参数 $arg（--help 查看用法）');
    }
  }

  return CliOptions(
    demo: demo,
    projectPath: projectPath,
    configPath: configPath,
    render: RenderOptions(key: key, clef: clef, maxFrames: maxFrames),
    outDir: outDir,
    detailIndex: detailIndex,
    selfCheck: selfCheck,
    emitSpec: emitSpec,
  );
}

void printUsage() {
  stdout.writeln('''OLED 五线谱渲染模拟器（128×64 单色）

用法：
  dart run tool/render_oled_staff.dart --demo twinkle --out tmp/staff_preview
  dart run tool/render_oled_staff.dart --demo wide --key G
  dart run tool/render_oled_staff.dart --project <path.pieproj> --key F
  dart run tool/render_oled_staff.dart --self-check

参数：
  --demo ${staffDemoNames.join('|')}  内置示例（默认 twinkle；调号内置）
  --project <path>    读取真实 .pieproj（format_version 16）
  --config <path>     读取单份 MusicConfig JSON
  --key <调号>        覆盖调号：C/G/D/A/E/B/F#/C#/F/Bb/Eb/Ab/Db/Gb/Cb（也支持 Am/Em/... 小调）
  --clef auto|treble|bass  谱号，默认 auto（自动分配，与固件一致）
  --frames <n>        最多渲染多少个滚动帧（0=全部）
  --detail-index <n>  指定放大细节帧
  --out <dir>         输出目录，默认 tmp/staff_preview
  --emit-spec         额外输出 spec.json（字形点阵与几何参数）
  --self-check        仅做自检（不写 PNG）

说明：线距/横向比例/最小间距/光标位置是与固件同源的整数常量
（staff_layout.dart），--space/--px-per-quarter/--min-note-gap/--cursor
只接受标准值，用于兼容旧脚本，不能真正覆盖。''');
}

MusicConfig loadConfig(CliOptions options) {
  if (options.projectPath != null) {
    final text = File(options.projectPath!).readAsStringSync();
    final json = jsonDecode(text);
    if (json is! Map) throw FormatException('工程文件不是 JSON 对象');
    final document = ProjectDocument.fromJson(Map<String, Object?>.from(json));
    final config = document.config;
    if (config is! MusicConfig) throw FormatException('不是音乐工程');
    return config;
  }
  if (options.configPath != null) {
    final text = File(options.configPath!).readAsStringSync();
    final json = jsonDecode(text);
    if (json is! Map) throw FormatException('配置不是 JSON 对象');
    return MusicConfig.fromJson(Map<String, Object?>.from(json));
  }
  return demoConfig(options.demo ?? 'twinkle');
}

// ---------------------------------------------------------------------------
// 输出
// ---------------------------------------------------------------------------

Future<void> writePreview({
  required StaffRenderer renderer,
  required String outDir,
  required int? detailIndex,
  required bool emitSpec,
}) async {
  final directory = Directory(outDir);
  await directory.create(recursive: true);
  final frames = renderer.renderAll();
  for (var i = 0; i < frames.length; i++) {
    final gray = bitmapToGray(frames[i]);
    final file = File('$outDir/frame_${i.toString().padLeft(3, '0')}.png');
    await file.writeAsBytes(encodePngGray(screenWidth, screenHeight, gray));
  }

  final detail = detailIndex ?? frames.length ~/ 2;
  if (detail >= 0 && detail < frames.length) {
    const scale = 8;
    const margin = 2;
    final gray = bitmapToGray(frames[detail], scale: scale, margin: margin);
    final width = (screenWidth + margin * 2) * scale;
    final height = (screenHeight + margin * 2) * scale;
    await File('$outDir/detail.png')
        .writeAsBytes(encodePngGray(width, height, gray));
  }

  // 对比图：每行 4 帧、放大 4 倍，帧号用 7×8 数字点阵画在每帧上方。
  const columns = 4;
  const scale = 4;
  const gap = 6;
  const labelHeight = 14;
  const margin = 6;
  final frameWidth = screenWidth * scale;
  final frameHeight = screenHeight * scale;
  final rows = (frames.length / columns).ceil();
  final sheetWidth = margin * 2 + columns * frameWidth + (columns - 1) * gap;
  final sheetHeight =
      margin * 2 + rows * (frameHeight + labelHeight) + (rows - 1) * gap;
  final sheet = Uint8List(sheetWidth * sheetHeight);
  for (var i = 0; i < frames.length; i++) {
    final col = i % columns;
    final row = i ~/ columns;
    final originX = margin + col * (frameWidth + gap);
    final originY = margin + row * (frameHeight + labelHeight + gap);
    final frameGray = bitmapToGray(frames[i], scale: scale);
    for (var y = 0; y < frameHeight; y++) {
      final dst = (originY + labelHeight + y) * sheetWidth + originX;
      sheet.setRange(dst, dst + frameWidth, frameGray, y * frameWidth);
    }
    final label = i.toString().padLeft(2, '0');
    var labelX = originX;
    for (var c = 0; c < label.length; c++) {
      final glyph = digitGlyphs[label[c]];
      if (glyph != null) {
        blitGlyphGray(
          sheet,
          sheetWidth,
          sheetHeight,
          glyph,
          labelX,
          originY + 2,
          2,
        );
        labelX += glyph.width * 2 + 2;
      }
    }
  }
  await File('$outDir/sheet.png')
      .writeAsBytes(encodePngGray(sheetWidth, sheetHeight, sheet));

  if (emitSpec) {
    await File('$outDir/spec.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(renderer.toSpecJson()),
    );
  }

  stdout.writeln(
    '已输出 ${frames.length} 帧到 $outDir/'
    '（frame_*.png / detail.png / sheet.png'
    '${emitSpec ? ' / spec.json' : ''}）',
  );
  stdout.writeln(
    '版面：线距 ${staffSpace}px，谱号 ${renderer.options.clef}，'
    '调号 ${keyNameForFifths(renderer.fifths)}'
    '（${renderer.fifths} 个升降号），拍号 '
    '${renderer.song.timeNumerator}/${renderer.song.timeDenominator}，'
    '左端固定区 ${renderer.panelWidth}px，滚动区起点 ${renderer.noteAreaStart}px，'
    '光标 x=${renderer.cursorX}',
  );
  for (var i = 0; i < frames.length; i++) {
    stdout.writeln('  ${renderer.describeFrame(i)}');
  }
}

// ---------------------------------------------------------------------------
// 自检
// ---------------------------------------------------------------------------

Future<int> runSelfCheck() async {
  var failures = 0;
  void check(bool condition, String message) {
    if (!condition) {
      failures++;
      stderr.writeln('FAIL: $message');
    }
  }

  for (final demo in staffDemoNames) {
    final config = demoConfig(demo);
    final renderer = StaffRenderer(config: config);
    final frames = renderer.renderAll();
    check(frames.isNotEmpty, '$demo 没有渲染出任何帧');
    for (final frame in frames) {
      check(
        frame.bytes.length == frameBytes,
        '$demo 帧长度应为 $frameBytes，实际 ${frame.bytes.length}',
      );
    }
    check(renderer.isDeterministic(0), '$demo 第 0 帧不是确定性输出');
    check(
      renderer.isDeterministic(renderer.visibleFrameCount - 1),
      '$demo 最后一帧不是确定性输出',
    );
    check(
      frames.length == renderer.visibleFrameCount,
      '$demo 帧数 ${frames.length} != ${renderer.visibleFrameCount}',
    );
    check(renderer.panelWidth < screenWidth, '$demo 左端固定区过宽');
    check(
      renderer.panelWidth < renderer.noteAreaStart &&
          renderer.noteAreaStart <= renderer.cursorX &&
          renderer.cursorX < screenWidth,
      '$demo 滚动区/光标几何越界（panel=${renderer.panelWidth} '
      'start=${renderer.noteAreaStart} cursor=${renderer.cursorX}）',
    );
    check(
      renderer.fifths == (staffDemoKeyFifths[demo] ?? 0),
      '$demo 默认调号应为 ${staffDemoKeyFifths[demo]}，实际 ${renderer.fifths}',
    );
    check(
      renderer.song.keyStepsTreble.length == renderer.keyCount &&
          renderer.song.keyStepsBass.length == renderer.keyCount,
      '$demo 调号步数表数量不符',
    );
    for (var i = 0; i < renderer.events.length; i++) {
      final event = renderer.events[i];
      if (event.isRest) continue;
      final y = staffYForStep(event.step);
      check(
        y >= 0 && y < screenHeight,
        '$demo frame $i: pitch ${event.pitch} 的 y=$y 超出屏幕',
      );
    }
    for (var i = 0; i < frames.length; i++) {
      for (final x in staffBarLineXs(renderer.song, i)) {
        check(
          x >= renderer.noteAreaStart && x < screenWidth,
          '$demo frame $i: 小节线 x=$x 落在禁区/屏外',
        );
      }
    }
  }

  // `--key` 覆盖：wide 默认 G，覆盖成 C 后应没有升降号。
  final overridden = StaffRenderer(
    config: demoConfig('wide'),
    options: const RenderOptions(key: 'C'),
  );
  check(overridden.fifths == 0, '--key C 未能覆盖 wide 的内置调号 G');

  // `--clef` 覆盖：mixed 的自动谱号会从低音切到高音，强制高音后必须全高音。
  final forced = StaffRenderer(
    config: demoConfig('mixed'),
    options: const RenderOptions(clef: 'treble'),
  );
  check(
    forced.events.every((event) => event.clef == 0),
    '--clef treble 未能强制全部事件使用高音谱号',
  );

  if (failures == 0) {
    stdout.writeln(
      'self-check OK：${staffDemoNames.length} 个示例全部通过'
      '（帧长/确定性/音高在屏内/调号/整数版面/--key/--clef）',
    );
  } else {
    stderr.writeln('self-check 失败 $failures 项');
  }
  return failures == 0 ? 0 : 1;
}

Future<void> main(List<String> args) async {
  try {
    final options = parseArgs(args);
    if (options.selfCheck) {
      exitCode = await runSelfCheck();
      return;
    }
    final config = loadConfig(options);
    final renderer = StaffRenderer(config: config, options: options.render);
    await writePreview(
      renderer: renderer,
      outDir: options.outDir,
      detailIndex: options.detailIndex,
      emitSpec: options.emitSpec,
    );
  } on ArgumentError catch (error) {
    stderr.writeln('参数错误：${error.message}');
    stderr.writeln('用 --help 查看用法。');
    exitCode = 64;
  } on Object catch (error) {
    stderr.writeln('渲染失败：$error');
    exitCode = 1;
  }
}
