import 'package:pieblock_core/pieblock_core.dart';
import 'package:test/test.dart';

MusicConfig musicConfig() => MusicConfig(
  sourceName: 'melody.mid',
  trackName: '主旋律',
  notes: const [
    MusicNote(id: 'a', pitch: 60, startTick: 0, durationTicks: 480),
    MusicNote(id: 'a-ref', pitch: 67, startTick: 0, durationTicks: 960),
    MusicNote(id: 'b', pitch: 62, startTick: 480, durationTicks: 480),
  ],
  tempoEvents: const [
    TempoEvent(tick: 0, microsecondsPerQuarter: 500000),
    TempoEvent(tick: 480, microsecondsPerQuarter: 1000000),
  ],
);

void main() {
  group('音乐项目', () {
    test('创建、JSON 往返与重叠设置默认值', () {
      final document = ProjectDocument.create(
        '音乐测试',
        ProjectKind.music,
      ).copyWith(config: musicConfig());
      final restored = ProjectDocument.fromJson(document.toJson());
      expect(restored.kind, ProjectKind.music);
      final config = restored.config as MusicConfig;
      expect(config.ticksPerQuarter, 480);
      expect(config.notes, hasLength(3));
      expect(config.overlapMode, MusicOverlapMode.nearest);
      expect(config.newNoteInterrupts, isTrue);
      expect(config.toJson()['overlap_mode'], 'nearest');
      expect(config.toJson()['new_note_interrupts'], isTrue);
      expect(
        config.notes.map((note) => note.toJson().keys),
        everyElement(isNot(contains('primary'))),
        reason: 'primary 概念已移除，不再写回工程文件',
      );
    });

    test('旧工程 JSON 里的 primary 被忽略、新字段取默认值', () {
      final restored = MusicConfig.fromJson({
        'ticks_per_quarter': 480,
        'notes': [
          {
            'id': 'a',
            'pitch': 60,
            'start_tick': 0,
            'duration_ticks': 480,
            'primary': true,
          },
        ],
        'tempo_events': [
          {'tick': 0, 'microseconds_per_quarter': 500000},
        ],
        'time_signature_events': [
          {'tick': 0, 'numerator': 4, 'denominator': 4},
        ],
      });
      expect(restored.notes.single.pitch, 60);
      expect(restored.notes.single.durationTicks, 480);
      expect(restored.overlapMode, MusicOverlapMode.nearest);
      expect(restored.newNoteInterrupts, isTrue);
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
      expect(
        selected.notes.map((note) => (note.pitch, note.startTick)),
        containsAll(const [(60, 0), (67, 0), (62, 480)]),
      );
    });

    test('Format 1 多轨文件按轨道长度连续解析', () {
      final midi = MidiCodec.parse([
        0x4d,
        0x54,
        0x68,
        0x64,
        0,
        0,
        0,
        6,
        0,
        1,
        0,
        2,
        1,
        0xe0,
        0x4d,
        0x54,
        0x72,
        0x6b,
        0,
        0,
        0,
        4,
        0,
        0xff,
        0x2f,
        0,
        0x4d,
        0x54,
        0x72,
        0x6b,
        0,
        0,
        0,
        12,
        0,
        0x90,
        60,
        100,
        0x83,
        0x60,
        0x80,
        60,
        0,
        0,
        0xff,
        0x2f,
        0,
      ]);

      expect(midi.format, 1);
      expect(midi.tracks, hasLength(2));
      expect(midi.tracks[1].notes.single.durationTicks, 480);
    });

    test('MIDI 导入保留和弦/重叠音并透传重叠策略', () {
      final source = MusicConfig(
        notes: const [
          MusicNote(id: 'a', pitch: 67, startTick: 0, durationTicks: 120),
          MusicNote(id: 'b', pitch: 65, startTick: 120, durationTicks: 120),
          MusicNote(id: 'c', pitch: 69, startTick: 120, durationTicks: 120),
        ],
      );
      final imported = MidiCodec.parse(MidiCodec.write(source)).selectTrack(
        0,
        overlapMode: MusicOverlapMode.lowest,
        newNoteInterrupts: false,
      );
      expect(imported.notes, hasLength(3), reason: '和弦不再被丢弃');
      expect(imported.overlapMode, MusicOverlapMode.lowest);
      expect(imported.newNoteInterrupts, isFalse);
      expect(
        imported.notes
            .where((note) => note.startTick == 120)
            .map((note) => note.pitch),
        containsAll(const [65, 69]),
      );
    });

    test('校验空音乐、非法音符与重叠警告', () {
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
      expect(messages, contains('音高'));
      expect(messages, contains('tick 0'));

      // 重叠只是 warning，不阻止生成/烧录。
      final overlapped = MusicConfig(
        notes: const [
          MusicNote(id: 'a', pitch: 60, startTick: 0, durationTicks: 960),
          MusicNote(id: 'b', pitch: 64, startTick: 480, durationTicks: 960),
        ],
      );
      final issues = ProjectValidator.validate(overlapped);
      expect(
        issues.where((issue) => issue.severity == IssueSeverity.error),
        isEmpty,
      );
      expect(
        issues
            .where((issue) => issue.severity == IssueSeverity.warning)
            .single
            .message,
        contains('1 处音符重叠'),
      );
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
