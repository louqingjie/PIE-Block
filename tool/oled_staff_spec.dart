// OLED 五线谱的共用定义：屏幕/位图、字形点阵、乐谱事件、时值、调号与音高映射。
//
// 该文件只放与“画布/乐理数据”有关的部分，渲染器与 CLI 在
// `tool/render_oled_staff.dart`。后续固件阶段会用同一份字形点阵与几何参数
// 生成 C 代码，所以这里的字形/映射要尽量保持可机械移植。
//
// 字形说明：谱号与拍号数字点阵由本机音乐符号字体离线栅格化后手工修补；
// 升/降/还原号、休止符、符头为手绘 1bit 点阵。仓库只提交点阵数据，不包含
// 任何字体文件。

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pieblock_core/pieblock_core.dart';

// ---------------------------------------------------------------------------
// 屏幕与帧缓冲
// ---------------------------------------------------------------------------

const int screenWidth = 128;
const int screenHeight = 64;
const int screenPages = screenHeight ~/ 8;
const int frameBytes = screenWidth * screenPages;

/// 1bit 位图；字节布局与 SSD1306 页寻址一致（bit0 = 页内最上一行）。
class Bitmap {
  Bitmap(this.width, this.height)
    : bytes = Uint8List(width * ((height + 7) ~/ 8));

  final int width, height;
  final Uint8List bytes;

  void setPixel(int x, int y, [bool on = true]) {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    final index = (y >> 3) * width + x;
    final mask = 1 << (y & 7);
    if (on) {
      bytes[index] |= mask;
    } else {
      bytes[index] &= ~mask;
    }
  }

  bool pixel(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return false;
    return (bytes[(y >> 3) * width + x] & (1 << (y & 7))) != 0;
  }

  void hLine(int x1, int x2, int y) {
    for (var x = math.min(x1, x2); x <= math.max(x1, x2); x++) {
      setPixel(x, y);
    }
  }

  void vLine(int x, int y1, int y2) {
    for (var y = math.min(y1, y2); y <= math.max(y1, y2); y++) {
      setPixel(x, y);
    }
  }

  void fillRect(int x, int y, int w, int h) {
    for (var yy = y; yy < y + h; yy++) {
      for (var xx = x; xx < x + w; xx++) {
        setPixel(xx, yy);
      }
    }
  }

  void strokeRect(int x, int y, int w, int h) {
    hLine(x, x + w - 1, y);
    hLine(x, x + w - 1, y + h - 1);
    vLine(x, y, y + h - 1);
    vLine(x + w - 1, y, y + h - 1);
  }
}

// ---------------------------------------------------------------------------
// 字形（1 = 着墨）
// ---------------------------------------------------------------------------

class Glyph {
  const Glyph(this.rows);

  final List<String> rows;

  int get width => rows.isEmpty ? 0 : rows.first.length;
  int get height => rows.length;

  void blit(Bitmap target, int x, int y) {
    for (var row = 0; row < rows.length; row++) {
      final line = rows[row];
      for (var col = 0; col < line.length; col++) {
        if (line[col] == '#') target.setPixel(x + col, y + row);
      }
    }
  }
}

/// 高音谱号（13×28）。放置：左端 x=1，上沿在谱表顶线上方 2px。
const Glyph trebleClefGlyph = Glyph(<String>[
  '......##.....',
  '.....####....',
  '.....#..#....',
  '.....#..#....',
  '.....#..#....',
  '.....#..#....',
  '.....###.....',
  '.....###.....',
  '....###......',
  '..#####......',
  '..###.#......',
  '.###..#......',
  '.##...####...',
  '##...######..',
  '#...########.',
  '#...##.#...#.',
  '#...#..#...#.',
  '##..#..#...#.',
  '.#......#..#.',
  '..#.....#.#..',
  '...#######...',
  '........#....',
  '........#....',
  '....##..##...',
  '....###.##...',
  '....###.#....',
  '.....###.....',
]);

/// 低音谱号（12×13，含右侧两个点）。
const Glyph bassClefGlyph = Glyph(<String>[
  '............',
  '...####.....',
  '.###..##....',
  '.##....##.##',
  '.#.....##.##',
  '.###...##...',
  '.####..##...',
  '..##...##.##',
  '.......#..##',
  '......##....',
  '....###.....',
  '.####.......',
]);

/// 升号（3×5，“井”字形；小尺寸下比 5×7 更干净）。
const Glyph sharpGlyph = Glyph(<String>[
  '.#.',
  '###',
  '.#.',
  '###',
  '.#.',
]);

/// 降号（4×7）。
const Glyph flatGlyph = Glyph(<String>[
  '#...',
  '#...',
  '#...',
  '#...',
  '###.',
  '#..#',
  '###.',
]);

/// 还原号（4×7）。
const Glyph naturalGlyph = Glyph(<String>[
  '#..#',
  '#..#',
  '####',
  '#..#',
  '####',
  '#..#',
  '#..#',
]);

/// 拍号数字（7×8）。
const Map<String, Glyph> digitGlyphs = <String, Glyph>{
  '0': Glyph(<String>[
    '..###..',
    '.##..#.',
    '.#...##',
    '.#.####',
    '####.##',
    '.##..##',
    '.#...#.',
    '..###..',
  ]),
  '1': Glyph(<String>[
    '..###..',
    '.#.##..',
    '...##..',
    '...##..',
    '...##..',
    '...##..',
    '...##..',
    '.#####.',
  ]),
  '2': Glyph(<String>[
    '..###..',
    '.#..##.',
    '.....#.',
    '....##.',
    '...##..',
    '..##...',
    '.##....',
    '.######',
  ]),
  '3': Glyph(<String>[
    '####..',
    '...##.',
    '...##.',
    '.###..',
    '...##.',
    '....#.',
    '...##.',
    '####..',
  ]),
  '4': Glyph(<String>[
    '...###.',
    '...###.',
    '..#.##.',
    '.##.##.',
    '.#..##.',
    '#######',
    '....##.',
    '....##.',
  ]),
  '5': Glyph(<String>[
    '#####.',
    '#.....',
    '#.....',
    '####..',
    '...##.',
    '....#.',
    '...##.',
    '####..',
  ]),
  '6': Glyph(<String>[
    '...###.',
    '.##....',
    '.#.....',
    '.#####.',
    '.##..#.',
    '.#...##',
    '.##..#.',
    '..###..',
  ]),
  '7': Glyph(<String>[
    '.#####.',
    '.....#.',
    '....##.',
    '....#..',
    '...##..',
    '...#...',
    '..##...',
    '..#....',
  ]),
  '8': Glyph(<String>[
    '..####.',
    '.#...#.',
    '.##.##.',
    '..###..',
    '.##.##.',
    '.#...#.',
    '.#...#.',
    '..####.',
  ]),
  '9': Glyph(<String>[
    '..###..',
    '.#...#.',
    '.#...#.',
    '.#..##.',
    '.#####.',
    '.....#.',
    '....##.',
    '.####..',
  ]),
};

/// 符头：实心 / 空心（4×3）。
const Glyph noteHeadFilled = Glyph(<String>['.##.', '####', '.##.']);
const Glyph noteHeadHollow = Glyph(<String>['.##.', '#..#', '.##.']);

/// 休止符。
const Glyph restWholeGlyph = Glyph(<String>['#####', '#####']);
const Glyph restHalfGlyph = Glyph(<String>['#####', '#####']);
const Glyph restQuarterGlyph = Glyph(<String>[
  '.##',
  '#..',
  '.#.',
  '..#',
  '.#.',
  '#..',
]);
const Glyph restEighthGlyph = Glyph(<String>['.#', '#.', '.#', '.#']);
const Glyph restSixteenthGlyph = Glyph(<String>['.#', '#.', '.#', '.#', '.#']);

// ---------------------------------------------------------------------------
// PNG 输出（8bit 灰度，不依赖第三方包）
// ---------------------------------------------------------------------------

Uint8List encodePngGray(int width, int height, Uint8List gray) {
  if (gray.length != width * height) {
    throw ArgumentError('灰度数据长度应为 ${width * height}');
  }
  final raw = Uint8List(height * (width + 1));
  for (var y = 0; y < height; y++) {
    final dst = y * (width + 1);
    raw[dst] = 0; // filter: none
    raw.setRange(dst + 1, dst + 1 + width, gray, y * width);
  }
  final compressed = ZLibCodec(level: 9).encode(raw);
  final out = BytesBuilder(copy: false);
  out.add(const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final typeBytes = ascii.encode(type);
    final length = ByteData(4)..setUint32(0, data.length);
    out.add(length.buffer.asUint8List());
    out.add(typeBytes);
    out.add(data);
    final crc = ByteData(4)..setUint32(0, _crc32(<int>[...typeBytes, ...data]));
    out.add(crc.buffer.asUint8List());
  }

  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 0) // grayscale
    ..setUint8(10, 0) // compression
    ..setUint8(11, 0) // filter
    ..setUint8(12, 0); // interlace
  chunk('IHDR', header.buffer.asUint8List());
  chunk('IDAT', compressed);
  chunk('IEND', const <int>[]);
  return out.toBytes();
}

Uint32List? _crcTable;

int _crc32(List<int> data) {
  final table = _crcTable ??= () {
    final result = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
      }
      result[n] = c;
    }
    return result;
  }();
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc = table[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// 把 1bit 位图放大 [scale] 倍并转成 8bit 灰度（255=亮）。
Uint8List bitmapToGray(Bitmap bitmap, {int scale = 1, int margin = 0}) {
  final width = (bitmap.width + margin * 2) * scale;
  final height = (bitmap.height + margin * 2) * scale;
  final gray = Uint8List(width * height);
  for (var y = 0; y < bitmap.height; y++) {
    for (var x = 0; x < bitmap.width; x++) {
      if (!bitmap.pixel(x, y)) continue;
      final left = (x + margin) * scale;
      final top = (y + margin) * scale;
      for (var dy = 0; dy < scale; dy++) {
        final row = (top + dy) * width;
        for (var dx = 0; dx < scale; dx++) {
          gray[row + left + dx] = 255;
        }
      }
    }
  }
  return gray;
}

/// 在 8bit 灰度画布上叠加字形（用于对比图的帧号）。
void blitGlyphGray(
  Uint8List canvas,
  int canvasWidth,
  int canvasHeight,
  Glyph glyph,
  int x,
  int y,
  int scale,
) {
  for (var row = 0; row < glyph.height; row++) {
    for (var col = 0; col < glyph.width; col++) {
      if (glyph.rows[row][col] != '#') continue;
      for (var dy = 0; dy < scale; dy++) {
        final py = y + row * scale + dy;
        if (py < 0 || py >= canvasHeight) continue;
        for (var dx = 0; dx < scale; dx++) {
          final px = x + col * scale + dx;
          if (px < 0 || px >= canvasWidth) continue;
          canvas[py * canvasWidth + px] = 255;
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// 乐谱解析：与蜂鸣器同源（MusicTimeline.soundingSpans）
// ---------------------------------------------------------------------------

class ScoreEvent {
  const ScoreEvent({
    required this.startTick,
    required this.durationTicks,
    this.pitch,
  });

  final int startTick;
  final int durationTicks;
  final int? pitch;

  bool get isRest => pitch == null;
  int get endTick => startTick + durationTicks;

  @override
  String toString() => isRest
      ? 'rest@$startTick+$durationTicks'
      : '$pitch@$startTick+$durationTicks';
}

/// 乐谱事件：发声区间按 `soundingSpans` 解析，区间之间的空白拆成休止符事件。
List<ScoreEvent> buildScore(MusicConfig config) {
  final spans = MusicTimeline.soundingSpans(config);
  final events = <ScoreEvent>[];
  var cursor = 0;
  for (final span in spans) {
    if (span.startTick > cursor) {
      events.addAll(_splitRest(cursor, span.startTick - cursor, config));
    }
    events.add(
      ScoreEvent(
        startTick: span.startTick,
        durationTicks: span.durationTicks,
        pitch: span.pitch,
      ),
    );
    cursor = span.endTick;
  }
  return events;
}

/// 休止区间按“最大标准休止符优先”拆分。
List<ScoreEvent> _splitRest(int startTick, int durationTicks, MusicConfig config) {
  const standardBeats = <double>[4, 3, 2, 1.5, 1, 0.75, 0.5, 0.25];
  final result = <ScoreEvent>[];
  var remaining = durationTicks;
  var tick = startTick;
  final minimumTicks = math.max(1, (config.ticksPerQuarter * 0.25).round());
  while (remaining > 0) {
    if (remaining < minimumTicks) {
      result.add(ScoreEvent(startTick: tick, durationTicks: remaining));
      break;
    }
    var chosen = standardBeats.last;
    for (final beats in standardBeats) {
      final ticks = (beats * config.ticksPerQuarter).round();
      if (ticks <= remaining) {
        chosen = beats;
        break;
      }
    }
    var ticks = (chosen * config.ticksPerQuarter).round();
    if (ticks <= 0) ticks = remaining;
    result.add(ScoreEvent(startTick: tick, durationTicks: ticks));
    tick += ticks;
    remaining -= ticks;
  }
  return result;
}

// ---------------------------------------------------------------------------
// 时值：tick → 标准音符时值
// ---------------------------------------------------------------------------

class NoteValue {
  const NoteValue(this.denominator, this.dots);

  /// 1=全音符、2=二分、4=四分、8=八分、16=十六分。
  final int denominator;
  final int dots;

  double get beats => (4.0 / denominator) * (dots == 1 ? 1.5 : 1);
  bool get hollow => denominator <= 2;
  bool get hasStem => denominator > 1;
  int get flagCount => denominator == 8 ? 1 : denominator == 16 ? 2 : 0;

  @override
  String toString() => '1/$denominator${dots == 1 ? '.' : ''}';
}

const List<NoteValue> _noteValueCandidates = <NoteValue>[
  NoteValue(1, 0),
  NoteValue(2, 1),
  NoteValue(2, 0),
  NoteValue(4, 1),
  NoteValue(4, 0),
  NoteValue(8, 1),
  NoteValue(8, 0),
  NoteValue(16, 1),
  NoteValue(16, 0),
];

/// 按拍数取最近的标准时值；approx 表示发生了取整（如三连音）。
({NoteValue value, bool approx}) noteValueForBeats(double beats) {
  var best = _noteValueCandidates.first;
  var bestDistance = double.infinity;
  for (final candidate in _noteValueCandidates) {
    final distance = (candidate.beats - beats).abs();
    if (distance < bestDistance - 1e-9) {
      best = candidate;
      bestDistance = distance;
    }
  }
  return (value: best, approx: bestDistance > 1e-6);
}

NoteValue noteValueForEvent(ScoreEvent event, MusicConfig config) =>
    noteValueForBeats(event.durationTicks / config.ticksPerQuarter).value;

// ---------------------------------------------------------------------------
// 调号与音高拼写
// ---------------------------------------------------------------------------

const Map<String, int> keyFifthsByName = <String, int>{
  'C': 0,
  'G': 1,
  'D': 2,
  'A': 3,
  'E': 4,
  'B': 5,
  'F#': 6,
  'C#': 7,
  'F': -1,
  'Bb': -2,
  'Eb': -3,
  'Ab': -4,
  'Db': -5,
  'Gb': -6,
  'Cb': -7,
  'Am': 0,
  'Em': 1,
  'Bm': 2,
  'F#m': 3,
  'C#m': 4,
  'G#m': 5,
  'D#m': 6,
  'A#m': 7,
  'Dm': -1,
  'Gm': -2,
  'Cm': -3,
  'Fm': -4,
  'Bbm': -5,
  'Ebm': -6,
  'Abm': -7,
};

int keyFifths(String key) {
  final fifths = keyFifthsByName[key];
  if (fifths == null) {
    throw ArgumentError(
      '不支持的调号 $key；可用：${keyFifthsByName.keys.join(' / ')}',
    );
  }
  return fifths;
}

/// 音名（0=C…6=B）对应的自然音半音。
const List<int> letterSemitones = <int>[0, 2, 4, 5, 7, 9, 11];

const List<int> sharpOrderLetters = <int>[3, 0, 4, 1, 5, 2, 6];
const List<int> flatOrderLetters = <int>[6, 2, 5, 1, 4, 0, 3];

const List<int> trebleSharpSteps = <int>[8, 5, 9, 6, 3, 7, 4];
const List<int> trebleFlatSteps = <int>[4, 7, 3, 6, 2, 5, 1];
const List<int> bassSharpSteps = <int>[6, 3, 7, 4, 1, 5, 2];
const List<int> bassFlatSteps = <int>[2, 5, 1, 4, 0, 3, -1];

int keyAlterationForLetter(int letter, int fifths) {
  if (fifths > 0 && sharpOrderLetters.indexOf(letter) < fifths) return 1;
  if (fifths < 0 && flatOrderLetters.indexOf(letter) < -fifths) return -1;
  return 0;
}

class PitchSpelling {
  const PitchSpelling(this.letter, this.octave, this.alteration);

  final int letter, octave, alteration;

  int get id => (letter << 4) | octave;

  String get name {
    const letterNames = 'CDEFGAB';
    final suffix = alteration == 1
        ? '#'
        : alteration == -1
        ? 'b'
        : '';
    return '${letterNames[letter]}$suffix$octave';
  }
}

/// MIDI 音高按调号倾向拼写（降号调优先用降号拼写）。
PitchSpelling spellPitch(int pitch, int fifths) {
  const sharpLetters = <int>[0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6];
  const sharpAlterations = <int>[0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0];
  const flatLetters = <int>[0, 1, 1, 2, 2, 3, 4, 4, 5, 5, 6, 6];
  const flatAlterations = <int>[0, -1, 0, -1, 0, 0, -1, 0, -1, 0, -1, 0];
  final preferFlat = fifths < 0;
  final pc = pitch % 12;
  final letter = (preferFlat ? flatLetters : sharpLetters)[pc];
  final alteration = (preferFlat ? flatAlterations : sharpAlterations)[pc];
  final naturalTick = letterSemitones[letter];
  final octave = ((pitch - alteration - naturalTick) ~/ 12) - 1;
  return PitchSpelling(letter, octave, alteration);
}

// ---------------------------------------------------------------------------
// 音高 → 谱表纵坐标
// ---------------------------------------------------------------------------

const List<int> _pitchClassLetterStep = <int>[0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6];

/// 全音阶序号（C4 = 28，E4 = 30，G2 = 18 …）。
int diatonicIndex(int pitch) {
  final octave = pitch ~/ 12 - 1;
  return octave * 7 + _pitchClassLetterStep[pitch % 12];
}

const int trebleBottomLineDiatonic = 30; // E4
const int bassBottomLineDiatonic = 18; // G2

int clefBottomDiatonic(String clef) =>
    clef == 'bass' ? bassBottomLineDiatonic : trebleBottomLineDiatonic;

/// 谱表底线（最下面那条线）的 y。
int staffBottomY(int staffTop, int space) => staffTop + 4 * space;

/// 符头中心的 y；越界音高会算到屏幕外，由调用方裁剪。
int pitchY(int pitch, String clef, int space, int staffTop) {
  final step = diatonicIndex(pitch) - clefBottomDiatonic(clef);
  return staffBottomY(staffTop, space) - (step * space ~/ 2);
}

/// 需要画的加线数量（0 = 谱表内）。
int ledgerCountForPitch(int pitch, String clef) {
  final step = diatonicIndex(pitch) - clefBottomDiatonic(clef);
  if (step > 8) return (step - 8) ~/ 2;
  if (step < 0) return (-step) ~/ 2;
  return 0;
}

/// 音符相对谱表中线的半格位置（负数=偏下），用于决定符干方向。
int halfSpaceOffset(int pitch, String clef) =>
    diatonicIndex(pitch) - clefBottomDiatonic(clef) - 4;
