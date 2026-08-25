import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pieblock_core/pieblock_core.dart';

import 'controller.dart';
import 'document_io.dart';
import 'music_preview.dart';

enum _MusicTool { select, pencil, erase, pan }

enum MusicViewportMode { fixed, paged, anchored }

class MusicEditorPage extends ConsumerStatefulWidget {
  MusicEditorPage({super.key, MusicPreviewService? previewService})
    : previewService = previewService ?? SoloudMusicPreview();
  final MusicPreviewService previewService;

  @override
  ConsumerState<MusicEditorPage> createState() => _MusicEditorPageState();
}

class _MusicEditorPageState extends ConsumerState<MusicEditorPage> {
  static const _rowHeight = 18.0, _keysWidth = 72.0, _eventLane = 48.0;
  static const _documentIo = AppDocumentIo();
  _MusicTool _tool = _MusicTool.select;
  MusicViewportMode _viewportMode = MusicViewportMode.paged;
  int _snapDivisor = 4;
  double _zoom = 1;
  final _selected = <String>{};
  final _horizontalScroll = ScrollController();
  final _verticalScroll = ScrollController();
  final _undo = <MusicConfig>[], _redo = <MusicConfig>[];
  MusicNote? _dragOriginal;
  Offset? _marqueeStart, _marqueeEnd;
  bool _resizing = false, _loopPreview = false;
  MusicNote? _clipboard;
  Timer? _positionTimer;
  int _playheadTick = 0;
  int _transportRequest = 0;
  bool _isLoading = false, _isPlaying = false, _isPaused = false;
  bool _initialPitchCentered = false;
  double? _followAnchorX;
  double? _lastViewportWidth;
  int? _auditionPointer, _auditionPitch;

  MusicConfig get _config =>
      ref.read(appControllerProvider).document!.config as MusicConfig;
  double get _pixelsPerQuarter => 120 * _zoom;
  int get _snapTicks => _snapDivisor == 0
      ? 1
      : math.max(1, (_config.ticksPerQuarter / _snapDivisor).round());

  @override
  void dispose() {
    _transportRequest++;
    _positionTimer?.cancel();
    _horizontalScroll.dispose();
    _verticalScroll.dispose();
    unawaited(widget.previewService.dispose());
    super.dispose();
  }

  void _commit(MusicConfig next, {bool history = true}) {
    final current = _config;
    if (history) {
      _undo.add(current);
      if (_undo.length > 100) _undo.removeAt(0);
      _redo.clear();
    }
    ref.read(appControllerProvider.notifier).updateConfig(next);
    setState(() {});
  }

  void _undoAction() {
    if (_undo.isEmpty) return;
    _redo.add(_config);
    final value = _undo.removeLast();
    ref.read(appControllerProvider.notifier).updateConfig(value);
    setState(() {});
  }

  void _redoAction() {
    if (_redo.isEmpty) return;
    _undo.add(_config);
    final value = _redo.removeLast();
    ref.read(appControllerProvider.notifier).updateConfig(value);
    setState(() {});
  }

  int _snap(int tick) =>
      _snapDivisor == 0 ? tick : (tick / _snapTicks).round() * _snapTicks;

  Rect _noteRect(MusicNote note) => Rect.fromLTWH(
    note.startTick / _config.ticksPerQuarter * _pixelsPerQuarter,
    (127 - note.pitch) * _rowHeight + 1,
    math.max(
      8,
      note.durationTicks / _config.ticksPerQuarter * _pixelsPerQuarter,
    ),
    _rowHeight - 2,
  );

  MusicNote? _hit(Offset position) {
    for (final note in _config.notes.reversed) {
      if (_noteRect(note).inflate(2).contains(position)) return note;
    }
    return null;
  }

  double _tickX(int tick) => tick / _config.ticksPerQuarter * _pixelsPerQuarter;

  int _pitchAtY(double y) => (127 - (y / _rowHeight).floor()).clamp(1, 127);

  bool _overlapsPrimary(MusicNote candidate) {
    return _config.notes.any(
      (note) =>
          note.primary &&
          note.id != candidate.id &&
          candidate.startTick < note.endTick &&
          candidate.endTick > note.startTick,
    );
  }

  void _tap(TapDownDetails details) {
    if (_tool == _MusicTool.pan) return;
    final hit = _hit(details.localPosition);
    if (hit != null) {
      if (!hit.primary) {
        if (_tool == _MusicTool.select) {
          _commit(_config.promote(hit.id));
          _selected
            ..clear()
            ..add(hit.id);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('参考音符只读；切换到“选择”后可点击提升为主旋律')),
          );
        }
      } else if (_tool == _MusicTool.erase) {
        _commit(
          _config.copyWith(
            notes: _config.notes.where((note) => note.id != hit.id).toList(),
          ),
        );
        _selected.remove(hit.id);
      } else {
        _selected
          ..clear()
          ..add(hit.id);
        setState(() {});
      }
      return;
    }
    if (_tool != _MusicTool.pencil) {
      _selected.clear();
      setState(() {});
      return;
    }
    final tick = math.max(
      0,
      _snap(
        (details.localPosition.dx / _pixelsPerQuarter * _config.ticksPerQuarter)
            .round(),
      ),
    );
    final pitch = _pitchAtY(details.localPosition.dy);
    final note = MusicNote(
      id: 'n${DateTime.now().microsecondsSinceEpoch}',
      pitch: pitch,
      startTick: tick,
      durationTicks: _snapTicks,
    );
    if (_overlapsPrimary(note)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('主旋律只能单音播放，请在空白时段添加音符')));
      return;
    }
    _commit(_config.copyWith(notes: [..._config.notes, note]));
    _selected
      ..clear()
      ..add(note.id);
  }

  void _panStart(DragStartDetails details) {
    if (_tool != _MusicTool.select) return;
    final hit = _hit(details.localPosition);
    if (hit == null) {
      _marqueeStart = details.localPosition;
      _marqueeEnd = details.localPosition;
      _selected.clear();
      setState(() {});
      return;
    }
    if (!hit.primary) return;
    _dragOriginal = hit;
    _resizing = (_noteRect(hit).right - details.localPosition.dx).abs() < 10;
    _undo.add(_config);
    _redo.clear();
    _selected
      ..clear()
      ..add(hit.id);
  }

  void _panUpdate(DragUpdateDetails details) {
    if (_tool == _MusicTool.pan) {
      if (_horizontalScroll.hasClients) {
        _horizontalScroll.jumpTo(
          (_horizontalScroll.offset - details.delta.dx).clamp(
            0,
            _horizontalScroll.position.maxScrollExtent,
          ),
        );
      }
      if (_verticalScroll.hasClients) {
        _verticalScroll.jumpTo(
          (_verticalScroll.offset - details.delta.dy).clamp(
            0,
            _verticalScroll.position.maxScrollExtent,
          ),
        );
      }
      return;
    }
    final original = _dragOriginal;
    if (original == null) {
      if (_marqueeStart != null) {
        _marqueeEnd = details.localPosition;
        final rect = Rect.fromPoints(_marqueeStart!, _marqueeEnd!);
        _selected
          ..clear()
          ..addAll(
            _config.notes
                .where((note) => note.primary && rect.overlaps(_noteRect(note)))
                .map((note) => note.id),
          );
        setState(() {});
      }
      return;
    }
    final tickDelta = _snap(
      ((details.localPosition.dx - _noteRect(original).left) /
              _pixelsPerQuarter *
              _config.ticksPerQuarter)
          .round(),
    );
    MusicNote next;
    if (_resizing) {
      final duration = _snap(
        ((details.localPosition.dx - _noteRect(original).left) /
                _pixelsPerQuarter *
                _config.ticksPerQuarter)
            .round(),
      );
      next = original.copyWith(durationTicks: math.max(_snapTicks, duration));
    } else {
      final pitch = _pitchAtY(details.localPosition.dy);
      next = original.copyWith(
        startTick: math.max(0, original.startTick + tickDelta),
        pitch: pitch,
      );
    }
    if (_overlapsPrimary(next)) return;
    _commit(
      _config.copyWith(
        notes: [
          for (final note in _config.notes)
            if (note.id == original.id) next else note,
        ],
      ),
      history: false,
    );
    _dragOriginal = next;
  }

  void _panEnd(DragEndDetails details) {
    _dragOriginal = null;
    _marqueeStart = null;
    _marqueeEnd = null;
    setState(() {});
  }

  void _deleteSelected() {
    if (_selected.isEmpty) return;
    _commit(
      _config.copyWith(
        notes: _config.notes
            .where((note) => !_selected.contains(note.id) || !note.primary)
            .toList(),
      ),
    );
    _selected.clear();
  }

  void _copy() {
    if (_selected.isEmpty) return;
    final id = _selected.first;
    for (final note in _config.notes) {
      if (note.id == id && note.primary) _clipboard = note;
    }
  }

  void _paste() {
    final source = _clipboard;
    if (source == null) return;
    final note = source.copyWith(
      id: 'n${DateTime.now().microsecondsSinceEpoch}',
      startTick: source.endTick,
    );
    if (_overlapsPrimary(note)) return;
    _commit(_config.copyWith(notes: [..._config.notes, note]));
    _selected
      ..clear()
      ..add(note.id);
  }

  Future<void> _importMidi() async {
    final file = await _documentIo.open(
      label: 'MIDI 文件',
      extensions: const ['mid', 'midi'],
      mimeTypes: const ['audio/midi', 'audio/x-midi', 'audio/mid'],
    );
    if (file == null || !mounted) return;
    try {
      final midi = MidiCodec.parse(file.bytes);
      if (!mounted) return;
      final playable = midi.tracks.indexed
          .where((entry) => entry.$2.playable)
          .toList();
      if (playable.isEmpty) throw const FormatException('MIDI 中没有可用的非鼓组旋律轨道');
      final selected = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('选择旋律轨道'),
          content: SizedBox(
            width: 480,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final entry in playable)
                  ListTile(
                    leading: const Icon(Icons.music_note),
                    title: Text(entry.$2.name),
                    subtitle: Text(
                      '${entry.$2.melodicNoteCount} 个音符${entry.$2.polyphonic ? ' · 包含重叠音，自动提取主旋律' : ''}',
                    ),
                    onTap: () => Navigator.pop(context, entry.$1),
                  ),
              ],
            ),
          ),
        ),
      );
      if (selected != null) {
        _commit(midi.selectTrack(selected, sourceName: file.name));
      }
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message.toString())));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('MIDI 导入失败：$error')));
      }
    }
  }

  Future<void> _exportMidi() async {
    final location = await _documentIo.create(
      suggestedName: '${_config.trackName ?? 'pieblock_music'}.mid',
      mimeType: 'audio/midi',
      extensions: const ['mid', 'midi'],
      bytes: Uint8List.fromList(MidiCodec.write(_config)),
    );
    if (location == null) return;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导出 ${AppDocumentIo.displayName(location)}')),
      );
    }
  }

  Future<void> _play() async {
    final errors = ProjectValidator.validate(_config)
        .where((issue) => issue.severity == IssueSeverity.error);
    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(errors.first.message)));
      return;
    }
    final request = ++_transportRequest;
    _positionTimer?.cancel();
    setState(() {
      _isLoading = true;
      _isPlaying = false;
      _isPaused = false;
    });
    if (_viewportMode == MusicViewportMode.anchored) {
      _captureFollowAnchor();
    }
    await widget.previewService.play(_config, looping: _loopPreview);
    if (!mounted || request != _transportRequest) return;
    if (!widget.previewService.playing) {
      setState(() => _isLoading = false);
      return;
    }
    setState(() {
      _isLoading = false;
      _isPlaying = true;
      _isPaused = false;
    });
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      if (!widget.previewService.playing) {
        _positionTimer?.cancel();
        setState(() {
          _isPlaying = false;
          _isPaused = false;
        });
        return;
      }
      final micros = widget.previewService.position.inMicroseconds;
      final previous = _playheadTick;
      final next = _tickAtMicros(micros);
      setState(() => _playheadTick = next);
      _followPlayhead(previousTick: previous);
    });
  }

  Future<void> _togglePause() async {
    if (!_isPlaying) return;
    await widget.previewService.togglePause();
    if (!mounted) return;
    setState(() => _isPaused = widget.previewService.paused);
  }

  int _tickAtMicros(int micros) {
    final maxTick = _config.notes.fold<int>(
      _config.ticksPerQuarter * 4,
      (value, note) => math.max(value, note.endTick),
    );
    var low = 0, high = maxTick;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (MusicTimeline.microsecondsAtTick(_config, middle) <= micros) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }

  Future<void> _stop() async {
    _transportRequest++;
    _positionTimer?.cancel();
    if (mounted) {
      setState(() {
        _isLoading = false;
        _isPlaying = false;
        _isPaused = false;
        _playheadTick = 0;
        _auditionPointer = null;
        _auditionPitch = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _followPlayhead(previousTick: null);
      });
    }
    await widget.previewService.stop();
  }

  void _setViewportMode(MusicViewportMode mode) {
    setState(() {
      _viewportMode = mode;
      _followAnchorX = null;
    });
    if (mode == MusicViewportMode.anchored) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _captureFollowAnchor();
      });
    } else if (mode == MusicViewportMode.paged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _followPlayhead(previousTick: null);
      });
    }
  }

  void _captureFollowAnchor() {
    if (!_horizontalScroll.hasClients) return;
    final position = _horizontalScroll.position;
    final width = position.viewportDimension;
    if (width <= 0) return;
    final playheadX = _tickX(_playheadTick);
    final visibleX = playheadX - position.pixels;
    if (visibleX >= 0 && visibleX <= width) {
      _followAnchorX = visibleX;
      return;
    }
    _followAnchorX = width / 2;
    _jumpHorizontal(playheadX - _followAnchorX!);
  }

  void _followPlayhead({required int? previousTick}) {
    if (!_horizontalScroll.hasClients ||
        _viewportMode == MusicViewportMode.fixed) {
      return;
    }
    final position = _horizontalScroll.position;
    final width = position.viewportDimension;
    if (width <= 0) return;
    final playheadX = _tickX(_playheadTick);
    if (_viewportMode == MusicViewportMode.anchored) {
      var anchor = _followAnchorX;
      if (anchor == null || anchor < 0 || anchor > width) {
        anchor = width / 2;
        _followAnchorX = anchor;
      }
      _jumpHorizontal(playheadX - anchor);
      return;
    }
    final looped = previousTick != null && _playheadTick < previousTick;
    if (looped ||
        playheadX < position.pixels ||
        playheadX >= position.pixels + width) {
      _jumpHorizontal((playheadX / width).floor() * width);
    }
  }

  void _jumpHorizontal(double target) {
    if (!_horizontalScroll.hasClients) return;
    final position = _horizontalScroll.position;
    _horizontalScroll.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  void _centerInitialPitch() {
    if (_initialPitchCentered || !_verticalScroll.hasClients) return;
    final position = _verticalScroll.position;
    if (position.viewportDimension <= 0) return;
    final c4Center = (127 - 60 + .5) * _rowHeight;
    _verticalScroll.jumpTo(
      (c4Center - position.viewportDimension / 2).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    _initialPitchCentered = true;
  }

  int _pitchAtPianoPosition(double localY) => _pitchAtY(
    localY + (_verticalScroll.hasClients ? _verticalScroll.offset : 0),
  );

  void _pianoDown(PointerDownEvent event) {
    _auditionPointer = event.pointer;
    _auditionAt(event.localPosition.dy);
  }

  void _pianoMove(PointerMoveEvent event) {
    if (_auditionPointer == event.pointer) _auditionAt(event.localPosition.dy);
  }

  void _auditionAt(double localY) {
    final pitch = _pitchAtPianoPosition(localY);
    if (pitch == _auditionPitch) return;
    setState(() => _auditionPitch = pitch);
    unawaited(widget.previewService.startPitch(pitch));
  }

  void _pianoUp(PointerEvent event) {
    if (_auditionPointer != event.pointer) return;
    setState(() {
      _auditionPointer = null;
      _auditionPitch = null;
    });
    unawaited(widget.previewService.stopPitch());
  }

  Widget _rollViewport(MusicConfig config, Size timelineSize) {
    final repaint = Listenable.merge([_horizontalScroll, _verticalScroll]);
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = math.max(0.0, constraints.maxWidth - _keysWidth);
        if (_lastViewportWidth != viewportWidth) {
          _lastViewportWidth = viewportWidth;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _viewportMode != MusicViewportMode.anchored) return;
            if (_followAnchorX == null || _followAnchorX! > viewportWidth) {
              _followAnchorX = viewportWidth / 2;
            }
            _followPlayhead(previousTick: null);
          });
        }
        return Column(
          children: [
            SizedBox(
              height: _eventLane,
              child: Row(
                children: [
                  SizedBox(
                    key: const ValueKey('music-roll-corner'),
                    width: _keysWidth,
                    child: const _RollCorner(),
                  ),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: repaint,
                      builder: (context, child) => CustomPaint(
                        key: const ValueKey('music-header-lane'),
                        size: Size.infinite,
                        painter: _EventLanePainter(
                          config: config,
                          pixelsPerQuarter: _pixelsPerQuarter,
                          horizontalOffset: _horizontalScroll.hasClients
                              ? _horizontalScroll.offset
                              : 0,
                          playheadTick: _playheadTick,
                          contentWidth: timelineSize.width,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: _keysWidth,
                    child: Listener(
                      key: const ValueKey('music-piano-keys'),
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _pianoDown,
                      onPointerMove: _pianoMove,
                      onPointerUp: _pianoUp,
                      onPointerCancel: _pianoUp,
                      child: AnimatedBuilder(
                        animation: repaint,
                        builder: (context, child) => CustomPaint(
                          size: Size.infinite,
                          painter: _PianoKeysPainter(
                            rowHeight: _rowHeight,
                            verticalOffset: _verticalScroll.hasClients
                                ? _verticalScroll.offset
                                : 0,
                            auditionPitch: _auditionPitch,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Scrollbar(
                      key: const ValueKey('music-horizontal-scrollbar'),
                      controller: _horizontalScroll,
                      thumbVisibility: true,
                      trackVisibility: true,
                      interactive: true,
                      scrollbarOrientation: ScrollbarOrientation.bottom,
                      notificationPredicate: (notification) =>
                          notification.metrics.axis == Axis.horizontal,
                      child: SingleChildScrollView(
                        controller: _horizontalScroll,
                        scrollDirection: Axis.horizontal,
                        child: Scrollbar(
                          controller: _verticalScroll,
                          thumbVisibility: true,
                          notificationPredicate: (notification) =>
                              notification.metrics.axis == Axis.vertical,
                          child: SingleChildScrollView(
                            controller: _verticalScroll,
                            child: GestureDetector(
                              key: const ValueKey('music-note-grid'),
                              behavior: HitTestBehavior.opaque,
                              onTapDown: _tap,
                              onPanStart: _panStart,
                              onPanUpdate: _panUpdate,
                              onPanEnd: _panEnd,
                              child: CustomPaint(
                                size: timelineSize,
                                painter: _PianoRollPainter(
                                  config: config,
                                  selected: Set.of(_selected),
                                  pixelsPerQuarter: _pixelsPerQuarter,
                                  rowHeight: _rowHeight,
                                  playheadTick: _playheadTick,
                                  marquee:
                                      _marqueeStart == null ||
                                          _marqueeEnd == null
                                      ? null
                                      : Rect.fromPoints(
                                          _marqueeStart!,
                                          _marqueeEnd!,
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editTempo({TempoEvent? event}) async {
    final tick = TextEditingController(text: '${event?.tick ?? _playheadTick}');
    final bpm = TextEditingController(
      text: (event?.bpm ?? 120).toStringAsFixed(2),
    );
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(event == null ? '添加速度事件' : '编辑速度事件'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: tick,
              enabled: event?.tick != 0,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Tick'),
            ),
            TextField(
              controller: bpm,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'BPM'),
            ),
          ],
        ),
        actions: [
          if (event != null && event.tick != 0)
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('删除'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (save == null) return;
    final events = [..._config.tempoEvents]..remove(event);
    if (save) {
      final value = double.tryParse(bpm.text) ?? 120;
      events.add(
        TempoEvent(
          tick: int.tryParse(tick.text) ?? 0,
          microsecondsPerQuarter: (60000000 / value.clamp(1, 999)).round(),
        ),
      );
    }
    events.sort((a, b) => a.tick.compareTo(b.tick));
    _commit(_config.copyWith(tempoEvents: events));
  }

  Future<void> _editMeter({TimeSignatureEvent? event}) async {
    final tick = TextEditingController(text: '${event?.tick ?? _playheadTick}');
    final numerator = TextEditingController(text: '${event?.numerator ?? 4}');
    var denominator = event?.denominator ?? 4;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(event == null ? '添加拍号事件' : '编辑拍号事件'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: tick,
                enabled: event?.tick != 0,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Tick'),
              ),
              TextField(
                controller: numerator,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '分子'),
              ),
              DropdownButtonFormField<int>(
                initialValue: denominator,
                decoration: const InputDecoration(labelText: '分母'),
                items: [1, 2, 4, 8, 16, 32, 64]
                    .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => denominator = value ?? 4),
              ),
            ],
          ),
          actions: [
            if (event != null && event.tick != 0)
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('删除'),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (save == null) return;
    final events = [..._config.timeSignatureEvents]..remove(event);
    if (save) {
      events.add(
        TimeSignatureEvent(
          tick: int.tryParse(tick.text) ?? 0,
          numerator: int.tryParse(numerator.text) ?? 4,
          denominator: denominator,
        ),
      );
    }
    events.sort((a, b) => a.tick.compareTo(b.tick));
    _commit(_config.copyWith(timeSignatureEvents: events));
  }

  @override
  Widget build(BuildContext context) {
    final config =
        ref.watch(appControllerProvider).document!.config as MusicConfig;
    final maxTick = config.notes.fold<int>(
      config.ticksPerQuarter * 16,
      (value, note) =>
          math.max(value, note.endTick + config.ticksPerQuarter * 4),
    );
    final timelineSize = Size(
      maxTick / config.ticksPerQuarter * _pixelsPerQuarter,
      127 * _rowHeight,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _centerInitialPitch();
    });
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            _undoAction,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true):
            _redoAction,
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): _copy,
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): _paste,
        const SingleActivator(LogicalKeyboardKey.delete): _deleteSelected,
      },
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _importMidi,
                      icon: const Icon(Icons.file_open),
                      label: const Text('导入 MIDI'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _exportMidi,
                      icon: const Icon(Icons.save_alt),
                      label: const Text('导出 MIDI'),
                    ),
                    IconButton(
                      onPressed: _undo.isEmpty ? null : _undoAction,
                      tooltip: '撤销 Ctrl+Z',
                      icon: const Icon(Icons.undo),
                    ),
                    IconButton(
                      onPressed: _redo.isEmpty ? null : _redoAction,
                      tooltip: '重做 Ctrl+Y',
                      icon: const Icon(Icons.redo),
                    ),
                    SegmentedButton<_MusicTool>(
                      segments: const [
                        ButtonSegment(
                          value: _MusicTool.select,
                          icon: Icon(Icons.near_me_outlined),
                          label: Text('选择'),
                        ),
                        ButtonSegment(
                          value: _MusicTool.pencil,
                          icon: Icon(Icons.edit),
                          label: Text('画笔'),
                        ),
                        ButtonSegment(
                          value: _MusicTool.erase,
                          icon: Icon(Icons.delete_outline),
                          label: Text('删除'),
                        ),
                        ButtonSegment(
                          value: _MusicTool.pan,
                          icon: Icon(Icons.pan_tool_outlined),
                          label: Text('平移'),
                        ),
                      ],
                      selected: {_tool},
                      onSelectionChanged: (value) =>
                          setState(() => _tool = value.first),
                    ),
                    DropdownButton<int>(
                      value: _snapDivisor,
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('不吸附')),
                        DropdownMenuItem(value: 1, child: Text('1/4')),
                        DropdownMenuItem(value: 2, child: Text('1/8')),
                        DropdownMenuItem(value: 4, child: Text('1/16')),
                        DropdownMenuItem(value: 6, child: Text('1/16 三连音')),
                        DropdownMenuItem(value: 8, child: Text('1/32')),
                      ],
                      onChanged: (value) =>
                          setState(() => _snapDivisor = value ?? 4),
                    ),
                    IconButton(
                      onPressed: _play,
                      tooltip: '播放',
                      icon: _isLoading
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow),
                    ),
                    IconButton(
                      onPressed: _isPlaying ? _togglePause : null,
                      tooltip: '暂停/继续',
                      icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
                    ),
                    IconButton(
                      onPressed: _stop,
                      tooltip: '停止',
                      icon: const Icon(Icons.stop),
                    ),
                    FilterChip(
                      label: const Text('循环预览'),
                      selected: _loopPreview,
                      onSelected: (value) =>
                          setState(() => _loopPreview = value),
                    ),
                    SegmentedButton<MusicViewportMode>(
                      segments: const [
                        ButtonSegment(
                          value: MusicViewportMode.fixed,
                          icon: Icon(Icons.crop_free),
                          label: Text('固定视窗'),
                        ),
                        ButtonSegment(
                          value: MusicViewportMode.paged,
                          icon: Icon(Icons.auto_stories_outlined),
                          label: Text('逐页跟随'),
                        ),
                        ButtonSegment(
                          value: MusicViewportMode.anchored,
                          icon: Icon(Icons.vertical_align_center),
                          label: Text('固定跟随'),
                        ),
                      ],
                      selected: {_viewportMode},
                      onSelectionChanged: (value) =>
                          _setViewportMode(value.first),
                    ),
                    MenuAnchor(
                      menuChildren: [
                        for (final event in config.tempoEvents)
                          MenuItemButton(
                            onPressed: () => _editTempo(event: event),
                            child: Text(
                              'Tick ${event.tick} · ${event.bpm.toStringAsFixed(2)} BPM',
                            ),
                          ),
                        MenuItemButton(
                          onPressed: _editTempo,
                          leadingIcon: const Icon(Icons.add),
                          child: const Text('添加速度事件'),
                        ),
                      ],
                      builder: (context, controller, child) =>
                          OutlinedButton.icon(
                            onPressed: controller.open,
                            icon: const Icon(Icons.speed),
                            label: Text('${config.tempoEvents.length} 个速度'),
                          ),
                    ),
                    MenuAnchor(
                      menuChildren: [
                        for (final event in config.timeSignatureEvents)
                          MenuItemButton(
                            onPressed: () => _editMeter(event: event),
                            child: Text(
                              'Tick ${event.tick} · ${event.numerator}/${event.denominator}',
                            ),
                          ),
                        MenuItemButton(
                          onPressed: _editMeter,
                          leadingIcon: const Icon(Icons.add),
                          child: const Text('添加拍号事件'),
                        ),
                      ],
                      builder: (context, controller, child) =>
                          OutlinedButton.icon(
                            onPressed: controller.open,
                            icon: const Icon(Icons.grid_4x4),
                            label: Text(
                              '${config.timeSignatureEvents.length} 个拍号',
                            ),
                          ),
                    ),
                    SizedBox(
                      width: 150,
                      child: Slider(
                        value: _zoom,
                        min: .5,
                        max: 3,
                        divisions: 10,
                        label: '${(_zoom * 100).round()}%',
                        onChanged: (value) {
                          setState(() => _zoom = value);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              _followPlayhead(previousTick: null);
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: _rollViewport(config, timelineSize)),
          ],
        ),
      ),
    );
  }
}

class _RollCorner extends StatelessWidget {
  const _RollCorner();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: Color(0xff171b20),
      border: Border(
        right: BorderSide(color: Colors.white24),
        bottom: BorderSide(color: Colors.white24),
      ),
    ),
    child: const Center(
      child: Text(
        'BPM / 拍号',
        style: TextStyle(color: Colors.white70, fontSize: 10),
      ),
    ),
  );
}

class _EventLanePainter extends CustomPainter {
  const _EventLanePainter({
    required this.config,
    required this.pixelsPerQuarter,
    required this.horizontalOffset,
    required this.playheadTick,
    required this.contentWidth,
  });

  final MusicConfig config;
  final double pixelsPerQuarter, horizontalOffset, contentWidth;
  final int playheadTick;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xff171b20),
    );
    canvas.save();
    canvas.translate(-horizontalOffset, 0);
    _paintTimeGrid(
      canvas,
      config,
      pixelsPerQuarter,
      contentWidth,
      size.height,
      header: true,
    );
    for (final event in config.tempoEvents) {
      final x = event.tick / config.ticksPerQuarter * pixelsPerQuarter;
      final label = TextPainter(
        text: TextSpan(
          text: '${event.bpm.toStringAsFixed(0)} BPM',
          style: const TextStyle(color: Colors.orangeAccent, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(x + 3, 3));
    }
    for (final event in config.timeSignatureEvents) {
      final x = event.tick / config.ticksPerQuarter * pixelsPerQuarter;
      final label = TextPainter(
        text: TextSpan(
          text: '${event.numerator}/${event.denominator}',
          style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(x + 3, 24));
    }
    final playheadX = playheadTick / config.ticksPerQuarter * pixelsPerQuarter;
    canvas.drawLine(
      Offset(playheadX, 0),
      Offset(playheadX, size.height),
      Paint()
        ..color = const Color(0xffef685d)
        ..strokeWidth = 2,
    );
    canvas.restore();
    canvas.drawLine(
      Offset(0, size.height - .5),
      Offset(size.width, size.height - .5),
      Paint()..color = Colors.white24,
    );
  }

  @override
  bool shouldRepaint(covariant _EventLanePainter oldDelegate) =>
      oldDelegate.config != config ||
      oldDelegate.pixelsPerQuarter != pixelsPerQuarter ||
      oldDelegate.horizontalOffset != horizontalOffset ||
      oldDelegate.playheadTick != playheadTick ||
      oldDelegate.contentWidth != contentWidth;
}

class _PianoKeysPainter extends CustomPainter {
  const _PianoKeysPainter({
    required this.rowHeight,
    required this.verticalOffset,
    required this.auditionPitch,
  });

  final double rowHeight, verticalOffset;
  final int? auditionPitch;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xff111418),
    );
    canvas.save();
    canvas.translate(0, -verticalOffset);
    const black = {1, 3, 6, 8, 10};
    for (var pitch = 1; pitch <= 127; pitch++) {
      final y = (127 - pitch) * rowHeight;
      final pitchClass = pitch % 12;
      final active = pitch == auditionPitch;
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, rowHeight),
        Paint()
          ..color = active
              ? const Color(0xffffc857)
              : black.contains(pitchClass)
              ? const Color(0xff111418)
              : const Color(0xffd7dce1),
      );
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()..color = Colors.black38,
      );
      if (pitchClass == 0) {
        final painter = TextPainter(
          text: TextSpan(
            text: 'C${pitch ~/ 12 - 1}',
            style: TextStyle(
              fontSize: 10,
              color: active || !black.contains(pitchClass)
                  ? Colors.black87
                  : Colors.white,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, Offset(6, y + 2));
      }
    }
    canvas.restore();
    canvas.drawLine(
      Offset(size.width - .5, 0),
      Offset(size.width - .5, size.height),
      Paint()..color = Colors.white24,
    );
  }

  @override
  bool shouldRepaint(covariant _PianoKeysPainter oldDelegate) =>
      oldDelegate.rowHeight != rowHeight ||
      oldDelegate.verticalOffset != verticalOffset ||
      oldDelegate.auditionPitch != auditionPitch;
}

void _paintTimeGrid(
  Canvas canvas,
  MusicConfig config,
  double pixelsPerQuarter,
  double contentWidth,
  double height, {
  bool header = false,
}) {
  final maxTick = (contentWidth / pixelsPerQuarter * config.ticksPerQuarter)
      .ceil();
  final meters = config.timeSignatureEvents.isEmpty
      ? const [TimeSignatureEvent(tick: 0, numerator: 4, denominator: 4)]
      : config.timeSignatureEvents;
  for (var meterIndex = 0; meterIndex < meters.length; meterIndex++) {
    final meter = meters[meterIndex];
    final segmentEnd = meterIndex + 1 < meters.length
        ? meters[meterIndex + 1].tick
        : maxTick;
    final denominator = meter.denominator > 0 ? meter.denominator : 4;
    final numerator = math.max(1, meter.numerator);
    final beatTicks = config.ticksPerQuarter * 4 / denominator;
    final barTicks = beatTicks * numerator;
    for (
      var tick = meter.tick.toDouble();
      tick <= segmentEnd;
      tick += beatTicks
    ) {
      final x = tick / config.ticksPerQuarter * pixelsPerQuarter;
      final strong = ((tick - meter.tick) % barTicks).abs() < .01;
      final gridPaint = Paint()
        ..color = strong
            ? (header ? Colors.white30 : Colors.white38)
            : Colors.white12
        ..strokeWidth = strong ? 1.5 : 1;
      canvas.drawLine(Offset(x, 0), Offset(x, height), gridPaint);
    }
  }
}

class _PianoRollPainter extends CustomPainter {
  const _PianoRollPainter({
    required this.config,
    required this.selected,
    required this.pixelsPerQuarter,
    required this.rowHeight,
    required this.playheadTick,
    required this.marquee,
  });
  final MusicConfig config;
  final Set<String> selected;
  final double pixelsPerQuarter, rowHeight;
  final int playheadTick;
  final Rect? marquee;

  @override
  void paint(Canvas canvas, Size size) {
    final dark = const Color(0xff20252b), light = const Color(0xff2b3138);
    canvas.drawRect(Offset.zero & size, Paint()..color = dark);
    const black = {1, 3, 6, 8, 10};
    for (var pitch = 1; pitch <= 127; pitch++) {
      final y = (127 - pitch) * rowHeight;
      final pitchClass = pitch % 12;
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, rowHeight),
        Paint()..color = black.contains(pitchClass) ? dark : light,
      );
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()..color = Colors.white10,
      );
    }
    _paintTimeGrid(canvas, config, pixelsPerQuarter, size.width, size.height);
    for (final note in config.notes.where((note) => !note.primary)) {
      _note(canvas, note, const Color(0x6657c7ff));
    }
    for (final note in config.notes.where((note) => note.primary)) {
      _note(
        canvas,
        note,
        selected.contains(note.id)
            ? const Color(0xffffc857)
            : const Color(0xff02acc0),
      );
    }
    final playheadX = playheadTick / config.ticksPerQuarter * pixelsPerQuarter;
    canvas.drawLine(
      Offset(playheadX, 0),
      Offset(playheadX, size.height),
      Paint()
        ..color = const Color(0xffef685d)
        ..strokeWidth = 2,
    );
    if (marquee case final rect?) {
      canvas.drawRect(rect, Paint()..color = const Color(0x3329b6f6));
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xff29b6f6),
      );
    }
  }

  void _note(Canvas canvas, MusicNote note, Color color) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        note.startTick / config.ticksPerQuarter * pixelsPerQuarter,
        (127 - note.pitch) * rowHeight + 1,
        math.max(
          8,
          note.durationTicks / config.ticksPerQuarter * pixelsPerQuarter,
        ),
        rowHeight - 2,
      ),
      const Radius.circular(3),
    );
    canvas.drawRRect(rect, Paint()..color = color);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white54,
    );
  }

  @override
  bool shouldRepaint(covariant _PianoRollPainter oldDelegate) =>
      oldDelegate.config != config ||
      oldDelegate.selected != selected ||
      oldDelegate.pixelsPerQuarter != pixelsPerQuarter ||
      oldDelegate.playheadTick != playheadTick ||
      oldDelegate.marquee != marquee;
}
