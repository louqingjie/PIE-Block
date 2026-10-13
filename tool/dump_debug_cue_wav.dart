// 把 DebugCues 的提示音曲线离线渲染成 WAV，便于不刷固件就试听。
//
// 与 lib/src/music_preview.dart 的渲染方式一致（22050Hz / 16bit 单声道 / 方波），
// 区别是数据源换成 DebugCues——也就是固件生成器用的同一份曲谱，
// 因此试听听到的就是固件会播的。
//
// 用法：dart run tool/dump_debug_cue_wav.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:pieblock_core/pieblock_core.dart';

const int _sampleRate = 22050;
const int _amplitude = 5200;

Uint8List _renderWav(List<DebugCueNote> notes, String label) {
  final totalSamples = notes.fold<int>(
    0,
    (total, note) => total + (note.durationMs * _sampleRate / 1000).round(),
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
  output.setUint32(24, _sampleRate, Endian.little);
  output.setUint32(28, _sampleRate * 2, Endian.little);
  output.setUint16(32, 2, Endian.little);
  output.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  output.setUint32(40, dataSize, Endian.little);

  var sample = 0;
  final phase = <int>[]; // 每个音从自己的相位 0 起，避免接缝处的爆音
  for (final note in notes) {
    final count = (note.durationMs * _sampleRate / 1000).round();
    final frequency = note.frequencyHz ?? 0;
    var index = 0;
    for (; index < count; index++) {
      final value = frequency == 0
          ? 0
          : ((index * frequency / _sampleRate) % 1 < .5 ? _amplitude : -_amplitude);
      output.setInt16(44 + sample * 2, value, Endian.little);
      sample++;
    }
    phase.add(index);
  }
  stdout.writeln(
    '  $label: ${notes.length} 段 / ${_ms(notes)} ms / ${dataSize ~/ 1024} KiB',
  );
  return output.buffer.asUint8List();
}

int _ms(List<DebugCueNote> notes) =>
    notes.fold(0, (total, note) => total + note.durationMs);

/// 取足够覆盖 [targetMs] 的前缀段数，用于生成节选试听文件。
int _prefixForDuration(List<DebugCueNote> notes, int targetMs) {
  var total = 0;
  for (var index = 0; index < notes.length; index++) {
    total += notes[index].durationMs;
    if (total >= targetMs) return index + 1;
  }
  return notes.length;
}

void main() {
  final outputDir = Directory('output/试听');
  if (!outputDir.existsSync()) outputDir.createSync(recursive: true);

  for (final style in DebugCueStyle.values) {
    stdout.writeln('${style.label}风格：');
    final allDone = DebugCues.allDone(style);
    final curves = <String, List<DebugCueNote>>{
      // 整项 = 上行 N 音 + 停顿 + 对称回落，固件里听到的就是这个。
      'fullStep3': DebugCues.fullStep(3, style),
      // 进位后的整项：音区升八度，个数重新从 1 开始。
      'fullStep6': DebugCues.fullStep(6, style),
      // 全部完成 = 《卡农》主题全曲（约 3 分钟，文件较大）。
      'allDone': allDone,
      // 前 60 秒节选：便于快速试听旋律，不用等完整曲。
      'allDoneHead':
          allDone.take(_prefixForDuration(allDone, 60000)).toList(),
    };
    for (final entry in curves.entries) {
      final name = 'cue_${entry.key}_${style.name}.wav';
      File('${outputDir.path}/$name').writeAsBytesSync(
        _renderWav(entry.value, name),
      );
    }
  }
  stdout.writeln('\n输出目录：${outputDir.path}');

  // 自检：渲染出来的音符数与音高必须和模型一致，防止渲染端悄悄漂移。
  final step3 = DebugCues.step(3, DebugCueStyle.standard)
      .where((note) => note.frequencyHz != null)
      .map((note) => note.frequencyHz!)
      .toList();
  final done3 = DebugCues.stepDone(3, DebugCueStyle.standard)
      .where((note) => note.frequencyHz != null)
      .map((note) => note.frequencyHz!)
      .toList();
  assert(step3.length == 3 && done3.length == 2, '第 3 项应为上行 3 声、回落 2 声');
  assert(step3.last != done3.first, '交界处不应同音高');
  stdout.writeln('自检通过：第 3 项 上行$step3 → 回落$done3');
}
