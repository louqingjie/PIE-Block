// OLED 五线谱渲染模拟器（128×64 单色，SSD1306 页格式）。
//
// 用途：在真正写固件（stc32g_sdcc 的 LCD_Init/LCD_WrDat 软件 SPI）之前，先按
// 精确的 128×64、1bit 像素栅格渲染滚动五线谱，输出放大的 PNG 供评审：
//   - 左端固定：谱号（高/低音，自动切换）+ 调号 + 拍号；
//   - 右侧滚动：按 tick 比例排布音符，每唱完一个音符整幅左移一个步进；
//   - 当前音符用 1px 方框高亮。
//
// 渲染结果与后续固件逐字节一致：帧缓冲为 8 页 × 128 列，buf[page*128+x] 的
// bit0 是该页最上一行（SSD1306 页寻址的字节序）。
//
// 字形/位图/乐谱解析等共用定义见 `tool/oled_staff_spec.dart`。
//
// 用法：
//   dart run tool/render_oled_staff.dart --demo twinkle --out tmp/staff_preview
//   dart run tool/render_oled_staff.dart --demo wide --key G
//   dart run tool/render_oled_staff.dart --project path/to/music.pieproj
//   dart run tool/render_oled_staff.dart --self-check
//
// 参数见 --help。

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pieblock_core/pieblock_core.dart';

import 'oled_staff_spec.dart';

/// 拍号数字的固定步进宽度（digitGlyphs 为 7×8）。
const int _timeDigitWidth = 7;

// ---------------------------------------------------------------------------
// 版面选项与渲染器
// ---------------------------------------------------------------------------

class RenderOptions {
  const RenderOptions({
    this.space = 6,
    this.staffTop = 14,
    this.pxPerQuarter = 16,
    this.minNoteGap = 6,
    this.cursorFraction = 0.30,
    this.key = 'C',
    this.clef = 'auto',
    this.maxFrames = 0,
  });

  final int space, staffTop, pxPerQuarter, minNoteGap, maxFrames;
  final double cursorFraction;
  final String key, clef;

  int get fifths => keyFifths(key);
}

class StaffRenderer {
  StaffRenderer({required this.config, required this.options})
    : events = buildScore(config) {
    if (events.isEmpty) {
      throw StateError('乐谱为空：该工程没有可显示的音符');
    }
    timeSignature = config.timeSignatureEvents.isEmpty
        ? const TimeSignatureEvent(tick: 0, numerator: 4, denominator: 4)
        : config.timeSignatureEvents.first;
    clefPerEvent = _assignClefs();
  }

  final MusicConfig config;
  final RenderOptions options;
  final List<ScoreEvent> events;
  late final TimeSignatureEvent timeSignature;
  late final List<String> clefPerEvent;

  int get fifths => options.fifths;
  int get space => options.space;
  int get staffTop => options.staffTop;
  int get staffBottom => staffBottomY(options.staffTop, options.space);
  int get middleLineY => options.staffTop + 2 * options.space;

  /// 左端固定区宽度：谱号 + 调号 + 拍号。
  int get panelWidth {
    var x = 1 + trebleClefGlyph.width + 1;
    x += fifths.abs() * 6; // 升/降号字形 5px 宽 + 1px 间距
    final digitCount = math.max(
      '${timeSignature.numerator}'.length,
      '${timeSignature.denominator}'.length,
    );
    x += 2 + _timeDigitWidth * digitCount + (digitCount - 1) + 1;
    return x;
  }

  /// 滚动内容从这里开始：固定区外再留 6px 隔离带，避免音符贴着
  /// 谱号/调号/拍号（隔离带里只有谱线，没有音符）。
  int get noteAreaStart => panelWidth + 6;

  double get cursorX =>
      noteAreaStart + (screenWidth - noteAreaStart) * options.cursorFraction;

  double get _pxPerTick => options.pxPerQuarter / config.ticksPerQuarter;

  int get barTicks {
    final denominator = math.max(1, timeSignature.denominator);
    final numerator = math.max(1, timeSignature.numerator);
    return (config.ticksPerQuarter * 4 ~/ denominator) * numerator;
  }

  int get visibleFrameCount {
    if (options.maxFrames > 0 && options.maxFrames < events.length) {
      return options.maxFrames;
    }
    return events.length;
  }

  List<Bitmap> renderAll() => [
    for (var index = 0; index < visibleFrameCount; index++) renderFrame(index),
  ];

  String clefForEvent(int index) => clefPerEvent[index];

  /// 顺序遍历音符分配谱号（3 个音符前瞻 + 迟滞）：同一个音符的谱号不随
  /// 当前播放位置改变，换谱号时在滚动区画一个谱号变更符号，符合单谱表记谱。
  List<String> _assignClefs() {
    if (options.clef == 'treble' || options.clef == 'bass') {
      return List<String>.filled(events.length, options.clef);
    }
    final result = List<String>.filled(events.length, 'treble');
    int cost(int index, String clef) {
      var maxLedger = 0;
      var seen = 0;
      for (var i = index; i < events.length && seen < 3; i++) {
        final event = events[i];
        if (event.isRest) continue;
        maxLedger = math.max(maxLedger, ledgerCountForPitch(event.pitch!, clef));
        seen++;
      }
      return maxLedger;
    }

    var current = 'treble';
    var firstIndex = 0;
    while (firstIndex < events.length && events[firstIndex].isRest) {
      firstIndex++;
    }
    if (firstIndex < events.length) {
      current = cost(firstIndex, 'treble') <= cost(firstIndex, 'bass')
          ? 'treble'
          : 'bass';
    }
    for (var i = 0; i < events.length; i++) {
      if (!events[i].isRest) {
        final other = current == 'treble' ? 'bass' : 'treble';
        if (cost(i, other) <= cost(i, current) - 2) current = other;
      }
      result[i] = current;
    }
    return result;
  }

  Bitmap renderFrame(int index) {
    final frame = Bitmap(screenWidth, screenHeight);
    _drawStaff(frame);
    final xs = layoutX(index);
    _drawBarLines(frame, index);
    // 先画滚动内容；固定区 + 隔离带里的内容最后统一清掉。
    for (var i = 0; i < events.length; i++) {
      final x = xs[i].round();
      if (x < noteAreaStart - 24 || x > screenWidth + 18) continue;
      final event = events[i];
      final noteClef = clefPerEvent[i];
      // 音符/休止符必须完整落在禁区外：任何被固定区/隔离带截断的音符不画。
      // 符头左沿 x-2、加线 x-3、临时记号 x-7；休止符最宽 x-2。
      final leftExtent = event.isRest
          ? 2
          : (_accidentalFor(i) != null ? 7 : 3);
      if (x - leftExtent < noteAreaStart) continue;
      if (event.isRest) {
        _drawRest(frame, event, x);
        continue;
      }
      final y = pitchY(event.pitch!, noteClef, space, staffTop);
      if (y < -2 || y > screenHeight + 1) continue;
      // 换谱号的地方画一个谱号变更符号，旧音符仍按旧谱号绘制；
      // 变更点落在固定区/隔离带里时不画（避免和固定谱号叠在一起）。
      if (i > 0 && noteClef != clefPerEvent[i - 1] &&
          x - 16 >= noteAreaStart) {
        _drawClef(frame, noteClef, x - 16);
      }
      _drawNote(frame, i, x, noteClef);
    }
    // 谱号/调号/拍号所在的左端固定区 + 隔离带是禁区：清空后只重绘谱线
    // 和固定内容，保证滚动内容绝不会贴着固定区。
    _drawFixedPanel(frame, clefPerEvent[index]);
    _drawCursorMarker(frame);
    return frame;
  }

  /// 重绘左端固定区（谱号 + 调号 + 拍号 + 谱线 + 隔离带）。
  void _drawFixedPanel(Bitmap frame, String clef) {
    frame.clearRect(0, 0, noteAreaStart, screenHeight);
    for (var line = 0; line <= 4; line++) {
      frame.hLine(0, noteAreaStart - 1, staffTop + line * space);
    }
    _drawClef(frame, clef, 1);
    _drawKeySignature(frame, clef);
    _drawTimeSignature(frame);
  }

  /// 当前播放位置的上方小三角（代替给音符套方框，避免遮住符头/符干）。
  void _drawCursorMarker(Bitmap frame) {
    final x = cursorX.round();
    final top = math.max(0, staffTop - 6);
    frame.hLine(x - 2, x + 2, top);
    frame.hLine(x - 1, x + 1, top + 1);
    frame.setPixel(x, top + 2);
  }

  // --- 谱线 / 固定区 -------------------------------------------------------

  void _drawStaff(Bitmap frame) {
    for (var line = 0; line <= 4; line++) {
      frame.hLine(0, screenWidth - 1, staffTop + line * space);
    }
  }

  void _drawClef(Bitmap frame, String clef, int x) {
    if (clef == 'bass') {
      // 低音谱号的两个点夹住 F 线（第 2 条线）。
      final fLine = staffTop + space;
      bassClefGlyph.blit(frame, x, fLine - 4);
    } else {
      trebleClefGlyph.blit(frame, x, staffTop - 2);
    }
  }

  void _drawKeySignature(Bitmap frame, String clef) {
    if (fifths == 0) return;
    final steps = clef == 'bass'
        ? (fifths > 0 ? bassSharpSteps : bassFlatSteps)
        : (fifths > 0 ? trebleSharpSteps : trebleFlatSteps);
    final glyph = fifths > 0 ? sharpGlyph : flatGlyph;
    var x = 1 + trebleClefGlyph.width + 1;
    for (var i = 0; i < fifths.abs(); i++) {
      final y = staffBottom - (steps[i] * space ~/ 2);
      _blitAccidental(frame, glyph, x, y);
      x += 6;
    }
  }

  /// 画升/降/还原号：先擦掉字形包围盒内的谱线像素，再落点阵。
  /// 升号中间的空心如果被谱线穿过会被填成实心，看起来像“工/日”；
  /// 擦除后升号两根竖线、两根横线和中间的洞都能看清。
  void _blitAccidental(Bitmap frame, Glyph glyph, int x, int centerY) {
    final top = centerY - glyph.height ~/ 2;
    for (var row = 0; row < glyph.height; row++) {
      final py = top + row;
      if (!_isStaffLineRow(py)) continue;
      for (var col = 0; col < glyph.width; col++) {
        if (glyph.rows[row][col] != '#') frame.setPixel(x + col, py, false);
      }
    }
    glyph.blit(frame, x, top);
  }

  bool _isStaffLineRow(int y) {
    for (var line = 0; line <= 4; line++) {
      if (y == staffTop + line * space) return true;
    }
    return false;
  }

  void _drawTimeSignature(Bitmap frame) {
    final numerator = '${timeSignature.numerator}';
    final denominator = '${timeSignature.denominator}';
    final digitCount = math.max(numerator.length, denominator.length);
    final width = _timeDigitWidth * digitCount + (digitCount - 1);
    var x = panelWidth - width - 1;
    // 数字 7×8：上数字跨第 1–2 线，下数字跨第 3–4 线。
    final topY = staffTop + space - 4;
    final bottomY = staffTop + 3 * space - 4;
    for (var i = 0; i < numerator.length; i++) {
      final glyph = digitGlyphs[numerator[i]];
      if (glyph != null) glyph.blit(frame, x, topY);
      x += _timeDigitWidth + 1;
    }
    x = panelWidth - width - 1;
    for (var i = 0; i < denominator.length; i++) {
      final glyph = digitGlyphs[denominator[i]];
      if (glyph != null) glyph.blit(frame, x, bottomY);
      x += _timeDigitWidth + 1;
    }
  }

  // --- 横向布局 -------------------------------------------------------------

  /// 计算每个事件符头中心的 x；当前音符固定在 cursorX，右侧按最小间距排开。
  List<double> layoutX(int index) {
    final playTick = events[index].startTick;
    final xs = List<double>.filled(events.length, 0);
    for (var i = 0; i < events.length; i++) {
      xs[i] = cursorX + (events[i].startTick - playTick) * _pxPerTick;
    }
    xs[index] = cursorX;
    var previous = cursorX;
    for (var i = index + 1; i < events.length; i++) {
      final minimum = previous + _advanceFor(i);
      if (xs[i] < minimum) xs[i] = minimum;
      previous = xs[i];
    }
    previous = cursorX;
    for (var i = index - 1; i >= 0; i--) {
      final maximum = previous - _advanceFor(i + 1);
      if (xs[i] > maximum) xs[i] = maximum;
      previous = xs[i];
    }
    return xs;
  }

  double _advanceFor(int index) {
    final event = events[index];
    final accidental = _accidentalFor(index);
    var width = event.isRest ? 7.0 : options.minNoteGap.toDouble();
    if (accidental != null) width += 4;
    if (index > 0 && clefPerEvent[index] != clefPerEvent[index - 1]) {
      width += 16; // 滚动区里的谱号变更符号
    }
    return width;
  }

  /// 当前小节内该音符需要的临时记号（sharp/flat/natural），无需则 null。
  String? _accidentalFor(int index) {
    final event = events[index];
    if (event.isRest) return null;
    final measureStart = barTicks <= 0
        ? 0
        : (event.startTick ~/ barTicks) * barTicks;
    final state = <int, int>{};
    for (var i = 0; i < events.length; i++) {
      final current = events[i];
      if (current.isRest) continue;
      if (current.startTick < measureStart) continue;
      if (current.startTick > event.startTick) break;
      final spelling = spellPitch(current.pitch!, fifths);
      final keyAlteration = keyAlterationForLetter(spelling.letter, fifths);
      final previous = state[spelling.id] ?? keyAlteration;
      final needed = spelling.alteration != previous
          ? (spelling.alteration == 0
                ? 'natural'
                : spelling.alteration > 0
                ? 'sharp'
                : 'flat')
          : null;
      state[spelling.id] = spelling.alteration;
      if (i == index) return needed;
    }
    return null;
  }

  // --- 小节线 ---------------------------------------------------------------

  void _drawBarLines(Bitmap frame, int index) {
    if (barTicks <= 0) return;
    final playTick = events[index].startTick;
    final firstTick = math.max(barTicks, (playTick ~/ barTicks) * barTicks);
    final lastTick = playTick + (screenWidth / _pxPerTick).ceil();
    for (var tick = firstTick; tick <= lastTick; tick += barTicks) {
      final x = (cursorX + (tick - playTick) * _pxPerTick).round();
      if (x < noteAreaStart || x >= screenWidth) continue;
      frame.vLine(x, staffTop, staffBottom);
    }
  }

  // --- 音符 / 休止符 --------------------------------------------------------

  void _drawNote(Bitmap frame, int index, int x, String clef) {
    final event = events[index];
    final pitch = event.pitch!;
    final noteValue = noteValueForEvent(event, config);
    final y = pitchY(pitch, clef, space, staffTop);
    _drawLedgerLines(frame, pitch, clef, x);
    final accidental = _accidentalFor(index);
    if (accidental != null) {
      final glyph = accidental == 'sharp'
          ? sharpGlyph
          : accidental == 'flat'
          ? flatGlyph
          : naturalGlyph;
      _blitAccidental(frame, glyph, x - 7, y);
    }

    final stemUp = halfSpaceOffset(pitch, clef) < 0;
    final headLeft = x - 2;
    final headTop = y - 1;
    final head = noteValue.hollow ? noteHeadHollow : noteHeadFilled;
    head.blit(frame, headLeft, headTop);
    if (noteValue.dots > 0) {
      frame.setPixel(x + 3, y - (noteValue.hollow ? 1 : 0));
    }
    if (noteValue.hasStem) {
      final stemX = stemUp ? headLeft + 3 : headLeft;
      final stemTop = stemUp ? headTop - 8 : headTop;
      final stemBottom = stemUp ? headTop : headTop + 3 + 8;
      frame.vLine(stemX, stemTop, stemBottom);
      for (var flag = 0; flag < noteValue.flagCount; flag++) {
        if (stemUp) {
          _drawFlagUp(frame, stemX, stemTop + flag * 3);
        } else {
          _drawFlagDown(frame, stemX, stemBottom - flag * 3);
        }
      }
    }
  }

  void _drawLedgerLines(Bitmap frame, int pitch, String clef, int x) {
    final step = diatonicIndex(pitch) - clefBottomDiatonic(clef);
    if (step > 8) {
      for (var lineStep = 10; lineStep <= step; lineStep += 2) {
        final lineY = staffBottom - (lineStep * space ~/ 2);
        frame.hLine(x - 3, x + 3, lineY);
      }
    } else if (step < 0) {
      for (var lineStep = -2; lineStep >= step; lineStep -= 2) {
        final lineY = staffBottom - (lineStep * space ~/ 2);
        frame.hLine(x - 3, x + 3, lineY);
      }
    }
  }

  void _drawFlagUp(Bitmap frame, int stemX, int y) {
    frame.setPixel(stemX + 1, y);
    frame.setPixel(stemX + 2, y + 1);
    frame.setPixel(stemX + 2, y + 2);
  }

  void _drawFlagDown(Bitmap frame, int stemX, int y) {
    frame.setPixel(stemX + 1, y);
    frame.setPixel(stemX + 2, y - 1);
    frame.setPixel(stemX + 2, y - 2);
  }

  void _drawRest(Bitmap frame, ScoreEvent event, int x) {
    final noteValue = noteValueForEvent(event, config);
    switch (noteValue.denominator) {
      case 1:
        restWholeGlyph.blit(frame, x - 2, staffTop + space + 1);
      case 2:
        restHalfGlyph.blit(frame, x - 2, middleLineY - 2);
      case 4:
        restQuarterGlyph.blit(frame, x - 1, middleLineY - 3);
      case 8:
        restEighthGlyph.blit(frame, x, middleLineY - 2);
      case 16:
        restSixteenthGlyph.blit(frame, x, middleLineY - 3);
    }
  }

  // --- 调试信息 -------------------------------------------------------------

  String describeFrame(int index) {
    final event = events[index];
    final value = noteValueForEvent(event, config);
    if (event.isRest) {
      return 'frame $index: 休止 ${value.beats.toStringAsFixed(2)} 拍';
    }
    final spelling = spellPitch(event.pitch!, fifths);
    return 'frame $index: ${spelling.name} (MIDI ${event.pitch}) '
        '${value.beats.toStringAsFixed(2)} 拍';
  }

  Map<String, Object?> toSpecJson() => <String, Object?>{
    'screen': {
      'width': screenWidth,
      'height': screenHeight,
      'pages': screenPages,
    },
    'options': {
      'space': space,
      'staffTop': staffTop,
      'pxPerQuarter': options.pxPerQuarter,
      'minNoteGap': options.minNoteGap,
      'cursorFraction': options.cursorFraction,
      'key': options.key,
      'fifths': fifths,
      'clef': options.clef,
    },
    'timeSignature': {
      'numerator': timeSignature.numerator,
      'denominator': timeSignature.denominator,
    },
    'panelWidth': panelWidth,
    'glyphs': {
      'trebleClef': trebleClefGlyph.rows,
      'bassClef': bassClefGlyph.rows,
      'sharp': sharpGlyph.rows,
      'flat': flatGlyph.rows,
      'natural': naturalGlyph.rows,
      'noteHeadFilled': noteHeadFilled.rows,
      'noteHeadHollow': noteHeadHollow.rows,
      'restWhole': restWholeGlyph.rows,
      'restHalf': restHalfGlyph.rows,
      'restQuarter': restQuarterGlyph.rows,
      'restEighth': restEighthGlyph.rows,
      'restSixteenth': restSixteenthGlyph.rows,
      'digits': {
        for (final entry in digitGlyphs.entries) entry.key: entry.value.rows,
      },
    },
    'events': [
      for (var i = 0; i < events.length; i++)
        {
          'pitch': events[i].pitch,
          'startTick': events[i].startTick,
          'durationTicks': events[i].durationTicks,
          'clef': clefPerEvent[i],
          'noteValue': noteValueForEvent(events[i], config).toString(),
          'description': describeFrame(i),
        },
    ],
  };

  /// 同一帧渲染两次并比较，用于自检确定性。
  bool isDeterministic(int index) {
    final first = renderFrame(index);
    final second = renderFrame(index);
    if (first.bytes.length != second.bytes.length) return false;
    for (var i = 0; i < first.bytes.length; i++) {
      if (first.bytes[i] != second.bytes[i]) return false;
    }
    return true;
  }
}

// ---------------------------------------------------------------------------
// 内置示例乐谱
// ---------------------------------------------------------------------------

/// (音高 / null=休止, 时值 tick)。
typedef DemoCell = (int? pitch, int ticks);

MusicConfig demoConfig(String name) {
  final cells = switch (name) {
    'twinkle' => const <DemoCell>[
      (60, 480), (60, 480), (67, 480), (67, 480),
      (69, 480), (69, 480), (67, 960),
      (65, 480), (65, 480), (64, 480), (64, 480),
      (62, 480), (62, 480), (60, 960),
    ],
    'wide' => const <DemoCell>[
      (72, 240), (71, 240), (69, 240), (67, 240),
      (66, 240), (64, 240), (62, 240), (60, 240),
      (60, 720), (62, 240), (64, 240), (67, 720),
      (72, 120), (74, 120), (76, 120), (79, 120),
      (81, 360), (84, 960),
    ],
    'bass' => const <DemoCell>[
      (41, 480), (43, 480), (45, 480), (46, 480),
      (48, 480), (50, 480), (52, 480), (53, 480),
      (55, 960), (null, 480), (53, 480), (48, 960),
    ],
    'mixed' => const <DemoCell>[
      (43, 480), (45, 480), (47, 480), (48, 480),
      (50, 480), (52, 480), (55, 480), (57, 480),
      (60, 480), (72, 480), (74, 480), (76, 480),
      (79, 480), (81, 480), (84, 960),
    ],
    'chromatic' => const <DemoCell>[
      (61, 240), (62, 240), (64, 240), (65, 240),
      (66, 480), (67, 240), (65, 240), (64, 480),
      (70, 240), (69, 240), (67, 960),
    ],
    'accidentals' => const <DemoCell>[
      // F#5 在顶线上（升号压在谱线上）、F5 还原、F#4 在间里、C#5、C#4…
      (78, 480), (77, 480), (78, 480), (66, 480),
      (65, 480), (73, 480), (61, 480), (62, 960),
    ],
    'rests' => const <DemoCell>[
      (60, 480), (null, 480), (62, 480), (null, 960),
      (64, 480), (65, 480), (null, 240), (67, 960),
    ],
    _ => throw ArgumentError(
      '未知示例 $name（可用 twinkle/wide/bass/mixed/chromatic/accidentals/rests）',
    ),
  };
  var tick = 0;
  final notes = <MusicNote>[];
  for (var i = 0; i < cells.length; i++) {
    final cell = cells[i];
    if (cell.$1 != null) {
      notes.add(
        MusicNote(
          id: 'n$i',
          pitch: cell.$1!,
          startTick: tick,
          durationTicks: cell.$2,
        ),
      );
    }
    tick += cell.$2;
  }
  return MusicConfig(
    notes: notes,
    ticksPerQuarter: 480,
    timeSignatureEvents: const [
      TimeSignatureEvent(tick: 0, numerator: 4, denominator: 4),
    ],
  );
}

// ---------------------------------------------------------------------------
// CLI
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
  var key = 'C';
  var clef = 'auto';
  var space = 6;
  var pxPerQuarter = 16;
  var minNoteGap = 6;
  var cursorFraction = 0.30;
  var maxFrames = 0;
  var outDir = 'tmp/staff_preview';
  int? detailIndex;
  var selfCheck = false;
  var emitSpec = false;

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
        space = int.parse(value());
      case '--px-per-quarter':
        pxPerQuarter = int.parse(value());
      case '--min-note-gap':
        minNoteGap = int.parse(value());
      case '--cursor':
        cursorFraction = double.parse(value());
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
    render: RenderOptions(
      space: space,
      pxPerQuarter: pxPerQuarter,
      minNoteGap: minNoteGap,
      cursorFraction: cursorFraction,
      key: key,
      clef: clef,
      maxFrames: maxFrames,
    ),
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
  --demo twinkle|wide|bass|mixed|chromatic|accidentals|rests  内置示例（默认 twinkle）
  --project <path>    读取真实 .pieproj（format_version 16）
  --config <path>     读取单份 MusicConfig JSON
  --key <调号>        C/G/D/A/E/B/F#/C#/F/Bb/Eb/Ab/Db/Gb/Cb（也支持 Am/Em/... 小调）
  --clef auto|treble|bass  谱号，默认 auto
  --space <px>        五线谱线距，默认 6
  --px-per-quarter <px>  横向比例，默认 16
  --min-note-gap <px>  音符最小间距，默认 6
  --cursor <0..1>     当前音符在滚动区的位置，默认 0.30
  --frames <n>        最多渲染多少个滚动帧（0=全部）
  --detail-index <n>  指定放大细节帧
  --out <dir>         输出目录，默认 tmp/staff_preview
  --emit-spec         额外输出 spec.json（字形点阵与几何参数）
  --self-check        仅做自检（不写 PNG）''');
}

MusicConfig loadConfig(CliOptions options) {
  if (options.projectPath != null) {
    final text = File(options.projectPath!).readAsStringSync();
    final json = jsonDecode(text);
    if (json is! Map) throw FormatException('工程文件不是 JSON 对象');
    final document = ProjectDocument.fromJson(
      Map<String, Object?>.from(json),
    );
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
    final scale = 8;
    final margin = 2;
    final gray = bitmapToGray(frames[detail], scale: scale, margin: margin);
    final width = (screenWidth + margin * 2) * scale;
    final height = (screenHeight + margin * 2) * scale;
    await File('$outDir/detail.png').writeAsBytes(
      encodePngGray(width, height, gray),
    );
  }

  // 对比图：每行 4 帧、放大 4 倍，帧号用 5×6 数字点阵画在每帧上方。
  const columns = 4;
  const scale = 4;
  const gap = 6;
  const labelHeight = 12;
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
  await File('$outDir/sheet.png').writeAsBytes(
    encodePngGray(sheetWidth, sheetHeight, sheet),
  );

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
    '版面：线距 ${renderer.options.space}px，谱号 ${renderer.options.clef}，'
    '调号 ${renderer.options.key}（${renderer.fifths} 个升降号），拍号 '
    '${renderer.timeSignature.numerator}/${renderer.timeSignature.denominator}，'
    '左端固定区 ${renderer.panelWidth}px',
  );
  for (var i = 0; i < frames.length; i++) {
    stdout.writeln('  ${renderer.describeFrame(i)}');
  }
}

Future<int> runSelfCheck() async {
  var failures = 0;
  void check(bool condition, String message) {
    if (!condition) {
      failures++;
      stderr.writeln('FAIL: $message');
    }
  }

  for (final demo in const <String>[
    'twinkle',
    'wide',
    'bass',
    'mixed',
    'chromatic',
    'accidentals',
    'rests',
  ]) {
    final config = demoConfig(demo);
    final renderer = StaffRenderer(
      config: config,
      options: const RenderOptions(),
    );
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
      frames.length == renderer.visibleFrameCount,
      '$demo 帧数 ${frames.length} != ${renderer.visibleFrameCount}',
    );
    check(renderer.panelWidth < screenWidth, '$demo 左端固定区过宽');
    for (var i = 0; i < renderer.events.length; i++) {
      final event = renderer.events[i];
      if (event.isRest) continue;
      final clef = renderer.clefForEvent(i);
      final y = pitchY(event.pitch!, clef, 6, 14);
      check(
        y >= 0 && y < screenHeight,
        '$demo frame $i: pitch ${event.pitch} 的 y=$y 超出屏幕',
      );
    }
    check(
      renderer.clefPerEvent.length == renderer.events.length,
      '$demo 谱号分配数量不符',
    );
  }
  if (failures == 0) {
    stdout.writeln('self-check OK：7 个示例全部通过（帧长/确定性/音高在屏内）');
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
