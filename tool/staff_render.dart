// OLED 五线谱渲染器（128×64 单色，SSD1306 页格式）与内置示例乐谱。
//
// 这里是“宿主侧预览”的可复用部分：
//   - 事件、调号、临时记号、时值全部来自 pieblock_core 的 buildStaffSong
//     （与固件代码生成器同源，渲染器不再做任何乐理判断）；
//   - 谱线/固定区/滚动区/音符坐标全部使用 staff_layout.dart 的整数函数，
//     与固件 C 渲染器（StaffRender.c）逐像素一致；
//   - 本文件只负责把 [StaffSongData] 落成 1bit 像素。
//
// CLI 与 PNG 输出在 `tool/render_oled_staff.dart`；主机对拍 fixture 在
// `tool/staff_fixtures.dart`。三者共用本文件，避免预览与固件悄悄漂移。

import 'dart:math' as math;

import 'package:pieblock_core/pieblock_core.dart';

import 'oled_staff_spec.dart';

/// 版面参数全部固定在 core 的 staff_layout.dart（固件同源），这里只保留
/// 预览选项：调号覆盖、谱号覆盖、最多渲染帧数。
class RenderOptions {
  const RenderOptions({this.key, this.clef = 'auto', this.maxFrames = 0});

  /// 调号覆盖（如 `G` / `F#` / `Bb`）；null = 用 [MusicConfig.keySignatureFifths]。
  final String? key;

  /// `auto` / `treble` / `bass`；auto = buildStaffSong 的自动谱号分配。
  final String clef;

  /// 最多渲染多少帧（0 = 全部事件）。
  final int maxFrames;

  /// 强制谱号（0=高音、1=低音）；auto 时为 null。
  int? get forcedClef => switch (clef) {
    'auto' => null,
    'treble' => 0,
    'bass' => 1,
    _ => throw ArgumentError('谱号只能是 auto/treble/bass，实际为 $clef'),
  };
}

/// 调号个数 → 大调名称（仅用于日志/spec.json 展示）。
String keyNameForFifths(int fifths) {
  const majorKeys = <String>[
    'C', 'G', 'D', 'A', 'E', 'B', 'F#', 'C#', //
    'F', 'Bb', 'Eb', 'Ab', 'Db', 'Gb', 'Cb',
  ];
  final index = fifths >= 0 ? fifths : 7 + (-fifths);
  if (index < 0 || index >= majorKeys.length) return 'C';
  return majorKeys[index];
}

/// [MusicConfig] 的调号与强制谱号覆盖（CLI 的 `--key` / `--clef`）。
MusicConfig effectiveConfig(MusicConfig config, RenderOptions options) {
  var effective = config;
  if (options.key != null) {
    effective = effective.copyWith(
      keySignatureFifths: staffKeyFifths(options.key!),
    );
  }
  // 提前验证谱号取值，让 CLI 在真正渲染前就报错。
  options.forcedClef;
  return effective;
}

/// 用强制谱号重写事件表的谱号与步数（只影响预览；fixture/固件用自动谱号）。
StaffSongData _forceClefSong(StaffSongData song, int clef) => StaffSongData(
  keyFifths: song.keyFifths,
  ticksPerQuarter: song.ticksPerQuarter,
  timeNumerator: song.timeNumerator,
  timeDenominator: song.timeDenominator,
  keyStepsTreble: song.keyStepsTreble,
  keyStepsBass: song.keyStepsBass,
  events: <StaffEventData>[
    for (final event in song.events)
      StaffEventData(
        tickDuration: event.tickDuration,
        durationMs: event.durationMs,
        pitch: event.pitch,
        step: event.isRest
            ? 0
            : staffStepForPitch(event.pitch, clef, song.keyFifths),
        clef: clef,
        accidental: event.accidental,
        noteValue: event.noteValue,
      ),
  ],
);

/// 五线谱模拟渲染器：一帧 = 1024 字节 SSD1306 页格式帧缓冲。
class StaffRenderer {
  StaffRenderer._({
    required this.config,
    required this.options,
    required this.song,
  });

  factory StaffRenderer({
    required MusicConfig config,
    RenderOptions options = const RenderOptions(),
  }) {
    final effective = effectiveConfig(config, options);
    var song = buildStaffSong(effective);
    final forcedClef = options.forcedClef;
    if (forcedClef != null) song = _forceClefSong(song, forcedClef);
    if (song.events.isEmpty) {
      throw StateError('乐谱为空：该工程没有可显示的音符');
    }
    return StaffRenderer._(config: effective, options: options, song: song);
  }

  final MusicConfig config;
  final RenderOptions options;
  final StaffSongData song;

  // --- 版面（全部来自 staff_layout.dart）-------------------------------------

  int get fifths => song.keyFifths;
  int get keyCount => song.keyCount;

  int get timeDigitCount =>
      staffTimeDigitCount(song.timeNumerator, song.timeDenominator);

  int get panelWidth =>
      staffPanelWidth(keyCount: keyCount, timeDigits: timeDigitCount);

  int get noteAreaStart =>
      staffNoteAreaStart(keyCount: keyCount, timeDigits: timeDigitCount);

  /// 当前音符中心的 x（整数像素）。
  int get cursorX => staffCursorX(noteAreaStart);

  int get barTicks => song.barTicks;

  List<StaffEventData> get events => song.events;

  int get visibleFrameCount {
    if (options.maxFrames > 0 && options.maxFrames < song.events.length) {
      return options.maxFrames;
    }
    return song.events.length;
  }

  // --- 渲染 ----------------------------------------------------------------

  List<Bitmap> renderAll() => <Bitmap>[
    for (var index = 0; index < visibleFrameCount; index++) renderFrame(index),
  ];

  Bitmap renderFrame(int index) {
    final frame = Bitmap(screenWidth, screenHeight);
    _drawStaff(frame);
    final xs = staffLayoutX(song, index);
    _drawBarLines(frame, index);
    // 先画滚动内容；固定区 + 隔离带里的内容最后统一清掉。
    for (var i = 0; i < song.events.length; i++) {
      final x = xs[i];
      if (x < noteAreaStart - 24 || x > screenWidth + 18) continue;
      final event = song.events[i];
      // 音符/休止符必须完整落在禁区外：任何被固定区/隔离带截断的音符不画。
      // 符头左沿 x-2、加线 x-3、临时记号最宽 x-8（升号 5px + 3px 间隙）；
      // 这里沿用旧版保守估计 7，配合固定区重绘保证滚动内容不侵入左端。
      final leftExtent = event.isRest ? 2 : (event.accidental != 0 ? 7 : 3);
      if (x - leftExtent < noteAreaStart) continue;
      if (event.isRest) {
        _drawRest(frame, event, x);
        continue;
      }
      final y = staffYForStep(event.step);
      if (y < -2 || y > screenHeight + 1) continue;
      // 换谱号的地方画一个谱号变更符号，旧音符仍按旧谱号绘制；
      // 变更点落在固定区/隔离带里时不画（避免和固定谱号叠在一起）。
      if (staffClefChangeAt(song, i) && x - 16 >= noteAreaStart) {
        _drawClef(frame, event.clef, x - 16);
      }
      _drawNote(frame, event, x, y);
    }
    // 谱号/调号/拍号所在的左端固定区 + 隔离带是禁区：清空后只重绘谱线
    // 和固定内容，保证滚动内容绝不会贴着固定区。
    _drawFixedPanel(frame, song.events[index].clef);
    _drawCursorMarker(frame);
    return frame;
  }

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

  // --- 谱线 / 固定区 ---------------------------------------------------------

  void _drawStaff(Bitmap frame) {
    for (var line = 0; line <= 4; line++) {
      frame.hLine(0, screenWidth - 1, staffTop + line * staffSpace);
    }
  }

  void _blit(Bitmap frame, StaffGlyph glyph, int x, int y) {
    for (var row = 0; row < glyph.height; row++) {
      final line = glyph.rows[row];
      for (var col = 0; col < line.length; col++) {
        if (line[col] == '#') frame.setPixel(x + col, y + row);
      }
    }
  }

  void _drawClef(Bitmap frame, int clef, int x) {
    if (clef == 1) {
      // 低音谱号的两个点夹住 F 线（第 2 条线）。
      final fLine = staffTop + staffSpace;
      _blit(frame, bassClefGlyph, x, fLine - 4);
    } else {
      _blit(frame, trebleClefGlyph, x, staffTop - 2);
    }
  }

  void _drawFixedPanel(Bitmap frame, int clef) {
    frame.clearRect(0, 0, noteAreaStart, screenHeight);
    for (var line = 0; line <= 4; line++) {
      frame.hLine(0, noteAreaStart - 1, staffTop + line * staffSpace);
    }
    _drawClef(frame, clef, 1);
    _drawKeySignature(frame, clef);
    _drawTimeSignature(frame);
  }

  void _drawKeySignature(Bitmap frame, int clef) {
    final count = song.keyCount;
    if (count == 0) return;
    final steps = clef == 1 ? song.keyStepsBass : song.keyStepsTreble;
    final glyph = song.keyIsSharp ? sharpGlyph : flatGlyph;
    var x = 1 + staffClefWidth + 1;
    for (var i = 0; i < count && i < steps.length; i++) {
      _blitAccidental(frame, glyph, x, staffYForStep(steps[i]));
      x += 6;
    }
  }

  void _drawTimeSignature(Bitmap frame) {
    final numerator = '${song.timeNumerator}';
    final denominator = '${song.timeDenominator}';
    final width = staffTimeDigitWidth * timeDigitCount + (timeDigitCount - 1);
    var x = panelWidth - width - 1;
    // 数字 7×8：上数字跨第 1–2 线，下数字跨第 3–4 线。
    final topY = staffTop + staffSpace - 4;
    final bottomY = staffTop + 3 * staffSpace - 4;
    for (var i = 0; i < numerator.length; i++) {
      final glyph = digitGlyphs[numerator[i]];
      if (glyph != null) _blit(frame, glyph, x, topY);
      x += staffTimeDigitWidth + 1;
    }
    x = panelWidth - width - 1;
    for (var i = 0; i < denominator.length; i++) {
      final glyph = digitGlyphs[denominator[i]];
      if (glyph != null) _blit(frame, glyph, x, bottomY);
      x += staffTimeDigitWidth + 1;
    }
  }

  /// 当前播放位置的上方小三角（代替给音符套方框，避免遮住符头/符干）。
  void _drawCursorMarker(Bitmap frame) {
    final x = cursorX;
    final top = math.max(0, staffTop - 6);
    frame.hLine(x - 2, x + 2, top);
    frame.hLine(x - 1, x + 1, top + 1);
    frame.setPixel(x, top + 2);
  }

  // --- 小节线 ---------------------------------------------------------------

  void _drawBarLines(Bitmap frame, int index) {
    for (final x in staffBarLineXs(song, index)) {
      frame.vLine(x, staffTop, staffBottomLineY());
    }
  }

  // --- 音符 / 休止符 --------------------------------------------------------

  /// 画升/降/还原号：先擦掉字形包围盒内的谱线像素，再落点阵。
  /// 升号中间的空心如果被谱线穿过会被填成实心，看起来像“工/日”；
  /// 擦除后升号两根竖线、两根横线和中间的洞都能看清。
  void _blitAccidental(Bitmap frame, StaffGlyph glyph, int x, int centerY) {
    final top = centerY - glyph.height ~/ 2;
    for (var row = 0; row < glyph.height; row++) {
      final py = top + row;
      if (!_isStaffLineRow(py)) continue;
      for (var col = 0; col < glyph.width; col++) {
        if (glyph.rows[row][col] != '#') frame.setPixel(x + col, py, false);
      }
    }
    _blit(frame, glyph, x, top);
  }

  bool _isStaffLineRow(int y) {
    for (var line = 0; line <= 4; line++) {
      if (y == staffTop + line * staffSpace) return true;
    }
    return false;
  }

  StaffGlyph _accidentalGlyph(int accidental) => switch (accidental) {
    1 => sharpGlyph,
    2 => flatGlyph,
    _ => naturalGlyph,
  };

  void _drawNote(Bitmap frame, StaffEventData event, int x, int y) {
    _drawLedgerLines(frame, event.step, x);
    if (event.accidental != 0) {
      final glyph = _accidentalGlyph(event.accidental);
      // 临时记号右沿统一落在 x-4，和符头（左沿 x-2）之间留 1px 空隙。
      _blitAccidental(frame, glyph, x - glyph.width - 3, y);
    }

    final stemUp = staffStemUpForStep(event.step);
    final headLeft = x - 2;
    final headTop = y - 1;
    final noteValue = event.noteValue;
    final head = noteValue.hollow ? noteHeadHollow : noteHeadFilled;
    _blit(frame, head, headLeft, headTop);
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

  void _drawLedgerLines(Bitmap frame, int step, int x) {
    if (step > 8) {
      for (var lineStep = 10; lineStep <= step; lineStep += 2) {
        frame.hLine(x - 3, x + 3, staffYForStep(lineStep));
      }
    } else if (step < 0) {
      for (var lineStep = -2; lineStep >= step; lineStep -= 2) {
        frame.hLine(x - 3, x + 3, staffYForStep(lineStep));
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

  void _drawRest(Bitmap frame, StaffEventData event, int x) {
    final middleLineY = staffTop + 2 * staffSpace;
    switch (event.noteValue.denominator) {
      case 1:
        _blit(frame, restWholeGlyph, x - 2, staffTop + staffSpace + 1);
      case 2:
        _blit(frame, restHalfGlyph, x - 2, middleLineY - 2);
      case 4:
        _blit(frame, restQuarterGlyph, x - 1, middleLineY - 3);
      case 8:
        _blit(frame, restEighthGlyph, x, middleLineY - 2);
      case 16:
        _blit(frame, restSixteenthGlyph, x, middleLineY - 3);
    }
  }

  // --- 调试信息 -------------------------------------------------------------

  String describeFrame(int index) {
    final event = song.events[index];
    if (event.isRest) {
      return 'frame $index: 休止 ${event.noteValue.beats.toStringAsFixed(2)} 拍';
    }
    final spelling = spellPitch(event.pitch, song.keyFifths);
    return 'frame $index: ${spelling.name} (MIDI ${event.pitch}) '
        '${event.noteValue.beats.toStringAsFixed(2)} 拍';
  }

  Map<String, Object?> toSpecJson() => <String, Object?>{
    'screen': {
      'width': screenWidth,
      'height': screenHeight,
      'pages': screenPages,
    },
    'options': {
      'space': staffSpace,
      'staffTop': staffTop,
      'pxPerQuarter': staffPxPerQuarter,
      'minNoteGap': staffMinNoteGap,
      'cursorFraction': 0.30,
      'key': keyNameForFifths(song.keyFifths),
      'fifths': song.keyFifths,
      'clef': options.clef,
    },
    'timeSignature': {
      'numerator': song.timeNumerator,
      'denominator': song.timeDenominator,
    },
    'panelWidth': panelWidth,
    'noteAreaStart': noteAreaStart,
    'cursorX': cursorX,
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
    'events': <Map<String, Object?>>[
      for (var i = 0; i < song.events.length; i++)
        <String, Object?>{
          'pitch': song.events[i].pitch,
          'step': song.events[i].step,
          'startTick': staffStartTickOf(song, i),
          'tickDuration': song.events[i].tickDuration,
          'durationMs': song.events[i].durationMs,
          'clef': song.events[i].clef,
          'accidental': song.events[i].accidental,
          'noteValue': song.events[i].noteValue.toString(),
          'description': describeFrame(i),
        },
    ],
  };
}

// ---------------------------------------------------------------------------
// 内置示例乐谱
// ---------------------------------------------------------------------------

/// (音高 / null=休止, 时值 tick)。
typedef DemoCell = (int? pitch, int ticks);

/// 全部内置示例名（CLI 与自检共用）。
const List<String> staffDemoNames = <String>[
  'twinkle',
  'wide',
  'bass',
  'mixed',
  'chromatic',
  'accidentals',
  'flats',
  'rests',
  'sevenSharps',
];

/// 每个示例的调号（升/降号个数）：wide=G、bass=F、flats=F、sevenSharps=C#，
/// 其余 C。`--key` 可以覆盖。
const Map<String, int> staffDemoKeyFifths = <String, int>{
  'twinkle': 0,
  'wide': 1,
  'bass': -1,
  'mixed': 0,
  'chromatic': 0,
  'accidentals': 0,
  'flats': -1,
  'rests': 0,
  'sevenSharps': 7,
};

/// 内置示例乐谱（音符与旧版完全一致；调号内置在 MusicConfig 里）。
MusicConfig demoConfig(String name) {
  final cells = switch (name) {
    'twinkle' => const <DemoCell>[
      (60, 480),
      (60, 480),
      (67, 480),
      (67, 480),
      (69, 480),
      (69, 480),
      (67, 960),
      (65, 480),
      (65, 480),
      (64, 480),
      (64, 480),
      (62, 480),
      (62, 480),
      (60, 960),
    ],
    'wide' => const <DemoCell>[
      (72, 240),
      (71, 240),
      (69, 240),
      (67, 240),
      (66, 240),
      (64, 240),
      (62, 240),
      (60, 240),
      (60, 720),
      (62, 240),
      (64, 240),
      (67, 720),
      (72, 120),
      (74, 120),
      (76, 120),
      (79, 120),
      (81, 360),
      (84, 960),
    ],
    'bass' => const <DemoCell>[
      (41, 480),
      (43, 480),
      (45, 480),
      (46, 480),
      (48, 480),
      (50, 480),
      (52, 480),
      (53, 480),
      (55, 960),
      (null, 480),
      (53, 480),
      (48, 960),
    ],
    'mixed' => const <DemoCell>[
      (43, 480),
      (45, 480),
      (47, 480),
      (48, 480),
      (50, 480),
      (52, 480),
      (55, 480),
      (57, 480),
      (60, 480),
      (72, 480),
      (74, 480),
      (76, 480),
      (79, 480),
      (81, 480),
      (84, 960),
    ],
    'chromatic' => const <DemoCell>[
      (61, 240),
      (62, 240),
      (64, 240),
      (65, 240),
      (66, 480),
      (67, 240),
      (65, 240),
      (64, 480),
      (70, 240),
      (69, 240),
      (67, 960),
    ],
    'accidentals' => const <DemoCell>[
      // F#5 在顶线上（升号压在谱线上）、F5 还原、F#4 在间里、C#5、C#4…
      (78, 480), (77, 480), (78, 480), (66, 480),
      (65, 480), (73, 480), (61, 480), (62, 960),
    ],
    'flats' => const <DemoCell>[
      // 调号 F：Ab4（间）、Gb4（线）、Gb5（顶线）、G5 还原…
      (68, 480), (68, 480), (67, 480), (66, 480),
      (78, 960), (79, 480), (77, 960),
    ],
    'rests' => const <DemoCell>[
      (60, 480),
      (null, 480),
      (62, 480),
      (null, 960),
      (64, 480),
      (65, 480),
      (null, 240),
      (67, 960),
    ],
    'sevenSharps' => const <DemoCell>[
      // C# 调（7 升号）：C#4/D#4/F#4/G#4/A#4/C#5/F#5，同小节内 F 还原需要 ♮。
      (61, 480), (63, 480), (66, 480), (68, 480), (70, 480), (73, 480),
      (78, 960),
      (65, 480), (64, 480), (60, 480), (62, 480), (67, 480), (69, 480),
      (71, 960),
    ],
    _ => throw ArgumentError('未知示例 $name（可用 ${staffDemoNames.join('/')}）'),
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
    keySignatureFifths: staffDemoKeyFifths[name] ?? 0,
    timeSignatureEvents: const <TimeSignatureEvent>[
      TimeSignatureEvent(tick: 0, numerator: 4, denominator: 4),
    ],
  );
}
