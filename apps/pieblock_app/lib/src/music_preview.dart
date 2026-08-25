import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:pieblock_core/pieblock_core.dart';

abstract interface class MusicPreviewService {
  bool get playing;
  bool get paused;
  Future<void> play(MusicConfig config, {required bool looping});
  Future<void> togglePause();
  Future<void> stop();
  Duration get position;
  Future<void> dispose();
}

class SoloudMusicPreview implements MusicPreviewService {
  final SoLoud _engine = SoLoud.instance;
  AudioSource? _source;
  SoundHandle? _handle;
  bool _paused = false;

  @override
  bool get playing =>
      _handle != null && _engine.getIsValidVoiceHandle(_handle!);
  @override
  bool get paused => _paused;

  @override
  Future<void> play(MusicConfig config, {required bool looping}) async {
    await stop();
    if (!_engine.isInitialized) {
      await _engine.init(automaticCleanup: false, lowLatency: true);
    }
    _source = await _engine.loadMem('pieblock_music_preview.wav', _wav(config));
    _handle = _engine.play(_source!, volume: .18, looping: looping);
    _paused = false;
  }

  @override
  Future<void> togglePause() async {
    final handle = _handle;
    if (handle == null || !_engine.getIsValidVoiceHandle(handle)) return;
    _paused = !_paused;
    _engine.setPause(handle, _paused);
  }

  @override
  Future<void> stop() async {
    final handle = _handle;
    _handle = null;
    _paused = false;
    if (handle != null &&
        _engine.isInitialized &&
        _engine.getIsValidVoiceHandle(handle)) {
      await _engine.stop(handle);
    }
    final source = _source;
    _source = null;
    if (source != null &&
        _engine.isInitialized &&
        _engine.isValidAudioSource(source)) {
      await _engine.disposeSource(source);
    }
  }

  @override
  Duration get position {
    final handle = _handle;
    if (handle == null ||
        !_engine.isInitialized ||
        !_engine.getIsValidVoiceHandle(handle)) {
      return Duration.zero;
    }
    return _engine.getPosition(handle);
  }

  @override
  Future<void> dispose() => stop();

  Uint8List _wav(MusicConfig config) {
    const sampleRate = 22050;
    final segments = MusicTimeline.segments(config);
    final totalSamples = segments.fold<int>(
      0,
      (total, segment) =>
          total + (segment.durationMs * sampleRate / 1000).round(),
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
    for (final segment in segments) {
      final count = (segment.durationMs * sampleRate / 1000).round();
      final frequency = segment.pitch == null
          ? 0.0
          : 440 * math.pow(2, (segment.pitch! - 69) / 12);
      for (var index = 0; index < count; index++) {
        final value = frequency == 0
            ? 0
            : ((index * frequency / sampleRate) % 1 < .5 ? 5200 : -5200);
        output.setInt16(44 + sample * 2, value, Endian.little);
        sample++;
      }
    }
    return output.buffer.asUint8List();
  }
}
