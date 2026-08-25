import 'package:pieblock_core/pieblock_core.dart';
import 'package:test/test.dart';

MusicConfig musicConfig() => MusicConfig(
  sourceName: 'melody.mid',
  trackName: '主旋律',
  notes: const [
    MusicNote(id: 'a', pitch: 60, startTick: 0, durationTicks: 480),
    MusicNote(
      id: 'a-ref',
      pitch: 67,
      startTick: 0,
      durationTicks: 960,
      primary: false,
    ),
    MusicNote(id: 'b', pitch: 62, startTick: 480, durationTicks: 480),
  ],
  tempoEvents: const [
    TempoEvent(tick: 0, microsecondsPerQuarter: 500000),
    TempoEvent(tick: 480, microsecondsPerQuarter: 1000000),
  ],
);

void main() {
  group('音乐项目', () {
    test('创建、JSON 往返和主音切换', () {
      final document = ProjectDocument.create(
        '音乐测试',
        ProjectKind.music,
      ).copyWith(config: musicConfig());
      final restored = ProjectDocument.fromJson(document.toJson());
      expect(restored.kind, ProjectKind.music);
      final config = restored.config as MusicConfig;
      expect(config.ticksPerQuarter, 480);
      expect(config.tempoEvents, hasLength(2));
      expect(
        config
            .promote('a-ref')
            .notes
            .singleWhere((n) => n.id == 'a-ref')
            .primary,
        isTrue,
      );
      expect(
        config.promote('a-ref').notes.singleWhere((n) => n.id == 'a').primary,
        isFalse,
      );
    });

    test('tempo map 累计、休止和重叠截断准确', () {
      final config = musicConfig().copyWith(
        notes: const [
          MusicNote(id: 'a', pitch: 60, startTick: 240, durationTicks: 960),
          MusicNote(id: 'b', pitch: 62, startTick: 720, durationTicks: 480),
        ],
      );
      final segments = MusicTimeline.segments(config);
      expect(segments.map((s) => s.pitch), [null, 60, 62]);
      expect(segments.map((s) => s.durationMs), [250, 750, 1000]);
    });

    test('MIDI 导出再解析保留全部音符、tempo 和拍号', () {
      final bytes = MidiCodec.write(musicConfig());
      final midi = MidiCodec.parse(bytes);
      expect(midi.format, 0);
      expect(midi.ticksPerQuarter, 480);
      expect(midi.tracks.single.melodicNoteCount, 3);
      expect(midi.tempoEvents, hasLength(2));
      expect(midi.timeSignatureEvents.single.denominator, 4);
      final selected = midi.selectTrack(0, sourceName: 'roundtrip.mid');
      expect(selected.notes, hasLength(3));
      expect(selected.notes.where((note) => note.primary), hasLength(2));
      expect(
        selected.notes
            .firstWhere((note) => note.startTick == 0 && note.primary)
            .pitch,
        67,
      );
    });

    test('最近音高选择平局时选择较高音', () {
      final source = MusicConfig(
        notes: const [
          MusicNote(id: 'a', pitch: 67, startTick: 0, durationTicks: 120),
          MusicNote(id: 'b', pitch: 65, startTick: 120, durationTicks: 120),
          MusicNote(
            id: 'c',
            pitch: 69,
            startTick: 120,
            durationTicks: 120,
            primary: false,
          ),
        ],
      );
      final imported = MidiCodec.parse(MidiCodec.write(source)).selectTrack(0);
      expect(
        imported.notes.firstWhere((n) => n.startTick == 120 && n.primary).pitch,
        69,
      );
    });

    test('校验空音乐、重复主音和非法事件', () {
      expect(ProjectValidator.validate(MusicConfig()), isNotEmpty);
      final invalid = MusicConfig(
        notes: const [
          MusicNote(id: 'a', pitch: 0, startTick: 0, durationTicks: 0),
          MusicNote(id: 'b', pitch: 60, startTick: 0, durationTicks: 10),
        ],
        tempoEvents: const [TempoEvent(tick: 1, microsecondsPerQuarter: 0)],
      );
      final messages = ProjectValidator.validate(invalid)
          .map((i) => i.message)
          .join('\n');
      expect(messages, contains('只能选择一个'));
      expect(messages, contains('音高'));
      expect(messages, contains('tick 0'));
    });

    test('生成单音固件且没有伪复音轮询', () {
      final code = CodeGenerator.generate(musicConfig());
      expect(code, contains('PWMB_CH3_P33'));
      expect(code, contains('musicFrequencies[segment->note]'));
      expect(code, contains('while (1)'));
      expect(code, contains('Music_Stop();'));
      expect(code, isNot(contains('Us_Delay')));
      expect(code, isNot(contains('voice_count')));
    });
  });
}
