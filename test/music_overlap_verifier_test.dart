// 独立验证：音乐卷帘「快捷键 Ctrl+A/C/V + 粘贴到播放头 + 重叠处理工具栏 +
// 重叠提示 + 框选/多选拖动 + 撤销历史」的对抗性 widget 测试。
//
// 本文件只新增测试，不修改 lib/。被测实现：lib/src/music_editor.dart。
// 契约来源：task-4 描述 + 现场代码阅读（以代码为准）。
//
// 几何事实（默认 zoom=1、ticksPerQuarter=480、吸附 1/16 → 120 tick）：
//   每四分音符 120px；x = tick/480*120；行高 18；
//   音符矩形 left = tick/480*120，top = (127-pitch)*18+1，
//   宽 = max(8, duration/480*120)，高 16；命中判定外扩 2px；
//   ValueKey('music-note-grid') 的局部坐标即内容坐标。
//
// 视口设为 1100x3000：127 个音高行共 2286px 全部可见，纵向滚动量为 0，
// 因此 pitch=1 / pitch=127 的夹取也能直接按在音符上验证。
// 指针统一用鼠标（pan slop = 2px），避免触屏滚动识别器抢手势。

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pieblock_app/src/controller.dart';
import 'package:pieblock_app/src/music_editor.dart';
import 'package:pieblock_app/src/music_preview.dart';
import 'package:pieblock_core/pieblock_core.dart';

const double _rowHeight = 18;
const double _ppq = 120;
const int _tpq = 480;

double _x(int tick) => tick / _tpq * _ppq;

double _y(int pitch) => (127 - pitch) * _rowHeight + _rowHeight / 2;

Offset _pt(int tick, int pitch) => Offset(_x(tick), _y(pitch));

MusicNote _n(String id, int pitch, int startTick, int durationTicks) =>
    MusicNote(
      id: id,
      pitch: pitch,
      startTick: startTick,
      durationTicks: durationTicks,
    );

/// 三个互不重叠的音符：c(240) / a(1920) / b(2400)。
List<MusicNote> _spread() => [
  _n('a', 60, 1920, 480),
  _n('b', 64, 2400, 480),
  _n('c', 55, 240, 480),
];

class _FakeMusicPreview implements MusicPreviewService {
  @override
  bool playing = false;

  @override
  bool paused = false;

  @override
  Duration position = Duration.zero;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> play(MusicConfig config, {required bool looping}) async {
    playing = true;
  }

  @override
  Future<void> togglePause() async {
    paused = !paused;
  }

  @override
  Future<void> stop() async {
    playing = false;
    position = Duration.zero;
  }

  @override
  Future<void> startPitch(int midiPitch) async {}

  @override
  Future<void> stopPitch() async {}
}

class _StaticProjectController extends AppController {
  _StaticProjectController(this.document);

  final ProjectDocument document;

  @override
  AppState build() => AppState(
    document: document,
    step: 0,
    maxVisitedStep: 0,
    saveStatus: SaveStatus.saved,
  );

  @override
  void updateConfig(ProjectConfig config) {
    final current = state.document;
    if (current == null) return;
    state = state.copyWith(
      document: current.copyWith(config: config),
      saveStatus: SaveStatus.saved,
    );
  }
}

ProjectDocument _document(List<MusicNote> notes) {
  final source = ProjectDocument.create('重叠验证', ProjectKind.music);
  return source.copyWith(
    config: MusicConfig(
      sourceName: 'overlap-verifier.mid',
      trackName: 'Verifier',
      notes: notes,
    ),
  );
}

class _Editor {
  _Editor(this.tester, this.preview);

  final WidgetTester tester;
  final _FakeMusicPreview preview;

  MusicConfig get config {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MusicEditorPage)),
      listen: false,
    );
    return container.read(appControllerProvider).document!.config
        as MusicConfig;
  }

  MusicNote note(String id) => config.notes.firstWhere((note) => note.id == id);

  bool has(String id) => config.notes.any((note) => note.id == id);

  int get noteCount => config.notes.length;

  Offset get gridOrigin =>
      tester.getTopLeft(find.byKey(const ValueKey('music-note-grid')));

  IconButton get undoButton => tester.widget<IconButton>(
    find.ancestor(
      of: find.byTooltip('撤销 Ctrl+Z'),
      matching: find.byType(IconButton),
    ),
  );

  IconButton get redoButton => tester.widget<IconButton>(
    find.ancestor(
      of: find.byTooltip('重做 Ctrl+Y'),
      matching: find.byType(IconButton),
    ),
  );

  bool get undoEnabled => undoButton.onPressed != null;

  bool get redoEnabled => redoButton.onPressed != null;

  Future<void> useTool(String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<TestGesture> press(Offset down) async {
    final gesture = await tester.startGesture(
      gridOrigin + down,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    return gesture;
  }

  /// 按下后按累计位移路径移动（[totals] 为相对按下点的累计量），最后松手。
  Future<void> dragPath(Offset down, List<Offset> totals) async {
    final gesture = await press(down);
    var travelled = Offset.zero;
    for (final total in totals) {
      await gesture.moveBy(total - travelled);
      travelled = total;
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
  }

  Future<void> drag(Offset down, Offset total) => dragPath(down, [total]);

  Future<void> tapContent(Offset point) async {
    await tester.tapAt(gridOrigin + point, kind: PointerDeviceKind.mouse);
    await tester.pump();
  }

  Future<void> ctrl(LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  Future<void> pressKey(LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

  /// 重叠提示会留下 SnackBar 计时器：测试结束前清掉，避免 pending timer 失败。
  Future<void> clearSnackBars({bool settle = false}) async {
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .clearSnackBars();
    await tester.pump();
    if (settle) await tester.pumpAndSettle();
  }
}

Future<_Editor> _pumpEditor(WidgetTester tester, List<MusicNote> notes) async {
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1100, 3000);
  final preview = _FakeMusicPreview();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appControllerProvider.overrideWith(
          () => _StaticProjectController(_document(notes)),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(body: MusicEditorPage(previewService: preview)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Editor(tester, preview);
}

/// 框选 a(1920..2400, p60) 与 b(2400..2880, p64)。
/// 从空白内容点 (400,1080)（pitch 67 行）拖到 (800,1240)（pitch 59 行）。
Future<void> _marqueeAB(_Editor editor) =>
    editor.drag(const Offset(400, 1080), const Offset(400, 160));

void main() {
  group('快捷键 Ctrl+A / Ctrl+C / Ctrl+V', () {
    testWidgets('T1 Ctrl+A→C→V：整块按最小时刻归一化粘贴，新 id，选中副本', (tester) async {
      final editor = await _pumpEditor(tester, _spread());

      await editor.ctrl(LogicalKeyboardKey.keyA);
      await editor.ctrl(LogicalKeyboardKey.keyC);
      await editor.ctrl(LogicalKeyboardKey.keyV);

      expect(editor.noteCount, 6, reason: '粘贴应新增一份三个音符的副本');
      final pasted = editor.config.notes.skip(3).toList();
      expect(
        pasted.map((note) => (note.pitch, note.startTick)).toList(),
        [(55, 0), (60, 1680), (64, 2160)],
        reason: '播放头 0 + 复制块相对偏移（最小时刻 240 归一化）',
      );
      expect(
        pasted.every(
          (note) => const {'a', 'b', 'c'}.every((id) => note.id != id),
        ),
        isTrue,
        reason: '粘贴必须生成新 id',
      );
      expect(find.textContaining('已允许重叠'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('music-overlap-warning')),
        findsOneWidget,
        reason: '粘贴造成重叠后应出现重叠徽标',
      );

      // 粘贴块处于选中状态：Delete 只删副本。
      await editor.pressKey(LogicalKeyboardKey.delete);
      expect(editor.noteCount, 3);
      expect(editor.has('a') && editor.has('b') && editor.has('c'), isTrue);
      await editor.clearSnackBars(settle: true);
    });

    testWidgets('T2 Ctrl+Z/Ctrl+Y：一次粘贴一条历史，撤销后回滚整块', (tester) async {
      final editor = await _pumpEditor(tester, _spread());
      expect(editor.undoEnabled, isFalse);

      await editor.ctrl(LogicalKeyboardKey.keyA);
      await editor.ctrl(LogicalKeyboardKey.keyC);
      await editor.ctrl(LogicalKeyboardKey.keyV);
      expect(editor.noteCount, 6);
      expect(editor.undoEnabled, isTrue);

      await editor.ctrl(LogicalKeyboardKey.keyZ);
      expect(editor.noteCount, 3, reason: '一次 Ctrl+Z 应回滚整块粘贴');
      expect(editor.has('a') && editor.has('b') && editor.has('c'), isTrue);
      expect(editor.undoEnabled, isFalse, reason: '粘贴只产生一条历史');
      expect(editor.redoEnabled, isTrue);

      await editor.ctrl(LogicalKeyboardKey.keyY);
      expect(editor.noteCount, 6, reason: 'Ctrl+Y 应恢复粘贴块');
      await editor.clearSnackBars(settle: true);
    });

    testWidgets('T3 空选区 Ctrl+C 与空剪贴板 Ctrl+V 都是 no-op；选区清空后剪贴板仍有效', (tester) async {
      final editor = await _pumpEditor(tester, _spread());

      await editor.ctrl(LogicalKeyboardKey.keyC);
      await editor.ctrl(LogicalKeyboardKey.keyV);
      expect(editor.noteCount, 3, reason: '没有复制内容时 Ctrl+V 不新增音符');

      await editor.ctrl(LogicalKeyboardKey.keyA);
      await editor.ctrl(LogicalKeyboardKey.keyC);
      // 点空白清空选区：剪贴板不应随之失效。
      await editor.tapContent(const Offset(300, 1000));
      await editor.ctrl(LogicalKeyboardKey.keyV);
      expect(editor.noteCount, 6, reason: '剪贴板独立于当前选区');
      await editor.clearSnackBars(settle: true);
    });

    testWidgets('T4 播放中 seek 到 1010ms：Ctrl+V 吸附到 1/16 网格（960 tick）', (tester) async {
      final editor = await _pumpEditor(tester, _spread());
      await editor.ctrl(LogicalKeyboardKey.keyA);
      await editor.ctrl(LogicalKeyboardKey.keyC);
      await editor.ctrl(LogicalKeyboardKey.keyV);
      expect(editor.config.notes.skip(3).map((note) => note.startTick), [
        0,
        1680,
        2160,
      ]);

      await tester.tap(find.byTooltip('播放'));
      await tester.pump();
      editor.preview.position = const Duration(milliseconds: 1010);
      await tester.pump(const Duration(milliseconds: 60));

      await editor.ctrl(LogicalKeyboardKey.keyV);
      final pasted = editor.config.notes.skip(6).toList();
      expect(pasted, hasLength(3));
      expect(
        pasted.map((note) => note.startTick).toList(),
        [960, 2640, 3120],
        reason: '1010ms = 969.6 tick，吸附到 1/16（120 tick）应为 960',
      );
      expect(pasted.map((note) => note.pitch).toList(), [55, 60, 64]);

      await tester.tap(find.byTooltip('停止'));
      await tester.pump();
      await editor.clearSnackBars(settle: true);
    });
  });

  group('重叠处理工具栏与警告', () {
    testWidgets('T5 重叠模式下拉切换真实驱动单音裁决，切换本身不弹提示', (tester) async {
      final editor = await _pumpEditor(tester, [
        _n('a', 62, 0, 960),
        _n('b', 60, 480, 960),
        _n('c', 67, 480, 480),
      ]);
      // a 从 0 持续到 960；b/c 在 480 与 a 重叠。
      expect(editor.config.overlapMode, MusicOverlapMode.nearest);
      expect(find.text('1 处重叠'), findsOneWidget);
      expect(
        tester.widget(find.byKey(const ValueKey('music-overlap-mode'))),
        isA<DropdownButton<MusicOverlapMode>>(),
        reason: '契约：模式控件必须是下拉',
      );

      List<String> lastSoundingId() => [
        for (final span in MusicTimeline.soundingSpans(
          editor.config,
        ))
          span.noteId,
      ];

      // 最近音阶：参照 62 → b(60) 距离 2 优于 c(67) 距离 5。
      expect(lastSoundingId().last, 'b');

      await tester.tap(find.byKey(const ValueKey('music-overlap-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取高音').last);
      await tester.pumpAndSettle();
      expect(editor.config.overlapMode, MusicOverlapMode.highest);
      expect(lastSoundingId().last, 'c', reason: '取高音应让 67 在 480 接管');
      expect(find.text('1 处重叠'), findsOneWidget, reason: '换策略不改变重叠处数');

      await tester.tap(find.byKey(const ValueKey('music-overlap-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取低音').last);
      await tester.pumpAndSettle();
      expect(editor.config.overlapMode, MusicOverlapMode.lowest);
      expect(lastSoundingId().last, 'b', reason: '取低音应让 60 在 480 接管');

      await tester.tap(find.byKey(const ValueKey('music-overlap-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取最近音阶').last);
      await tester.pumpAndSettle();
      expect(editor.config.overlapMode, MusicOverlapMode.nearest);
      expect(lastSoundingId().last, 'b');
      expect(
        find.textContaining('已允许重叠'),
        findsNothing,
        reason: '切换策略不产生新重叠，不应弹提示',
      );
    });

    testWidgets('T6 新音符打断开关切换裁决，但不影响重叠计数', (tester) async {
      final editor = await _pumpEditor(tester, [
        _n('a', 60, 0, 960),
        _n('b', 64, 480, 960),
      ]);
      expect(editor.config.newNoteInterrupts, isTrue);
      expect(
        tester.widget(find.byKey(const ValueKey('music-new-note-interrupts'))),
        isA<FilterChip>(),
        reason: '契约：新音符打断必须是 FilterChip',
      );
      final withInterrupts = MusicTimeline.soundingSpans(editor.config);
      expect(withInterrupts.map((span) => span.noteId).toList(), ['a', 'b']);
      expect(find.text('1 处重叠'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('music-new-note-interrupts')));
      await tester.pumpAndSettle();
      expect(editor.config.newNoteInterrupts, isFalse);
      final withoutInterrupts = MusicTimeline.soundingSpans(editor.config);
      expect(
        withoutInterrupts.map((span) => span.noteId).toList(),
        ['a'],
        reason: 'nearest + 不打断：正在发声的 a 保持',
      );
      expect(find.text('1 处重叠'), findsOneWidget, reason: '开关不影响重叠处数');
      expect(
        find.textContaining('已允许重叠'),
        findsNothing,
        reason: '切换开关不产生新重叠，不应弹提示',
      );

      await tester.tap(find.byKey(const ValueKey('music-new-note-interrupts')));
      await tester.pumpAndSettle();
      expect(editor.config.newNoteInterrupts, isTrue);
      expect(
        MusicTimeline.soundingSpans(
          editor.config,
        ).map((span) => span.noteId).toList(),
        ['a', 'b'],
      );
    });

    testWidgets('T7 徽标显示多区间处数，删除音符后处数下降，撤销后恢复', (tester) async {
      final editor = await _pumpEditor(tester, [
        _n('a', 60, 0, 480),
        _n('b', 64, 240, 480),
        _n('c', 67, 600, 1200),
      ]);
      // b 与 a 重叠 [240,480)、与 c 重叠 [600,720) → 两处。
      expect(MusicTimeline.overlapCount(editor.config), 2);
      expect(find.text('2 处重叠'), findsOneWidget);
      expect(
        tester.widget(find.byKey(const ValueKey('music-overlap-warning'))),
        isA<Chip>(),
        reason: '契约：重叠徽标必须是 Chip',
      );

      // 删掉 a：[240,480) 消失，只剩 [600,720)。
      await editor.tapContent(_pt(0, 60) + const Offset(60, 0));
      await editor.pressKey(LogicalKeyboardKey.delete);
      expect(editor.noteCount, 2);
      expect(find.text('1 处重叠'), findsOneWidget);

      await editor.ctrl(LogicalKeyboardKey.keyZ);
      expect(editor.noteCount, 3);
      expect(find.text('2 处重叠'), findsOneWidget);
    });

    testWidgets('T8 提示只在重叠处数增加时出现；拖开后徽标消失且不提示', (tester) async {
      final editor = await _pumpEditor(tester, [
        _n('a', 60, 0, 480),
        _n('b', 67, 1920, 480),
      ]);
      expect(find.byKey(const ValueKey('music-overlap-warning')), findsNothing);

      // 把 a 拖到 b 的起始位置：0 处 → 1 处，允许并提示。
      await editor.drag(_pt(0, 60) + const Offset(60, 0), const Offset(480, 0));
      expect(editor.note('a').startTick, 1920);
      expect(find.text('1 处重叠'), findsOneWidget);
      expect(find.textContaining('已允许重叠'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining('取最近音阶'),
        ),
        findsOneWidget,
        reason: '提示文案应带当前重叠策略名（工具栏下拉里也有同名文案，需限定在 SnackBar 内）',
      );
      await editor.clearSnackBars(settle: true);

      // 继续把 a 拖离 b：1 处 → 0 处，不应再提示，徽标消失。
      await editor.drag(_pt(1920, 60) + const Offset(60, 0), const Offset(480, 0));
      expect(editor.note('a').startTick, 3840);
      expect(MusicTimeline.overlapCount(editor.config), 0);
      expect(find.byKey(const ValueKey('music-overlap-warning')), findsNothing);
      expect(
        find.textContaining('已允许重叠'),
        findsNothing,
        reason: '重叠数没有增加就不应打扰用户',
      );
    });

    testWidgets('T9 框选：不写撤销历史、不误报重叠提示、且确实选中两个音符', (tester) async {
      final editor = await _pumpEditor(tester, [
        _n('a', 60, 0, 960),
        _n('b', 64, 480, 960),
      ]);
      expect(MusicTimeline.overlapCount(editor.config), 1);

      // 文档本来就有重叠，框选两个音符（不是拖动音符）。
      await editor.drag(const Offset(500, 1080), const Offset(-500, 160));

      expect(editor.noteCount, 2);
      expect(editor.note('a').startTick, 0);
      expect(editor.note('b').startTick, 480);
      expect(editor.undoEnabled, isFalse, reason: '框选不产生撤销记录');
      expect(
        find.textContaining('已允许重叠'),
        findsNothing,
        reason: '框选不是拖动音符，不应弹重叠提示',
      );

      // 框选确实选中了两个音符：Delete 全删。
      await editor.pressKey(LogicalKeyboardKey.delete);
      expect(editor.noteCount, 0);
    });

    testWidgets('T10 画笔新建重叠音符：允许落笔、提示一次、撤销一条', (tester) async {
      final editor = await _pumpEditor(tester, [_n('a', 60, 1920, 480)]);
      await editor.useTool('画笔');

      // a 占 1920..2400，在时间重叠、音高不同的行落笔。
      await editor.tapContent(_pt(1920, 64) + const Offset(60, 0));
      expect(editor.noteCount, 2);
      expect(editor.config.notes.last.pitch, 64);
      expect(editor.config.notes.last.startTick, 2160);
      expect(find.text('1 处重叠'), findsOneWidget);
      expect(find.textContaining('已允许重叠'), findsOneWidget);

      await editor.ctrl(LogicalKeyboardKey.keyZ);
      expect(editor.noteCount, 1, reason: '一次落笔只产生一条撤销历史');
      expect(editor.undoEnabled, isFalse);
      await editor.clearSnackBars(settle: true);
    });

    testWidgets('T11 粘贴造成重叠：弹一次提示并显示徽标', (tester) async {
      final editor = await _pumpEditor(tester, [_n('a', 60, 0, 960)]);
      await editor.ctrl(LogicalKeyboardKey.keyA);
      await editor.ctrl(LogicalKeyboardKey.keyC);
      await editor.ctrl(LogicalKeyboardKey.keyV);

      expect(editor.noteCount, 2);
      expect(MusicTimeline.overlapCount(editor.config), 1);
      expect(find.text('1 处重叠'), findsOneWidget);
      expect(find.textContaining('已允许重叠'), findsOneWidget);
      await editor.clearSnackBars(settle: true);
    });
  });

  group('多选拖动与撤销历史', () {
    testWidgets('T12 框选两个音符后复制：相对偏移归一化且粘贴保持音高', (tester) async {
      final editor = await _pumpEditor(tester, _spread());
      await _marqueeAB(editor);

      await editor.ctrl(LogicalKeyboardKey.keyC);
      await editor.ctrl(LogicalKeyboardKey.keyV);
      expect(editor.noteCount, 5);
      final pasted = editor.config.notes.skip(3).toList();
      expect(
        pasted.map((note) => (note.pitch, note.startTick)).toList(),
        [(60, 0), (64, 480)],
        reason: '只复制选中的 a/b，最小时刻 1920 归一化后落到播放头 0',
      );
      expect(
        pasted.map((note) => note.id).toSet().intersection(const {
          'a',
          'b',
          'c',
        }),
        isEmpty,
        reason: '粘贴必须生成新 id',
      );
      await editor.clearSnackBars(settle: true);
    });

    testWidgets('T13 多选后按在右缘仍整组平移，不进入调时值', (tester) async {
      final editor = await _pumpEditor(tester, _spread());
      await _marqueeAB(editor);

      // a 的矩形 x=480..600，按在右缘内 4px 处；单选中会触发 resize。
      await editor.drag(const Offset(596, 1215), const Offset(120, 0));

      expect(editor.note('a').startTick, 2400);
      expect(editor.note('b').startTick, 2880);
      expect(editor.note('a').pitch, 60);
      expect(editor.note('b').pitch, 64);
      expect(editor.note('a').durationTicks, 480, reason: '多选一律平移，不调时值');
      expect(editor.note('b').durationTicks, 480);
      expect(editor.note('c').startTick, 240, reason: '未选中的 c 不动');

      await editor.ctrl(LogicalKeyboardKey.keyZ);
      expect(editor.note('a').startTick, 1920);
      expect(editor.note('b').startTick, 2400);
    });

    testWidgets('T14 Ctrl+A 全选后拖动：整组平移且重叠数不变不提示', (tester) async {
      final editor = await _pumpEditor(tester, [
        _n('a', 60, 0, 960),
        _n('b', 64, 480, 960),
      ]);
      expect(MusicTimeline.overlapCount(editor.config), 1);
      await editor.ctrl(LogicalKeyboardKey.keyA);
      await editor.drag(_pt(0, 60) + const Offset(60, 0), const Offset(120, 0));

      expect(editor.note('a').startTick, 480);
      expect(editor.note('b').startTick, 960);
      expect(editor.note('a').pitch, 60);
      expect(editor.note('b').pitch, 64);
      expect(
        MusicTimeline.overlapCount(editor.config),
        1,
        reason: '整组等量平移不改变重叠关系',
      );
      expect(find.text('1 处重叠'), findsOneWidget);
      expect(
        find.textContaining('已允许重叠'),
        findsNothing,
        reason: '重叠数没有增加，不应弹提示',
      );

      await editor.ctrl(LogicalKeyboardKey.keyZ);
      expect(editor.note('a').startTick, 0);
      expect(editor.note('b').startTick, 480);
    });

    testWidgets('T15 一次拖动只留一条历史：拖出再拖回按下点后一次 Ctrl+Z 归位', (tester) async {
      final editor = await _pumpEditor(tester, [_n('a', 60, 1920, 480)]);
      final gesture = await editor.press(const Offset(540, 1215));
      await gesture.moveBy(const Offset(4, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(116, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-120, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(editor.note('a').startTick, 1920, reason: '拖回按下点应回到原位');
      expect(editor.undoEnabled, isTrue);

      await editor.ctrl(LogicalKeyboardKey.keyZ);
      expect(editor.note('a').startTick, 1920);
      expect(
        editor.undoEnabled,
        isFalse,
        reason: '一次拖动（含中途往返）只应保留一条撤销历史',
      );
    });

    testWidgets('T16 抖动 1px 不产生撤销历史；向左拖过头 startTick 夹到 0', (tester) async {
      final editor = await _pumpEditor(tester, [_n('a', 60, 1920, 480)]);

      // 1px 抖动：不超过鼠标 pan slop（2px），也不应留下历史。
      final jitter = await editor.press(const Offset(540, 1215));
      await jitter.moveBy(const Offset(1, 0));
      await tester.pump();
      await jitter.up();
      await tester.pump();
      expect(editor.undoEnabled, isFalse, reason: '1px 抖动不应产生撤销记录');
      expect(editor.note('a').startTick, 1920);

      // 向左拖 1400px（-5600 tick），startTick 应夹到 0。
      await editor.drag(const Offset(540, 1215), const Offset(-1400, 0));
      expect(editor.note('a').startTick, 0);
      expect(editor.note('a').durationTicks, 480);

      await editor.ctrl(LogicalKeyboardKey.keyZ);
      expect(editor.note('a').startTick, 1920);
    });

    testWidgets('T17 音高夹取：向上拖到 127，再从 127 向下拖到 1', (tester) async {
      final editor = await _pumpEditor(tester, [_n('a', 60, 1920, 480)]);

      await editor.drag(const Offset(540, 1215), const Offset(0, -3000));
      expect(editor.note('a').pitch, 127, reason: '向上不得超过 MIDI 127');
      expect(editor.note('a').startTick, 1920, reason: '纯纵向拖动不改变时刻');
      expect(editor.note('a').durationTicks, 480);

      // 127 行在 3000px 视口内可见：从它往下拖到最底。
      await editor.drag(const Offset(540, 9), const Offset(0, 3000));
      expect(editor.note('a').pitch, 1, reason: '向下不得低于 MIDI 1');
      expect(editor.note('a').startTick, 1920);
    });

    testWidgets('T18 粘贴→撤销→Delete：不误删原音符、不产生历史、Ctrl+Y 仍可重做粘贴', (tester) async {
      final editor = await _pumpEditor(tester, _spread());
      await editor.ctrl(LogicalKeyboardKey.keyA);
      await editor.ctrl(LogicalKeyboardKey.keyC);
      await editor.ctrl(LogicalKeyboardKey.keyV);
      expect(editor.noteCount, 6);

      await editor.ctrl(LogicalKeyboardKey.keyZ);
      expect(editor.noteCount, 3);
      expect(editor.undoEnabled, isFalse);
      expect(editor.redoEnabled, isTrue);

      // 撤销后 _selected 里不存在的粘贴 id 已被清理：Delete 是彻底的 no-op，
      // 既不误删原音符，也不写入“内容不变”的撤销记录、不清空重做栈。
      await editor.pressKey(LogicalKeyboardKey.delete);
      expect(editor.noteCount, 3);
      expect(editor.has('a') && editor.has('b') && editor.has('c'), isTrue);
      expect(
        editor.undoEnabled,
        isFalse,
        reason: '空选区 Delete 不应产生撤销记录',
      );
      expect(
        editor.redoEnabled,
        isTrue,
        reason: '空选区 Delete 不应清空重做栈',
      );

      // 重做链路仍然完好：Ctrl+Y 恢复粘贴块。
      await editor.ctrl(LogicalKeyboardKey.keyY);
      expect(editor.noteCount, 6, reason: 'Delete no-op 后仍应能重做粘贴');
      await editor.clearSnackBars(settle: true);
    });

    testWidgets('T19 单音符右缘调时值拉长到与别的音符重叠：允许并提示，一条撤销', (tester) async {
      final editor = await _pumpEditor(tester, [
        _n('a', 60, 0, 480),
        _n('b', 67, 1920, 480),
      ]);
      // a 宽 120px，按在右缘内 4px（命中区 min(10, width*0.25)=10px）→ resize。
      await editor.drag(const Offset(116, 1215), const Offset(480, 0));

      expect(editor.note('a').durationTicks, 2400, reason: '调时值不再拒绝重叠');
      expect(editor.note('a').startTick, 0);
      expect(editor.note('a').pitch, 60);
      expect(editor.note('b').durationTicks, 480, reason: '组外音符不受影响');
      expect(MusicTimeline.overlapCount(editor.config), 1);
      expect(find.text('1 处重叠'), findsOneWidget);
      expect(find.textContaining('已允许重叠'), findsOneWidget);

      await editor.ctrl(LogicalKeyboardKey.keyZ);
      expect(editor.note('a').durationTicks, 480, reason: '一次调时值只留一条历史');
      expect(editor.undoEnabled, isFalse);
      await editor.clearSnackBars(settle: true);
    });

    testWidgets('T20 拖动被 PointerCancel 中断后，后续框选不受残留拖动状态影响', (tester) async {
      final editor = await _pumpEditor(tester, [
        _n('a', 60, 0, 480),
        _n('b', 67, 1920, 480),
      ]);
      final gesture = await editor.press(_pt(0, 60) + const Offset(60, 0));
      await gesture.moveBy(const Offset(4, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(476, 0));
      await tester.pump();
      expect(editor.note('a').startTick, 1920, reason: '拖到与 b 重叠');
      await gesture.cancel();
      await tester.pump();
      await editor.clearSnackBars(settle: true);

      // 取消后再框选（起点是空白）：不应拖走 a，也不应弹重叠提示。
      await editor.drag(const Offset(500, 1080), const Offset(-500, 160));
      expect(editor.note('a').startTick, 1920, reason: '框选不应拖走 a');
      expect(editor.note('a').pitch, 60);
      expect(
        find.textContaining('已允许重叠'),
        findsNothing,
        reason: '取消拖动后的残留不应让框选误报',
      );
      await editor.clearSnackBars(settle: true);
    });
  });
}