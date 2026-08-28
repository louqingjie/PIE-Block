import 'dart:isolate';
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
  Future<void> startPitch(int midiPitch);
  Future<void> stopPitch();
  Duration get position;
  Future<void> dispose();
}

class SoloudMusicPreview implements MusicPreviewService {
  final SoLoud _engine = SoLoud.instance;
  AudioSource? _source;
  SoundHandle? _handle;
  AudioSource? _pitchSource;
  SoundHandle? _pitchHandle;
  Future<void>? _initializing;
  bool _paused = false;
  int _playRequest = 0;
  int _pitchRequest = 0;

  @override
  bool get playing =>
      _handle != null &&
      _engine.isInitialized &&
      _engine.getIsValidVoiceHandle(_handle!);

  @override
  bool get paused => _paused;

  Future<void> _ensureInitialized() async {
    if (_engine.isInitialized) return;
    final pending = _initializing;
    if (pending != null) return pending;
    final initializing = _engine.init(
      automaticCleanup: false,
      lowLatency: true,
    );
    _initializing = initializing;
    try {
      await initializing;
    } finally {
      if (identical(_initializing, initializing)) _initializing = null;
    }
  }

  @override
  Future<void> play(MusicConfig config, {required bool looping}) async {
    final request = ++_playRequest;
    await _stopMusic();
    if (request != _playRequest) return;
    await _ensureInitialized();
    if (request != _playRequest) return;

    final wav = await Isolate.run(() => _renderMusicPreviewWav(config));
    if (request != _playRequest) return;
    final source = await _engine.loadMem('pieblock_music_preview.wav', wav);
    if (request != _playRequest) {
      if (_engine.isValidAudioSource(source)) {
        await _engine.disposeSource(source);
      }
      return;
    }
    _source = source;
    _handle = _engine.play(source, volume: .18, looping: looping);
    _paused = false;
  }

  @override
  Future<void> togglePause() async {
    final handle = _handle;
    if (handle == null || !_engine.getIsValidVoiceHandle(handle)) return;
    _paused = !_paused;
    _engine.setPause(handle, _paused);
  }

  Future<void> _stopMusic() async {
    final handle = _handle;
    final source = _source;
    _handle = null;
    _source = null;
    _paused = false;
    if (handle != null &&
        _engine.isInitialized &&
        _engine.getIsValidVoiceHandle(handle)) {
      await _engine.stop(handle);
    }
    if (source != null &&
        _engine.isInitialized &&
        _engine.isValidAudioSource(source)) {
      await _engine.disposeSource(source);
    }
  }

  @override
  Future<void> stop() async {
    _playRequest++;
    await Future.wait([_stopMusic(), stopPitch()]);
  }

  @override
  Future<void> startPitch(int midiPitch) async {
    if (midiPitch < 1 || midiPitch > 127) return;
    final request = ++_pitchRequest;
    await _stopPitchHandle();
    if (request != _pitchRequest) return;
    await _ensureInitialized();
    if (request != _pitchRequest) return;
    var source = _pitchSource;
    if (source == null || !_engine.isValidAudioSource(source)) {
      source = await _engine.loadWaveform(WaveForm.square, false, 1, 0);
      if (request != _pitchRequest) {
        if (_engine.isValidAudioSource(source)) {
          await _engine.disposeSource(source);
        }
        return;
      }
      _pitchSource = source;
    }
    final frequency = 440 * math.pow(2, (midiPitch - 69) / 12);
    _engine.setWaveformFreq(source, frequency.toDouble());
    _pitchHandle = _engine.play(source, volume: .14);
  }

  Future<void> _stopPitchHandle() async {
    final handle = _pitchHandle;
    _pitchHandle = null;
    if (handle != null &&
        _engine.isInitialized &&
        _engine.getIsValidVoiceHandle(handle)) {
      await _engine.stop(handle);
    }
  }

  @override
  Future<void> stopPitch() async {
    _pitchRequest++;
    await _stopPitchHandle();
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
  Future<void> dispose() async {
    await stop();
    final source = _pitchSource;
    _pitchSource = null;
    if (source != null &&
        _engine.isInitialized &&
        _engine.isValidAudioSource(source)) {
      await _engine.disposeSource(source);
    }
  }
}

Uint8List _renderMusicPreviewWav(MusicConfig config) {
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
