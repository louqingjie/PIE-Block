import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pieblock_app/src/debug_cue_wav.dart';
import 'package:pieblock_core/pieblock_core.dart';

/// 解析 [renderDebugCueWav] 的输出，返回 (采样率, 单声道 16bit 采样值)。
({int sampleRate, List<double> samples}) _decode(Uint8List wav) {
  final data = ByteData.sublistView(wav);
  final sampleRate = data.getUint32(24, Endian.little);
  final channels = data.getUint16(22, Endian.little);
  final bits = data.getUint16(34, Endian.little);
  expect(channels, 1);
  expect(bits, 16);
  final samples = <double>[];
  for (var offset = 44; offset + 1 < wav.length; offset += 2) {
    samples.add(data.getInt16(offset, Endian.little).toDouble());
  }
  return (sampleRate: sampleRate, samples: samples);
}

/// 加汉宁窗的单频 DFT 幅度（按窗和归一，满幅方波的基波约为 1）。
double _magnitude(List<double> samples, int sampleRate, double frequency) {
  var real = 0.0, imag = 0.0, windowSum = 0.0;
  for (var i = 0; i < samples.length; i++) {
    final window = 0.5 - 0.5 * math.cos(2 * math.pi * i / (samples.length - 1));
    final angle = 2 * math.pi * frequency * i / sampleRate;
    real += samples[i] * window * math.cos(angle);
    imag += samples[i] * window * math.sin(angle);
    windowSum += window;
  }
  return math.sqrt(real * real + imag * imag) / (windowSum / 2);
}

void main() {
  test('试听合成用 48kHz 带限方波，不是会混叠的朴素方波', () {
    final wav = renderDebugCueWav(const [DebugCueNote(5274, 200)]);
    final decoded = _decode(wav);
    expect(decoded.sampleRate, debugCueSampleRate);
    expect(decoded.sampleRate, 48000);
    expect(decoded.samples.length, 48000 * 200 ~/ 1000);
    // 静音段与音符都写满了，没有截断。
    expect(decoded.samples.any((s) => s.abs() > 1000), isTrue);
  });

  test('高音区的音不再有混叠产生的非谐波分量', () {
    // 旧版朴素方波在 22.05kHz 下：5274Hz 会在 6227Hz 处凭空多出 35% 幅度、
    // 4186Hz 在 9491Hz 处 32%。这里逐音检查「除奇次谐波以外没有明显能量」。
    for (final frequency in const [2093, 3136, 4186, 5274]) {
      final wav = renderDebugCueWav([DebugCueNote(frequency, 120)]);
      final decoded = _decode(wav);
      final fundamental = _magnitude(decoded.samples, decoded.sampleRate,
          frequency.toDouble());
      expect(fundamental, greaterThan(1000), reason: '$frequency Hz 应有声音');

      var worst = 0.0;
      var worstAt = 0.0;
      for (var candidate = 200.0; candidate <= 12000; candidate += 50) {
        // 跳过奇次谐波本身（±40Hz 容差）。
        final harmonicIndex = (candidate / frequency).round();
        final isHarmonic =
            harmonicIndex.isOdd &&
            (candidate - harmonicIndex * frequency).abs() < 40;
        if (isHarmonic) continue;
        final magnitude =
            _magnitude(decoded.samples, decoded.sampleRate, candidate);
        if (magnitude > worst) {
          worst = magnitude;
          worstAt = candidate;
        }
      }
      expect(
        worst / fundamental,
        lessThan(0.05),
        reason: '$frequency Hz 的最大非谐波分量应低于基波的 5%（实测 '
            '${(worst / fundamental * 100).toStringAsFixed(1)}% @ ${worstAt.round()}Hz）',
      );
    }
  });

  test('带限方波仍保留奇次谐波（听感仍是蜂鸣器的方波而不是正弦）', () {
    final wav = renderDebugCueWav(const [DebugCueNote(1047, 200)]);
    final decoded = _decode(wav);
    final fundamental = _magnitude(decoded.samples, decoded.sampleRate, 1047);
    final third = _magnitude(decoded.samples, decoded.sampleRate, 3141);
    // 理想方波的 3 次谐波是基波的 1/3。
    expect(third / fundamental, greaterThan(0.2));
    expect(third / fundamental, lessThan(0.45));
  });
}
