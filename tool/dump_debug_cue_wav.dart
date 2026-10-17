// 把 DebugCues 的步序提示离线渲染成 WAV，便于不刷固件就试听。
//
// 合成走 lib/src/debug_cue_wav.dart 的同一份实现（48kHz、带限方波，无混叠），
// 所以这些文件与 App 内「提示音试听」听到的完全一致；数据源也是固件生成器
// 用的同一份曲线。
//
// 用法：dart run tool/dump_debug_cue_wav.dart
import 'dart:io';

import 'package:pieblock_app/src/debug_cue_wav.dart';
import 'package:pieblock_core/pieblock_core.dart';

void main() {
  final outputDir = Directory('output/试听');
  if (!outputDir.existsSync()) outputDir.createSync(recursive: true);

  // 十项都导出：高音区（第 6 项起，尤其 9/10 项的 4186Hz / 5274Hz）是最容易
  // 暴露混叠的地方，留一份可以直接听。
  for (var index = 1; index <= 10; index += 1) {
    final notes = DebugCues.step(index);
    final name = 'cue_step$index.wav';
    final wav = renderDebugCueWav(notes);
    File('${outputDir.path}/$name').writeAsBytesSync(wav);
    stdout.writeln(
      '  $name: ${notes.length} 段 / ${_ms(notes)} ms / ${wav.length ~/ 1024} KiB',
    );
  }
  stdout.writeln('\n输出目录：${outputDir.path}');

  // 自检：音符数与总时长必须和模型一致，防止渲染端悄悄漂移。
  final step3 = DebugCues.step(3)
      .where((note) => note.frequencyHz != null)
      .map((note) => note.frequencyHz!)
      .toList();
  final step3Ms = DebugCues.durationMs(DebugCues.step(3));
  assert(step3.length == 3 && step3Ms == 940, '第 3 项应为上行 3 声、940ms');
  assert(step3.first < step3.last, '第 3 项应是上行');
  stdout.writeln('自检通过：第 3 项 上行$step3（$step3Ms ms）');
}

int _ms(List<DebugCueNote> notes) =>
    notes.fold(0, (total, note) => total + note.durationMs);
