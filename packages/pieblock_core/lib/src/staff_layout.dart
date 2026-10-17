/// 五线谱版面：纯整数几何。Dart 模拟器与固件 C 渲染器必须使用同一套公式，
/// 主机对拍测试会逐字节比较两边的 128×64 帧。
library;

import 'staff_notation.dart';

const int staffScreenWidth = 128;
const int staffScreenHeight = 64;
const int staffSpace = 6;
const int staffTop = 14;
const int staffPxPerQuarter = 16;
const int staffMinNoteGap = 6;
const int staffPanelGutter = 6;
const int staffClefWidth = 13;
const int staffTimeDigitWidth = 7;

/// 谱表底线（最下面一条线）的 y。
int staffBottomLineY() => staffTop + 4 * staffSpace;

/// 符头中心 / 调号符号中心 / 加线的 y（[step] 相对谱号底线）。
int staffYForStep(int step) => staffBottomLineY() - (step * staffSpace ~/ 2);

/// 左端固定区宽度：谱号 + 调号 + 拍号。
int staffPanelWidth({required int keyCount, required int timeDigits}) =>
    1 +
    staffClefWidth +
    1 +
    6 * keyCount +
    2 +
    staffTimeDigitWidth * timeDigits +
    (timeDigits - 1) +
    1;

/// 滚动内容从这里开始：固定区外再留 6px 隔离带（只有谱线）。
int staffNoteAreaStart({required int keyCount, required int timeDigits}) =>
    staffPanelWidth(keyCount: keyCount, timeDigits: timeDigits) +
    staffPanelGutter;

/// 当前音符中心的 x；固定区/隔离带之后滚动区的 30%。
int staffCursorX(int noteAreaStart) =>
    noteAreaStart + ((staffScreenWidth - noteAreaStart) * 3 ~/ 10);

/// 与 Dart `double.round()` 等价的“半值远离 0”整数除法。
int staffRoundDiv(int numerator, int denominator) {
  if (denominator == 0) return 0;
  if (denominator < 0) {
    numerator = -numerator;
    denominator = -denominator;
  }
  if (numerator >= 0) return (numerator + denominator ~/ 2) ~/ denominator;
  return -((-numerator + denominator ~/ 2) ~/ denominator);
}

/// 拍号数字位数（分子/分母取较大位数）。
int staffTimeDigitCount(int numerator, int denominator) {
  final n = '$numerator'.length;
  final d = '$denominator'.length;
  return n > d ? n : d;
}

/// 事件 i 与 i-1 之间是否换谱号（i=0 时为 false）。
bool staffClefChangeAt(StaffSongData song, int index) =>
    index > 0 && song.events[index].clef != song.events[index - 1].clef;

/// 事件在滚动区排布时的最小推进量（像素）。
int staffAdvanceFor(StaffEventData event, {required bool clefChange}) {
  var width = event.isRest ? 7 : staffMinNoteGap;
  if (event.accidental != 0) width += 4;
  if (clefChange) width += 16;
  return width;
}

/// 计算每一帧中所有事件的符头中心 x（整数像素）。
///
/// 当前事件固定在光标处，其余先按 tick 比例排布，再按最小间距前/后扫描，
/// 防止 16 分音符符头重叠。公式与固件 `StaffRender.c` 完全一致。
List<int> staffLayoutX(StaffSongData song, int index) {
  final keyCount = song.keyCount;
  final timeDigits = staffTimeDigitCount(
    song.timeNumerator,
    song.timeDenominator,
  );
  final noteAreaStart = staffNoteAreaStart(
    keyCount: keyCount,
    timeDigits: timeDigits,
  );
  final cursorX = staffCursorX(noteAreaStart);
  final playTick = _startTickOf(song, index);
  final xs = List<int>.filled(song.events.length, 0);
  for (var i = 0; i < song.events.length; i++) {
    final delta = _startTickOf(song, i) - playTick;
    xs[i] =
        cursorX +
        staffRoundDiv(delta * staffPxPerQuarter, song.ticksPerQuarter);
  }
  xs[index] = cursorX;
  var previous = cursorX;
  for (var i = index + 1; i < song.events.length; i++) {
    final minimum =
        previous +
        staffAdvanceFor(song.events[i], clefChange: staffClefChangeAt(song, i));
    if (xs[i] < minimum) xs[i] = minimum;
    previous = xs[i];
  }
  previous = cursorX;
  for (var i = index - 1; i >= 0; i--) {
    final maximum =
        previous -
        staffAdvanceFor(
          song.events[i + 1],
          clefChange: staffClefChangeAt(song, i + 1),
        );
    if (xs[i] > maximum) xs[i] = maximum;
    previous = xs[i];
  }
  return xs;
}

int _startTickOf(StaffSongData song, int index) {
  var tick = 0;
  for (var i = 0; i < index; i++) {
    tick += song.events[i].tickDuration;
  }
  return tick;
}

/// 当前事件在整首曲子中的起始 tick（外部调试/测试用）。
int staffStartTickOf(StaffSongData song, int index) =>
    _startTickOf(song, index);

/// 可见的小节线 x 列表；与固件同一公式（只返回落在滚动区内的线）。
List<int> staffBarLineXs(StaffSongData song, int index) {
  final barTicks = song.barTicks;
  if (barTicks <= 0) return const <int>[];
  final keyCount = song.keyCount;
  final timeDigits = staffTimeDigitCount(
    song.timeNumerator,
    song.timeDenominator,
  );
  final noteAreaStart = staffNoteAreaStart(
    keyCount: keyCount,
    timeDigits: timeDigits,
  );
  final cursorX = staffCursorX(noteAreaStart);
  final playTick = _startTickOf(song, index);
  final result = <int>[];
  final firstBar = playTick ~/ barTicks;
  final maxTick =
      playTick +
      ((staffScreenWidth / staffPxPerQuarter) * song.ticksPerQuarter).ceil();
  for (var bar = firstBar; ; bar++) {
    final tick = bar * barTicks;
    if (tick < barTicks) continue;
    if (tick > maxTick) break;
    final x =
        cursorX +
        staffRoundDiv(
          (tick - playTick) * staffPxPerQuarter,
          song.ticksPerQuarter,
        );
    if (x < noteAreaStart || x >= staffScreenWidth) continue;
    result.add(x);
  }
  return result;
}
