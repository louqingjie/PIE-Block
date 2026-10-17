// OLED 五线谱模拟器的几何/乐理映射回归测试。
//
// 新结构下这些断言锁定的是“模拟器与固件共用”的唯一事实来源：
//   - 乐理/事件/时值/调号拼写 → pieblock_core 的 staff_notation.dart；
//   - 整数版面（x 布局 / y / 固定区 / 小节线 / 光标）→ staff_layout.dart；
//   - 字形点阵 → staff_glyphs.dart；
//   - 模拟器只负责落笔（tool/staff_render.dart）。
//
// 与固件的主机对拍 fixture 见 test/staff_fixture_test.dart。

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pieblock_core/pieblock_core.dart';

import '../tool/render_oled_staff.dart';

MusicConfig twinkle() => demoConfig('twinkle');

MusicConfig configWithNotes(List<MusicNote> notes) => MusicConfig(
  notes: notes,
  ticksPerQuarter: 480,
  timeSignatureEvents: const <TimeSignatureEvent>[
    TimeSignatureEvent(tick: 0, numerator: 4, denominator: 4),
  ],
);

void main() {
  group('音高映射（core 单一来源）', () {
    test('按调号拼写后的全音阶序号 / 谱表步数', () {
      expect(spelledDiatonicIndex(60, 0), 28); // C4
      expect(spelledDiatonicIndex(64, 0), 30); // E4
      expect(spelledDiatonicIndex(43, 0), 18); // G2

      expect(staffStepForPitch(60, 0, 0), -2); // C4 高音谱号下加线
      expect(staffStepForPitch(64, 0, 0), 0); // E4 底线
      expect(staffStepForPitch(67, 0, 0), 2); // G4 第 2 线
      expect(staffStepForPitch(77, 0, 0), 8); // F5 顶线
      expect(staffStepForPitch(43, 1, 0), 0); // G2 低音谱号底线
      expect(staffStepForPitch(60, 1, 0), 10); // C4 低音谱号上加线
    });

    test('谱表步数 → 整数 y（staffYForStep = 38 - step*6~/2）', () {
      expect(staffBottomLineY(), 38);
      expect(staffYForStep(-2), 44); // C4 高音谱号下加线
      expect(staffYForStep(0), 38); // E4 底线
      expect(staffYForStep(2), 32); // G4 第 2 线
      expect(staffYForStep(8), 14); // F5 顶线
      expect(staffYForStep(10), 8); // C4 低音谱号上加线
      expect(staffYForStep(12), 2); // C6 高音谱号上加线
    });

    test('加线数量', () {
      expect(staffLedgerCountForStep(-2), 1); // C4
      expect(staffLedgerCountForStep(-4), 2); // A3
      expect(staffLedgerCountForStep(9), 0); // G5（顶线上方的间）
      expect(staffLedgerCountForStep(10), 1); // A5
      expect(staffLedgerCountForStep(12), 2); // C6
    });

    test('符干方向按中线判断', () {
      expect(staffStemUpForStep(-2), isTrue); // C4 中线以下，符干向上
      expect(staffStemUpForStep(5), isFalse); // C5 中线以上，符干向下
      expect(staffStemUpForStep(4), isFalse); // B4 中线上，符干向下
    });

    test('按调号拼写定位：Ab4 在 A 间、G#4 在 G 线、Bb4 在 B 线', () {
      // 同一个 MIDI 音高在不同调号下记谱位置不同。
      expect(staffYForStep(staffStepForPitch(68, 0, -1)), 29); // Ab4（A 间）
      expect(staffYForStep(staffStepForPitch(68, 0, 0)), 32); // G#4（G 线）
      expect(staffYForStep(staffStepForPitch(70, 0, -1)), 26); // Bb4（B 线）
      expect(staffYForStep(staffStepForPitch(66, 0, -1)), 32); // Gb4（G 线）
      expect(staffYForStep(staffStepForPitch(46, 1, -1)), 32); // Bb2（低音 B 线）
      expect(staffLedgerCountForStep(staffStepForPitch(68, 0, -1)), 0);
      expect(staffStemUpForStep(staffStepForPitch(68, 0, -1)), isTrue);
    });

    test('降号演示：Ab4 记在 A 间，降号紧贴符头左侧', () {
      final renderer = StaffRenderer(config: demoConfig('flats'));
      final frame = renderer.renderFrame(0);
      final song = renderer.song;
      expect(song.keyFifths, -1);
      expect(song.events.first.accidental, 2, reason: 'Ab4 需要降号');
      final x = staffLayoutX(song, 0)[0];
      final y = staffYForStep(song.events.first.step);
      expect(x, renderer.cursorX);
      expect(y, 29);
      final left = x - flatGlyph.width - 3;
      final top = y - flatGlyph.height ~/ 2;
      // 4×7 降号：左侧竖线 + 底部闭合圆弧。
      expect(frame.pixel(left, top), isTrue, reason: '降号竖线顶缺失');
      expect(frame.pixel(left, top + 4), isTrue, reason: '降号圆弧左上缺失');
      expect(frame.pixel(left + 1, top + 4), isTrue, reason: '降号圆弧上横缺失');
      // 和符头（左沿 x-2）之间留 1px 空隙。
      expect(frame.pixel(left + 4, y), isFalse, reason: '降号与符头之间应有 1px 空隙');
      expect(frame.pixel(x - 2, y), isTrue, reason: '符头左沿缺失');
    });
  });

  group('时值（core）', () {
    test('标准时值映射', () {
      String value(double beats) =>
          staffNoteValueForBeats(beats).value.toString();
      expect(value(4), '1/1');
      expect(value(3), '1/2.');
      expect(value(2), '1/2');
      expect(value(1.5), '1/4.');
      expect(value(1), '1/4');
      expect(value(0.75), '1/8.');
      expect(value(0.5), '1/8');
      expect(value(0.25), '1/16');
    });

    test('三连音等非标准时值标记为近似', () {
      final result = staffNoteValueForBeats(1 / 3);
      expect(result.approx, isTrue);
    });

    test('时值编码与固件一致（0 全音符 … 8 附点十六分）', () {
      expect(staffNoteValueForCode(0).denominator, 1);
      expect(staffNoteValueForCode(1).denominator, 2);
      expect(staffNoteValueForCode(2).dots, 1);
      expect(staffNoteValueForCode(3).denominator, 4);
      expect(staffNoteValueForCode(5).denominator, 8);
      expect(staffNoteValueForCode(7).denominator, 16);
    });
  });

  group('调号', () {
    test('调号升降号个数', () {
      expect(staffKeyFifths('C'), 0);
      expect(staffKeyFifths('G'), 1);
      expect(staffKeyFifths('F'), -1);
      expect(staffKeyFifths('Bb'), -2);
      expect(staffKeyFifths('F#'), 6);
      expect(staffKeyFifths('Am'), 0);
      expect(() => staffKeyFifths('H'), throwsArgumentError);
    });

    test('内置示例的调号：wide=G、bass=F、flats=F、sevenSharps=C#，其余 C', () {
      expect(demoConfig('wide').keySignatureFifths, 1);
      expect(demoConfig('bass').keySignatureFifths, -1);
      expect(demoConfig('flats').keySignatureFifths, -1);
      expect(demoConfig('sevenSharps').keySignatureFifths, 7);
      for (final demo in <String>[
        'twinkle',
        'mixed',
        'chromatic',
        'accidentals',
        'rests',
      ]) {
        expect(demoConfig(demo).keySignatureFifths, 0, reason: demo);
      }
      expect(staffDemoKeyFifths['wide'], 1);
      expect(staffDemoKeyFifths['flats'], -1);
    });

    test('音名字母的调号升降', () {
      expect(keyAlterationForLetter(3, 1), 1); // G 调：F#
      expect(keyAlterationForLetter(0, 1), 0); // G 调：C 不变
      expect(keyAlterationForLetter(6, -1), -1); // F 调：Bb
    });

    test('按调号拼写音名', () {
      expect(spellPitch(61, 0).name, 'C#4');
      expect(spellPitch(61, -1).name, 'Db4');
      expect(spellPitch(70, 0).name, 'A#4');
      expect(spellPitch(70, -1).name, 'Bb4');
      expect(spellPitch(60, 0).name, 'C4');
      expect(spellPitch(61, 7).name, 'C#4');
    });

    test('调号位置表（高音/低音各一套）', () {
      expect(staffKeyStepsForClef(1, bass: false), <int>[8]); // F5
      expect(staffKeyStepsForClef(-1, bass: false), <int>[4]); // B4
      expect(staffKeyStepsForClef(1, bass: true), <int>[6]); // F3
      expect(staffKeyStepsForClef(-1, bass: true), <int>[2]); // B2
      expect(staffKeyStepsForClef(7, bass: false), <int>[8, 5, 9, 6, 3, 7, 4]);
      expect(staffKeyStepsForClef(-7, bass: true), <int>[2, 5, 1, 4, 0, 3, -1]);
      expect(staffKeyStepsForClef(0, bass: false), isEmpty);
    });

    test('key --key 覆盖：wide 默认 G，覆盖成 C/F 后 FIFTHS 变化', () {
      expect(StaffRenderer(config: demoConfig('wide')).fifths, 1);
      expect(
        StaffRenderer(
          config: demoConfig('wide'),
          options: const RenderOptions(key: 'C'),
        ).fifths,
        0,
      );
      expect(
        StaffRenderer(
          config: demoConfig('wide'),
          options: const RenderOptions(key: 'F'),
        ).fifths,
        -1,
      );
      expect(keyNameForFifths(7), 'C#');
      expect(keyNameForFifths(-1), 'F');
    });
  });

  group('字形与遮罩', () {
    test('字形表与固件 enum 顺序一致（22 个，行宽 ≤ 16）', () {
      expect(staffGlyphList, hasLength(staffFirmwareGlyphCount));
      expect(staffFirmwareGlyphCount, 22);
      expect(StaffGlyphId.values, hasLength(22));
      expect(digitGlyphs, hasLength(10));
      for (final glyph in staffGlyphList) {
        expect(glyph.height, greaterThan(0));
        expect(glyph.width, inInclusiveRange(1, 16));
        for (final row in glyph.rows) {
          expect(row.length, glyph.width, reason: '字形行宽必须一致');
        }
      }
    });

    test('升号完整显示，谱线不会填满中间的空心', () {
      expect(sharpGlyph.width, 5);
      expect(sharpGlyph.height, 7);
      final renderer = StaffRenderer(
        config: configWithNotes(<MusicNote>[
          MusicNote(id: 'n0', pitch: 78, startTick: 0, durationTicks: 480),
        ]),
      );
      final frame = renderer.renderFrame(0);
      final x = staffLayoutX(renderer.song, 0)[0];
      final step = renderer.song.events.first.step;
      final y = staffYForStep(step);
      expect(y, 14, reason: 'F#5 在顶线上，临时升号会压在谱线上');
      final left = x - sharpGlyph.width - 3;
      final top = y - sharpGlyph.height ~/ 2;
      // 第 3 行是 '.#.#.'：两根竖线保留、三处空心全黑，
      // 说明谱线像素被擦掉，没有把洞填成“日”。
      final middle = top + 3;
      expect(frame.pixel(left + 1, middle), isTrue, reason: '左竖线缺失');
      expect(frame.pixel(left + 3, middle), isTrue, reason: '右竖线缺失');
      for (final col in <int>[0, 2, 4]) {
        expect(
          frame.pixel(left + col, middle),
          isFalse,
          reason: '升号空心列 $col 被谱线填充',
        );
      }
    });

    test('还原号是紧凑 ♮ 形状（中间只留 1px 空洞）', () {
      expect(naturalGlyph.rows, <String>[
        '#..',
        '#..',
        '###',
        '#.#',
        '###',
        '..#',
        '..#',
      ]);
      final renderer = StaffRenderer(
        config: configWithNotes(<MusicNote>[
          MusicNote(id: 'n0', pitch: 78, startTick: 0, durationTicks: 480),
          // 同小节内 F#5 之后再出现 F5：需要还原号取消升号。
          MusicNote(id: 'n1', pitch: 77, startTick: 480, durationTicks: 480),
        ]),
      );
      final frame = renderer.renderFrame(1);
      expect(renderer.song.events[1].accidental, 3, reason: 'F5 需要还原号');
      final x = staffLayoutX(renderer.song, 1)[1];
      expect(x, renderer.cursorX);
      final y = staffYForStep(renderer.song.events[1].step);
      expect(y, 14);
      final left = x - naturalGlyph.width - 3;
      final top = y - naturalGlyph.height ~/ 2;
      // 上段只有左竖线，下段只有右竖线。
      expect(frame.pixel(left, top), isTrue, reason: '左上竖线缺失');
      expect(frame.pixel(left + 1, top), isFalse);
      expect(frame.pixel(left + 2, top + 6), isTrue, reason: '右下竖线缺失');
      expect(frame.pixel(left, top + 6), isFalse);
      // 中性行（压在谱线上，字形第 4 行 '#.#'）：
      // 两根竖线保留、中间 1px 空洞不被谱线填充。
      final middle = y;
      expect(frame.pixel(left, middle), isTrue);
      expect(frame.pixel(left + 2, middle), isTrue);
      expect(
        frame.pixel(left + 1, middle),
        isFalse,
        reason: '还原号中间 1px 空洞被谱线填充',
      );
    });
  });

  group('帧缓冲与位序', () {
    test('页格式字节序（bit0 = 页内最上一行）', () {
      final bitmap = Bitmap(screenWidth, screenHeight);
      expect(bitmap.bytes.length, frameBytes);
      expect(frameBytes, 1024);
      bitmap.setPixel(0, 0);
      expect(bitmap.bytes[0], 1);
      bitmap.setPixel(0, 7);
      expect(bitmap.bytes[0], 0x81);
      bitmap.setPixel(0, 8);
      expect(bitmap.bytes[128], 1);
      bitmap.setPixel(127, 63);
      expect(bitmap.bytes[1023] & 0x80, 0x80);
      expect(bitmap.pixel(127, 63), isTrue);
      expect(bitmap.pixel(126, 63), isFalse);
    });

    test('PNG 编码头正确', () {
      final png = encodePngGray(
        2,
        2,
        Uint8List.fromList(<int>[0, 255, 255, 0]),
      );
      expect(png.sublist(0, 8), <int>[
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
      ]);
      final header = ByteData.sublistView(png);
      expect(header.getUint32(16), 2); // width
      expect(header.getUint32(20), 2); // height
    });
  });

  group('乐谱解析与整数版面', () {
    test('发声区间 + 休止拆分成事件（buildStaffSong）', () {
      final twinkleSong = buildStaffSong(twinkle());
      expect(twinkleSong.events, hasLength(14));
      expect(twinkleSong.events.every((event) => !event.isRest), isTrue);
      expect(twinkleSong.events.first.pitch, 60);
      expect(staffStartTickOf(twinkleSong, 13), 6720);

      final restSong = buildStaffSong(demoConfig('rests'));
      expect(restSong.events, hasLength(8));
      expect(restSong.events.where((event) => event.isRest), hasLength(3));
      expect(restSong.events.first.pitch, 60);
      expect(restSong.events[1].noteValue.denominator, 4); // 1 拍休止
      expect(restSong.events[3].noteValue.denominator, 2); // 2 拍休止
      expect(restSong.events[6].noteValue.denominator, 8); // 半拍休止
    });

    test('拍号与小节线', () {
      final renderer = StaffRenderer(config: twinkle());
      expect(renderer.song.timeNumerator, 4);
      expect(renderer.song.timeDenominator, 4);
      expect(renderer.barTicks, 1920);
      final lines = staffBarLineXs(renderer.song, 0);
      expect(lines, isNotEmpty);
      for (final x in lines) {
        expect(x, inInclusiveRange(renderer.noteAreaStart, screenWidth - 1));
      }
      // 第 0 帧 playTick=0：第一根可见小节线在 1920 tick 后 = 64px。
      expect(lines.first, renderer.cursorX + 64);
      // 每根线间距 = barTicks 对应的像素。
      for (var i = 1; i < lines.length; i++) {
        expect(lines[i] - lines[i - 1], 64);
      }
    });

    test('整数版面：固定区宽度/隔离带/光标位置', () {
      int panel(int fifths) =>
          staffPanelWidth(keyCount: fifths.abs(), timeDigits: 1);
      expect(panel(0), 25);
      expect(panel(1), 31);
      expect(panel(2), 37);
      expect(panel(7), 67);
      expect(staffNoteAreaStart(keyCount: 0, timeDigits: 1), 31);
      expect(staffNoteAreaStart(keyCount: 1, timeDigits: 1), 37);
      expect(staffCursorX(31), 31 + ((screenWidth - 31) * 3 ~/ 10));
      expect(staffCursorX(31), 60);
      expect(staffCursorX(37), 64);

      final cMajor = StaffRenderer(config: twinkle());
      expect(cMajor.panelWidth, 25);
      expect(cMajor.noteAreaStart, 31);
      expect(cMajor.cursorX, 60);
      expect(cMajor.fifths, 0);

      final gMajor = StaffRenderer(
        config: demoConfig('twinkle'),
        options: const RenderOptions(key: 'G'),
      );
      expect(gMajor.panelWidth, 31);
      expect(gMajor.noteAreaStart, 37);
      expect(gMajor.cursorX, 64);
    });

    test('staffRoundDiv 与 Dart double.round 一致（半值远离 0）', () {
      expect(staffRoundDiv(1, 2), 1);
      expect(staffRoundDiv(-1, 2), -1);
      expect(staffRoundDiv(3, 2), 2);
      expect(staffRoundDiv(-3, 2), -2);
      expect(staffRoundDiv(2, 3), 1);
      expect(staffRoundDiv(-2, 3), -1);
      expect(staffRoundDiv(0, 480), 0);
      expect(staffRoundDiv(192, 480), 0);
      expect(staffRoundDiv(240, 480), 1);
    });

    test('当前音符固定在 cursorX，后续音符按最小间距递增', () {
      final renderer = StaffRenderer(config: twinkle());
      final song = renderer.song;
      final xs = staffLayoutX(song, 0);
      expect(xs, hasLength(song.events.length));
      expect(xs[0], renderer.cursorX);
      for (var i = 1; i < xs.length; i++) {
        final advance = staffAdvanceFor(
          song.events[i],
          clefChange: staffClefChangeAt(song, i),
        );
        expect(
          xs[i] - xs[i - 1],
          greaterThanOrEqualTo(advance),
          reason: '事件 $i 的最小间距被破坏',
        );
      }
      // 第 0 帧的右侧没有 16 分音符挤压时，按 tick 比例排列。
      expect(xs[1] - xs[0], 16);
      expect(xs[2] - xs[1], 16);
    });

    test('推进宽度：休止 7 / 音符 6 / 临时记号 +4 / 换谱号 +16', () {
      final accidentals = buildStaffSong(demoConfig('accidentals'));
      final first = accidentals.events.first;
      expect(first.accidental, isNot(0));
      expect(staffAdvanceFor(first, clefChange: false), staffMinNoteGap + 4);
      final rests = buildStaffSong(demoConfig('rests'));
      expect(staffAdvanceFor(rests.events[1], clefChange: false), 7);
      final mixed = buildStaffSong(demoConfig('mixed'));
      final clefChangeIndex = List<int>.generate(
        mixed.events.length,
        (i) => i,
      ).firstWhere((i) => staffClefChangeAt(mixed, i), orElse: () => -1);
      expect(clefChangeIndex, greaterThan(0), reason: 'mixed 应当发生换谱号');
      expect(
        staffAdvanceFor(mixed.events[clefChangeIndex], clefChange: true),
        staffAdvanceFor(mixed.events[clefChangeIndex], clefChange: false) + 16,
      );
    });

    test('自动谱号：低音旋律用低音谱号，跨音域时切换', () {
      final mixed = buildStaffSong(demoConfig('mixed'));
      expect(mixed.events.first.clef, 1, reason: 'mixed 开头在低音区');
      expect(mixed.events.last.clef, 0, reason: 'mixed 结尾在高音区');
      expect(mixed.events.map((event) => event.clef).toSet(), <int>{0, 1});

      final twinkleSong = buildStaffSong(twinkle());
      expect(twinkleSong.events.every((event) => event.clef == 0), isTrue);
    });

    test('强制谱号覆盖自动选择', () {
      final renderer = StaffRenderer(
        config: demoConfig('mixed'),
        options: const RenderOptions(clef: 'treble'),
      );
      expect(renderer.events.every((event) => event.clef == 0), isTrue);
      expect(
        renderer.events
            .where((event) => !event.isRest)
            .every(
              (event) =>
                  event.step ==
                  staffStepForPitch(event.pitch, 0, renderer.fifths),
            ),
        isTrue,
      );
      final bass = StaffRenderer(
        config: demoConfig('mixed'),
        options: const RenderOptions(clef: 'bass'),
      );
      expect(bass.events.every((event) => event.clef == 1), isTrue);
    });

    test('换谱号处绘制小谱号（落在滚动区内才画）', () {
      final renderer = StaffRenderer(config: demoConfig('mixed'));
      final song = renderer.song;
      final changeIndex = List<int>.generate(
        song.events.length,
        (i) => i,
      ).firstWhere((i) => staffClefChangeAt(song, i));
      final xs = staffLayoutX(song, changeIndex);
      final x = xs[changeIndex];
      expect(x - 16, greaterThanOrEqualTo(renderer.noteAreaStart));
      final frame = renderer.renderFrame(changeIndex);
      // 换谱号符号用当前事件的谱号字形画在 x-16。
      final clef = song.events[changeIndex].clef;
      final glyph = clef == 1 ? bassClefGlyph : trebleClefGlyph;
      // 找字形中第一个 '#' 的位置，断言该像素被点亮。
      var found = false;
      for (var row = 0; row < glyph.height && !found; row++) {
        final col = glyph.rows[row].indexOf('#');
        if (col < 0) continue;
        final top = clef == 1 ? staffTop + staffSpace - 4 : staffTop - 2;
        expect(
          frame.pixel(x - 16 + col, top + row),
          isTrue,
          reason: '换谱号字形 (row=$row, col=$col) 未绘制',
        );
        found = true;
      }
      expect(found, isTrue);
    });

    test('左端固定区（含隔离带）是禁区：滚动内容不得侵入', () {
      List<int> panelPixels(StaffRenderer renderer, Bitmap frame) => <int>[
        for (var x = 0; x < renderer.noteAreaStart; x++)
          for (var y = 0; y < screenHeight; y++) frame.pixel(x, y) ? 1 : 0,
      ];
      for (final demo in <String>['twinkle', 'wide', 'bass']) {
        final renderer = StaffRenderer(config: demoConfig(demo));
        final frames = renderer.renderAll();
        final reference = panelPixels(renderer, frames.first);
        for (var i = 1; i < frames.length; i++) {
          expect(
            panelPixels(renderer, frames[i]),
            reference,
            reason: '$demo frame $i 的固定区被滚动内容覆盖',
          );
        }
      }
    });

    test('每帧都是 1024 字节且确定性', () {
      final renderer = StaffRenderer(config: twinkle());
      final frames = renderer.renderAll();
      expect(frames, hasLength(14));
      for (final frame in frames) {
        expect(frame.bytes.length, frameBytes);
      }
      expect(renderer.isDeterministic(0), isTrue);
      expect(renderer.isDeterministic(7), isTrue);
    });

    test('高/低音谱号下示例里的音符都在屏内', () {
      for (final demo in staffDemoNames) {
        final renderer = StaffRenderer(config: demoConfig(demo));
        for (var i = 0; i < renderer.events.length; i++) {
          final event = renderer.events[i];
          if (event.isRest) continue;
          final y = staffYForStep(event.step);
          expect(
            y >= 0 && y < screenHeight,
            isTrue,
            reason: '$demo frame $i 的 y=$y 超出屏幕',
          );
        }
      }
    });

    test('frames 选项限制渲染帧数', () {
      final renderer = StaffRenderer(
        config: twinkle(),
        options: const RenderOptions(maxFrames: 3),
      );
      expect(renderer.visibleFrameCount, 3);
      expect(renderer.renderAll(), hasLength(3));
    });

    test('spec.json 结构包含字形与整数版面信息', () {
      final renderer = StaffRenderer(
        config: demoConfig('flats'),
        options: const RenderOptions(clef: 'auto'),
      );
      final spec = renderer.toSpecJson();
      expect(spec['screen'], isA<Map<String, Object?>>());
      final options = spec['options']! as Map<String, Object?>;
      expect(options['key'], 'F');
      expect(options['fifths'], -1);
      expect(options['pxPerQuarter'], staffPxPerQuarter);
      expect(options['minNoteGap'], staffMinNoteGap);
      expect(spec['panelWidth'], renderer.panelWidth);
      expect(spec['noteAreaStart'], renderer.noteAreaStart);
      expect(spec['cursorX'], renderer.cursorX);
      final glyphs = spec['glyphs']! as Map<String, Object?>;
      expect(glyphs['trebleClef'], trebleClefGlyph.rows);
      expect(glyphs['sharp'], sharpGlyph.rows);
      expect((glyphs['digits']! as Map<String, Object?>), hasLength(10));
      final events = spec['events']! as List<Object?>;
      expect(events, hasLength(renderer.events.length));
      final first = events.first! as Map<String, Object?>;
      expect(first['pitch'], 68);
      expect(first['startTick'], 0);
      expect(first['step'], renderer.events.first.step);
      expect(first['accidental'], 2);
      expect(first['clef'], renderer.events.first.clef);
    });
  });

  group('CLI 参数', () {
    test('默认参数与 demo 调号', () {
      final options = parseArgs(<String>[]);
      expect(options.demo, isNull);
      expect(options.render.key, isNull);
      expect(options.render.clef, 'auto');
      expect(options.selfCheck, isFalse);
      expect(options.emitSpec, isFalse);
      expect(options.outDir, 'tmp/staff_preview');
      final renderer = StaffRenderer(
        config: loadConfig(options),
        options: options.render,
      );
      expect(renderer.fifths, 0, reason: '默认 demo twinkle 是 C 调');
    });

    test('--key 覆盖内置 demo 的调号', () {
      final options = parseArgs(<String>['--demo', 'wide', '--key', 'C']);
      final renderer = StaffRenderer(
        config: loadConfig(options),
        options: options.render,
      );
      expect(renderer.fifths, 0);
      expect(renderer.panelWidth, 25);
    });

    test('--frames / --clef / --self-check 解析', () {
      final options = parseArgs(<String>[
        '--demo',
        'mixed',
        '--frames',
        '2',
        '--clef',
        'bass',
        '--self-check',
      ]);
      expect(options.render.maxFrames, 2);
      expect(options.render.clef, 'bass');
      expect(options.selfCheck, isTrue);
      final renderer = StaffRenderer(
        config: loadConfig(options),
        options: options.render,
      );
      expect(renderer.renderAll(), hasLength(2));
      expect(renderer.events.every((event) => event.clef == 1), isTrue);
    });

    test('整数版面参数只接受固件标准值', () {
      expect(
        () => parseArgs(<String>['--space', '7']),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => parseArgs(<String>['--px-per-quarter', '20']),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => parseArgs(<String>['--min-note-gap', '8']),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => parseArgs(<String>['--cursor', '0.5']),
        throwsA(isA<ArgumentError>()),
      );
      // 标准值仍然接受（兼容旧脚本）。
      final options = parseArgs(<String>[
        '--space',
        '$staffSpace',
        '--px-per-quarter',
        '$staffPxPerQuarter',
        '--min-note-gap',
        '$staffMinNoteGap',
        '--cursor',
        '0.30',
      ]);
      expect(options.demo, isNull);
    });

    test('未知参数/非法谱号报错', () {
      expect(
        () => parseArgs(<String>['--bogus']),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => StaffRenderer(
          config: demoConfig('twinkle'),
          options: const RenderOptions(clef: 'alto'),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => StaffRenderer(config: configWithNotes(<MusicNote>[])),
        throwsA(isA<StateError>()),
      );
    });
  });
}
