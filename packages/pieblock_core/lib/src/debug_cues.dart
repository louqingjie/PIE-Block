/// 调试模式提示音曲谱：固件生成器与 Flutter 端试听共用同一份数据。
///
/// 方案说明见 docs/design/调试模式提示音方案.md。三通道编码：
/// - 事件层用旋律轮廓区分：READY 上行、DONE 下行、全部完成从低音区起音；
/// - 步序层用「音区（八度）+ 点数（<=5）」双通道冗余编码，
///   音区表示十位、点数表示个位；
/// - 摩擦轮斜坡扫频（频率跟随占空比）编码连续过程量，由固件单独处理，
///   不在此列。
///
/// 音高取十二平均律 A4=440Hz，与 _music 生成器的 MIDI 频率表同源；
/// 全部落在无源蜂鸣器的有效响应区，避开旧版 500Hz 平音所在的弱区。
library;

/// 提示音里的一段音：[frequencyHz] 为 null 表示静音间隔。
class DebugCueNote {
  const DebugCueNote(this.frequencyHz, this.durationMs);

  final int? frequencyHz;
  final int durationMs;
}

/// 提示音风格。[standard] 是默认；[compact] 压缩时值，供 durationMs 很短
/// 的调试序列使用，避免提示音喧宾夺主。
enum DebugCueStyle {
  standard('标准'),
  compact('紧凑');

  const DebugCueStyle(this.label);

  final String label;
}

abstract final class DebugCues {
  /// 步序码单个音区覆盖的项数（人类可靠计数约 4~5 声，故取 5）。
  static const int zoneSpan = 5;

  static const int noteC5 = 523;
  static const int noteE5 = 659;
  static const int noteG5 = 784;
  static const int noteC6 = 1047;
  static const int noteE6 = 1319;
  static const int noteG6 = 1568;

  /// 低音区（步 1~5）。
  static const int zoneLow = noteG5;

  /// 高音区（步 6 起），与低音区正好差一个八度。
  static const int zoneHigh = noteG6;

  static int _unit(DebugCueStyle style) => style == DebugCueStyle.compact ? 60 : 110;

  static int _gap(DebugCueStyle style) => style == DebugCueStyle.compact ? 30 : 70;

  /// 该风格下步序码单元与间隔的时值，固件生成器据此渲染宏。
  static ({int unitMs, int gapMs}) stepTiming(DebugCueStyle style) =>
      (unitMs: _unit(style), gapMs: _gap(style));

  /// 该风格下事件音的各段时值，固件生成器据此渲染宏。
  static ({
    int eventNoteMs,
    int eventDoneMs,
    int eventGapMs,
    int allDoneNoteMs,
    int allDoneTailMs,
  }) eventTiming(DebugCueStyle style) {
    final compact = style == DebugCueStyle.compact;
    return (
      eventNoteMs: compact ? 60 : 90,
      eventDoneMs: compact ? 70 : 140,
      eventGapMs: compact ? 20 : 40,
      allDoneNoteMs: 120,
      allDoneTailMs: compact ? 200 : 300,
    );
  }

  /// 步骤开始：上行大三和弦分解，只听走向就能与 [done] 区分。
  static List<DebugCueNote> ready(DebugCueStyle style) {
    final t = eventTiming(style);
    return [
      DebugCueNote(noteC6, t.eventNoteMs),
      DebugCueNote(null, t.eventGapMs),
      DebugCueNote(noteE6, t.eventNoteMs),
      DebugCueNote(null, t.eventGapMs),
      DebugCueNote(noteG6, t.eventNoteMs),
    ];
  }

  /// 步骤完成：下行四度，轮廓与 [ready] 相反。
  static List<DebugCueNote> done(DebugCueStyle style) {
    final t = eventTiming(style);
    return [
      DebugCueNote(noteG6, t.eventDoneMs),
      DebugCueNote(null, t.eventGapMs),
      DebugCueNote(noteC6, t.eventDoneMs),
    ];
  }

  /// 全部完成：全方案唯一从低音区起音的旋律，与步兵/工程启动曲同音。
  static List<DebugCueNote> allDone(DebugCueStyle style) {
    final t = eventTiming(style);
    return [
      DebugCueNote(noteC5, t.allDoneNoteMs),
      DebugCueNote(null, t.eventGapMs),
      DebugCueNote(noteE5, t.allDoneNoteMs),
      DebugCueNote(null, t.eventGapMs),
      DebugCueNote(noteG5, t.allDoneNoteMs),
      DebugCueNote(null, t.eventGapMs),
      DebugCueNote(noteC6, t.allDoneTailMs),
    ];
  }

  /// 第 [index] 项的步序提示（[index] 从 1 开始）：音区表示十位、点数表示个位。
  ///
  /// [index] 超出 1~10 时按最后一段处理，不抛异常——调试序列的项数由用户
  /// 配置决定，这里只负责把序号映射成可辨识的提示音。
  static List<DebugCueNote> step(int index, DebugCueStyle style) {
    final offset = index < 1 ? 0 : index - 1;
    final count = offset % zoneSpan + 1;
    final frequency = offset ~/ zoneSpan == 0 ? zoneLow : zoneHigh;
    final unit = _unit(style);
    final gap = _gap(style);
    return [
      for (var i = 0; i < count; i++) ...[
        DebugCueNote(frequency, unit),
        if (i + 1 < count) DebugCueNote(null, gap),
      ],
    ];
  }

  /// 一个测试项的完整提示：READY + 步序码 + DONE，用于试听。
  static List<DebugCueNote> fullStep(int index, DebugCueStyle style) => [
    ...ready(style),
    ...step(index, style),
    ...done(style),
  ];

  static const List<DebugCueStyle> styles = DebugCueStyle.values;

  static DebugCueStyle styleByName(String? name) {
    for (final style in DebugCueStyle.values) {
      if (style.name == name) return style;
    }
    return DebugCueStyle.standard;
  }

  /// 曲线总时长（毫秒）。
  static int durationMs(Iterable<DebugCueNote> notes) =>
      notes.fold(0, (total, note) => total + note.durationMs);
}
