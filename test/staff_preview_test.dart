// OLED 五线谱模拟器的几何/乐理映射回归测试。
//
// 这些断言锁定“后续固件要照抄”的映射表：音高→y、加线数、时值、调号位置、
// 帧缓冲位序；改字形不影响这些纯数据换算。

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pieblock_core/pieblock_core.dart';

import '../tool/oled_staff_spec.dart';
import '../tool/render_oled_staff.dart';

MusicConfig twinkle() => demoConfig('twinkle');

void main() {
  group('音高映射', () {
    test('全音阶序号', () {
      expect(diatonicIndex(60), 28); // C4
      expect(diatonicIndex(64), 30); // E4
      expect(diatonicIndex(67), 32); // G4
      expect(diatonicIndex(71), 34); // B4
      expect(diatonicIndex(43), 18); // G2
    });

    test('高音谱号符头 y（space=6, staffTop=14）', () {
      expect(pitchY(60, 'treble', 6, 14), 44); // C4 加线
      expect(pitchY(64, 'treble', 6, 14), 38); // E4 底线
      expect(pitchY(67, 'treble', 6, 14), 32); // G4 第 2 线
      expect(pitchY(77, 'treble', 6, 14), 14); // F5 顶线
    });

    test('低音谱号符头 y', () {
      expect(pitchY(43, 'bass', 6, 14), 38); // G2 底线
      expect(pitchY(60, 'bass', 6, 14), 8); // C4 上加线
    });

    test('加线数量', () {
      expect(ledgerCountForPitch(60, 'treble'), 1); // C4
      expect(ledgerCountForPitch(57, 'treble'), 2); // A3
      expect(ledgerCountForPitch(79, 'treble'), 0); // G5（顶线上方的间）
      expect(ledgerCountForPitch(81, 'treble'), 1); // A5
      expect(ledgerCountForPitch(84, 'treble'), 2); // C6
    });

    test('符干方向按中线判断', () {
      expect(halfSpaceOffset(60, 'treble') < 0, isTrue); // C4 中线以下
      expect(halfSpaceOffset(72, 'treble') > 0, isTrue); // C5 中线以上
      expect(halfSpaceOffset(71, 'treble'), 0); // B4 中线上
    });
  });

  group('时值', () {
    test('标准时值映射', () {
      String value(double beats) => noteValueForBeats(beats).value.toString();
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
      final result = noteValueForBeats(1 / 3);
      expect(result.approx, isTrue);
    });
  });

  group('调号', () {
    test('调号升降号个数', () {
      expect(keyFifths('C'), 0);
      expect(keyFifths('G'), 1);
      expect(keyFifths('F'), -1);
      expect(keyFifths('Bb'), -2);
      expect(keyFifths('F#'), 6);
      expect(keyFifths('Am'), 0);
      expect(() => keyFifths('H'), throwsArgumentError);
    });

    test('音名字母的调号升降', () {
      expect(keyAlterationForLetter(3, 1), 1); // G 调：F#
      expect(keyAlterationForLetter(0, 1), 0); // G 调：C 不变
      expect(keyAlterationForLetter(6, -1), -1); // F 调：Bb
    });

    test('按调号拼写音名', () {
      final cSharp = spellPitch(61, 0); // C 调：C#4
      expect(cSharp.name, 'C#4');
      final dFlat = spellPitch(61, -1); // F 调：Db4
      expect(dFlat.name, 'Db4');
      expect(spellPitch(70, 0).name, 'A#4');
      expect(spellPitch(70, -1).name, 'Bb4');
      expect(spellPitch(60, 0).name, 'C4');
    });

    test('调号位置表（高音/低音各一套）', () {
      expect(trebleSharpSteps.first, 8); // F5
      expect(trebleFlatSteps.first, 4); // B4
      expect(bassSharpSteps.first, 6); // F3
      expect(bassFlatSteps.first, 2); // B2
    });
  });

  group('帧缓冲与位序', () {
    test('页格式字节序（bit0 = 页内最上一行）', () {
      final bitmap = Bitmap(screenWidth, screenHeight);
      expect(bitmap.bytes.length, frameBytes);
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

  group('乐谱解析与版面', () {
    test('发声区间 + 休止拆分成事件', () {
      final twinkleEvents = buildScore(twinkle());
      expect(twinkleEvents, hasLength(14));
      expect(twinkleEvents.every((event) => !event.isRest), isTrue);

      final restEvents = buildScore(demoConfig('rests'));
      expect(restEvents, hasLength(8));
      expect(restEvents.where((event) => event.isRest), hasLength(3));
      expect(restEvents.first.pitch, 60);
    });

    test('拍号与小节线', () {
      final renderer = StaffRenderer(
        config: twinkle(),
        options: const RenderOptions(),
      );
      expect(renderer.timeSignature.numerator, 4);
      expect(renderer.timeSignature.denominator, 4);
      expect(renderer.barTicks, 1920);
    });

    test('左端固定区宽度随调号数量变化', () {
      StaffRenderer build(String key) => StaffRenderer(
        config: demoConfig('twinkle'),
        options: RenderOptions(key: key),
      );
      expect(build('C').panelWidth, 25);
      expect(build('G').panelWidth, 29);
      expect(build('D').panelWidth, 33);
    });

    test('当前音符固定在 cursorX，后续音符按最小间距递增', () {
      final renderer = StaffRenderer(
        config: twinkle(),
        options: const RenderOptions(),
      );
      final xs = renderer.layoutX(0);
      expect(xs[0], renderer.cursorX);
      for (var i = 1; i < xs.length; i++) {
        expect(xs[i] - xs[i - 1], greaterThanOrEqualTo(5));
      }
    });

    test('自动谱号：低音旋律用低音谱号，跨音域时切换', () {
      final mixed = StaffRenderer(
        config: demoConfig('mixed'),
        options: const RenderOptions(),
      );
      expect(mixed.clefPerEvent.first, 'bass');
      expect(mixed.clefPerEvent.last, 'treble');
      expect(mixed.clefPerEvent.toSet(), containsAll(<String>{'bass', 'treble'}));

      final twinkleRenderer = StaffRenderer(
        config: twinkle(),
        options: const RenderOptions(),
      );
      expect(twinkleRenderer.clefPerEvent.every((clef) => clef == 'treble'), isTrue);
    });

    test('强制谱号覆盖自动选择', () {
      final renderer = StaffRenderer(
        config: demoConfig('mixed'),
        options: const RenderOptions(clef: 'treble'),
      );
      expect(renderer.clefPerEvent.every((clef) => clef == 'treble'), isTrue);
    });

    test('左端固定区是禁区：滚动内容不得侵入', () {
      List<int> panelPixels(StaffRenderer renderer, Bitmap frame) => <int>[
        for (var x = 0; x < renderer.panelWidth; x++)
          for (var y = 0; y < screenHeight; y++)
            frame.pixel(x, y) ? 1 : 0,
      ];
      for (final demo in <String>['twinkle', 'wide', 'bass']) {
        final renderer = StaffRenderer(
          config: demoConfig(demo),
          options: const RenderOptions(),
        );
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
      final renderer = StaffRenderer(
        config: twinkle(),
        options: const RenderOptions(),
      );
      final frames = renderer.renderAll();
      expect(frames, hasLength(14));
      for (final frame in frames) {
        expect(frame.bytes.length, frameBytes);
      }
      expect(renderer.isDeterministic(0), isTrue);
      expect(renderer.isDeterministic(7), isTrue);
    });

    test('高/低音谱号下示例里的音符都在屏内', () {
      for (final demo in <String>['twinkle', 'wide', 'bass', 'mixed', 'rests']) {
        final renderer = StaffRenderer(
          config: demoConfig(demo),
          options: const RenderOptions(),
        );
        for (var i = 0; i < renderer.events.length; i++) {
          final event = renderer.events[i];
          if (event.isRest) continue;
          final clef = renderer.clefPerEvent[i];
          final y = pitchY(event.pitch!, clef, 6, 14);
          expect(
            y >= 0 && y < screenHeight,
            isTrue,
            reason: '$demo frame $i 的 y=$y 超出屏幕',
          );
        }
      }
    });
  });
}
