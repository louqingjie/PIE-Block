/// 调试模式提示音曲谱：固件生成器与 Flutter 端试听共用同一份数据。
///
/// 方案说明见 docs/design/调试模式提示音方案.md。编码思路是**一条上行音型贯穿全局**：
/// - 步序层用「上行音型的前 N 个音」表示第 N 项——**个数即序号**。
///   音型长度上限 5（人类可靠计数约 4~5），超过 5 用音区（八度）进位；
/// - 提示只有这一段上行：开始区（重复一遍完整音型）与结束区（对称回落）
///   都已删除——前者重复已知信息，后者不携带任何新信息，却比整段上行还长；
/// - 调试序列在固件里循环执行，跑完最后一项自动回到第 1 项，
///   所以没有「全部完成」的收尾旋律；
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
  /// 步序按序号取它的前缀，音型本身不单独播放。
  static const List<int> ascentLow = [noteC6, noteE6, noteG6, noteC7, noteE7];

  /// 上行音型（高音区）：整组升高一个八度。
  static const List<int> ascentHigh = [noteC7, noteE7, 3136, 4186, 5274];

  /// 按音区取上行音型。
  static List<int> ascent(bool high) => high ? ascentHigh : ascentLow;

  // 时值只有一套，就是下面这组常量：提示音不再提供风格切换，
  // 要整体加速/放慢直接改这几个数值即可。
  /// 步序码单元（一个音的发声时长）。
  static const int unitMs = 220;

  /// 步序码内部各音之间的间隔。
  static const int gapMs = 140;

  /// 分区停顿：步序音与随后的测试动作之间的静默。
  ///
  /// 测试动作的噪音会盖掉步序音，所以要留一段静默把两者分开。
  static const int sectionGapMs = 300;

  /// 第 [index] 项的步序提示（[index] 从 1 开始）。
  ///
  /// 用「上行音型的前 N 个音」表示第 N 项：**个数即序号**，不需要任何前言。
  /// 音区（八度）负责进位：项 1~5 用低八度那组，项 6 起换高八度那组。
  ///
  /// 提示只有这一段上行：没有开始区（个数已经说明序号），也没有结束区的
  /// 回落乐句（它不携带任何新信息，却要花掉比整段上行还长的时间）。
  /// 「这一项做完了」由动作本身、随后的 1s 静默和下一次上行共同表达。
  ///
  /// [index] 超出 1~10 时按最后一段处理，不抛异常——调试序列的项数由用户
  /// 配置决定，这里只负责把序号映射成可辨识的提示音。
  static List<DebugCueNote> step(int index) {
    final offset = index < 1 ? 0 : index - 1;
    final count = offset % zoneSpan + 1;
    final high = offset ~/ zoneSpan != 0;
    final motif = ascent(high).take(count).toList();
    return [
      for (var i = 0; i < motif.length; i++) ...[
        DebugCueNote(motif[i], unitMs),
        if (i + 1 < motif.length) DebugCueNote(null, gapMs),
      ],
    ];
  }

  /// 曲线总时长（毫秒）。
  static int durationMs(Iterable<DebugCueNote> notes) =>
      notes.fold(0, (total, note) => total + note.durationMs);
}
