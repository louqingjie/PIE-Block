// 音乐卷帘快捷键（Ctrl+A/C/V）与「重叠处理」工具栏的回归测试。
//
// 几何事实与手势说明见 `music_note_drag_test.dart` 文件头：内容坐标 = 网格局部
// 坐标，按 tick → x = tick/480*120、音高 → y = (127-pitch)*18+9 换算。
// 所有指针操作统一用鼠标，避免触屏滚动识别器抢手势。

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
const double _pixelsPerQuarter = 120;
const int _ticksPerQuarter = 480;

double _x(int tick) => tick / _ticksPerQuarter * _pixelsPerQuarter;

double _y(int pitch) => (127 - pitch) * _rowHeight + _rowHeight / 2;

Offset _pt(int tick, int pitch) => Offset(_x(tick), _y(pitch));

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
  final source = ProjectDocument.create('快捷键测试', ProjectKind.music);
  return source.copyWith(
    config: MusicConfig(
      sourceName: 'shortcuts.mid',
      trackName: 'Shortcuts',
      notes: notes,
    ),
  );
}

MusicNote _n(String id, int pitch, int startTick, int durationTicks) =>
    MusicNote(
      id: id,
      pitch: pitch,
      startTick: startTick,
      durationTicks: durationTicks,
    );

/// 三音文档：c 在 240、a 在 1920、b 在 2400，互相不重叠。
List<MusicNote> _spreadNotes() => [
  _n('a', 60, 1920, 480),
  _n('b', 64, 2400, 480),
  _n('c', 55, 240, 480),
];

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

  Future<void> useTool(String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> drag(Offset down, Offset total) async {
    final gesture = await tester.startGesture(
      gridOrigin + down,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(4, 0));
    await tester.pump();
    await gesture.moveBy(total - const Offset(4, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
  }

  Future<void> tapContent(Offset point) async {
    await tester.tapAt(gridOrigin + point, kind: PointerDeviceKind.mouse);
    await tester.pump();
  }

  /// 发送 Ctrl+[key] 组合键。
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
  Future<void> clearSnackBars() async {
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .clearSnackBars();
    await tester.pump();
  }
}

/// 模拟“向导页 rebuild 时重新构造 MusicEditorPage”：同一个 State 收到新 widget，
/// 但注入的 previewService 变了。用于回归“停止键停不掉旧播放器”。
class _RebuildHost extends StatefulWidget {
  const _RebuildHost({super.key, required this.initialPreview});
  final MusicPreviewService initialPreview;

  @override
  State<_RebuildHost> createState() => _RebuildHostState();
}

class _RebuildHostState extends State<_RebuildHost> {
  late MusicPreviewService _preview = widget.initialPreview;

  void swapPreview(MusicPreviewService next) {
    setState(() => _preview = next);
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: MusicEditorPage(previewService: _preview));
}

Future<_Editor> _pumpEditor(WidgetTester tester, List<MusicNote> notes) async {
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 900);
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

void main() {
  group('快捷键', () {
    testWidgets('Ctrl+A 全选后 Delete 删除全部音符', (tester) async {
      final editor = await _pumpEditor(tester, _spreadNotes());
      expect(editor.noteCount, 3);

      await editor.ctrl(LogicalKeyboardKey.keyA);
      await editor.pressKey(LogicalKeyboardKey.delete);

      expect(editor.noteCount, 0, reason: 'Ctrl+A 应选中全部音符');
    });

    testWidgets('Ctrl+A 全选后拖动任一音符，整组平移', (tester) async {
      final editor = await _pumpEditor(tester, _spreadNotes());

      await editor.ctrl(LogicalKeyboardKey.keyA);
      await editor.drag(_pt(1920, 60), const Offset(120, 36));

      expect(editor.note('a').startTick, 2400);
      expect(editor.note('a').pitch, 58);
      expect(editor.note('b').startTick, 2880, reason: '整组按同一位移平移');
      expect(editor.note('b').pitch, 62);
      expect(editor.note('c').startTick, 720, reason: '整组按同一位移平移');
      expect(editor.note('c').pitch, 53);
      expect(editor.noteCount, 3);
    });

    testWidgets('Ctrl+C/Ctrl+V 多选粘贴到播放头（0 tick），保持相对偏移与音高', (tester) async {
      final editor = await _pumpEditor(tester, _spreadNotes());

      await editor.ctrl(LogicalKeyboardKey.keyA);
      await editor.ctrl(LogicalKeyboardKey.keyC);
      await editor.ctrl(LogicalKeyboardKey.keyV);

      expect(editor.noteCount, 6, reason: '粘贴应新增一份三个音符的副本');
      final pasted = editor.config.notes.skip(3).toList();
      expect(
        pasted.map((note) => (note.pitch, note.startTick)).toList(),
        [(55, 0), (60, 1680), (64, 2160)],
        reason: '播放头 0 tick + 复制块相对偏移（最小时刻 240 归一化）',
      );
      expect(
        pasted.every(
          (note) => const {'a', 'b', 'c'}.every((id) => note.id != id),
        ),
        isTrue,
        reason: '粘贴必须生成新 id',
      );
      expect(find.textContaining('已允许重叠'), findsOneWidget);
      await editor.clearSnackBars();

      // 粘贴后新音符应处于选中状态：Delete 只删粘贴出来的副本。
      await editor.pressKey(LogicalKeyboardKey.delete);
      expect(editor.noteCount, 3);
      expect(editor.has('a'), isTrue);
      expect(editor.has('b'), isTrue);
      expect(editor.has('c'), isTrue);
    });

    testWidgets('Ctrl+C/Ctrl+V 粘贴到播放头（播放中 seek 到 960 tick）', (tester) async {
      final editor = await _pumpEditor(tester, _spreadNotes());

      await editor.tapContent(_pt(1920, 60));
      await editor.ctrl(LogicalKeyboardKey.keyC);
      await editor.ctrl(LogicalKeyboardKey.keyV);
      expect(editor.config.notes.skip(3).single.startTick, 0, reason: '播放头在 0');

      // 播放并 seek 到 1000ms：120 BPM 下 1000ms = 960 tick。
      await tester.tap(find.byTooltip('播放'));
      await tester.pump();
      editor.preview.position = const Duration(milliseconds: 1000);
      await tester.pump(const Duration(milliseconds: 60));
      await editor.ctrl(LogicalKeyboardKey.keyV);
      expect(
        editor.config.notes.last.startTick,
        960,
        reason: '粘贴落到播放头并吸附到 1/16 网格',
      );

      await tester.tap(find.byTooltip('停止'));
      await tester.pump();
      await editor.clearSnackBars();
    });

    testWidgets('空选区 Ctrl+C 与空剪贴板 Ctrl+V 都是 no-op', (tester) async {
      final editor = await _pumpEditor(tester, _spreadNotes());

      await editor.ctrl(LogicalKeyboardKey.keyC);
      await editor.ctrl(LogicalKeyboardKey.keyV);
      expect(editor.noteCount, 3, reason: '没有复制内容时 Ctrl+V 不新增音符');
    });

    testWidgets('空工程 Ctrl+A 不崩、无撤销记录', (tester) async {
      final editor = await _pumpEditor(tester, const []);
      await editor.ctrl(LogicalKeyboardKey.keyA);
      expect(editor.noteCount, 0);
      expect(tester.takeException(), isNull);
    });
  });

  group('重叠处理工具栏', () {
    testWidgets('切换重叠模式与「新音符打断」写入配置', (tester) async {
      final editor = await _pumpEditor(tester, _spreadNotes());
      expect(editor.config.overlapMode, MusicOverlapMode.nearest);
      expect(editor.config.newNoteInterrupts, isTrue);

      await tester.tap(find.byKey(const ValueKey('music-overlap-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取低音').last);
      await tester.pumpAndSettle();
      expect(editor.config.overlapMode, MusicOverlapMode.lowest);

      await tester.tap(find.byKey(const ValueKey('music-new-note-interrupts')));
      await tester.pumpAndSettle();
      expect(editor.config.newNoteInterrupts, isFalse);
    });

    testWidgets('无重叠时不显示重叠徽标', (tester) async {
      final editor = await _pumpEditor(tester, _spreadNotes());
      expect(editor.noteCount, 3);
      expect(
        find.byKey(const ValueKey('music-overlap-warning')),
        findsNothing,
        reason: '没有重叠时不应显示徽标',
      );
    });

    testWidgets('有重叠时显示「N 处重叠」', (tester) async {
      final editor = await _pumpEditor(tester, [
        _n('a', 60, 0, 960),
        _n('b', 64, 480, 960),
      ]);
      expect(editor.noteCount, 2);
      expect(find.byKey(const ValueKey('music-overlap-warning')), findsOneWidget);
      expect(find.text('1 处重叠'), findsOneWidget);
    });

    testWidgets('文档本来就有重叠时，框选不应弹重叠提示', (tester) async {
      final editor = await _pumpEditor(tester, [
        _n('a', 60, 0, 960),
        _n('b', 64, 480, 960),
      ]);

      // 从空白行起框，圈住两个音符；框选不是拖动音符，不应弹「已允许重叠」。
      await editor.drag(const Offset(300, 1000), const Offset(400, 250));

      expect(find.textContaining('已允许重叠'), findsNothing);
      expect(editor.noteCount, 2);
    });

    testWidgets('画笔新建重叠音符：允许落笔并提示按策略单音发声', (tester) async {
      final editor = await _pumpEditor(tester, [_n('a', 60, 1920, 480)]);
      await editor.useTool('画笔');

      // 在 a 所在时段、不同音高行落笔：时间重叠但音高不同。
      await editor.tapContent(_pt(1920, 62));

      expect(editor.noteCount, 2, reason: '允许重叠：画笔应正常新建');
      expect(editor.config.notes.last.pitch, 62);
      expect(editor.config.notes.last.startTick, 1920);
      expect(find.textContaining('已允许重叠'), findsOneWidget);
      expect(find.text('1 处重叠'), findsOneWidget);
      await editor.clearSnackBars();
    });
  });

  group('播放控制', () {
    testWidgets('播放与暂停合并为一个键：暂停后同一按钮变为“继续”', (tester) async {
      final editor = await _pumpEditor(tester, _spreadNotes());
      expect(find.byTooltip('播放'), findsOneWidget);
      expect(find.byTooltip('继续'), findsNothing);

      // 停止状态：按一次开始播放，按钮变成“暂停”。
      await tester.tap(find.byTooltip('播放'));
      await tester.pump();
      expect(editor.preview.playing, isTrue);
      expect(find.byTooltip('暂停'), findsOneWidget);
      expect(
        find.byTooltip('播放'),
        findsNothing,
        reason: '播放中不应再出现第二个播放键',
      );

      // 播放中：按同一个键暂停，按钮变成“继续”。
      await tester.tap(find.byTooltip('暂停'));
      await tester.pump();
      expect(editor.preview.paused, isTrue);
      expect(find.byTooltip('继续'), findsOneWidget);
      expect(find.byTooltip('播放'), findsNothing);

      // 暂停状态：按同一个键继续播放，按钮变回“暂停”。
      await tester.tap(find.byTooltip('继续'));
      await tester.pump();
      expect(editor.preview.paused, isFalse);
      expect(find.byTooltip('暂停'), findsOneWidget);

      // 停止后回到初始的“播放”，且开始键仍从停止态可用。
      await tester.tap(find.byTooltip('停止'));
      await tester.pump();
      expect(editor.preview.playing, isFalse);
      expect(find.byTooltip('播放'), findsOneWidget);
      expect(find.byTooltip('继续'), findsNothing);
    });
  });

  group('调号', () {
    testWidgets('工具栏调号下拉更新配置并进入生成代码', (tester) async {
      final editor = await _pumpEditor(tester, _spreadNotes());
      expect(editor.config.keySignatureFifths, 0);

      await tester.tap(find.byKey(const ValueKey('music-key-signature')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('G 大调 / E 小调').last);
      await tester.pumpAndSettle();

      expect(editor.config.keySignatureFifths, 1);
      final code = CodeGenerator.generate(editor.config);
      expect(code, contains('STAFF_KEY_COUNT 1'));
      expect(code, contains('staffKeyStepsTreble'));
    });
  });

  group('播放器生命周期', () {
    testWidgets('播放中父级重建，停止键仍停掉最初的声音', (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 900);
      final first = _FakeMusicPreview();
      final second = _FakeMusicPreview();
      final hostKey = GlobalKey<_RebuildHostState>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appControllerProvider.overrideWith(
              () => _StaticProjectController(_document(_spreadNotes())),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: _RebuildHost(key: hostKey, initialPreview: first),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('播放'));
      await tester.pump();
      expect(first.playing, isTrue);

      // 父级 rebuild：同一个 State 收到新 widget，注入的播放器换成 second。
      hostKey.currentState!.swapPreview(second);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('停止'));
      await tester.pump();
      expect(first.playing, isFalse, reason: '停止必须作用于 State 持有的最初播放器');
      expect(second.playing, isFalse, reason: '新注入的播放器从未开始播放');
    });
  });
}
