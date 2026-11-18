// 开发期基准生成器：MIDI 编解码 golden（写出字节逐字节、解析结构、错误文案）。
//
// 运行：cd tui/parity/tools && dart run bin/export_midi_goldens.dart
import 'dart:convert';
import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';

void main() {
  final toolsDir = Directory.current.absolute.path;
  final repoRoot = Directory(toolsDir).parent.parent.parent;
  final outputDir = Directory('${repoRoot.path}${Platform.pathSeparator}tui'
      '${Platform.pathSeparator}parity${Platform.pathSeparator}golden'
      '${Platform.pathSeparator}midi');
  outputDir.createSync(recursive: true);

  final template = _loadProject(repoRoot, 'assets/templates/music.pieproj');
  final defaultDoc = ProjectDocument.create(ProjectKind.music);
  final synthetic = MusicConfig(
    ticksPerQuarter: 480,
    trackName: '测试曲目',
    notes: const [
      MusicNote(id: 'n1', pitch: 60, startTick: 0, durationTicks: 480),
      MusicNote(id: 'n2', pitch: 64, startTick: 0, durationTicks: 480),
      MusicNote(id: 'n3', pitch: 67, startTick: 240, durationTicks: 720),
      MusicNote(id: 'n4', pitch: 72, startTick: 960, durationTicks: 240),
    ],
    overlapMode: MusicOverlapMode.highest,
    newNoteInterrupts: false,
    keySignatureFifths: -3,
    tempoEvents: const [
      TempoEvent(tick: 0, microsecondsPerQuarter: 500000),
      TempoEvent(tick: 960, microsecondsPerQuarter: 400000),
    ],
    timeSignatureEvents: const [
      TimeSignatureEvent(tick: 0, numerator: 3, denominator: 4),
      TimeSignatureEvent(tick: 1440, numerator: 4, denominator: 4),
    ],
  );

  final configs = <({String name, ProjectDocument document})>[
    (name: 'music_template', document: template),
    (name: 'music_default', document: defaultDoc),
    (
      name: 'music_synthetic',
      document: ProjectDocument.fromJson({
        ...defaultDoc.toJson(),
        'config': synthetic.toJson(),
      }),
    ),
  ];

  final writeCases = <Object?>[];
  final parseCases = <Object?>[];
  for (final entry in configs) {
    final config = entry.document.config as MusicConfig;
    final bytes = MidiCodec.write(config);
    writeCases.add({
      'name': entry.name,
      'document': entry.document.toJson(),
      'hex': _hex(bytes),
    });
    final parsed = MidiCodec.parse(bytes);
    parseCases.add({
      'name': '${entry.name}_roundtrip',
      'hex': _hex(bytes),
      ..._parseResult(parsed),
    });
  }

  final errorCases = <(String, List<int>, String)>[
    ('bad_header', [0x4e, 0x4f, 0x50, 0x45], '不是标准 MIDI 文件'),
    (
      'format2',
      [...ascii.encode('MThd'), 0, 0, 0, 6, 0, 2, 0, 1, 0, 96],
      '不支持 MIDI Format 2',
    ),
    (
      'smpte',
      [...ascii.encode('MThd'), 0, 0, 0, 6, 0, 0, 0, 1, 0xe7, 0x28],
      '不支持 SMPTE 时间格式',
    ),
    (
      'ppq_zero',
      [...ascii.encode('MThd'), 0, 0, 0, 6, 0, 0, 0, 1, 0, 0],
      'MIDI PPQ 不能为 0',
    ),
    (
      'truncated_header',
      [...ascii.encode('MThd'), 0, 0, 0, 6, 0, 0],
      'MIDI 文件意外结束',
    ),
  ];
  for (final (name, bytes, message) in errorCases) {
    try {
      MidiCodec.parse(bytes);
      parseCases.add({'name': name, 'hex': _hex(bytes), 'error': null});
    } on FormatException catch (error) {
      parseCases.add({'name': name, 'hex': _hex(bytes), 'error': error.message});
    }
  }

  // running status + meta 事件的手工样本：一个轨道、两个音符、变速/拍号/调号。
  final runningStatus = _runningStatusMidi();
  parseCases.add({
    'name': 'running_status_handcrafted',
    'hex': _hex(runningStatus),
    ..._parseResult(MidiCodec.parse(runningStatus)),
  });

  final target = File(
    '${outputDir.path}${Platform.pathSeparator}midi.json',
  );
  target.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({
      'writeCases': writeCases,
      'parseCases': parseCases,
    })}\n',
  );
  stdout.writeln('midi golden: ${target.path}');
}

Map<String, Object?> _parseResult(MidiFileData parsed) {
  var selectedIndex = -1;
  for (var index = 0; index < parsed.tracks.length; index++) {
    if (parsed.tracks[index].playable) {
      selectedIndex = index;
      break;
    }
  }
  return {
    'format': parsed.format,
    'ticksPerQuarter': parsed.ticksPerQuarter,
    'keySignatureFifths': parsed.keySignatureFifths,
    'tracks': [
      for (final track in parsed.tracks)
        {
          'name': track.name,
          'melodicNoteCount': track.melodicNoteCount,
          'playable': track.playable,
          'polyphonic': track.polyphonic,
          'endTick': track.endTick,
          'notes': [
            for (final note in track.notes)
              {
                'pitch': note.pitch,
                'channel': note.channel,
                'startTick': note.startTick,
                'durationTicks': note.durationTicks,
              },
          ],
        },
    ],
    'tempoEvents': [
      for (final event in parsed.tempoEvents)
        {
          'tick': event.tick,
          'microsecondsPerQuarter': event.microsecondsPerQuarter,
        },
    ],
    'timeSignatureEvents': [
      for (final event in parsed.timeSignatureEvents)
        {
          'tick': event.tick,
          'numerator': event.numerator,
          'denominator': event.denominator,
        },
    ],
    if (selectedIndex >= 0)
      'selectedTrack': parsed
          .selectTrack(selectedIndex)
          .toJson(),
  };
}

/// 手工构造：MThd + 单轨道，包含 name/tempo/meter/keysig 与 running status。
List<int> _runningStatusMidi() {
  final track = <int>[
    0x00, 0xff, 0x03, 0x03, ...ascii.encode('abc'),
    0x00, 0xff, 0x51, 0x03, 0x07, 0xa1, 0x20,
    0x00, 0xff, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08,
    0x00, 0xff, 0x59, 0x02, 0xfd, 0x00,
    0x00, 0x90, 60, 100,
    0x60, 64, 100, // running status note on
    0x60, 60, 0,
    0x00, 64, 0, // running status note off
    0x00, 0xff, 0x2f, 0x00,
  ];
  return [
    ...ascii.encode('MThd'),
    0, 0, 0, 6,
    0, 0,
    0, 1,
    0, 96,
    ...ascii.encode('MTrk'),
    0, 0, (track.length >> 8) & 0xff, track.length & 0xff,
    ...track,
  ];
}

ProjectDocument _loadProject(Directory repoRoot, String relative) {
  final file = File('${repoRoot.path}${Platform.pathSeparator}'
      '${relative.replaceAll('/', Platform.pathSeparator)}');
  return ProjectDocument.fromJson(
    Map<String, Object?>.from(jsonDecode(file.readAsStringSync()) as Map),
  );
}

String _hex(List<int> bytes) =>
    bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
