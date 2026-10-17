import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:pieblock_core/pieblock_core.dart';

import 'debug_cue_wav.dart';
import 'platform/background_run.dart';

/// 调试提示音试听服务：按 [DebugCues] 的曲线合成方波并播放。
///
/// 抽成接口是为了让 UI 与 flutter_soloud 解耦：控件测试里没有原生动态库，
/// 注入假实现即可构建面板，不需要真的出声。
abstract interface class DebugCuePreviewService {
  Future<void> play(List<DebugCueNote> notes);
  Future<void> stop();
  Future<void> dispose();
}

/// 用 flutter_soloud 播放的试听实现。
///
/// 与固件共用 `DebugCues` 里的音高与时值，因此听到的就是烧录后的效果；
/// 蜂鸣器是单音方波，这里同样用方波合成，不引入任何音频资源文件。
class SoloudDebugCuePreview implements DebugCuePreviewService {
  /// 按需取引擎：`SoLoud.instance` 会立刻加载原生动态库，
  /// 放在字段初始化器里会让构造对象本身就可能抛异常（测试环境没有该库）。
  late final SoLoud _engine = SoLoud.instance;
  AudioSource? _source;
  SoundHandle? _handle;
  Future<void>? _initializing;
  int _request = 0;

  Future<void> _ensureInitialized() async {
    if (_engine.isInitialized) return;
    final pending = _initializing;
    if (pending != null) return pending;
    final initializing = _engine.init(automaticCleanup: false, lowLatency: true);
    _initializing = initializing;
    try {
      await initializing;
    } finally {
      if (identical(_initializing, initializing)) _initializing = null;
    }
  }

  @override
  Future<void> play(List<DebugCueNote> notes) async {
    final request = ++_request;
    await _stop();
    if (request != _request) return;
    await _ensureInitialized();
    if (request != _request) return;

    final wav = await runInBackground(() => renderDebugCueWav(notes));
    if (request != _request) return;
    final source = await _engine.loadMem('pieblock_debug_cue.wav', wav);
    if (request != _request) {
      if (_engine.isValidAudioSource(source)) {
        await _engine.disposeSource(source);
      }
      return;
    }
    _source = source;
    _handle = _engine.play(source, volume: .18);
  }

  Future<void> _stop() async {
    final handle = _handle;
    final source = _source;
    _handle = null;
    _source = null;
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
    _request++;
    await _stop();
  }

  @override
  Future<void> dispose() => stop();
}
