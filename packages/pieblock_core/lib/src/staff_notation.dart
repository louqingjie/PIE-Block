/// 五线谱显示模型：把 [MusicConfig] 解析成固件/模拟器共用的显示事件。
///
/// 这是“画面与蜂鸣器同源”的落点：
/// - 发声区间来自 [MusicTimeline.soundingSpans]（与固件音乐段、卷帘灰色显示一致）；
/// - 区间之间的空白按标准时值拆成休止符；
/// - 每个事件预先算好固件渲染需要的一切：谱号、相对谱号底线的全音阶步数
///   （已按调号拼写）、临时记号、时值编码、毫秒时长。这样 C 渲染器只做几何，
///   不需要在单片机上重做乐理判断。
library;

import 'dart:math' as math;

import 'models.dart';
import 'music.dart';
import 'staff_glyphs.dart';

// ---------------------------------------------------------------------------
// 调号
// ---------------------------------------------------------------------------

/// 调号升/降号个数的合法范围（15 个大调 / 15 个关系小调）。
const int staffKeyFifthsMin = -7;
const int staffKeyFifthsMax = 7;

/// 编辑器下拉用的调号选项（标签同时给出大调与关系小调）。
const List<({int fifths, String label})> staffKeySignatureOptions =
    <({int fifths, String label})>[
      (fifths: 0, label: 'C 大调 / A 小调'),
      (fifths: 1, label: 'G 大调 / E 小调'),
      (fifths: 2, label: 'D 大调 / B 小调'),
      (fifths: 3, label: 'A 大调 / F♯ 小调'),
      (fifths: 4, label: 'E 大调 / C♯ 小调'),
      (fifths: 5, label: 'B 大调 / G♯ 小调'),
      (fifths: 6, label: 'F♯ 大调 / D♯ 小调'),
      (fifths: 7, label: 'C♯ 大调 / A♯ 小调'),
      (fifths: -1, label: 'F 大调 / D 小调'),
      (fifths: -2, label: 'B♭ 大调 / G 小调'),
      (fifths: -3, label: 'E♭ 大调 / C 小调'),
      (fifths: -4, label: 'A♭ 大调 / F 小调'),
      (fifths: -5, label: 'D♭ 大调 / B♭ 小调'),
      (fifths: -6, label: 'G♭ 大调 / E♭ 小调'),
      (fifths: -7, label: 'C♭ 大调 / A♭ 小调'),
    ];

String staffKeyLabelForFifths(int fifths) {
  for (final option in staffKeySignatureOptions) {
    if (option.fifths == fifths) return option.label;
  }
  return 'C 大调 / A 小调';
}

const Map<String, int> staffKeyFifthsByName = <String, int>{
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

int staffKeyFifths(String key) {
  final fifths = staffKeyFifthsByName[key];
  if (fifths == null) {
    throw ArgumentError(
      '不支持的调号 $key；可用：${staffKeyFifthsByName.keys.join(' / ')}',
    );
  }
  return fifths;
}

const List<int> letterSemitones = <int>[0, 2, 4, 5, 7, 9, 11];
const List<int> sharpOrderLetters = <int>[3, 0, 4, 1, 5, 2, 6];
const List<int> flatOrderLetters = <int>[6, 2, 5, 1, 4, 0, 3];

const List<int> trebleSharpSteps = <int>[8, 5, 9, 6, 3, 7, 4];
const List<int> trebleFlatSteps = <int>[4, 7, 3, 6, 2, 5, 1];
const List<int> bassSharpSteps = <int>[6, 3, 7, 4, 1, 5, 2];
const List<int> bassFlatSteps = <int>[2, 5, 1, 4, 0, 3, -1];

List<int> staffKeyStepsForClef(int fifths, {required bool bass}) {
  final table = bass
      ? (fifths >= 0 ? bassSharpSteps : bassFlatSteps)
      : (fifths >= 0 ? trebleSharpSteps : trebleFlatSteps);
  return table.take(fifths.abs()).toList(growable: false);
}

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
// 音高 → 谱表步数
// ---------------------------------------------------------------------------

const int trebleBottomLineDiatonic = 30; // E4
const int bassBottomLineDiatonic = 18; // G2

/// 谱号底线（最下面一条线）对应的全音阶序号。
int clefBottomDiatonic(int clef) =>
    clef == 1 ? bassBottomLineDiatonic : trebleBottomLineDiatonic;

/// 按调号拼写后的全音阶序号（C4 = 28，E4 = 30，G2 = 18 …）。
int spelledDiatonicIndex(int pitch, int fifths) {
  final spelling = spellPitch(pitch, fifths);
  return spelling.octave * 7 + spelling.letter;
}

/// 符头相对谱号底线的步数（0 = 底线；正数向上）。
int staffStepForPitch(int pitch, int clef, int fifths) =>
    spelledDiatonicIndex(pitch, fifths) - clefBottomDiatonic(clef);

/// 需要画的加线数量（0 = 谱表内）。
int staffLedgerCountForStep(int step) {
  if (step > 8) return (step - 8) ~/ 2;
  if (step < 0) return (-step) ~/ 2;
  return 0;
}

/// 符干方向：中线以下向上（返回 true）。
bool staffStemUpForStep(int step) => step - 4 < 0;

// ---------------------------------------------------------------------------
// 时值
// ---------------------------------------------------------------------------

class StaffNoteValue {
  const StaffNoteValue(this.denominator, this.dots, this.code);

  /// 1=全音符、2=二分、4=四分、8=八分、16=十六分。
  final int denominator;
  final int dots;

  /// 固件里的紧凑编码；C 侧 `StaffRender.h` 使用同一组数值。
  final int code;

  double get beats => (4.0 / denominator) * (dots == 1 ? 1.5 : 1);
  bool get hollow => denominator <= 2;
  bool get hasStem => denominator > 1;
  int get flagCount => denominator == 8
      ? 1
      : denominator == 16
      ? 2
      : 0;

  @override
  String toString() => '1/$denominator${dots == 1 ? '.' : ''}';
}

const List<StaffNoteValue> _noteValueCandidates = <StaffNoteValue>[
  StaffNoteValue(1, 0, 0),
  StaffNoteValue(2, 1, 2),
  StaffNoteValue(2, 0, 1),
  StaffNoteValue(4, 1, 4),
  StaffNoteValue(4, 0, 3),
  StaffNoteValue(8, 1, 6),
  StaffNoteValue(8, 0, 5),
  StaffNoteValue(16, 1, 8),
  StaffNoteValue(16, 0, 7),
];

/// 按拍数取最近的标准时值；`approx` 表示发生了取整（如三连音）。
({StaffNoteValue value, bool approx}) staffNoteValueForBeats(double beats) {
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

StaffNoteValue staffNoteValueForCode(int code) =>
    _noteValueCandidates.firstWhere((value) => value.code == code);

// ---------------------------------------------------------------------------
// 乐谱事件：发声区间 + 休止拆分
// ---------------------------------------------------------------------------

class StaffScoreEvent {
  const StaffScoreEvent({
    required this.startTick,
    required this.durationTicks,
    this.pitch,
  });

  final int startTick;
  final int durationTicks;

  /// null = 休止符。
  final int? pitch;

  bool get isRest => pitch == null;
  int get endTick => startTick + durationTicks;
}

List<StaffScoreEvent> buildStaffScoreEvents(MusicConfig config) {
  final spans = MusicTimeline.soundingSpans(config);
  final events = <StaffScoreEvent>[];
  var cursor = 0;
  for (final span in spans) {
    if (span.startTick > cursor) {
      events.addAll(
        _splitRestEvents(
          cursor,
          span.startTick - cursor,
          config.ticksPerQuarter,
        ),
      );
    }
    events.add(
      StaffScoreEvent(
        startTick: span.startTick,
        durationTicks: span.durationTicks,
        pitch: span.pitch,
      ),
    );
    cursor = span.endTick;
  }
  return events;
}

List<StaffScoreEvent> _splitRestEvents(
  int startTick,
  int durationTicks,
  int ticksPerQuarter,
) {
  const standardBeats = <double>[4, 3, 2, 1.5, 1, 0.75, 0.5, 0.25];
  final result = <StaffScoreEvent>[];
  var remaining = durationTicks;
  var tick = startTick;
  final minimumTicks = math.max(1, (ticksPerQuarter * 0.25).round());
  while (remaining > 0) {
    if (remaining < minimumTicks) {
      result.add(StaffScoreEvent(startTick: tick, durationTicks: remaining));
      break;
    }
    var chosen = standardBeats.last;
    for (final beats in standardBeats) {
      final ticks = (beats * ticksPerQuarter).round();
      if (ticks <= remaining) {
        chosen = beats;
        break;
      }
    }
    var ticks = (chosen * ticksPerQuarter).round();
    if (ticks <= 0) ticks = remaining;
    result.add(StaffScoreEvent(startTick: tick, durationTicks: ticks));
    tick += ticks;
    remaining -= ticks;
  }
  return result;
}

// ---------------------------------------------------------------------------
// 谱号分配（单谱表自动换谱号）
// ---------------------------------------------------------------------------

/// 顺序遍历事件分配谱号（3 个音符前瞻 + 迟滞）：同一个音符的谱号不随播放
/// 位置改变；换谱号时固件在滚动区画一个小谱号。
List<int> assignStaffClefs(
  List<StaffScoreEvent> events, {
  required int fifths,
  int? forcedClef,
}) {
  if (forcedClef != null && (forcedClef == 0 || forcedClef == 1)) {
    return List<int>.filled(events.length, forcedClef);
  }
  final result = List<int>.filled(events.length, 0);
  int cost(int index, int clef) {
    var maxLedger = 0;
    var seen = 0;
    for (var i = index; i < events.length && seen < 3; i++) {
      final event = events[i];
      if (event.isRest) continue;
      final step = staffStepForPitch(event.pitch!, clef, fifths);
      maxLedger = math.max(maxLedger, staffLedgerCountForStep(step));
      seen++;
    }
    return maxLedger;
  }

  var current = 0;
  var firstIndex = 0;
  while (firstIndex < events.length && events[firstIndex].isRest) {
    firstIndex++;
  }
  if (firstIndex < events.length) {
    current = cost(firstIndex, 0) <= cost(firstIndex, 1) ? 0 : 1;
  }
  for (var i = 0; i < events.length; i++) {
    if (!events[i].isRest) {
      final other = 1 - current;
      if (cost(i, other) <= cost(i, current) - 2) current = other;
    }
    result[i] = current;
  }
  return result;
}

// ---------------------------------------------------------------------------
// 显示事件 / 显示歌曲
// ---------------------------------------------------------------------------

/// 供固件 C 渲染器使用的紧凑事件。字段与 `StaffRender.h` 的 SoA 表一一对应。
class StaffEventData {
  const StaffEventData({
    required this.tickDuration,
    required this.durationMs,
    required this.pitch,
    required this.step,
    required this.clef,
    required this.accidental,
    required this.noteValue,
  });

  /// 本事件占用的 tick 数（事件首尾相接，C 侧用累加得到 startTick）。
  final int tickDuration;

  /// 蜂鸣器/等待使用的毫秒时长（≥1）。
  final int durationMs;

  /// MIDI 音高；0 = 休止符。
  final int pitch;

  /// 相对谱号底线的全音阶步数（已按调号拼写；休止符为 0）。
  final int step;

  /// 0 = 高音谱号，1 = 低音谱号。
  final int clef;

  /// 0 = 无，1 = ♯，2 = ♭，3 = ♮。
  final int accidental;

  final StaffNoteValue noteValue;

  bool get isRest => pitch == 0;
}

class StaffSongData {
  const StaffSongData({
    required this.keyFifths,
    required this.ticksPerQuarter,
    required this.timeNumerator,
    required this.timeDenominator,
    required this.keyStepsTreble,
    required this.keyStepsBass,
    required this.events,
  });

  final int keyFifths;
  final int ticksPerQuarter;
  final int timeNumerator;
  final int timeDenominator;

  /// 调号每个升降号在谱表上的步数（相对底线，不含谱号偏移）。
  final List<int> keyStepsTreble;
  final List<int> keyStepsBass;

  final List<StaffEventData> events;

  int get keyCount => keyFifths.abs();

  bool get keyIsSharp => keyFifths >= 0;

  /// 一小节的 tick 数（与模拟器/固件同一公式）。
  int get barTicks =>
      (ticksPerQuarter * 4 ~/ math.max(1, timeDenominator)) *
      math.max(1, timeNumerator);
}

/// 把 [MusicConfig] 解析成固件/模拟器共用的显示歌曲。
StaffSongData buildStaffSong(MusicConfig config) {
  final fifths = config.keySignatureFifths.clamp(
    staffKeyFifthsMin,
    staffKeyFifthsMax,
  );
  final ticksPerQuarter = math.max(1, config.ticksPerQuarter);
  final scoreEvents = buildStaffScoreEvents(config);
  final clefs = assignStaffClefs(scoreEvents, fifths: fifths);
  final barTicks =
      (ticksPerQuarter * 4 ~/ math.max(1, _firstDenominator(config))) *
      math.max(1, _firstNumerator(config));
  final measureAlterations = <int, int>{};
  var currentMeasure = -1;

  final events = <StaffEventData>[];
  for (var i = 0; i < scoreEvents.length; i++) {
    final event = scoreEvents[i];
    final noteValue = staffNoteValueForBeats(
      event.durationTicks / ticksPerQuarter,
    ).value;
    final startMicros = MusicTimeline.microsecondsAtTick(
      config,
      event.startTick,
    );
    final endMicros = MusicTimeline.microsecondsAtTick(config, event.endTick);
    final durationMs = math.max(1, ((endMicros - startMicros) / 1000).round());
    if (event.isRest) {
      events.add(
        StaffEventData(
          tickDuration: event.durationTicks,
          durationMs: durationMs,
          pitch: 0,
          step: 0,
          clef: clefs[i],
          accidental: 0,
          noteValue: noteValue,
        ),
      );
      continue;
    }
    final spelling = spellPitch(event.pitch!, fifths);
    final measure = barTicks <= 0 ? 0 : event.startTick ~/ barTicks;
    if (measure != currentMeasure) {
      measureAlterations.clear();
      currentMeasure = measure;
    }
    final keyAlteration = keyAlterationForLetter(spelling.letter, fifths);
    final previous = measureAlterations[spelling.id] ?? keyAlteration;
    final accidental = spelling.alteration == previous
        ? 0
        : spelling.alteration == 0
        ? 3
        : spelling.alteration > 0
        ? 1
        : 2;
    measureAlterations[spelling.id] = spelling.alteration;
    events.add(
      StaffEventData(
        tickDuration: event.durationTicks,
        durationMs: durationMs,
        pitch: event.pitch!,
        step: staffStepForPitch(event.pitch!, clefs[i], fifths),
        clef: clefs[i],
        accidental: accidental,
        noteValue: noteValue,
      ),
    );
  }

  return StaffSongData(
    keyFifths: fifths,
    ticksPerQuarter: ticksPerQuarter,
    timeNumerator: _firstNumerator(config),
    timeDenominator: _firstDenominator(config),
    keyStepsTreble: staffKeyStepsForClef(fifths, bass: false),
    keyStepsBass: staffKeyStepsForClef(fifths, bass: true),
    events: List.unmodifiable(events),
  );
}

int _firstNumerator(MusicConfig config) => config.timeSignatureEvents.isEmpty
    ? 4
    : config.timeSignatureEvents.first.numerator;

int _firstDenominator(MusicConfig config) => config.timeSignatureEvents.isEmpty
    ? 4
    : config.timeSignatureEvents.first.denominator;

/// 便携访问字形表（模拟器与代码生成器共用）。
StaffGlyph staffGlyphById(StaffGlyphId id) => staffGlyphList[id.index];
