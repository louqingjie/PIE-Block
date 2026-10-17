import 'models.dart';

class MusicSegment {
  const MusicSegment({required this.pitch, required this.durationMs});
  final int? pitch;
  final int durationMs;
}

/// 一次真正发声的区间：落在某个音符内部，范围是 `[startTick, endTick)`。
///
/// 蜂鸣器同时只能发一个音，所以重叠音符会被裁决成单声部区间序列：同一个
/// 音符可能只有一部分出现在结果里（被后起始的音符打断）；完全没有出现在
/// 结果里的音符整段不发声（卷帘里显示为灰色）。
class MusicSoundingSpan {
  const MusicSoundingSpan({
    required this.noteId,
    required this.pitch,
    required this.startTick,
    required this.endTick,
  });

  final String noteId;
  final int pitch, startTick, endTick;
  int get durationTicks => endTick - startTick;
}

abstract final class MusicTimeline {
  /// 按配置里的重叠策略把全部合法音符裁决成单声部发声区间。
  ///
  /// 规则（与卷帘灰色显示、固件音乐段一一对应）：
  /// - 合法音符按起始 tick 分组处理；同一 tick 起始的一组按
  ///   [MusicConfig.overlapMode] 选一个发声，其余整段不发声；
  /// - 后起始的音符与前一个仍在发声的音符重叠时：
  ///   - [MusicConfig.newNoteInterrupts] 勾选 → 后起始音符无条件接管，
  ///     前一个音符从接管点起到结束不发声；
  ///   - 未勾选 → 按策略严格比较（取高音/取低音看音高，取最近音阶看与
  ///     “上一个有效发声音高”的距离，而正在发声的音符本身就是该音高，
  ///     所以等同于“后起始音符让位”），不更优就整条不发声；
  /// - 已经被打断的音符不会在压住它的音符结束后恢复发声；
  /// - 曲首没有“上一个有效发声音高”，`nearest` 退化为取最高音。
  static List<MusicSoundingSpan> soundingSpans(MusicConfig config) {
    final notes = _playableNotes(config);
    final spans = <MusicSoundingSpan>[];
    MusicNote? sounding;
    int? effectivePitch;
    var index = 0;
    while (index < notes.length) {
      final tick = notes[index].startTick;
      final group = <MusicNote>[];
      while (index < notes.length && notes[index].startTick == tick) {
        group.add(notes[index++]);
      }
      // 前一个发声音符已经自然结束：它的区间在产出时就已经截止。
      if (sounding != null && tick >= sounding.endTick) sounding = null;
      final pick = _pick(
        group,
        config.overlapMode,
        sounding?.pitch ?? effectivePitch,
      );
      MusicNote? winner;
      if (sounding == null || config.newNoteInterrupts) {
        winner = pick;
      } else if (_beats(
        pick,
        sounding,
        config.overlapMode,
        effectivePitch ?? sounding.pitch,
      )) {
        winner = pick;
      }
      if (winner == null) continue;
      if (sounding != null && spans.isNotEmpty) {
        final last = spans.removeLast();
        // 组按起始 tick 严格递增处理，接管点必然晚于上一段的起点。
        if (tick > last.startTick) {
          spans.add(
            MusicSoundingSpan(
              noteId: last.noteId,
              pitch: last.pitch,
              startTick: last.startTick,
              endTick: tick,
            ),
          );
        }
      }
      spans.add(
        MusicSoundingSpan(
          noteId: winner.id,
          pitch: winner.pitch,
          startTick: tick,
          endTick: winner.endTick,
        ),
      );
      sounding = winner;
      effectivePitch = winner.pitch;
    }
    return spans;
  }

  /// 重叠处数：同时活动音符数 ≥ 2 的极大 tick 区间的个数。
  ///
  /// 用于工具栏的「N 处重叠」提示与校验器警告，统计的是“重叠区域”而不是
  /// 音符对数，和弦（同一时刻三个音）算一处。同一个 tick 上「一个音符结束、
  /// 另一个音符开始」时先合并结算该 tick 的所有端点，因此连续重叠段（如
  /// A 持续、B 结束后 C 紧接着开始）仍算一处。
  static int overlapCount(MusicConfig config) {
    final notes = _playableNotes(config);
    if (notes.length < 2) return 0;
    final events = <(int, int)>[
      for (final note in notes) ...[(note.startTick, 1), (note.endTick, -1)],
    ]..sort((a, b) {
        final tick = a.$1.compareTo(b.$1);
        if (tick != 0) return tick;
        return a.$2.compareTo(b.$2);
      });
    var active = 0, count = 0;
    var overlapping = false;
    var index = 0;
    while (index < events.length) {
      final tick = events[index].$1;
      while (index < events.length && events[index].$1 == tick) {
        active += events[index].$2;
        index++;
      }
      if (active >= 2) {
        if (!overlapping) {
          count++;
          overlapping = true;
        }
      } else {
        overlapping = false;
      }
    }
    return count;
  }

  static int microsecondsAtTick(MusicConfig config, int tick) {
    final events = [...config.tempoEvents]
      ..sort((a, b) => a.tick.compareTo(b.tick));
    var cursor = 0;
    var tempo = events.isEmpty ? 500000 : events.first.microsecondsPerQuarter;
    var total = 0.0;
    for (final event in events) {
      if (event.tick <= 0) {
        tempo = event.microsecondsPerQuarter;
        continue;
      }
      if (event.tick >= tick) break;
      total += (event.tick - cursor) * tempo / config.ticksPerQuarter;
      cursor = event.tick;
      tempo = event.microsecondsPerQuarter;
    }
    total += (tick - cursor).clamp(0, tick) * tempo / config.ticksPerQuarter;
    return total.round();
  }

  static List<MusicSegment> segments(MusicConfig config) {
    final result = <MusicSegment>[];
    var cursorTick = 0;
    for (final span in soundingSpans(config)) {
      if (span.startTick > cursorTick) {
        _append(
          result,
          null,
          microsecondsAtTick(config, span.startTick) -
              microsecondsAtTick(config, cursorTick),
        );
      }
      _append(
        result,
        span.pitch,
        microsecondsAtTick(config, span.endTick) -
            microsecondsAtTick(config, span.startTick),
      );
      cursorTick = span.endTick;
    }
    return result;
  }

  /// 合法音符，按 (起始 tick, 音高降序, id) 稳定排序。
  static List<MusicNote> _playableNotes(MusicConfig config) => [
    for (final note in config.notes)
      if (note.startTick >= 0 &&
          note.durationTicks > 0 &&
          note.pitch >= 1 &&
          note.pitch <= 127)
        note,
  ]..sort((a, b) {
      final tick = a.startTick.compareTo(b.startTick);
      if (tick != 0) return tick;
      final pitch = b.pitch.compareTo(a.pitch);
      return pitch != 0 ? pitch : a.id.compareTo(b.id);
    });

  /// 同一 tick 组内挑一个发声候选。
  static MusicNote _pick(
    List<MusicNote> group,
    MusicOverlapMode mode,
    int? reference,
  ) {
    var best = group.first;
    for (final candidate in group.skip(1)) {
      best = switch (mode) {
        MusicOverlapMode.highest => _preferredHigher(best, candidate),
        MusicOverlapMode.lowest => _preferredLower(best, candidate),
        MusicOverlapMode.nearest => reference == null
            ? _preferredHigher(best, candidate)
            : _preferredNearer(best, candidate, reference),
      };
    }
    return best;
  }

  /// 后起始候选是否比正在发声的音符更优（仅在“新音符打断”未勾选时使用）。
  static bool _beats(
    MusicNote candidate,
    MusicNote current,
    MusicOverlapMode mode,
    int reference,
  ) => switch (mode) {
    MusicOverlapMode.highest => candidate.pitch > current.pitch,
    MusicOverlapMode.lowest => candidate.pitch < current.pitch,
    // current 就是“上一个有效发声音高”本身（距离 0），候选不可能更近，
    // 因此取最近音阶且不勾选打断时，正在发声的音符保持。
    MusicOverlapMode.nearest =>
      (candidate.pitch - reference).abs() <
          (current.pitch - reference).abs(),
  };

  static MusicNote _preferredHigher(MusicNote a, MusicNote b) {
    if (a.pitch != b.pitch) return a.pitch > b.pitch ? a : b;
    return _preferredLonger(a, b);
  }

  static MusicNote _preferredLower(MusicNote a, MusicNote b) {
    if (a.pitch != b.pitch) return a.pitch < b.pitch ? a : b;
    return _preferredLonger(a, b);
  }

  static MusicNote _preferredNearer(MusicNote a, MusicNote b, int reference) {
    final ad = (a.pitch - reference).abs();
    final bd = (b.pitch - reference).abs();
    if (ad != bd) return ad < bd ? a : b;
    return _preferredHigher(a, b);
  }

  static MusicNote _preferredLonger(MusicNote a, MusicNote b) {
    if (a.durationTicks != b.durationTicks) {
      return a.durationTicks > b.durationTicks ? a : b;
    }
    return a.id.compareTo(b.id) <= 0 ? a : b;
  }

  static void _append(List<MusicSegment> target, int? pitch, int micros) {
    final millis = (micros / 1000).round().clamp(1, 0x7fffffff);
    if (target.isNotEmpty && target.last.pitch == pitch) {
      final previous = target.removeLast();
      target.add(
        MusicSegment(pitch: pitch, durationMs: previous.durationMs + millis),
      );
    } else {
      target.add(MusicSegment(pitch: pitch, durationMs: millis));
    }
  }
}
