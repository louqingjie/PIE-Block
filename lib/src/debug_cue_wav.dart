/// 调试提示音的 WAV 合成：把 `DebugCues` 的曲线渲染成 16bit 单声道 WAV。
///
/// 这里刻意**不用朴素的 1-bit 方波**（`相位 < 半周期 ? +a : -a`）：高音区的音
/// （4186Hz / 5274Hz）在每个采样率下只有 4~8 个采样/周期，那种写法会凭空造出
/// 非谐波分量——实测 5274Hz 用 22.05kHz 朴素方波时会在 6.2kHz 处出现幅度 35%
/// 的假分量（4186Hz 在 9.5kHz 处 32%），听起来就是破音。真机的 PWM 是按频率
/// 连续翻转的，没有这个问题，所以试听要对得上耳朵就必须**带限合成**。
///
/// 做法：按奇次谐波求和（只取低于 Nyquist 的项），即理想方波的带限近似；采样
/// 率取 48kHz，让 5kHz 附近仍保住 3 次谐波。基波幅度与方波一致（方波基波是
/// 振幅的 4/π 倍），因此响度与旧版连贯，只是没有了混叠噪声。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pieblock_core/pieblock_core.dart';

/// 合成用的采样率：48kHz 让高音区还留得住 3 次谐波。
const int debugCueSampleRate = 48000;

/// 单个音的峰值幅度（与旧版方波一致；带限后 Gibbs 过冲约 9%，远未削顶）。
const int _amplitude = 5200;

/// 把提示音曲线渲染成 16bit 单声道 WAV。
Uint8List renderDebugCueWav(List<DebugCueNote> notes) {
  const sampleRate = debugCueSampleRate;
  final totalSamples = notes.fold<int>(
    0,
    (total, note) => total + (note.durationMs * sampleRate / 1000).round(),
  );
  final dataSize = totalSamples * 2;
  final output = ByteData(44 + dataSize);
  void ascii(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      output.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  ascii(0, 'RIFF');
  output.setUint32(4, 36 + dataSize, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  output.setUint32(16, 16, Endian.little);
  output.setUint16(20, 1, Endian.little);
  output.setUint16(22, 1, Endian.little);
  output.setUint32(24, sampleRate, Endian.little);
  output.setUint32(28, sampleRate * 2, Endian.little);
  output.setUint16(32, 2, Endian.little);
  output.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  output.setUint32(40, dataSize, Endian.little);

  var sample = 0;
  for (final note in notes) {
    final count = (note.durationMs * sampleRate / 1000).round();
    final frequency = note.frequencyHz;
    if (frequency == null || frequency <= 0) {
      for (var index = 0; index < count; index++) {
        output.setInt16(44 + sample * 2, 0, Endian.little);
        sample++;
      }
      continue;
    }
    // 每个音符内部相位从 0 开始，避免音与音之间出现相位跳变导致的咔哒声。
    for (final value in _bandLimitedSquare(frequency, count)) {
      output.setInt16(44 + sample * 2, value, Endian.little);
      sample++;
    }
  }
  return output.buffer.asUint8List();
}

/// [length] 个采样长度的带限方波：[frequency] Hz，只含低于 Nyquist 的奇次谐波。
Iterable<int> _bandLimitedSquare(int frequency, int length) sync* {
  final harmonics = <int>[
    for (var k = 1; k * frequency * 2 < debugCueSampleRate; k += 2) k,
  ];
  final buffer = Float64List(length);
  for (final k in harmonics) {
    final step = 2 * math.pi * k * frequency / debugCueSampleRate;
    final weight = 1 / k;
    for (var index = 0; index < length; index++) {
      buffer[index] += math.sin(step * index) * weight;
    }
  }
  // 4/π 把奇次谐波和还原成方波幅度，保证基波电平与旧版一致。
  final scale = 4 / math.pi * _amplitude;
  for (var index = 0; index < length; index++) {
    final value = (buffer[index] * scale).round();
    yield value > 32767
        ? 32767
        : value < -32768
        ? -32768
        : value;
  }
}
