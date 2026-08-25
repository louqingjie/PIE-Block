import 'dart:convert';
import 'dart:typed_data';

import 'models.dart';

class MidiTrackData {
  const MidiTrackData({required this.name, required this.notes});
  final String name;
  final List<MidiSourceNote> notes;
  int get melodicNoteCount => notes.where((note) => note.channel != 9).length;
  bool get playable => melodicNoteCount > 0;
  bool get polyphonic {
    final melodic = notes.where((note) => note.channel != 9).toList()
      ..sort((a, b) => a.startTick.compareTo(b.startTick));
    var end = -1;
    for (final note in melodic) {
      if (note.startTick < end) return true;
      end = note.endTick > end ? note.endTick : end;
    }
    return false;
  }

  int get endTick =>
      notes.fold(0, (end, note) => note.endTick > end ? note.endTick : end);
}

class MidiFileData {
  const MidiFileData({
    required this.format,
    required this.ticksPerQuarter,
    required this.tracks,
    required this.tempoEvents,
    required this.timeSignatureEvents,
  });
  final int format, ticksPerQuarter;
  final List<MidiTrackData> tracks;
  final List<TempoEvent> tempoEvents;
  final List<TimeSignatureEvent> timeSignatureEvents;

  MusicConfig selectTrack(int index, {String? sourceName}) {
    if (index < 0 || index >= tracks.length || !tracks[index].playable) {
      throw const FormatException('请选择包含旋律音符的 MIDI 轨道');
    }
    final source =
        tracks[index].notes.where((note) => note.channel != 9).toList()
          ..sort((a, b) {
            final tick = a.startTick.compareTo(b.startTick);
            return tick != 0 ? tick : b.pitch.compareTo(a.pitch);
          });
    final grouped = <int, List<MidiSourceNote>>{};
    for (final note in source) {
      grouped.putIfAbsent(note.startTick, () => []).add(note);
    }
    int? previousPitch;
    var serial = 0;
    final notes = <MusicNote>[];
    for (final entry in grouped.entries) {
      final candidates = entry.value;
      candidates.sort((a, b) {
        if (previousPitch == null) return b.pitch.compareTo(a.pitch);
        final ad = (a.pitch - previousPitch).abs();
        final bd = (b.pitch - previousPitch).abs();
        return ad != bd ? ad.compareTo(bd) : b.pitch.compareTo(a.pitch);
      });
      final selected = candidates.first;
      previousPitch = selected.pitch;
      for (final note in candidates) {
        notes.add(
          MusicNote(
            id: 'm${serial++}',
            pitch: note.pitch,
            startTick: note.startTick,
            durationTicks: note.durationTicks,
            primary: identical(note, selected),
          ),
        );
      }
    }
    return MusicConfig(
      ticksPerQuarter: ticksPerQuarter,
      sourceName: sourceName,
      trackName: tracks[index].name,
      notes: notes,
      tempoEvents: tempoEvents.isEmpty
          ? const [TempoEvent(tick: 0, microsecondsPerQuarter: 500000)]
          : tempoEvents,
      timeSignatureEvents: timeSignatureEvents.isEmpty
          ? const [TimeSignatureEvent(tick: 0, numerator: 4, denominator: 4)]
          : timeSignatureEvents,
    );
  }
}

class MidiSourceNote {
  const MidiSourceNote({
    required this.pitch,
    required this.channel,
    required this.startTick,
    required this.durationTicks,
  });
  final int pitch, channel, startTick, durationTicks;
  int get endTick => startTick + durationTicks;
}

abstract final class MidiCodec {
  static MidiFileData parse(List<int> bytes) {
    final reader = _Reader(Uint8List.fromList(bytes));
    if (reader.ascii(4) != 'MThd') throw const FormatException('不是标准 MIDI 文件');
    final headerLength = reader.u32();
    if (headerLength < 6) throw const FormatException('MIDI 文件头损坏');
    final format = reader.u16(),
        trackCount = reader.u16(),
        division = reader.u16();
    if (format > 1) throw const FormatException('不支持 MIDI Format 2');
    if ((division & 0x8000) != 0) throw const FormatException('不支持 SMPTE 时间格式');
    if (division == 0) throw const FormatException('MIDI PPQ 不能为 0');
    reader.skip(headerLength - 6);
    final tracks = <MidiTrackData>[];
    final tempos = <TempoEvent>[];
    final meters = <TimeSignatureEvent>[];
    for (var trackIndex = 0; trackIndex < trackCount; trackIndex++) {
      if (reader.ascii(4) != 'MTrk') throw const FormatException('MIDI 轨道块损坏');
      final end = reader.position + reader.u32();
      if (end > reader.length) throw const FormatException('MIDI 轨道长度越界');
      var tick = 0, runningStatus = 0;
      var name = '轨道 ${trackIndex + 1}';
      final active = <int, List<int>>{};
      final notes = <MidiSourceNote>[];
      while (reader.position < end) {
        tick += reader.vlq();
        var status = reader.u8();
        if (status < 0x80) {
          if (runningStatus == 0)
            throw const FormatException('无效的 running status');
          reader.position--;
          status = runningStatus;
        } else if (status < 0xf0) {
          runningStatus = status;
        }
        if (status == 0xff) {
          final type = reader.u8(), length = reader.vlq();
          final data = reader.take(length);
          if (type == 0x03) name = utf8.decode(data, allowMalformed: true);
          if (type == 0x51 && data.length == 3) {
            tempos.add(
              TempoEvent(
                tick: tick,
                microsecondsPerQuarter:
                    (data[0] << 16) | (data[1] << 8) | data[2],
              ),
            );
          }
          if (type == 0x58 && data.length >= 2) {
            meters.add(
              TimeSignatureEvent(
                tick: tick,
                numerator: data[0],
                denominator: 1 << data[1],
              ),
            );
          }
          continue;
        }
        if (status == 0xf0 || status == 0xf7) {
          reader.skip(reader.vlq());
          continue;
        }
        if (status >= 0xf0) {
          reader.skip(
            const {0xf1: 1, 0xf2: 2, 0xf3: 1}.containsKey(status)
                ? const {0xf1: 1, 0xf2: 2, 0xf3: 1}[status]!
                : 0,
          );
          continue;
        }
        final command = status & 0xf0, channel = status & 0x0f;
        final a = reader.u8();
        final b = command == 0xc0 || command == 0xd0 ? 0 : reader.u8();
        if (command == 0x90 && b > 0) {
          active.putIfAbsent((channel << 8) | a, () => []).add(tick);
        } else if (command == 0x80 || command == 0x90 && b == 0) {
          final starts = active[(channel << 8) | a];
          if (starts != null && starts.isNotEmpty) {
            final start = starts.removeAt(0);
            if (tick > start) {
              notes.add(
                MidiSourceNote(
                  pitch: a,
                  channel: channel,
                  startTick: start,
                  durationTicks: tick - start,
                ),
              );
            }
          }
        }
      }
      reader.position = end;
      tracks.add(MidiTrackData(name: name, notes: List.unmodifiable(notes)));
    }
    tempos.sort((a, b) => a.tick.compareTo(b.tick));
    meters.sort((a, b) => a.tick.compareTo(b.tick));
    return MidiFileData(
      format: format,
      ticksPerQuarter: division,
      tracks: List.unmodifiable(tracks),
      tempoEvents: List.unmodifiable(_dedupeTempo(tempos)),
      timeSignatureEvents: List.unmodifiable(_dedupeMeter(meters)),
    );
  }

  static Uint8List write(MusicConfig config) {
    final events = <_WriteEvent>[];
    final name = utf8.encode(config.trackName ?? 'PIE-Block Music');
    events.add(_WriteEvent(0, 0, [0xff, 0x03, ..._vlq(name.length), ...name]));
    for (final tempo in config.tempoEvents) {
      final value = tempo.microsecondsPerQuarter;
      events.add(
        _WriteEvent(tempo.tick, 0, [
          0xff,
          0x51,
          0x03,
          (value >> 16) & 0xff,
          (value >> 8) & 0xff,
          value & 0xff,
        ]),
      );
    }
    for (final meter in config.timeSignatureEvents) {
      var exponent = 0, denominator = meter.denominator;
      while (denominator > 1) {
        denominator >>= 1;
        exponent++;
      }
      events.add(
        _WriteEvent(meter.tick, 0, [
          0xff,
          0x58,
          0x04,
          meter.numerator,
          exponent,
          24,
          8,
        ]),
      );
    }
    for (final note in config.notes) {
      events
        ..add(_WriteEvent(note.startTick, 2, [0x90, note.pitch, 100]))
        ..add(_WriteEvent(note.endTick, 1, [0x80, note.pitch, 0]));
    }
    events.sort((a, b) {
      final tick = a.tick.compareTo(b.tick);
      return tick != 0 ? tick : a.priority.compareTo(b.priority);
    });
    final track = <int>[];
    var previousTick = 0;
    for (final event in events) {
      track
        ..addAll(_vlq(event.tick - previousTick))
        ..addAll(event.bytes);
      previousTick = event.tick;
    }
    track.addAll([0, 0xff, 0x2f, 0]);
    final output = <int>[
      ...ascii.encode('MThd'),
      ..._u32(6),
      0,
      0,
      0,
      1,
      (config.ticksPerQuarter >> 8) & 0xff,
      config.ticksPerQuarter & 0xff,
      ...ascii.encode('MTrk'),
      ..._u32(track.length),
      ...track,
    ];
    return Uint8List.fromList(output);
  }

  static List<TempoEvent> _dedupeTempo(List<TempoEvent> source) {
    final values = <int, TempoEvent>{};
    for (final event in source) {
      values[event.tick] = event;
    }
    return values.values.toList()..sort((a, b) => a.tick.compareTo(b.tick));
  }

  static List<TimeSignatureEvent> _dedupeMeter(
    List<TimeSignatureEvent> source,
  ) {
    final values = <int, TimeSignatureEvent>{};
    for (final event in source) {
      values[event.tick] = event;
    }
    return values.values.toList()..sort((a, b) => a.tick.compareTo(b.tick));
  }

  static List<int> _u32(int value) => [
    value >> 24,
    value >> 16,
    value >> 8,
    value,
  ].map((e) => e & 0xff).toList();
  static List<int> _vlq(int value) {
    var buffer = value & 0x7f;
    final bytes = <int>[];
    while ((value >>= 7) > 0) {
      buffer <<= 8;
      buffer |= (value & 0x7f) | 0x80;
    }
    while (true) {
      bytes.add(buffer & 0xff);
      if ((buffer & 0x80) == 0) break;
      buffer >>= 8;
    }
    return bytes;
  }
}

class _WriteEvent {
  const _WriteEvent(this.tick, this.priority, this.bytes);
  final int tick, priority;
  final List<int> bytes;
}

class _Reader {
  _Reader(this.bytes);
  final Uint8List bytes;
  int position = 0;
  int get length => bytes.length;
  int u8() {
    if (position >= length) throw const FormatException('MIDI 文件意外结束');
    return bytes[position++];
  }

  int u16() => (u8() << 8) | u8();
  int u32() => (u8() << 24) | (u8() << 16) | (u8() << 8) | u8();
  String ascii(int count) => asciiDecode(take(count));
  String asciiDecode(List<int> value) => String.fromCharCodes(value);
  Uint8List take(int count) {
    if (count < 0 || position + count > length)
      throw const FormatException('MIDI 数据长度越界');
    final value = bytes.sublist(position, position + count);
    position += count;
    return value;
  }

  void skip(int count) {
    take(count);
  }

  int vlq() {
    var value = 0;
    for (var i = 0; i < 4; i++) {
      final byte = u8();
      value = (value << 7) | (byte & 0x7f);
      if ((byte & 0x80) == 0) return value;
    }
    throw const FormatException('MIDI VLQ 超过四字节');
  }
}
