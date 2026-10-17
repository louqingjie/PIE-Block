// 独立验证：重叠单音裁决 + 派生数据 + JSON + 校验器 + MIDI 导入。
//
// 这是对抗性验证套件：期望值按冻结契约逐条推导，另有独立实现的 oracle 与
// 随机用例子集对拍，不复用被测实现的私有逻辑。
import 'dart:math';

import 'package:pieblock_core/pieblock_core.dart';
import 'package:test/test.dart';

MusicNote _n(String id, int pitch, int startTick, int durationTicks) =>
    MusicNote(
      id: id,
      pitch: pitch,
      startTick: startTick,
      durationTicks: durationTicks,
    );

MusicConfig _c(
  List<MusicNote> notes, {
  MusicOverlapMode mode = MusicOverlapMode.nearest,
  bool interrupts = true,
}) => MusicConfig(
  notes: notes,
  overlapMode: mode,
  newNoteInterrupts: interrupts,
);

/// (noteId, pitch, startTick, endTick)
typedef _Span = (String, int, int, int);

List<_Span> _spansOf(MusicConfig config) => [
  for (final span in MusicTimeline.soundingSpans(config))
    (span.noteId, span.pitch, span.startTick, span.endTick),
];

List<MusicNote> _legalNotes(MusicConfig config) => [
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

/// 契约的独立实现：组内选优 + 接管判定 + 旧区间截断。
///
/// 与 packages/pieblock_core/lib/src/music.dart 的实现是两套独立代码，只有
/// 契约文本是共同来源。
MusicNote _better(
  MusicNote a,
  MusicNote b,
  MusicOverlapMode mode,
  int? reference,
) {
  switch (mode) {
    case MusicOverlapMode.highest:
      if (a.pitch != b.pitch) return a.pitch > b.pitch ? a : b;
      return _longer(a, b);
    case MusicOverlapMode.lowest:
      if (a.pitch != b.pitch) return a.pitch < b.pitch ? a : b;
      return _longer(a, b);
    case MusicOverlapMode.nearest:
      if (reference == null) {
        if (a.pitch != b.pitch) return a.pitch > b.pitch ? a : b;
        return _longer(a, b);
      }
      final ad = (a.pitch - reference).abs();
      final bd = (b.pitch - reference).abs();
      if (ad != bd) return ad < bd ? a : b;
      if (a.pitch != b.pitch) return a.pitch > b.pitch ? a : b;
      return _longer(a, b);
  }
}

MusicNote _longer(MusicNote a, MusicNote b) {
  if (a.durationTicks != b.durationTicks) {
    return a.durationTicks > b.durationTicks ? a : b;
  }
  return a.id.compareTo(b.id) <= 0 ? a : b;
}

List<_Span> _oracleSpans(MusicConfig config) {
  final notes = _legalNotes(config);
  final spans = <_Span>[];
  MusicNote? sounding;
  int? lastEffective;
  var index = 0;
  while (index < notes.length) {
    final tick = notes[index].startTick;
    final group = <MusicNote>[];
    while (index < notes.length && notes[index].startTick == tick) {
      group.add(notes[index++]);
    }
    if (sounding != null && tick >= sounding.endTick) sounding = null;
    final reference = sounding?.pitch ?? lastEffective;
    var pick = group.first;
    for (final candidate in group.skip(1)) {
      pick = _better(pick, candidate, config.overlapMode, reference);
    }
    final bool take;
    if (sounding == null || config.newNoteInterrupts) {
      take = true;
    } else {
      take = switch (config.overlapMode) {
        MusicOverlapMode.highest => pick.pitch > sounding.pitch,
        MusicOverlapMode.lowest => pick.pitch < sounding.pitch,
        // 正在发声的音高本身就是参照，距离恒为 0，候选不可能更近。
        MusicOverlapMode.nearest => false,
      };
    }
    if (!take) continue;
    if (sounding != null) {
      final last = spans.removeLast();
      if (tick > last.$3) {
        spans.add((last.$1, last.$2, last.$3, tick));
      }
    }
    spans.add((pick.id, pick.pitch, tick, pick.endTick));
    sounding = pick;
    lastEffective = pick.pitch;
  }
  return spans;
}

/// 独立实现的重叠区间计数：按契约「极大 tick 区间」语义，同一个 tick 先合并
/// 结算所有端点再判定是否处于重叠，因此「A 持续、B 结束同时 C 开始」这种连续
/// 重叠段仍算一处；首尾相接（该 tick 结算后 activity 降到 1）不算重叠。
int _oracleOverlapCount(MusicConfig config) {
  final notes = _legalNotes(config);
  if (notes.length < 2) return 0;
  final events = <(int, int)>[
    for (final note in notes) ...[(note.startTick, 1), (note.endTick, -1)],
  ]..sort((a, b) {
      final tick = a.$1.compareTo(b.$1);
      return tick != 0 ? tick : a.$2.compareTo(b.$2);
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

List<(int?, int)> _oracleSegments(MusicConfig config, List<_Span> spans) {
  final result = <(int?, int)>[];
  var cursor = 0;
  void add(int? pitch, int micros) {
    final millis = (micros / 1000).round().clamp(1, 0x7fffffff);
    if (result.isNotEmpty && result.last.$1 == pitch) {
      final previous = result.removeLast();
      result.add((pitch, previous.$2 + millis));
    } else {
      result.add((pitch, millis));
    }
  }

  for (final span in spans) {
    if (span.$3 > cursor) {
      add(
        null,
        MusicTimeline.microsecondsAtTick(config, span.$3) -
            MusicTimeline.microsecondsAtTick(config, cursor),
      );
    }
    add(
      span.$2,
      MusicTimeline.microsecondsAtTick(config, span.$4) -
          MusicTimeline.microsecondsAtTick(config, span.$3),
    );
    cursor = span.$4;
  }
  return result;
}

void _expectSpans(MusicConfig config, List<_Span> expected) {
  expect(_spansOf(config), expected);
  expect(_oracleSpans(config), expected, reason: '独立 oracle 也应得到相同裁决');
}

void main() {
  group('裁决：同 tick 组内选优', () {
    test('曲首三音和弦 nearest 无参照 → 取最高音', () {
      final config = _c([
        _n('low', 55, 0, 480),
        _n('mid', 60, 0, 480),
        _n('high', 67, 0, 480),
      ]);
      _expectSpans(config, [('high', 67, 0, 480)]);
    });

    test('同音高三音组：duration 更长的胜出', () {
      final config = _c(
        [
          _n('short', 60, 0, 240),
          _n('long', 60, 0, 960),
          _n('middle', 60, 0, 480),
        ],
        mode: MusicOverlapMode.highest,
      );
      _expectSpans(config, [('long', 60, 0, 960)]);
    });

    test('同音高同长度：按 id 字典序取最小（highest/lowest 一致）', () {
      final notes = [_n('z', 60, 0, 480), _n('a', 60, 0, 480)];
      _expectSpans(
        _c(notes, mode: MusicOverlapMode.highest),
        [('a', 60, 0, 480)],
      );
      _expectSpans(
        _c(notes, mode: MusicOverlapMode.lowest),
        [('a', 60, 0, 480)],
      );
    });

    test('nearest 用上一有效发声音高做参照（三音组）', () {
      final config = _c([
        _n('prev', 62, 0, 480),
        _n('far-low', 55, 480, 480),
        _n('exact', 62, 480, 480),
        _n('far-high', 67, 480, 480),
      ]);
      _expectSpans(config, [
        ('prev', 62, 0, 480),
        ('exact', 62, 480, 960),
      ]);
    });

    test('nearest 距离平局取较高音', () {
      final config = _c([
        _n('prev', 62, 0, 480),
        _n('lower', 58, 480, 480),
        _n('higher', 66, 480, 480),
      ]);
      _expectSpans(config, [
        ('prev', 62, 0, 480),
        ('higher', 66, 480, 960),
      ]);
    });

    test('nearest 参照跨越休止后仍然有效', () {
      final config = _c([
        _n('a', 60, 0, 120),
        _n('near', 55, 960, 240),
        _n('far', 70, 960, 240),
        _n('next', 50, 1200, 240),
        _n('next-far', 62, 1200, 240),
      ]);
      // 120..960 是休止；960 组参照仍是 60 → 55；1200 组参照变成 55 → 50。
      _expectSpans(config, [
        ('a', 60, 0, 120),
        ('near', 55, 960, 1200),
        ('next', 50, 1200, 1440),
      ]);
    });

    test('nearest 的参照跟随打断者音高，而不是最初的音', () {
      final config = _c([
        _n('a', 60, 0, 1920),
        _n('b', 64, 300, 300),
        _n('c-low', 60, 700, 240),
        _n('c-high', 68, 700, 240),
      ]);
      // b 打断后上一有效音高是 64；60 与 68 距离都是 4 → 取较高音 68。
      _expectSpans(config, [
        ('a', 60, 0, 300),
        ('b', 64, 300, 600),
        ('c-high', 68, 700, 940),
      ]);
    });
  });

  group('裁决：后起始音符接管', () {
    test('打断开关开启时三种模式都无条件接管', () {
      for (final mode in MusicOverlapMode.values) {
        final config = _c(
          [_n('a', 60, 0, 960), _n('b', 50, 480, 960)],
          mode: mode,
        );
        _expectSpans(config, [
          ('a', 60, 0, 480),
          ('b', 50, 480, 1440),
        ]);
      }
    });

    test('打断关闭 + highest：更高才接管，否则整组不发声', () {
      final takeover = _c(
        [_n('a', 60, 0, 960), _n('b', 64, 480, 960)],
        mode: MusicOverlapMode.highest,
        interrupts: false,
      );
      _expectSpans(takeover, [
        ('a', 60, 0, 480),
        ('b', 64, 480, 1440),
      ]);
      final rejected = _c(
        [_n('a', 60, 0, 960), _n('b', 55, 480, 960)],
        mode: MusicOverlapMode.highest,
        interrupts: false,
      );
      _expectSpans(rejected, [('a', 60, 0, 960)]);
    });

    test('打断关闭 + lowest：更低才接管，否则整组不发声', () {
      final takeover = _c(
        [_n('a', 60, 0, 960), _n('b', 55, 480, 960)],
        mode: MusicOverlapMode.lowest,
        interrupts: false,
      );
      _expectSpans(takeover, [
        ('a', 60, 0, 480),
        ('b', 55, 480, 1440),
      ]);
      final rejected = _c(
        [_n('a', 60, 0, 960), _n('b', 64, 480, 960)],
        mode: MusicOverlapMode.lowest,
        interrupts: false,
      );
      _expectSpans(rejected, [('a', 60, 0, 960)]);
    });

    test('打断关闭 + nearest：正在发声的音符永不被打断', () {
      for (final pitch in [55, 60, 64, 90]) {
        final config = _c(
          [_n('a', 60, 0, 960), _n('b', pitch, 480, 960)],
          mode: MusicOverlapMode.nearest,
          interrupts: false,
        );
        _expectSpans(config, [('a', 60, 0, 960)]);
      }
    });

    test('打断关闭 + highest：同音高不算更优，不接管', () {
      final config = _c(
        [_n('a', 60, 0, 960), _n('b', 60, 480, 960)],
        mode: MusicOverlapMode.highest,
        interrupts: false,
      );
      _expectSpans(config, [('a', 60, 0, 960)]);
    });

    test('打断关闭 + nearest：前音符结束后新组无条件发声', () {
      final config = _c(
        [_n('a', 60, 0, 960), _n('b', 90, 960, 960)],
        mode: MusicOverlapMode.nearest,
        interrupts: false,
      );
      _expectSpans(config, [
        ('a', 60, 0, 960),
        ('b', 90, 960, 1920),
      ]);
    });

    test('被打断的尾巴不恢复：打断者先结束也留空', () {
      final config = _c([_n('b', 60, 0, 960), _n('a', 64, 300, 480)]);
      // a 在 780 结束，但 b 的 780..960 不会恢复发声。
      _expectSpans(config, [
        ('b', 60, 0, 300),
        ('a', 64, 300, 780),
      ]);
    });

    test('多重打断依次接管', () {
      final config = _c([
        _n('a', 60, 0, 1920),
        _n('b', 64, 300, 1920),
        _n('c', 55, 600, 300),
      ]);
      _expectSpans(config, [
        ('a', 60, 0, 300),
        ('b', 64, 300, 600),
        ('c', 55, 600, 900),
      ]);
    });

    test('中间组整段静音后，后续更优组仍可接管', () {
      final config = _c(
        [
          _n('a', 60, 0, 1920),
          _n('losing', 55, 300, 1920),
          _n('winning', 64, 600, 1920),
        ],
        mode: MusicOverlapMode.highest,
        interrupts: false,
      );
      _expectSpans(config, [
        ('a', 60, 0, 600),
        ('winning', 64, 600, 2520),
      ]);
    });
  });

  group('裁决：非法音符', () {
    test('非法音符被过滤，也不参与 nearest 参照', () {
      final config = _c([
        _n('bad-pitch-high', 128, 0, 480),
        _n('bad-pitch-zero', 0, 0, 480),
        _n('bad-negative', 60, -10, 480),
        _n('bad-zero-duration', 60, 0, 0),
        _n('near', 55, 240, 240),
        _n('far', 70, 240, 240),
      ]);
      // 没有合法前置音 → nearest 无参照 → 取最高音 70。
      _expectSpans(config, [('far', 70, 240, 480)]);
    });

    test('非法音符不参与 overlapCount', () {
      final config = _c([
        _n('legal', 60, 0, 960),
        _n('illegal', 0, 480, 960),
      ]);
      expect(MusicTimeline.overlapCount(config), 0);
    });

    test('完全静音的输家整段不出现', () {
      final config = _c(
        [_n('loser', 55, 0, 480), _n('winner', 67, 0, 480)],
        mode: MusicOverlapMode.highest,
      );
      _expectSpans(config, [('winner', 67, 0, 480)]);
      expect(
        MusicTimeline.soundingSpans(config).any((span) => span.noteId == 'loser'),
        isFalse,
      );
    });
  });

  group('重叠处数 overlapCount', () {
    test('同 tick 三音和弦算一处', () {
      expect(
        MusicTimeline.overlapCount(
          _c([_n('a', 60, 0, 480), _n('b', 64, 0, 480), _n('c', 67, 0, 480)]),
        ),
        1,
      );
    });

    test('两段分离的重叠区分别计数', () {
      expect(
        MusicTimeline.overlapCount(
          _c([
            _n('a', 60, 0, 480),
            _n('b', 64, 240, 480),
            _n('c', 67, 600, 600),
          ]),
        ),
        2,
      );
    });

    test('嵌套包含关系算一处', () {
      expect(
        MusicTimeline.overlapCount(
          _c([_n('a', 60, 0, 1920), _n('b', 64, 480, 480)]),
        ),
        1,
      );
    });

    test('首尾相衔接不算重叠', () {
      expect(
        MusicTimeline.overlapCount(
          _c([_n('a', 60, 0, 480), _n('b', 64, 480, 480)]),
        ),
        0,
      );
    });

    test('一个长音包住两个分离和弦：算两处', () {
      expect(
        MusicTimeline.overlapCount(
          _c([
            _n('long', 60, 0, 2000),
            _n('chord1-a', 64, 400, 200),
            _n('chord1-b', 67, 400, 200),
            _n('chord2-a', 55, 1200, 200),
            _n('chord2-b', 58, 1200, 200),
          ]),
        ),
        2,
      );
    });

    test('空工程与全非法音符没有重叠', () {
      expect(MusicTimeline.overlapCount(MusicConfig()), 0);
      expect(
        MusicTimeline.overlapCount(
          _c([_n('a', 0, 0, 480), _n('b', 128, 0, 480)]),
        ),
        0,
      );
    });

    test('同 tick 一音结束一音开始时，若第三个音持续，连续重叠段只算一处', () {
      // A 横跨 0..1440；B 240..480 与 C 480..720 首尾相接。
      // 修复后同一个 tick 先合并结算所有端点：480 处 active 仍 ≥2，
      // 因此 [240,720) 是一个连续的极大重叠区间，只算 1 处。
      expect(
        MusicTimeline.overlapCount(
          _c([
            _n('A', 60, 0, 1440),
            _n('B', 64, 240, 240),
            _n('C', 67, 480, 240),
          ]),
        ),
        1,
      );
    });

    test('真正分离的两段连续重叠（中间 active 掉到 1）仍算两处', () {
      // A 横跨 0..1440；B 240..360、D 600..720 与 A 重叠，但 360..600 只有 A。
      expect(
        MusicTimeline.overlapCount(
          _c([
            _n('A', 60, 0, 1440),
            _n('B', 64, 240, 120),
            _n('D', 67, 600, 120),
          ]),
        ),
        2,
      );
    });
  });

  group('派生数据 segments / tempo', () {
    test('休止与发声段交错', () {
      final config = _c(
        [_n('a', 60, 0, 240), _n('b', 67, 480, 240)],
        mode: MusicOverlapMode.highest,
      );
      final segments = MusicTimeline.segments(config);
      expect(
        segments.map((segment) => (segment.pitch, segment.durationMs)),
        [(60, 250), (null, 250), (67, 250)],
      );
    });

    test('相邻同音高合并成一段', () {
      final config = _c([_n('a', 60, 0, 480), _n('b', 60, 480, 480)]);
      final segments = MusicTimeline.segments(config);
      expect(
        segments.map((segment) => (segment.pitch, segment.durationMs)),
        [(60, 1000)],
      );
    });

    test('曲首静音保留为 null 段', () {
      final config = _c([_n('a', 60, 480, 480)]);
      expect(
        MusicTimeline.segments(config).map(
          (segment) => (segment.pitch, segment.durationMs),
        ),
        [(null, 500), (60, 500)],
      );
    });

    test('tempo map 影响片段时长', () {
      final config = MusicConfig(
        notes: [_n('a', 60, 0, 480), _n('b', 62, 480, 480)],
        tempoEvents: const [
          TempoEvent(tick: 0, microsecondsPerQuarter: 500000),
          TempoEvent(tick: 480, microsecondsPerQuarter: 250000),
        ],
      );
      expect(
        MusicTimeline.segments(config).map(
          (segment) => (segment.pitch, segment.durationMs),
        ),
        [(60, 500), (62, 250)],
      );
    });

    test('microsecondsAtTick 对未排序 tempoEvents 排序后计算', () {
      final config = MusicConfig(
        notes: [_n('a', 60, 0, 960)],
        tempoEvents: const [
          TempoEvent(tick: 960, microsecondsPerQuarter: 250000),
          TempoEvent(tick: 0, microsecondsPerQuarter: 500000),
        ],
      );
      expect(MusicTimeline.microsecondsAtTick(config, 0), 0);
      expect(MusicTimeline.microsecondsAtTick(config, 480), 500000);
      // tempo 变更从它自己的 tick 起生效：tick 960 之前仍是旧的 500000。
      expect(MusicTimeline.microsecondsAtTick(config, 960), 1000000);
      expect(MusicTimeline.microsecondsAtTick(config, 1440), 1250000);
    });

    test('非法音符不产生片段，但会留下曲首静音', () {
      final config = _c([
        _n('bad', 0, 0, 480),
        _n('good', 60, 480, 480),
      ]);
      expect(
        MusicTimeline.segments(config).map(
          (segment) => (segment.pitch, segment.durationMs),
        ),
        [(null, 500), (60, 500)],
      );
    });
  });

  group('JSON 往返与旧格式兼容', () {
    test('完整往返保留重叠设置 / 音符 / 事件', () {
      final original = MusicConfig(
        ticksPerQuarter: 960,
        sourceName: 'src.mid',
        trackName: 'Lead',
        notes: [
          _n('a', 60, 0, 480),
          _n('b', 64, 0, 480),
          _n('c', 67, 960, 240),
        ],
        overlapMode: MusicOverlapMode.lowest,
        newNoteInterrupts: false,
        tempoEvents: const [
          TempoEvent(tick: 0, microsecondsPerQuarter: 500000),
          TempoEvent(tick: 960, microsecondsPerQuarter: 400000),
        ],
        timeSignatureEvents: const [
          TimeSignatureEvent(tick: 0, numerator: 3, denominator: 4),
        ],
      );
      final reloaded = MusicConfig.fromJson(original.toJson());
      expect(reloaded.ticksPerQuarter, 960);
      expect(reloaded.sourceName, 'src.mid');
      expect(reloaded.trackName, 'Lead');
      expect(reloaded.overlapMode, MusicOverlapMode.lowest);
      expect(reloaded.newNoteInterrupts, isFalse);
      expect(
        reloaded.notes.map((note) => note.toJson()).toList(),
        original.notes.map((note) => note.toJson()).toList(),
      );
      expect(reloaded.tempoEvents.map((event) => event.toJson()).toList(), [
        const TempoEvent(tick: 0, microsecondsPerQuarter: 500000).toJson(),
        const TempoEvent(tick: 960, microsecondsPerQuarter: 400000).toJson(),
      ]);
      expect(reloaded.timeSignatureEvents.single.denominator, 4);
      expect(reloaded.toJson(), original.toJson());
    });

    test('三种模式名都能往返', () {
      for (final mode in MusicOverlapMode.values) {
        final config = MusicConfig(overlapMode: mode, notes: [_n('a', 60, 0, 1)]);
        expect(
          MusicConfig.fromJson(config.toJson()).overlapMode,
          mode,
        );
      }
    });

    test('旧 JSON 无重叠字段 → 默认 nearest/打断开启，旧 primary 被忽略', () {
      final legacy = <String, Object?>{
        'ticks_per_quarter': 480,
        'source_name': 'legacy.mid',
        'track_name': 'Legacy',
        'notes': [
          {
            'id': 'a',
            'pitch': 60,
            'start_tick': 0,
            'duration_ticks': 480,
            'primary': true,
          },
          {
            'id': 'b',
            'pitch': 64,
            'start_tick': 480,
            'duration_ticks': 480,
            'primary': false,
          },
        ],
      };
      final config = MusicConfig.fromJson(legacy);
      expect(config.overlapMode, MusicOverlapMode.nearest);
      expect(config.newNoteInterrupts, isTrue);
      expect(config.notes, hasLength(2));
      expect(config.notes.first.id, 'a');
      // 旧 primary 字段不被解析进模型，也不会写回 JSON。
      expect(config.toJson().toString(), isNot(contains('primary')));
    });

    test('旧 JSON 的 primary 标志不参与裁决（已删除字段被忽略）', () {
      final config = MusicConfig.fromJson(const {
        'notes': [
          {
            'id': 'old-primary',
            'pitch': 60,
            'start_tick': 0,
            'duration_ticks': 480,
            'primary': true,
          },
          {
            'id': 'other',
            'pitch': 67,
            'start_tick': 0,
            'duration_ticks': 480,
            'primary': false,
          },
        ],
      });
      // 曲首 nearest 无参照 → 取最高音 67，与旧 primary 字段无关。
      expect(_spansOf(config), [('other', 67, 0, 480)]);
    });

    test('未知 overlap_mode 回退 nearest', () {
      final config = MusicConfig.fromJson(const {
        'notes': <Object?>[],
        'overlap_mode': 'chord-legacy',
      });
      expect(config.overlapMode, MusicOverlapMode.nearest);
    });

    test('MusicNote JSON 键集合固定，不写 primary', () {
      final json = _n('x', 60, 0, 480).toJson();
      expect(json.keys.toSet(), {'id', 'pitch', 'start_tick', 'duration_ticks'});
      expect(MusicNote.fromJson({...json, 'primary': true}).pitch, 60);
    });

    test('notes 不可变，copyWith 保留/修改重叠设置', () {
      final config = _c([_n('a', 60, 0, 480)]);
      expect(
        () => config.notes.add(_n('b', 64, 0, 480)),
        throwsUnsupportedError,
      );
      final copied = config.copyWith(newNoteInterrupts: false);
      expect(copied.newNoteInterrupts, isFalse);
      expect(copied.overlapMode, MusicOverlapMode.nearest);
      expect(copied.notes.single.id, 'a');
      expect(
        config.copyWith(overlapMode: MusicOverlapMode.highest).overlapMode,
        MusicOverlapMode.highest,
      );
    });
  });

  group('MidiFileData.selectTrack', () {
    MidiFileData buildFile({
      List<TempoEvent> tempoEvents = const [
        TempoEvent(tick: 0, microsecondsPerQuarter: 500000),
      ],
      List<TimeSignatureEvent> timeSignatureEvents = const [
        TimeSignatureEvent(tick: 0, numerator: 4, denominator: 4),
      ],
    }) => MidiFileData(
      format: 1,
      ticksPerQuarter: 960,
      tracks: [
        MidiTrackData(
          name: 'Chords',
          notes: const [
            MidiSourceNote(
              pitch: 60,
              channel: 0,
              startTick: 0,
              durationTicks: 480,
            ),
            MidiSourceNote(
              pitch: 64,
              channel: 0,
              startTick: 0,
              durationTicks: 480,
            ),
            MidiSourceNote(
              pitch: 67,
              channel: 0,
              startTick: 480,
              durationTicks: 240,
            ),
            // 鼓组：必须被丢弃。
            MidiSourceNote(
              pitch: 38,
              channel: 9,
              startTick: 0,
              durationTicks: 120,
            ),
          ],
        ),
        const MidiTrackData(
          name: 'Drums only',
          notes: [
            MidiSourceNote(
              pitch: 38,
              channel: 9,
              startTick: 0,
              durationTicks: 120,
            ),
          ],
        ),
        const MidiTrackData(name: 'Empty', notes: []),
      ],
      tempoEvents: tempoEvents,
      timeSignatureEvents: timeSignatureEvents,
    );

    test('旋律轨道保留全部和弦音并透传重叠设置', () {
      final file = buildFile();
      final imported = file.selectTrack(
        0,
        sourceName: 'chords.mid',
        overlapMode: MusicOverlapMode.lowest,
        newNoteInterrupts: false,
      );
      expect(file.tracks[0].melodicNoteCount, 3);
      expect(file.tracks[0].polyphonic, isTrue);
      expect(imported.notes, hasLength(3), reason: '和弦音不得在导入阶段丢弃');
      // 起始 tick 升序、同 tick 音高降序的稳定顺序。
      expect(imported.notes.map((note) => note.pitch), [64, 60, 67]);
      expect(imported.notes.map((note) => note.startTick), [0, 0, 480]);
      expect(imported.notes.map((note) => note.id), ['m0', 'm1', 'm2']);
      expect(imported.ticksPerQuarter, 960);
      expect(imported.sourceName, 'chords.mid');
      expect(imported.trackName, 'Chords');
      expect(imported.overlapMode, MusicOverlapMode.lowest);
      expect(imported.newNoteInterrupts, isFalse);
      // 导入后按设置裁决：lowest 在 tick 0 取 60，tick 480 单独 67。
      expect(_spansOf(imported), [
        ('m1', 60, 0, 480),
        ('m2', 67, 480, 720),
      ]);
      expect(MusicTimeline.overlapCount(imported), 1);
    });

    test('鼓组轨道与越界索引抛 FormatException', () {
      final file = buildFile();
      expect(
        () => file.selectTrack(1),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => file.selectTrack(2),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => file.selectTrack(3),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => file.selectTrack(-1),
        throwsA(isA<FormatException>()),
      );
    });

    test('空 tempo / 拍号事件回退默认值', () {
      final file = buildFile(tempoEvents: const [], timeSignatureEvents: const []);
      final imported = file.selectTrack(0);
      expect(imported.tempoEvents.single.tick, 0);
      expect(imported.tempoEvents.single.microsecondsPerQuarter, 500000);
      expect(imported.timeSignatureEvents.single.numerator, 4);
      expect(imported.timeSignatureEvents.single.denominator, 4);
      expect(imported.overlapMode, MusicOverlapMode.nearest);
      expect(imported.newNoteInterrupts, isTrue);
    });

    test('MidiTrackData 顺序轨道非 polyphonic、鼓组不计入旋律音符', () {
      const sequential = MidiTrackData(
        name: 'Mono',
        notes: [
          MidiSourceNote(pitch: 60, channel: 0, startTick: 0, durationTicks: 480),
          MidiSourceNote(
            pitch: 62,
            channel: 0,
            startTick: 480,
            durationTicks: 480,
          ),
        ],
      );
      expect(sequential.polyphonic, isFalse);
      expect(sequential.melodicNoteCount, 2);
      expect(
        const MidiTrackData(
          name: 'Drums',
          notes: [
            MidiSourceNote(
              pitch: 38,
              channel: 9,
              startTick: 0,
              durationTicks: 120,
            ),
          ],
        ).melodicNoteCount,
        0,
      );
    });

    test('MidiCodec 写入-解析往返后再导入仍保留和弦', () {
      final source = MusicConfig(
        ticksPerQuarter: 480,
        trackName: 'Chord Track',
        notes: [
          _n('a', 60, 0, 480),
          _n('b', 64, 0, 480),
          _n('c', 67, 480, 480),
        ],
        tempoEvents: const [
          TempoEvent(tick: 0, microsecondsPerQuarter: 400000),
        ],
        timeSignatureEvents: const [
          TimeSignatureEvent(tick: 0, numerator: 3, denominator: 4),
        ],
      );
      final parsed = MidiCodec.parse(MidiCodec.write(source));
      expect(parsed.tracks, hasLength(1));
      expect(parsed.tracks.single.name, 'Chord Track');
      expect(parsed.tracks.single.melodicNoteCount, 3);
      expect(parsed.tracks.single.polyphonic, isTrue);
      final imported = parsed.selectTrack(
        0,
        sourceName: 'roundtrip.mid',
        overlapMode: MusicOverlapMode.highest,
      );
      expect(imported.notes.map((note) => note.pitch), [64, 60, 67]);
      expect(imported.overlapMode, MusicOverlapMode.highest);
      expect(imported.tempoEvents.single.microsecondsPerQuarter, 400000);
      expect(imported.timeSignatureEvents.single.numerator, 3);
    });
  });

  group('校验器：重叠只警告不阻断', () {
    test('空音符是 required error', () {
      final issues = ProjectValidator.validate(MusicConfig());
      final error = issues.where(
        (issue) => issue.severity == IssueSeverity.error,
      );
      expect(
        error.any(
          (issue) =>
              issue.fieldPath == 'music.notes' &&
              issue.kind == ValidationIssueKind.required &&
              issue.message.contains('至少添加一个音符'),
        ),
        isTrue,
      );
    });

    test('合法重叠配置：无 error，恰有一条 warning 带模式标签与处数', () {
      final config = _c([
        _n('a', 60, 0, 960),
        _n('b', 64, 480, 960),
      ]);
      final issues = ProjectValidator.validate(config);
      expect(
        issues.where((issue) => issue.severity == IssueSeverity.error),
        isEmpty,
        reason: '重叠不得阻断生成/烧录',
      );
      final warnings = issues
          .where((issue) => issue.severity == IssueSeverity.warning)
          .toList();
      expect(warnings, hasLength(1));
      expect(warnings.single.fieldPath, 'music.notes');
      expect(warnings.single.message, contains('1 处音符重叠'));
      expect(warnings.single.message, contains('取最近音阶'));
      expect(warnings.single.message, isNot(contains('每 tick')));
    });

    test('warning 的处数与模式标签跟随配置', () {
      final config = _c(
        [
          _n('a', 60, 0, 480),
          _n('b', 64, 240, 480),
          _n('c', 67, 600, 600),
        ],
        mode: MusicOverlapMode.lowest,
      );
      final warnings = ProjectValidator.validate(config)
          .where((issue) => issue.severity == IssueSeverity.warning)
          .toList();
      expect(warnings.single.message, contains('2 处音符重叠'));
      expect(warnings.single.message, contains('取低音'));
    });

    test('非法音符造成的“重叠”不产生 warning', () {
      final config = _c([
        _n('a', 60, 0, 960),
        _n('bad', 200, 480, 960),
      ]);
      final issues = ProjectValidator.validate(config);
      expect(
        issues.any(
          (issue) =>
              issue.severity == IssueSeverity.error &&
              issue.message.contains('MIDI 音高'),
        ),
        isTrue,
      );
      expect(
        issues.where((issue) => issue.severity == IssueSeverity.warning),
        isEmpty,
        reason: '非法音符被 timeline 过滤，不应再计重叠',
      );
    });

    test('代码生成使用裁决后的单声部结果', () {
      final config = _c(
        [_n('a', 60, 0, 960), _n('b', 64, 480, 960)],
        mode: MusicOverlapMode.nearest,
        interrupts: false,
      );
      final code = CodeGenerator.generate(config);
      expect(code, contains('{1000UL, 60},'));
      expect(code, isNot(contains(', 64}')));
    });
  });

  group('随机对拍：独立 oracle', () {
    test('300 组随机配置的裁决与 oracle 完全一致且满足不变式', () {
      final random = Random(20261017);
      for (var seed = 0; seed < 300; seed++) {
        final count = random.nextInt(8);
        final notes = <MusicNote>[];
        for (var index = 0; index < count; index++) {
          final invalid = random.nextInt(10) == 0;
          notes.add(
            _n(
              'n$index',
              invalid
                  ? [0, 128, -3][random.nextInt(3)]
                  : 30 + random.nextInt(70),
              random.nextInt(12) == 0 ? -20 : random.nextInt(2600),
              random.nextInt(12) == 0 ? 0 : 1 + random.nextInt(1400),
            ),
          );
        }
        final config = MusicConfig(
          notes: notes,
          overlapMode: MusicOverlapMode.values[random.nextInt(3)],
          newNoteInterrupts: random.nextBool(),
        );
        final spans = MusicTimeline.soundingSpans(config);
        final reason = 'seed=$seed config=${config.toJson()}';
        expect(_spansOf(config), _oracleSpans(config), reason: reason);
        var previousEnd = -1;
        for (final span in spans) {
          expect(span.endTick, greaterThan(span.startTick), reason: reason);
          expect(span.startTick, greaterThanOrEqualTo(previousEnd), reason: reason);
          final note = _legalNotes(config).firstWhere(
            (note) => note.id == span.noteId,
          );
          expect(span.startTick, greaterThanOrEqualTo(note.startTick));
          expect(span.endTick, lessThanOrEqualTo(note.endTick));
          previousEnd = span.endTick;
        }
        // segments 与裁决结果一致：音高序列（相邻同音合并）与总时长。
        final expectedSegments = _oracleSegments(
          config,
          _spansOf(config),
        );
        final segments = MusicTimeline.segments(config);
        expect(
          segments.map((segment) => segment.pitch).toList(),
          expectedSegments.map((segment) => segment.$1).toList(),
          reason: reason,
        );
        final total = segments.fold<int>(
          0,
          (value, segment) => value + segment.durationMs,
        );
        final expectedTotal = expectedSegments.fold<int>(
          0,
          (value, segment) => value + segment.$2,
        );
        expect(total, closeTo(expectedTotal, segments.length + 1), reason: reason);
        expect(
          MusicTimeline.overlapCount(config),
          _oracleOverlapCount(config),
          reason: reason,
        );
      }
    });
  });
}
