import 'models.dart';

class MusicSegment {
  const MusicSegment({required this.pitch, required this.durationMs});
  final int? pitch;
  final int durationMs;
}

abstract final class MusicTimeline {
  static List<MusicNote> primaryNotes(MusicConfig config) {
    final byStart = <int, MusicNote>{};
    for (final note in config.notes) {
      if (note.primary &&
          note.startTick >= 0 &&
          note.durationTicks > 0 &&
          note.pitch >= 1 &&
          note.pitch <= 127) {
        byStart.putIfAbsent(note.startTick, () => note);
      }
    }
    return byStart.values.toList()
      ..sort((a, b) => a.startTick.compareTo(b.startTick));
  }

  static int microsecondsAtTick(MusicConfig config, int tick) {
    final events = [...config.tempoEvents]
      ..sort((a, b) => a.tick.compareTo(b.tick));
    var cursor = 0;
    var tempo = events.isEmpty ? 500000 : events.first.microsecondsPerQuarter;
    var total = 0.0;
    for (final event in events) {
      if (event.tick <= 0) {
        tempo = event.microsecondsPerQuarter;
        continue;
      }
      if (event.tick >= tick) break;
      total += (event.tick - cursor) * tempo / config.ticksPerQuarter;
      cursor = event.tick;
      tempo = event.microsecondsPerQuarter;
    }
    total += (tick - cursor).clamp(0, tick) * tempo / config.ticksPerQuarter;
    return total.round();
  }

  static List<MusicSegment> segments(MusicConfig config) {
    final notes = primaryNotes(config);
    final result = <MusicSegment>[];
    var cursorTick = 0;
    for (var index = 0; index < notes.length; index++) {
      final note = notes[index];
      if (note.startTick > cursorTick) {
        _append(
          result,
          null,
          microsecondsAtTick(config, note.startTick) -
              microsecondsAtTick(config, cursorTick),
        );
      }
      final nextStart = index + 1 < notes.length
          ? notes[index + 1].startTick
          : note.endTick;
      final endTick = note.endTick.clamp(note.startTick + 1, nextStart);
      _append(
        result,
        note.pitch,
        microsecondsAtTick(config, endTick) -
            microsecondsAtTick(config, note.startTick),
      );
      cursorTick = endTick;
    }
    return result;
  }

  static void _append(List<MusicSegment> target, int? pitch, int micros) {
    final millis = (micros / 1000).round().clamp(1, 0x7fffffff);
    if (target.isNotEmpty && target.last.pitch == pitch) {
      final previous = target.removeLast();
      target.add(
        MusicSegment(pitch: pitch, durationMs: previous.durationMs + millis),
      );
    } else {
      target.add(MusicSegment(pitch: pitch, durationMs: millis));
    }
  }
}
