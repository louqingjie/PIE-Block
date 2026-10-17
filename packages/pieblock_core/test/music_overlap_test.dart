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

/// 单声部发声区间：(音符 id, 起始 tick, 结束 tick, 音高)。
List<(String, int, int, int)> _spansOf(MusicConfig config) => [
  for (final span in MusicTimeline.soundingSpans(config))
    (span.noteId, span.startTick, span.endTick, span.pitch),
];

void main() {
  group('重叠裁决', () {
    test('顺序旋律不受策略影响', () {
      final config = _c([_n('a', 60, 0, 480), _n('b', 62, 480, 480)]);
      expect(_spansOf(config), [('a', 0, 480, 60), ('b', 480, 960, 62)]);
      expect(
        MusicTimeline.segments(config).map((segment) => segment.pitch),
        [60, 62],
      );
    });

    test('休止区间保留为 null 段', () {
      final config = _c([_n('a', 60, 0, 240), _n('b', 62, 480, 240)]);
      expect(_spansOf(config), [('a', 0, 240, 60), ('b', 480, 720, 62)]);
      expect(
        MusicTimeline.segments(config).map((segment) => segment.pitch),
        [60, null, 62],
      );
    });

    test('曲首同 tick 和弦：取最近音阶时没有参照，取最高音', () {
      final notes = [_n('low', 60, 0, 480), _n('high', 67, 0, 480)];
      expect(_spansOf(_c(notes)), [('high', 0, 480, 67)]);
      expect(_spansOf(_c(notes, mode: MusicOverlapMode.highest)), [
        ('high', 0, 480, 67),
      ]);
      expect(_spansOf(_c(notes, mode: MusicOverlapMode.lowest)), [
        ('low', 0, 480, 60),
      ]);
    });

    test('和弦输家整段不发声，也不参与后续参照', () {
      final config = _c([
        _n('a', 60, 0, 120),
        _n('b', 72, 0, 120),
        _n('c', 60, 120, 120),
      ]);
      // 第一个和弦取最高音 b(72)；下一个音符按“上一有效音高 72”就近选 c。
      expect(_spansOf(config), [
        ('b', 0, 120, 72),
        ('c', 120, 240, 60),
      ]);
    });

    test('同一 tick 同音高取更长的音符', () {
      final config = _c(
        [_n('short', 60, 0, 480), _n('long', 60, 0, 960)],
        mode: MusicOverlapMode.highest,
      );
      expect(_spansOf(config), [('long', 0, 960, 60)]);
    });

    test('取最近音阶：有参照时取距离最小的音符', () {
      final config = _c(
        [
          _n('a', 60, 0, 480),
          _n('near', 62, 480, 480),
          _n('far', 69, 480, 480),
        ],
        mode: MusicOverlapMode.nearest,
      );
      expect(_spansOf(config), [('a', 0, 480, 60), ('near', 480, 960, 62)]);
    });

    test('取最近音阶：距离相同时取较高音', () {
      final config = _c(
        [
          _n('a', 60, 0, 480),
          _n('lower', 58, 480, 480),
          _n('higher', 62, 480, 480),
        ],
        mode: MusicOverlapMode.nearest,
      );
      expect(
        _spansOf(config).map((span) => span.$1),
        containsAll(const ['a', 'higher']),
      );
    });

    test('新音符打断：后起始音符接管，旧音符从打断点灰到尾且不恢复', () {
      final config = _c([
        _n('a', 60, 0, 1920),
        _n('b', 64, 600, 600),
      ]);
      expect(_spansOf(config), [
        ('a', 0, 600, 60),
        ('b', 600, 1200, 64),
      ]);
      // a 在 1200..1920 不会恢复发声：a 只出现过一次区间。
      expect(
        _spansOf(config).where((span) => span.$1 == 'a'),
        hasLength(1),
      );
    });

    test('多重打断依次接管', () {
      final config = _c([
        _n('a', 60, 0, 1920),
        _n('b', 64, 300, 1920),
        _n('c', 67, 600, 300),
      ]);
      expect(_spansOf(config), [
        ('a', 0, 300, 60),
        ('b', 300, 600, 64),
        ('c', 600, 900, 67),
      ]);
    });

    test('不勾选打断 + 取高音：更高的后起始音符仍接管', () {
      final config = _c(
        [_n('a', 60, 0, 960), _n('b', 64, 480, 960)],
        mode: MusicOverlapMode.highest,
        interrupts: false,
      );
      expect(_spansOf(config), [('a', 0, 480, 60), ('b', 480, 1440, 64)]);
    });

    test('不勾选打断 + 取高音：更低的后起始音符整段不发声', () {
      final config = _c(
        [_n('a', 60, 0, 960), _n('b', 55, 480, 960)],
        mode: MusicOverlapMode.highest,
        interrupts: false,
      );
      expect(_spansOf(config), [('a', 0, 960, 60)]);
    });

    test('不勾选打断 + 取低音：更低的音符接管', () {
      final config = _c(
        [_n('a', 60, 0, 960), _n('b', 55, 480, 960)],
        mode: MusicOverlapMode.lowest,
        interrupts: false,
      );
      expect(_spansOf(config), [('a', 0, 480, 60), ('b', 480, 1440, 55)]);
    });

    test('不勾选打断 + 取最近音阶：正在发声的音符保持', () {
      final config = _c(
        [_n('a', 60, 0, 960), _n('b', 64, 480, 960)],
        mode: MusicOverlapMode.nearest,
        interrupts: false,
      );
      expect(_spansOf(config), [('a', 0, 960, 60)]);
    });

    test('三种策略在同一条重叠数据上给出不同结果', () {
      final notes = [
        _n('a', 62, 0, 960),
        _n('b', 60, 480, 960),
        _n('c', 67, 480, 480),
      ];
      expect(
        _spansOf(_c(notes, mode: MusicOverlapMode.highest)).last,
        ('c', 480, 960, 67),
      );
      expect(
        _spansOf(_c(notes, mode: MusicOverlapMode.lowest)).last,
        ('b', 480, 1440, 60),
      );
      expect(
        _spansOf(_c(notes, mode: MusicOverlapMode.nearest)).last,
        ('b', 480, 1440, 60),
        reason: '60 距离上一有效音高 62 更近',
      );
    });

    test('发声区间不变式：有序、不重叠、落在音符内部', () {
      final config = _c([
        _n('a', 60, 0, 1920),
        _n('b', 64, 300, 1920),
        _n('c', 67, 600, 300),
        _n('d', 55, 1950, 120),
      ]);
      final spans = MusicTimeline.soundingSpans(config);
      expect(spans, isNotEmpty);
      for (var index = 0; index < spans.length; index++) {
        final span = spans[index];
        expect(span.endTick, greaterThan(span.startTick));
        final note = config.notes.firstWhere((note) => note.id == span.noteId);
        expect(span.startTick, greaterThanOrEqualTo(note.startTick));
        expect(span.endTick, lessThanOrEqualTo(note.endTick));
        if (index > 0) {
          expect(
            span.startTick,
            greaterThanOrEqualTo(spans[index - 1].endTick),
            reason: '单声部区间不得重叠',
          );
        }
      }
    });

    test('非法音符被忽略，不会卡住裁决', () {
      final config = _c([
        _n('bad-pitch', 0, 0, 480),
        _n('bad-duration', 60, 0, 0),
        _n('ok', 62, 0, 480),
      ]);
      expect(_spansOf(config), [('ok', 0, 480, 62)]);
    });
  });

  group('重叠统计', () {
    test('同 tick 和弦算一处重叠', () {
      final config = _c([_n('a', 60, 0, 480), _n('b', 64, 0, 480)]);
      expect(MusicTimeline.overlapCount(config), 1);
    });

    test('两段分离的重叠分别计数', () {
      final config = _c([
        _n('a', 60, 0, 480),
        _n('b', 64, 240, 480),
        _n('c', 67, 960, 480),
        _n('d', 69, 1200, 480),
      ]);
      expect(MusicTimeline.overlapCount(config), 2);
    });

    test('连续重叠段（一个音结束、另一个紧接着开始）算一处', () {
      final config = _c([
        _n('a', 60, 0, 1440),
        _n('b', 64, 240, 240),
        _n('c', 67, 480, 240),
      ]);
      expect(MusicTimeline.overlapCount(config), 1);
    });

    test('首尾相衔接不算重叠', () {
      final config = _c([_n('a', 60, 0, 480), _n('b', 64, 480, 480)]);
      expect(MusicTimeline.overlapCount(config), 0);
    });

    test('包含关系算一处重叠', () {
      final config = _c([_n('a', 60, 0, 1920), _n('b', 64, 480, 480)]);
      expect(MusicTimeline.overlapCount(config), 1);
    });

    test('空工程与非法音符没有重叠', () {
      expect(MusicTimeline.overlapCount(MusicConfig()), 0);
      expect(
        MusicTimeline.overlapCount(
          _c([_n('a', 60, 0, 0), _n('b', 64, 0, 0)]),
        ),
        0,
      );
    });
  });

  group('派生数据', () {
    test('segments 与裁决结果一致（含 tempo）', () {
      final config = MusicConfig(
        notes: const [
          MusicNote(id: 'a', pitch: 60, startTick: 0, durationTicks: 480),
          MusicNote(id: 'b', pitch: 67, startTick: 0, durationTicks: 480),
        ],
        overlapMode: MusicOverlapMode.highest,
        tempoEvents: const [
          TempoEvent(tick: 0, microsecondsPerQuarter: 500000),
        ],
      );
      final segments = MusicTimeline.segments(config);
      expect(segments, hasLength(1));
      expect(segments.single.pitch, 67);
      expect(segments.single.durationMs, 500);
    });

    test('固件代码生成使用裁决后的音符', () {
      final config = MusicConfig(
        notes: const [
          MusicNote(id: 'a', pitch: 60, startTick: 0, durationTicks: 480),
          MusicNote(id: 'b', pitch: 67, startTick: 0, durationTicks: 480),
        ],
        overlapMode: MusicOverlapMode.highest,
      );
      final code = CodeGenerator.generate(config);
      expect(code, contains('{500UL, 67},'));
      expect(code, isNot(contains('{500UL, 60},')));
    });

    test('配置默认值与策略标签', () {
      final config = MusicConfig();
      expect(config.overlapMode, MusicOverlapMode.nearest);
      expect(config.newNoteInterrupts, isTrue);
      expect(MusicOverlapMode.highest.label, '取高音');
      expect(MusicOverlapMode.lowest.label, '取低音');
      expect(MusicOverlapMode.nearest.label, '取最近音阶');
    });
  });
}
