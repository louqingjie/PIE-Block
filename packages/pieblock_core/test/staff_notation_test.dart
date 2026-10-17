// 五线谱显示模型 / 调号 / 代码生成数据表的回归测试。

import 'dart:convert';

import 'package:pieblock_core/pieblock_core.dart';
import 'package:test/test.dart';

MusicConfig _twinkle({int keySignatureFifths = 0}) {
  const melody = <int>[60, 60, 67, 67, 69, 69, 67, 65, 65, 64, 64, 62, 62, 60];
  const durations = <int>[
    480, 480, 480, 480, 480, 480, 960, //
    480, 480, 480, 480, 480, 480, 960,
  ];
  final notes = <MusicNote>[];
  var tick = 0;
  for (var i = 0; i < melody.length; i++) {
    notes.add(
      MusicNote(
        id: 'n$i',
        pitch: melody[i],
        startTick: tick,
        durationTicks: durations[i],
      ),
    );
    tick += durations[i];
  }
  return MusicConfig(
    ticksPerQuarter: 480,
    notes: notes,
    keySignatureFifths: keySignatureFifths,
  );
}

void main() {
  group('显示事件', () {
    test('twinkle：14 个发声事件，时长之和与音频一致', () {
      final song = buildStaffSong(_twinkle());
      expect(song.events, hasLength(14));
      expect(song.events.every((event) => !event.isRest), isTrue);
      expect(song.events.first.pitch, 60);
      final displayMs = song.events.fold<int>(
        0,
        (total, event) => total + event.durationMs,
      );
      final audioMs = MusicTimeline.segments(_twinkle())
          .fold<int>(0, (total, segment) => total + segment.durationMs);
      expect((displayMs - audioMs).abs(), lessThan(60));
    });

    test('休止拆成标准时值事件', () {
      final config = MusicConfig(
        ticksPerQuarter: 480,
        notes: const <MusicNote>[
          MusicNote(id: 'a', pitch: 60, startTick: 0, durationTicks: 480),
          MusicNote(id: 'b', pitch: 62, startTick: 1440, durationTicks: 480),
        ],
      );
      final song = buildStaffSong(config);
      expect(song.events, hasLength(3));
      expect(song.events[1].isRest, isTrue);
      expect(song.events[1].tickDuration, 960);
      expect(song.events[1].noteValue.code, 1); // 二分休止
      expect(song.events[1].durationMs, greaterThan(0));
    });

    test('降号调按拼写定位：Ab4 在 A 间、Bb4 在 B 线', () {
      final config = MusicConfig(
        ticksPerQuarter: 480,
        keySignatureFifths: -1,
        notes: const <MusicNote>[
          MusicNote(id: 'ab', pitch: 68, startTick: 0, durationTicks: 480),
          MusicNote(id: 'bb', pitch: 70, startTick: 480, durationTicks: 480),
          MusicNote(id: 'gb', pitch: 66, startTick: 960, durationTicks: 480),
        ],
      );
      final song = buildStaffSong(config);
      // step 相对高音谱号底线 E4（30）：A4=33→3，B4=34→4，G4=32→2。
      expect(song.events[0].step, 3);
      expect(song.events[1].step, 4);
      expect(song.events[2].step, 2);
      // F 大调调号里已有 Bb，所以 Bb4 不画临时记号；Ab4/Gb4 才画降号。
      expect(song.events.map((event) => event.accidental), <int>[2, 0, 2]);
    });

    test('调号内音不画临时记号，取消升号时画还原号', () {
      final config = MusicConfig(
        ticksPerQuarter: 480,
        notes: const <MusicNote>[
          MusicNote(id: 'fsharp', pitch: 66, startTick: 0, durationTicks: 480),
          MusicNote(id: 'f', pitch: 65, startTick: 480, durationTicks: 480),
          MusicNote(
            id: 'fsharp2',
            pitch: 66,
            startTick: 960,
            durationTicks: 480,
          ),
        ],
      );
      final song = buildStaffSong(config);
      expect(song.events[0].accidental, 1); // ♯
      expect(song.events[1].accidental, 3); // ♮
      expect(song.events[2].accidental, 1); // 再次 ♯
    });

    test('跨小节复位：下一小节同音不再画还原号', () {
      final config = MusicConfig(
        ticksPerQuarter: 480,
        notes: const <MusicNote>[
          MusicNote(id: 'a', pitch: 66, startTick: 0, durationTicks: 480),
          // 第二小节（tick 1920 起）里 F 自然音，不需要还原号。
          MusicNote(id: 'b', pitch: 65, startTick: 1920, durationTicks: 480),
        ],
      );
      final song = buildStaffSong(config);
      expect(song.events[0].accidental, 1);
      expect(song.events[1].accidental, 0);
    });

    test('自动谱号：低音区用低音谱号，跨音域后换高音谱号', () {
      final config = MusicConfig(
        ticksPerQuarter: 480,
        notes: const <MusicNote>[
          MusicNote(id: 'a', pitch: 43, startTick: 0, durationTicks: 480),
          MusicNote(id: 'b', pitch: 45, startTick: 480, durationTicks: 480),
          MusicNote(id: 'c', pitch: 72, startTick: 960, durationTicks: 480),
          MusicNote(id: 'd', pitch: 74, startTick: 1440, durationTicks: 480),
        ],
      );
      final song = buildStaffSong(config);
      expect(song.events.first.clef, 1); // 低音谱号
      expect(song.events.last.clef, 0); // 高音谱号
      expect(song.events.map((event) => event.clef).toSet(), {0, 1});
    });

    test('时值编码与拍数对应', () {
      expect(staffNoteValueForBeats(4).value.code, 0);
      expect(staffNoteValueForBeats(3).value.code, 2);
      expect(staffNoteValueForBeats(2).value.code, 1);
      expect(staffNoteValueForBeats(1.5).value.code, 4);
      expect(staffNoteValueForBeats(1).value.code, 3);
      expect(staffNoteValueForBeats(0.75).value.code, 6);
      expect(staffNoteValueForBeats(0.5).value.code, 5);
      expect(staffNoteValueForBeats(0.25).value.code, 7);
      for (var code = 0; code <= 8; code++) {
        expect(staffNoteValueForCode(code).code, code);
      }
    });
  });

  group('调号与配置', () {
    test('调号纵向位置表', () {
      final gMajor = buildStaffSong(_twinkle(keySignatureFifths: 1));
      expect(gMajor.keyCount, 1);
      expect(gMajor.keyIsSharp, isTrue);
      expect(gMajor.keyStepsTreble, <int>[8]);
      expect(gMajor.keyStepsBass, <int>[6]);
      final fMajor = buildStaffSong(_twinkle(keySignatureFifths: -1));
      expect(fMajor.keyIsSharp, isFalse);
      expect(fMajor.keyStepsTreble, <int>[4]);
      expect(fMajor.keyStepsBass, <int>[2]);
      final seven = buildStaffSong(_twinkle(keySignatureFifths: 7));
      expect(seven.keyStepsTreble, <int>[8, 5, 9, 6, 3, 7, 4]);
    });

    test('MusicConfig JSON 调号往返', () {
      final json = _twinkle(keySignatureFifths: -3).toJson();
      expect(json['key_signature_fifths'], -3);
      final restored = MusicConfig.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, Object?>,
      );
      expect(restored.keySignatureFifths, -3);
      // 旧工程缺字段时默认 C 大调。
      final legacy = Map<String, Object?>.from(json)
        ..remove('key_signature_fifths');
      expect(MusicConfig.fromJson(legacy).keySignatureFifths, 0);
    });

    test('调号越界被校验器拦下', () {
      final config = _twinkle(keySignatureFifths: 8);
      final issues = ProjectValidator.validate(config);
      expect(
        issues.any(
          (issue) =>
              issue.severity == IssueSeverity.error &&
              issue.message.contains('调号'),
        ),
        isTrue,
      );
    });
  });

  group('MIDI 调号', () {
    test('写出再解析保留调号', () {
      for (final fifths in <int>[0, 2, -3, 7, -7]) {
        final bytes = MidiCodec.write(_twinkle(keySignatureFifths: fifths));
        final parsed = MidiCodec.parse(bytes);
        expect(parsed.keySignatureFifths, fifths);
        final selected = parsed.selectTrack(0);
        expect(selected.keySignatureFifths, fifths);
      }
    });

    test('没有调号 meta 的 MIDI 默认 C 大调', () {
      // 手工构造一个只有轨名的 MIDI（无 0x59 meta）。
      final track = <int>[
        0x00, 0xff, 0x03, 0x03, 0x61, 0x62, 0x63, // track name "abc"
        0x00, 0xff, 0x2f, 0x00,
      ];
      final file = <int>[
        ...'MThd'.codeUnits,
        0x00,
        0x00,
        0x00,
        0x06,
        0x00,
        0x00,
        0x00,
        0x01,
        0x01,
        0xe0,
        ...'MTrk'.codeUnits,
        0x00,
        0x00,
        0x00,
        track.length,
        ...track,
      ];
      final parsed = MidiCodec.parse(file);
      expect(parsed.keySignatureFifths, 0);
    });
  });

  group('代码生成备注', () {
    test('音乐 main.c 含 SDCC 五线谱分支与 Keil 回退分支', () {
      final code = CodeGenerator.generate(_twinkle());
      expect(code, contains('#if defined(__SDCC)'));
      expect(code, contains('OLED_Staff.h'));
      expect(code, contains('STAFF_EVENT_COUNT'));
      expect(code, contains('static const StaffSong staffSong'));
      expect(code, contains('OLEDStaff_Show(&staffSong, i)'));
      expect(code, contains('#else'));
      expect(code, contains('musicSegments'));
      expect(code, contains('#define MUSIC_SEGMENT_COUNT '));
      expect(code, contains('STAFF_EVENT_COUNT 14'));
      expect(code, contains('PWMB_CH3_P33'));
    });

    test('代码生成器发射的字形行/事件数与模型一致', () {
      final song = buildStaffSong(_twinkle());
      final tables = emitStaffFirmwareTables(song, prefix: 'staff');
      expect(tables, contains('#define STAFF_EVENT_COUNT 14'));
      expect(tables, contains('staffGlyphRows[]'));
      expect(tables, contains('staffGlyphDescs[]'));
      expect(tables, contains('staffSong'));
      expect(tables, contains('staffKeyStepsTreble'));
    });
  });
}
