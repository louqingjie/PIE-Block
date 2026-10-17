import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pieblock_core/pieblock_core.dart';

import 'controller.dart';
import 'platform/document_io.dart';
import 'music_preview.dart';

enum _MusicTool { select, pencil, erase, pan }

enum MusicViewportMode { fixed, paged, anchored }

class MusicEditorPage extends ConsumerStatefulWidget {
  const MusicEditorPage({super.key, this.previewService});

  /// 测试注入用；正式运行时为 null，由 State 在 initState 创建并持有。
  /// 不能在这里直接 `?? SoloudMusicPreview()`：父级（向导页）每次 rebuild 都会
  /// 构造新的 MusicEditorPage，而 Flutter 会复用同一个 State。若 service 跟着
  /// widget 走，播放中调参数/改窗口大小就会把 State 的引用换成新实例，旧实例
  /// 没人 dispose，声音会一直响，停止键也只能停掉新实例。
  final MusicPreviewService? previewService;

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

  /// 本次拖动开始时被移动的音符（按下那一刻的原始值），拖动过程中不改写，
  /// 这样位移量始终相对按下位置计算，多音符整组平移也不会累积误差。
  final _dragOriginals = <String, MusicNote>{};
  String? _dragAnchorId;

  /// 本次指针按下之前就已经选中的音符：画笔模式据此判断「按下已选中的音符」
  /// 应该拖动整组而不是新建音符。用 Listener 记录，避免 onTapDown 与
  /// onPanStart 竞争手势竞技场导致快拖时拿不到按下事件。
  final _selectionAtPointerDown = <String>{};

  /// 本次拖动的起点（按下位置），位移量相对它计算，音符不会在起拖瞬间跳到
  /// 指针下，多选整组平移也保持抓取点相对音符不动。
  Offset? _dragStart;
  Offset? _marqueeStart, _marqueeEnd;
  bool _resizing = false, _loopPreview = false;

  /// undo 快照延后到本次拖动首次真正改变数据时再记录：按住音符只是选中、
  /// 或抖动一两个像素就松手时，不再留下一条“撤销了什么都没发生”的历史。
  bool _dragHistoryPending = false;

  /// 多选剪贴板：保存相对最小时刻归一化后的音符，粘贴时整块落到播放头。
  List<MusicNote> _clipboard = const [];

  /// 本次拖动开始时的重叠处数：松手后只在重叠处数变多时提示一次。
  int _overlapAtPointerDown = 0;

  /// 本次手势是否真的在拖动音符（框选/平移不参与重叠提示）。
  bool _overlapTracked = false;

  /// 单音裁决结果缓存：配置对象不变时（同一帧内的多次读取）不重复计算。
  MusicConfig? _resolutionConfig;
  List<MusicSoundingSpan> _resolutionSpans = const [];
  int _resolutionOverlaps = 0;

  Timer? _positionTimer;
  int _playheadTick = 0;
  int _transportRequest = 0;
  bool _isLoading = false, _isPlaying = false, _isPaused = false;
  bool _initialPitchCentered = false;
  double? _followAnchorX;
  double? _lastViewportWidth;
  int? _auditionPointer, _auditionPitch;

  /// 播放器生命周期跟随 State，而不是跟随会频繁重建的 widget。
  late final MusicPreviewService _preview;

  MusicConfig get _config =>
      ref.read(appControllerProvider).document!.config as MusicConfig;
  double get _pixelsPerQuarter => 120 * _zoom;
  int get _snapTicks => _snapDivisor == 0
      ? 1
      : math.max(1, (_config.ticksPerQuarter / _snapDivisor).round());

  @override
  void initState() {
    super.initState();
    _preview = widget.previewService ?? SoloudMusicPreview();
  }

  @override
  void dispose() {
    _transportRequest++;
    _positionTimer?.cancel();
    _horizontalScroll.dispose();
    _verticalScroll.dispose();
    unawaited(_preview.dispose());
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
    _pruneSelection(value);
    setState(() {});
  }

  void _redoAction() {
    if (_redo.isEmpty) return;
    _undo.add(_config);
    final value = _redo.removeLast();
    ref.read(appControllerProvider.notifier).updateConfig(value);
    _pruneSelection(value);
    setState(() {});
  }

  /// 撤销/重做后把选区里已经不存在的音符 id 清掉：否则后续 Delete/拖动会
  /// 对着空气提交一条内容不变的撤销记录，还会顺带清空重做栈。
  void _pruneSelection(MusicConfig config) {
    final ids = {for (final note in config.notes) note.id};
    _selected.removeWhere((id) => !ids.contains(id));
  }

  int _snap(int tick) =>
      _snapDivisor == 0 ? tick : (tick / _snapTicks).round() * _snapTicks;

  /// 按当前配置算一次单音裁决结果与重叠处数（两者都要遍历音符，一起算）。
  void _resolve() {
    final config = _config;
    if (identical(config, _resolutionConfig)) return;
    _resolutionConfig = config;
    _resolutionSpans = MusicTimeline.soundingSpans(config);
    _resolutionOverlaps = MusicTimeline.overlapCount(config);
  }

  String get _overlapLabel => _config.overlapMode.label;

  /// 本次操作把重叠处数变多时提示一次；没有新增重叠就不打扰。
  void _warnOverlapSince(int before) {
    if (!mounted) return;
    _resolve();
    final after = _resolutionOverlaps;
    if (after <= before) return;
    _overlapWarning('已允许重叠：现在共 $after 处重叠，将按「$_overlapLabel」只发声一个');
  }

  void _overlapWarning(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

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

  void _tap(TapDownDetails details) {
    if (_tool == _MusicTool.pan) return;
    final hit = _hit(details.localPosition);
    if (hit != null) {
      if (_tool == _MusicTool.erase) {
        _commit(
          _config.copyWith(
            notes: _config.notes.where((note) => note.id != hit.id).toList(),
          ),
        );
        _selected.remove(hit.id);
      } else if (_tool == _MusicTool.pencil &&
          !_selectionAtPointerDown.contains(hit.id)) {
        // 画笔：点到未选中的音符只是把它设为单选，不进入拖动。
        _selected
          ..clear()
          ..add(hit.id);
        setState(() {});
      } else if (!_selected.contains(hit.id)) {
        // 选择模式（以及画笔下按下已选中的音符）：点到未选中的音符替换成单选，
        // 点到已选中的音符保持整组选中，随后可整组拖动。
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
    // 允许重叠：只提示「已按策略单音发声」，不再拒绝这次落笔。
    final before = MusicTimeline.overlapCount(_config);
    _commit(_config.copyWith(notes: [..._config.notes, note]));
    _selected
      ..clear()
      ..add(note.id);
    _warnOverlapSince(before);
  }

  /// 记录本次指针按下前已选中的音符。放在 Listener 里而不是 onTapDown，
  /// 因为快速拖动时手势竞技场会把 tap 判负，onTapDown 可能根本不触发。
  void _rememberSelectionOnPointerDown(PointerDownEvent event) {
    _selectionAtPointerDown
      ..clear()
      ..addAll(_selected);
  }

  void _panStart(DragStartDetails details) {
    if (_tool == _MusicTool.pan) return;
    final hit = _hit(details.localPosition);
    if (hit == null) {
      if (_tool != _MusicTool.select) return;
      _marqueeStart = details.localPosition;
      _marqueeEnd = details.localPosition;
      _selected.clear();
      setState(() {});
      return;
    }
    // 选择模式：按住任意音符即可拖动。画笔模式：只有按住按下前就已经选中的
    // 音符才拖动（否则它是刚被画笔选中的目标，保持画笔的原有行为）。
    final movable =
        _tool == _MusicTool.select ||
        (_tool == _MusicTool.pencil &&
            _selectionAtPointerDown.contains(hit.id));
    if (!movable) return;
    if (!_selected.contains(hit.id)) {
      _selected
        ..clear()
        ..add(hit.id);
    }
    _dragOriginals
      ..clear()
      ..addEntries([
        for (final note in _config.notes)
          if (_selected.contains(note.id)) MapEntry(note.id, note),
      ]);
    _dragOriginals.putIfAbsent(hit.id, () => hit);
    _dragAnchorId = hit.id;
    _dragStart = details.localPosition;
    _overlapAtPointerDown = MusicTimeline.overlapCount(_config);
    _overlapTracked = true;
    // 调时值的命中区随音符宽度收缩（下限 3px）：满宽音符仍是右缘 10px，
    // 短音符（最小绘制宽度 8px）左侧始终留得下可拖动的区域。
    final anchorRect = _noteRect(hit);
    final resizeZone = math.min(10.0, math.max(3.0, anchorRect.width * 0.25));
    _resizing =
        _dragOriginals.length == 1 &&
        (anchorRect.right - details.localPosition.dx).abs() < resizeZone;
    _dragHistoryPending = true;
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
    final anchor = _dragOriginals[_dragAnchorId];
    if (anchor == null) {
      if (_marqueeStart != null) {
        _marqueeEnd = details.localPosition;
        final rect = Rect.fromPoints(_marqueeStart!, _marqueeEnd!);
        _selected
          ..clear()
          ..addAll(
            _config.notes
                .where((note) => rect.overlaps(_noteRect(note)))
                .map((note) => note.id),
          );
        setState(() {});
      }
      return;
    }
    final start = _dragStart ?? details.localPosition;
    final anchorLeft = _noteRect(anchor).left;
    final tickDelta = _snap(
      ((details.localPosition.dx - start.dx) /
              _pixelsPerQuarter *
              _config.ticksPerQuarter)
          .round(),
    );
    if (_resizing) {
      final next = anchor.copyWith(
        durationTicks: math.max(
          _snapTicks,
          _snap(
            ((details.localPosition.dx - anchorLeft) /
                    _pixelsPerQuarter *
                    _config.ticksPerQuarter)
                .round(),
          ),
        ),
      );
      if (next.durationTicks == anchor.durationTicks) return;
      _commit(
        _config.copyWith(
          notes: [
            for (final note in _config.notes)
              if (note.id == next.id) next else note,
          ],
        ),
        history: _dragHistoryPending,
      );
      _dragHistoryPending = false;
      _dragOriginals[next.id] = next;
      return;
    }
    // 整组平移：所有被拖动音符共享同一 (tickDelta, pitchDelta)，时长不变。
    final pitchDelta = _clampPitchDelta(
      _pitchAtY(details.localPosition.dy) - _pitchAtY(start.dy),
    );
    final startDelta = _clampTickDelta(tickDelta);
    final moved = <String, MusicNote>{
      for (final entry in _dragOriginals.entries)
        entry.key: entry.value.copyWith(
          startTick: entry.value.startTick + startDelta,
          pitch: entry.value.pitch + pitchDelta,
        ),
    };
    // 早退条件看“结果是否与当前配置一致”，而不是“位移是否为 0”：指针绕回按下
    // 位置附近时位移会吸附回 0，此时必须把音符放回原位，不能停在上一帧的位移上。
    final current = {for (final note in _config.notes) note.id: note};
    final unchanged = moved.entries.every((entry) {
      final note = current[entry.key];
      return note != null &&
          note.pitch == entry.value.pitch &&
          note.startTick == entry.value.startTick &&
          note.durationTicks == entry.value.durationTicks;
    });
    if (unchanged) return;
    _commit(
      _config.copyWith(
        notes: [for (final note in _config.notes) moved[note.id] ?? note],
      ),
      history: _dragHistoryPending,
    );
    _dragHistoryPending = false;
  }

  int _clampTickDelta(int delta) {
    final earliest = _dragOriginals.values
        .map((note) => note.startTick)
        .reduce(math.min);
    return math.max(delta, -earliest);
  }

  int _clampPitchDelta(int delta) {
    final lowest = _dragOriginals.values
        .map((note) => note.pitch)
        .reduce(math.min);
    final highest = _dragOriginals.values
        .map((note) => note.pitch)
        .reduce(math.max);
    return delta.clamp(1 - lowest, 127 - highest);
  }

  void _panEnd(DragEndDetails details) {
    final before = _overlapAtPointerDown;
    final tracked = _overlapTracked;
    _overlapAtPointerDown = 0;
    _overlapTracked = false;
    _dragOriginals.clear();
    _dragAnchorId = null;
    _dragStart = null;
    _dragHistoryPending = false;
    _resizing = false;
    _marqueeStart = null;
    _marqueeEnd = null;
    setState(() {});
    if (tracked) _warnOverlapSince(before);
  }

  void _deleteSelected() {
    final ids = _selected.where((id) => _config.notes.any((n) => n.id == id));
    if (ids.isEmpty) {
      if (_selected.isNotEmpty) setState(_selected.clear);
      return;
    }
    _commit(
      _config.copyWith(
        notes: _config.notes
            .where((note) => !_selected.contains(note.id))
            .toList(),
      ),
    );
    _selected.clear();
  }

  /// 全选（Ctrl+A）：所有音符都是可编辑、可发声候选，不分主次。
  void _selectAll() {
    if (_config.notes.isEmpty) return;
    setState(() {
      _selected
        ..clear()
        ..addAll(_config.notes.map((note) => note.id));
    });
  }

  /// 复制选中音符（Ctrl+C）：按最小时刻归一化成相对偏移，粘贴时整块落到播放头。
  void _copy() {
    final copies = [
      for (final note in _config.notes)
        if (_selected.contains(note.id)) note,
    ];
    if (copies.isEmpty) return;
    copies.sort((a, b) {
      final tick = a.startTick.compareTo(b.startTick);
      if (tick != 0) return tick;
      final pitch = b.pitch.compareTo(a.pitch);
      return pitch != 0 ? pitch : a.id.compareTo(b.id);
    });
    final baseTick = copies.first.startTick;
    _clipboard = [
      for (final note in copies)
        note.copyWith(startTick: note.startTick - baseTick),
    ];
  }

  /// 粘贴（Ctrl+V）：整块落到播放头（吸附到网格），保持相对时刻与音高。
  void _paste() {
    if (_clipboard.isEmpty) return;
    final baseTick = _snap(math.max(0, _playheadTick));
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final pasted = [
      for (final (index, source) in _clipboard.indexed)
        source.copyWith(
          id: 'n${stamp}_$index',
          startTick: baseTick + source.startTick,
        ),
    ];
    final before = MusicTimeline.overlapCount(_config);
    _commit(_config.copyWith(notes: [..._config.notes, ...pasted]));
    _selected
      ..clear()
      ..addAll(pasted.map((note) => note.id));
    _warnOverlapSince(before);
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
                      '${entry.$2.melodicNoteCount} 个音符${entry.$2.polyphonic ? ' · 包含重叠音，导入后按重叠处理单音发声' : ''}',
                    ),
                    onTap: () => Navigator.pop(context, entry.$1),
                  ),
              ],
            ),
          ),
        ),
      );
      if (selected != null) {
        final imported = midi.selectTrack(
          selected,
          sourceName: file.name,
          overlapMode: _config.overlapMode,
          newNoteInterrupts: _config.newNoteInterrupts,
        );
        _commit(imported);
        final overlaps = MusicTimeline.overlapCount(imported);
        if (overlaps > 0) {
          _overlapWarning(
            '已导入 ${imported.notes.length} 个音符，检测到 $overlaps 处重叠，'
            '将按「${imported.overlapMode.label}」只发声一个',
          );
        }
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
    await _preview.play(_config, looping: _loopPreview);
    if (!mounted || request != _transportRequest) return;
    if (!_preview.playing) {
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
      if (!_preview.playing) {
        _positionTimer?.cancel();
        setState(() {
          _isPlaying = false;
          _isPaused = false;
        });
        return;
      }
      final micros = _preview.position.inMicroseconds;
      final previous = _playheadTick;
      final next = _tickAtMicros(micros);
      setState(() => _playheadTick = next);
      _followPlayhead(previousTick: previous);
    });
  }

  Future<void> _togglePause() async {
    if (!_isPlaying) return;
    await _preview.togglePause();
    if (!mounted) return;
    setState(() => _isPaused = _preview.paused);
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
    await _preview.stop();
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
    unawaited(_preview.startPitch(pitch));
  }

  void _pianoUp(PointerEvent event) {
    if (_auditionPointer != event.pointer) return;
    setState(() {
      _auditionPointer = null;
      _auditionPitch = null;
    });
    unawaited(_preview.stopPitch());
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
                    child: ClipRect(
                      key: const ValueKey('music-header-clip'),
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
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: _keysWidth,
                    child: ClipRect(
                      key: const ValueKey('music-piano-clip'),
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
                            child: Listener(
                              onPointerDown: _rememberSelectionOnPointerDown,
                              child: GestureDetector(
                                key: const ValueKey('music-note-grid'),
                                behavior: HitTestBehavior.opaque,
                                dragStartBehavior: DragStartBehavior.down,
                                onTapDown: _tap,
                                onPanStart: _panStart,
                                onPanUpdate: _panUpdate,
                                onPanEnd: _panEnd,
                                child: CustomPaint(
                                  size: timelineSize,
                                  painter: _PianoRollPainter(
                                    config: config,
                                    selected: Set.of(_selected),
                                    sounding: _resolutionSpans,
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
    _resolve();
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
        const SingleActivator(LogicalKeyboardKey.keyA, control: true):
            _selectAll,
        const SingleActivator(LogicalKeyboardKey.delete): _deleteSelected,
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compactToolbar = constraints.maxWidth < 600;
                return SizedBox(
                  key: const ValueKey('music-toolbar-panel'),
                  width: double.infinity,
                  child: Material(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (compactToolbar)
                            IconButton.filledTonal(
                              onPressed: _importMidi,
                              tooltip: '导入 MIDI',
                              icon: const Icon(Icons.file_open),
                            )
                          else
                            FilledButton.tonalIcon(
                              onPressed: _importMidi,
                              icon: const Icon(Icons.file_open),
                              label: const Text('导入 MIDI'),
                            ),
                          if (compactToolbar)
                            IconButton.outlined(
                              onPressed: _exportMidi,
                              tooltip: '导出 MIDI',
                              icon: const Icon(Icons.save_alt),
                            )
                          else
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
                            showSelectedIcon: !compactToolbar,
                            segments: [
                              ButtonSegment(
                                value: _MusicTool.select,
                                icon: const Icon(Icons.near_me_outlined),
                                label: compactToolbar ? null : const Text('选择'),
                                tooltip: '选择',
                              ),
                              ButtonSegment(
                                value: _MusicTool.pencil,
                                icon: const Icon(Icons.edit),
                                label: compactToolbar ? null : const Text('画笔'),
                                tooltip: '画笔',
                              ),
                              ButtonSegment(
                                value: _MusicTool.erase,
                                icon: const Icon(Icons.delete_outline),
                                label: compactToolbar ? null : const Text('删除'),
                                tooltip: '删除',
                              ),
                              ButtonSegment(
                                value: _MusicTool.pan,
                                icon: const Icon(Icons.pan_tool_outlined),
                                label: compactToolbar ? null : const Text('平移'),
                                tooltip: '平移',
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
                              DropdownMenuItem(
                                value: 6,
                                child: Text('1/16 三连音'),
                              ),
                              DropdownMenuItem(value: 8, child: Text('1/32')),
                            ],
                            onChanged: (value) =>
                                setState(() => _snapDivisor = value ?? 4),
                          ),
                          if (!compactToolbar) const Text('重叠处理'),
                          Tooltip(
                            message: '重叠处理：重叠音符按哪种规则只发声一个',
                            child: DropdownButton<MusicOverlapMode>(
                              key: const ValueKey('music-overlap-mode'),
                              value: config.overlapMode,
                              items: [
                                for (final mode in MusicOverlapMode.values)
                                  DropdownMenuItem(
                                    value: mode,
                                    child: Text(mode.label),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value == null ||
                                    value == config.overlapMode) {
                                  return;
                                }
                                _commit(
                                  _config.copyWith(overlapMode: value),
                                );
                              },
                            ),
                          ),
                          Tooltip(
                            message: '勾选后，后起始的音符会打断前一个音符的延音（被打断部分变灰）',
                            child: FilterChip(
                              key: const ValueKey('music-new-note-interrupts'),
                              label: const Text('新音符打断'),
                              selected: config.newNoteInterrupts,
                              onSelected: (value) => _commit(
                                _config.copyWith(newNoteInterrupts: value),
                              ),
                            ),
                          ),
                          Tooltip(
                            message: '调号：固件五线谱左端显示的调号（也影响升降号拼写位置）',
                            child: DropdownButton<int>(
                              key: const ValueKey('music-key-signature'),
                              value: config.keySignatureFifths,
                              items: [
                                for (final option in staffKeySignatureOptions)
                                  DropdownMenuItem(
                                    value: option.fifths,
                                    child: Text(
                                      compactToolbar
                                          ? option.label.split(' / ').first
                                          : option.label,
                                    ),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value == null ||
                                    value == config.keySignatureFifths) {
                                  return;
                                }
                                _commit(
                                  _config.copyWith(keySignatureFifths: value),
                                );
                              },
                            ),
                          ),
                          if (_resolutionOverlaps > 0)
                            Tooltip(
                              message:
                                  '灰色为不发声的音符/片段；重叠按「${config.overlapMode.label}」只发声一个',
                              child: Chip(
                                key: const ValueKey('music-overlap-warning'),
                                avatar: const Icon(
                                  Icons.warning_amber_rounded,
                                  size: 16,
                                ),
                                label: Text('$_resolutionOverlaps 处重叠'),
                              ),
                            ),
                          // 播放/暂停合并成一个键：停止时是“播放”，播放中是“暂停”，
                          // 暂停后仍由同一个键“继续”，不再出现两个播放按钮。
                          IconButton(
                            onPressed: _isLoading
                                ? null
                                : _isPlaying
                                ? _togglePause
                                : _play,
                            tooltip: _isPlaying
                                ? (_isPaused ? '继续' : '暂停')
                                : '播放',
                            icon: _isLoading
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _isPlaying && !_isPaused
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                  ),
                          ),
                          IconButton(
                            onPressed: _stop,
                            tooltip: '停止',
                            icon: const Icon(Icons.stop),
                          ),
                          if (compactToolbar)
                            IconButton.filledTonal(
                              isSelected: _loopPreview,
                              onPressed: () =>
                                  setState(() => _loopPreview = !_loopPreview),
                              tooltip: '循环预览',
                              icon: const Icon(Icons.repeat),
                              selectedIcon: const Icon(Icons.repeat_on),
                            )
                          else
                            FilterChip(
                              label: const Text('循环预览'),
                              selected: _loopPreview,
                              onSelected: (value) =>
                                  setState(() => _loopPreview = value),
                            ),
                          SegmentedButton<MusicViewportMode>(
                            showSelectedIcon: !compactToolbar,
                            segments: [
                              ButtonSegment(
                                value: MusicViewportMode.fixed,
                                icon: const Icon(Icons.crop_free),
                                label: compactToolbar
                                    ? null
                                    : const Text('固定视窗'),
                                tooltip: '固定视窗',
                              ),
                              ButtonSegment(
                                value: MusicViewportMode.paged,
                                icon: const Icon(Icons.auto_stories_outlined),
                                label: compactToolbar
                                    ? null
                                    : const Text('逐页跟随'),
                                tooltip: '逐页跟随',
                              ),
                              ButtonSegment(
                                value: MusicViewportMode.anchored,
                                icon: const Icon(Icons.vertical_align_center),
                                label: compactToolbar
                                    ? null
                                    : const Text('固定跟随'),
                                tooltip: '固定跟随',
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
                                compactToolbar
                                ? IconButton.outlined(
                                    onPressed: controller.open,
                                    tooltip:
                                        '速度事件（${config.tempoEvents.length}）',
                                    icon: const Icon(Icons.speed),
                                  )
                                : OutlinedButton.icon(
                                    onPressed: controller.open,
                                    icon: const Icon(Icons.speed),
                                    label: Text(
                                      '${config.tempoEvents.length} 个速度',
                                    ),
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
                                compactToolbar
                                ? IconButton.outlined(
                                    onPressed: controller.open,
                                    tooltip:
                                        '拍号事件（${config.timeSignatureEvents.length}）',
                                    icon: const Icon(Icons.grid_4x4),
                                  )
                                : OutlinedButton.icon(
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
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
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
                );
              },
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
    canvas.clipRect(Offset.zero & size);
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
    canvas.clipRect(Offset.zero & size);
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
    required this.sounding,
    required this.pixelsPerQuarter,
    required this.rowHeight,
    required this.playheadTick,
    required this.marquee,
  });
  final MusicConfig config;
  final Set<String> selected;

  /// 单音裁决后真正发声的区间：不在里面的音符/片段画成灰色。
  final List<MusicSoundingSpan> sounding;
  final double pixelsPerQuarter, rowHeight;
  final int playheadTick;
  final Rect? marquee;

  static const _muted = Color(0xff59626c);
  static const _active = Color(0xff02acc0);
  static const _selectedActive = Color(0xffffc857);

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
    final byNote = <String, List<MusicSoundingSpan>>{};
    for (final span in sounding) {
      byNote.putIfAbsent(span.noteId, () => []).add(span);
    }
    // 先铺所有音符的灰色底，再叠发声片段，最后画边框：重叠音符的灰色
    // 部分不会盖住别的音符正在发声的片段。
    for (final note in config.notes) {
      canvas.drawRRect(_body(note), Paint()..color = _muted);
    }
    for (final note in config.notes) {
      final spans = byNote[note.id];
      if (spans == null) continue;
      final body = _bodyRect(note);
      final color = selected.contains(note.id) ? _selectedActive : _active;
      for (final span in spans) {
        final left = math.max(
          body.left,
          span.startTick / config.ticksPerQuarter * pixelsPerQuarter,
        );
        final right = math.min(
          body.right,
          span.endTick / config.ticksPerQuarter * pixelsPerQuarter,
        );
        if (right <= left) continue;
        final whole =
            span.startTick == note.startTick && span.endTick == note.endTick;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(left, body.top, right, body.bottom),
            Radius.circular(whole ? 3 : 1.5),
          ),
          Paint()..color = color,
        );
      }
    }
    for (final note in config.notes) {
      final on = selected.contains(note.id);
      canvas.drawRRect(
        _body(note),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = on ? Colors.white70 : Colors.white24
          ..strokeWidth = on ? 1.5 : 1,
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

  Rect _bodyRect(MusicNote note) => Rect.fromLTWH(
    note.startTick / config.ticksPerQuarter * pixelsPerQuarter,
    (127 - note.pitch) * rowHeight + 1,
    math.max(
      8,
      note.durationTicks / config.ticksPerQuarter * pixelsPerQuarter,
    ),
    rowHeight - 2,
  );

  RRect _body(MusicNote note) =>
      RRect.fromRectAndRadius(_bodyRect(note), const Radius.circular(3));

  @override
  bool shouldRepaint(covariant _PianoRollPainter oldDelegate) =>
      oldDelegate.config != config ||
      oldDelegate.selected != selected ||
      oldDelegate.sounding != sounding ||
      oldDelegate.pixelsPerQuarter != pixelsPerQuarter ||
      oldDelegate.playheadTick != playheadTick ||
      oldDelegate.marquee != marquee;
}
