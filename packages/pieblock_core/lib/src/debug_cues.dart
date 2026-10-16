/// 调试模式提示音曲谱：固件生成器与 Flutter 端试听共用同一份数据。
///
/// 方案说明见 docs/design/调试模式提示音方案.md。编码思路是**一条上行音型贯穿全局**：
/// - 步序层用「上行音型的前 N 个音」表示第 N 项——**个数即序号**。
///   音型长度上限 5（人类可靠计数约 4~5），超过 5 用音区（八度）进位；
/// - 结束层用「同一音型的对称回落」呼应，首尾成对，整体像一句有起有落的乐句；
/// - **不再单独播一遍完整音型做开始区**：个数已经承载了序号信息，
///   再播一遍完整音型只是重复同一句话，还让每项提示凭空长出 1 秒多；
/// - 调试序列在固件里循环执行，跑完最后一项自动回到第 1 项，
///   所以没有「全部完成」的收尾旋律——每项的回落音就是这一项结束的标志；
/// - 摩擦轮斜坡扫频（频率跟随占空比）编码连续过程量，由固件单独处理，不在此列。
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

/// 提示音风格。[standard] 是默认；[compact] 把标准风格的时值整体减半，
/// 供 durationMs 很短的调试序列使用，避免提示音喧宾夺主。
enum DebugCueStyle {
  standard('标准', 1),
  compact('紧凑', 2);

  const DebugCueStyle(this.label, this._speedDivisor);

  final String label;

  /// 相对标准风格的加速倍数：标准为 1，紧凑把每个时值除以 2（即快一倍）。
  final int _speedDivisor;

  /// 把标准风格的时值换算成本风格的时值，向下取整到毫秒。
  int scale(int standardMs) => standardMs ~/ _speedDivisor;
}

abstract final class DebugCues {
  /// 单个音区覆盖的项数：即上行音型的音数，也是每项上行音的个数上限。
  ///
  /// 人类可靠计数约 4~5，所以取 5；超过 5 用八度音区进位。
  static const int zoneSpan = 5;

  static const int noteC5 = 523;
  static const int noteE5 = 659;
  static const int noteG5 = 784;
  static const int noteC6 = 1047;
  static const int noteE6 = 1319;
  static const int noteG6 = 1568;
  static const int noteC7 = 2093;
  static const int noteE7 = 2637;

  /// 上行音型（低音区）：C6-E6-G6-C7-E7。
  ///
  /// 前半段 C6-E6-G6 是原本的大三和弦分解，后两个音 C7-E7 是为「音数最多
  /// 要有 5 个」续上的，保持三度叠置，听起来仍是同一条上行的自然延伸。
  /// 步序按序号取它的前缀，回落按 [descent] 取它的对称回落，
  /// 音型本身不单独播放。
  static const List<int> ascentLow = [noteC6, noteE6, noteG6, noteC7, noteE7];

  /// 上行音型（高音区）：整组升高一个八度。
  static const List<int> ascentHigh = [noteC7, noteE7, 3136, 4186, 5274];

  /// 按音区取上行音型。
  static List<int> ascent(bool high) => high ? ascentHigh : ascentLow;

  /// 结束区的回落音型：从步序落音**下面**开始往回走的对称回落。
  ///
  /// 规则是「跳过落音、再倒序」：
  /// - 完整倒序会让交界处出现同音高的两声连读（上行 G → 回落 G），
  ///   分不出「步序结束」和「回落开始」，所以回落必须**跳过步序落音**；
  /// - 项 2 的步序是 [C6, E6]，跳过落音 E6 后只剩单音 C6——它比落音低一个
  ///   三度，方向明确，单音即可；
  /// - 项 1 的步序只有一个音，跳过落音后什么都不剩，此时保留回落到一个音
  ///   （音型首音），使「上行一个音 → 回落一个音」成为唯一可行的呼应。
  static List<int> descent(int count, bool high) {
    final scale = ascent(high);
    // 步序用到的音，去掉最后一个（= 落音）后倒序。
    final List<int> below = scale.take(count).toList();
    if (below.length > 1) {
      return below.sublist(0, below.length - 1).reversed.toList();
    }
    // 项 1：跳过落音后为空，回到音型首音本身。
    return <int>[scale.first];
  }

  // 以下 *_STD 常量是标准风格的时值基准，也是唯一需要修改的时值来源：
  // 紧凑风格一律由 DebugCueStyle.scale 折算，不要再单独写一套数值。
  static const int _unitStd = 220;
  static const int _gapStd = 140;
  static const int _eventDoneStd = 280;
  static const int _eventGapStd = 80;

  /// 分区停顿：步序音与测试动作之间、测试动作与回落之间的静默，
  /// 标准风格下 300ms。
  ///
  /// 必须明显长于 [_gapStd]（140ms）：140ms 只是把音符分开，听感上仍是一个
  /// 连续乐句；300ms 才能让人听出「一段结束、另一段开始」。
  static const int _sectionGapStd = 300;

  /// 该风格下步序码单元与间隔的时值，固件生成器据此渲染宏。
  static ({int unitMs, int gapMs}) stepTiming(DebugCueStyle style) =>
      (unitMs: style.scale(_unitStd), gapMs: style.scale(_gapStd));

  /// 该风格下回落音与分区停顿的时值，固件生成器据此渲染宏。
  static ({int eventDoneMs, int eventGapMs, int sectionGapMs}) eventTiming(
    DebugCueStyle style,
  ) => (
    eventDoneMs: style.scale(_eventDoneStd),
    eventGapMs: style.scale(_eventGapStd),
    sectionGapMs: style.scale(_sectionGapStd),
  );

  /// 第 [index] 项的步序提示（[index] 从 1 开始）。
  ///
  /// 用「上行音型的前 N 个音」表示第 N 项：**个数即序号**，不需要任何前言。
  /// 音区（八度）负责进位：项 1~5 用低八度那组，项 6 起换高八度那组。
  ///
  /// [index] 超出 1~10 时按最后一段处理，不抛异常——调试序列的项数由用户
  /// 配置决定，这里只负责把序号映射成可辨识的提示音。
  static List<DebugCueNote> step(int index, DebugCueStyle style) {
    final offset = index < 1 ? 0 : index - 1;
    final count = offset % zoneSpan + 1;
    final high = offset ~/ zoneSpan != 0;
    final timing = stepTiming(style);
    final motif = ascent(high).take(count).toList();
    return [
      for (var i = 0; i < motif.length; i++) ...[
        DebugCueNote(motif[i], timing.unitMs),
        if (i + 1 < motif.length) DebugCueNote(null, timing.gapMs),
      ],
    ];
  }

  /// 第 [index] 项的结束提示：步序音型的对称回落。
  ///
  /// 回落是上行音型跳过步序落音后倒序（见 [descent]），与 [step] 同一音区，
  /// 所以「上行 N 个音 → 回落」构成一句首尾呼应的乐句，不再需要额外的开始区。
  static List<DebugCueNote> stepDone(int index, DebugCueStyle style) {
    final offset = index < 1 ? 0 : index - 1;
    final count = offset % zoneSpan + 1;
    final high = offset ~/ zoneSpan != 0;
    final timing = stepTiming(style);
    final motif = descent(count, high);
    return [
      for (var i = 0; i < motif.length; i++) ...[
        DebugCueNote(motif[i], timing.unitMs),
        if (i + 1 < motif.length) DebugCueNote(null, timing.gapMs),
      ],
    ];
  }

  /// 一个测试项的完整提示：上行前 N 个音 → 停顿 → 对称回落，用于试听。
  ///
  /// 两个段落，中间一段 sectionGapMs 静默。不再有开始区——个数本身就说明
  /// 了是第几项，先播一遍完整音型只是把同一句话说两遍。
  static List<DebugCueNote> fullStep(int index, DebugCueStyle style) {
    final t = eventTiming(style);
    return [
      ...step(index, style),
      DebugCueNote(null, t.sectionGapMs),
      ...stepDone(index, style),
    ];
  }

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
