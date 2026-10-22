// 音乐卷帘音符拖动实现的【独立对抗性验证】（task-3）。
// 被测实现：lib/src/music_editor.dart（本文件只读，不修改任何 lib/ 代码）。
//
// 命名约定：
//   C* = 契约 / 回归用例，断言“合理产品行为”，期望全部通过。
//   X* = 缺陷探针，同样断言“合理产品行为”；失败输出即为缺陷证据（不是测试写错）。
//
// 轮次：
//   第 1 轮：X1（拖出去再拖回按下点不归位）、X2（调时值可压住组外主音符）实测失败，
//           已作为缺陷上报；其余用例通过。
//   第 2 轮：lead 修复后 X1/X2 转为回归护栏（期望通过），并新增 C22–C27 覆盖修复
//           本身的边界（拒绝帧不锁死后续合法帧、拒绝帧不写历史、归位后只留一条历史、
//           死区抖动仍无历史、可扩到相邻音符边界但不回滚已生效值）。
//
// 几何事实（默认 zoom=1、ticksPerQuarter=480、吸附 1/16 → 120 tick）：
//   每四分音符 120px、行高 18、琴键宽 72、事件栏 48；
//   音符矩形 left = tick/480*120，top = (127-pitch)*18+1，
//   宽 = max(8, duration/480*120)，高 16；命中判定外扩 2px。
//   控件 ValueKey('music-note-grid') 的局部坐标即内容坐标：
//   global = getTopLeft(grid) + 局部坐标。
//
// 本文件把窗口设为 1100x3000：127 个音高行共 2286px 全部落在视口内，纵向滚动量为 0
// （_centerInitialPitch 被 clamp 到 0），因此任何内容坐标点都能直接命中，
// 便于验证 pitch=1 / pitch=127 这类边界的夹取。
//
// 手势：网格外还套着横向 / 纵向 SingleChildScrollView，它们的拖动识别器默认不接受
// 鼠标指针，因此统一用 PointerDeviceKind.mouse 让网格自己的 pan 识别器赢得竞技场
// （鼠标 pan slop = 2px）。实现以“相对 _dragStart 的绝对位置”计算位移，
// 结果与 dragStartBehavior 吞掉多少 slop 无关。

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pieblock_app/src/controller.dart';
import 'package:pieblock_app/src/music_editor.dart';
import 'package:pieblock_app/src/music_preview.dart';
import 'package:pieblock_core/pieblock_core.dart';

const double _rowHeight = 18;
const double _ppq = 120; // 每四分音符像素
const int _tpq = 480; // 默认 ticksPerQuarter
const int _snap = 120; // 默认吸附（1/16）

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

/// 主文档。
///   a   p60  1920..2400  与 b 首尾相接
///   b   p64  2400..2880  与 a 只隔 0 tick
///   s   p55   960..990   短音符：duration 30 tick = 7.5px，靠 max(8, …) 画成 8px 宽
///   o   p50  5760..6240  远端障碍音符（组平移撞它用）
List<MusicNote> _base() => [
  _n('a', 60, 1920, 480),
  _n('b', 64, 2400, 480),
  _n('s', 55, 960, 30),
  _n('o', 50, 5760, 480),
];

/// 最小 MusicPreviewService 实现，避免测试碰原生音频引擎。
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

/// 固定文档的 AppController 子类（不落盘、不留 pending timer）。
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
  final source = ProjectDocument.create('拖动对抗性验证', ProjectKind.music);
  return source.copyWith(
    config: MusicConfig(
      sourceName: 'edge.mid',
      trackName: 'Edge',
      notes: notes,
    ),
  );
}

class _Editor {
  _Editor(this.tester);

  final WidgetTester tester;

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

  Future<void> useTool(String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  /// 在内容坐标 [down] 按下（鼠标指针，未超过 slop 前不会起 pan）。
  Future<TestGesture> press(Offset down) async {
    final gesture = await tester.startGesture(
      gridOrigin + down,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    return gesture;
  }

  /// 按下后按累计位移路径移动（[totals] 是相对按下点的累计总量），最后松手。
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

  /// 点按（不拖动）：仍用鼠标指针，避免触摸 slop 影响。
  Future<void> tapContent(Offset point) async {
    await tester.tapAt(gridOrigin + point, kind: PointerDeviceKind.mouse);
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

Future<_Editor> _pumpEditor(WidgetTester tester, List<MusicNote> notes) async {
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  tester.view.devicePixelRatio = 1;
  // 3000 高：127 行（2286px）全可见，纵向滚动量 0；1100 宽：显示工具文字标签。
  tester.view.physicalSize = const Size(1100, 3000);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appControllerProvider.overrideWith(
          () => _StaticProjectController(_document(notes)),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: MusicEditorPage(previewService: _FakeMusicPreview()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Editor(tester);
}

/// 框选 a、b（内容坐标 (440,1080) → (740,1240)）。
Future<void> _marqueeAB(_Editor editor) =>
    editor.drag(const Offset(440, 1080), const Offset(300, 160));

void main() {
  group('C 契约 / 回归', () {
    testWidgets('C1 短音符（30 tick，绘制 8px）从左侧 1px 处仍能整体拖动', (tester) async {
      final editor = await _pumpEditor(tester, _base());

      // s 的绘制矩形 x=240..248（duration 30 tick 只有 7.5px，被 max(8,…) 撑到 8px）。
      // 右缘调时值命中区 = min(10, max(3, 8*0.25)) = 3px，所以左侧 7px 都可拖动。
      await editor.drag(
        _pt(960, 55) + const Offset(1, 0),
        const Offset(120, 0),
      );

      expect(
        editor.note('s').startTick,
        1440,
        reason: '120px = 480 tick，短音符应从左侧按住整体右移，而不是被 resize 吞掉',
      );
      expect(editor.note('s').durationTicks, 30, reason: '整体拖动不得改变时长');
      expect(editor.note('s').pitch, 55);
    });

    testWidgets('C2 短音符中部（距右缘 4px，> 3px 命中区）也能整体拖动', (tester) async {
      final editor = await _pumpEditor(tester, _base());

      await editor.drag(
        _pt(960, 55) + const Offset(4, 0),
        const Offset(-120, 0),
      );

      expect(editor.note('s').startTick, 480, reason: '8px 宽音符中间也应能整体拖动');
      expect(editor.note('s').durationTicks, 30);
    });

    testWidgets('C3 短音符右缘 1px 内是调时值，且被抬到最小吸附单位', (tester) async {
      final editor = await _pumpEditor(tester, _base());

      await editor.drag(_pt(960, 55) + const Offset(7, 0), const Offset(4, 0));

      expect(editor.note('s').startTick, 960, reason: '调时值不得改 startTick');
      expect(editor.note('s').pitch, 55, reason: '调时值不得改 pitch');
      expect(
        editor.note('s').durationTicks,
        _snap,
        reason: '低于一个吸附单位的时长会被抬到 120 tick（实现的下限）',
      );
    });

    testWidgets('C4 单选宽音符右缘 5px 内拖动是调时值：时长 = 原位 + 吸附位移，不瞬跳', (tester) async {
      final editor = await _pumpEditor(tester, [
        _n('a', 60, 1920, 480),
        _n('b', 50, 5760, 480),
      ]);

      // a 的右缘 x=600，按在 595（命中区内 5px），右移 250px = 1000 tick → 吸附 960。
      await editor.drag(Offset(_x(2400) - 5, _y(60)), const Offset(250, 0));

      expect(editor.note('a').startTick, 1920);
      expect(editor.note('a').pitch, 60);
      expect(editor.note('a').durationTicks, 480 + 960);
    });

    testWidgets('C5 多选时按在同一右缘位置一律平移（不进入调时值）', (tester) async {
      final editor = await _pumpEditor(tester, _base());
      await _marqueeAB(editor);

      // 与 C4 相同的位置（a 右缘内 1px），但选中了 a+b → 必须整组平移。
      await editor.drag(Offset(_x(2400) - 1, _y(60)), const Offset(250, 0));

      expect(editor.note('a').durationTicks, 480, reason: '多选时不得进入调时值');
      expect(editor.note('a').startTick, 2880);
      expect(editor.note('b').startTick, 3360, reason: '整组按同一位移平移');
      expect(editor.note('b').durationTicks, 480);
    });

    testWidgets('C6 组平移允许压住组外音符：整组到位并提示重叠', (tester) async {
      final editor = await _pumpEditor(tester, _base());
      await _marqueeAB(editor);

      // 整组右移 960px = 3840 tick：a → 5760..6240 与 o(5760..6240) 完全重叠。
      await editor.drag(_pt(1920, 60) + const Offset(1, 0), const Offset(960, 0));

      expect(editor.note('o').startTick, 5760, reason: '组外音符不得被推动');
      expect(editor.note('a').startTick, 5760, reason: '允许重叠后位移应生效');
      expect(editor.note('b').startTick, 6240, reason: '组内相对相位保持不变');
      expect(editor.note('a').durationTicks, 480);
      expect(editor.note('b').durationTicks, 480);
      expect(
        find.textContaining('已允许重叠'),
        findsOneWidget,
        reason: '产生重叠后要给一条提示',
      );
      await editor.clearSnackBars();

      await tester.tap(find.byTooltip('撤销 Ctrl+Z'));
      await tester.pumpAndSettle();
      expect(editor.note('a').startTick, 1920);
      expect(editor.note('b').startTick, 2400);
      expect(editor.undoButton.onPressed, isNull, reason: '一次拖动只能留下一条撤销历史');
    });

    testWidgets('C7 组左移越界：最早音符夹到 0，组内间距保持', (tester) async {
      final editor = await _pumpEditor(tester, [
        _n('a', 60, 480, 480),
        _n('b', 64, 1920, 480),
      ]);
      await editor.drag(const Offset(100, 1100), const Offset(550, 140));

      await editor.drag(
        _pt(480, 60) + const Offset(1, 0),
        const Offset(-300, 0),
      );

      expect(editor.note('a').startTick, 0, reason: '越界时刻夹到 0');
      expect(editor.note('b').startTick, 1440, reason: '组内相对相位保持（原差值 1440）');
      expect(editor.note('a').pitch, 60);
      expect(editor.note('b').pitch, 64);
    });

    testWidgets('C8 组内音高跨度大：最高音已在 127 时整组不能继续上移（不改跨度）', (tester) async {
      final editor = await _pumpEditor(tester, [
        _n('lo', 120, 1920, 480),
        _n('hi', 127, 3840, 480),
      ]);
      // 框选两个音符收紧的矩形。
      await editor.drag(const Offset(2, 2), const Offset(1198, 298));

      // 同时给横向位移，确认纵向被夹住时横向仍然生效（组是刚体）。
      await editor.drag(
        _pt(1920, 120) + const Offset(1, 0),
        const Offset(120, -3000),
      );

      expect(editor.note('lo').pitch, 120, reason: '最高音已到 127，整组不得再上移');
      expect(editor.note('hi').pitch, 127);
      expect(editor.note('lo').startTick, 2400, reason: '横向位移应照常生效');
      expect(editor.note('hi').startTick, 4320);
      expect(
        editor.note('hi').pitch - editor.note('lo').pitch,
        7,
        reason: '刚体平移不得改变组内音高跨度',
      );
    });

    testWidgets('C9 组底部夹取：最低音到 1，组内跨度保持', (tester) async {
      final editor = await _pumpEditor(tester, [
        _n('lo', 1, 960, 120),
        _n('hi', 7, 1920, 120),
      ]);
      await editor.drag(const Offset(200, 2100), const Offset(400, 195));

      await editor.drag(
        _pt(960, 1) + const Offset(1, 0),
        const Offset(-120, 3000),
      );

      expect(editor.note('lo').pitch, 1, reason: '音高下界为 1');
      expect(editor.note('hi').pitch, 7, reason: '组内跨度 6 保持');
      expect(editor.note('lo').startTick, 480);
      expect(editor.note('hi').startTick, 1440);
    });

    testWidgets('C10 点按已选中的音符不拖动 → 保持多选（不产生撤销记录）', (tester) async {
      final editor = await _pumpEditor(tester, _base());
      await _marqueeAB(editor);

      await editor.tapContent(_pt(1920, 60) + const Offset(1, 0));
      expect(editor.undoButton.onPressed, isNull, reason: '点按选择不应产生撤销记录');

      await editor.drag(
        _pt(2400, 64) + const Offset(1, 0),
        const Offset(250, 0),
      );

      expect(editor.note('a').startTick, 2880, reason: '多选应被保持，a 随组移动');
      expect(editor.note('b').startTick, 3360);
    });

    testWidgets('C11 点按未选中的音符 → 收敛为单选（旧多选被清空）', (tester) async {
      final editor = await _pumpEditor(tester, _base());
      await _marqueeAB(editor);

      await editor.tapContent(_pt(960, 55) + const Offset(4, 0));
      expect(editor.undoButton.onPressed, isNull);

      await editor.drag(
        _pt(960, 55) + const Offset(4, 0),
        const Offset(120, 0),
      );

      expect(editor.note('s').startTick, 1440);
      expect(editor.note('a').startTick, 1920, reason: '旧多选应已被清空，a 不得跟随');
      expect(editor.note('b').startTick, 2400);
    });

    testWidgets('C12 画笔模式下拖动已选中音符：整组平移、不新建、不清空多选', (tester) async {
      final editor = await _pumpEditor(tester, _base());
      await _marqueeAB(editor);
      await editor.useTool('画笔');

      await editor.drag(
        _pt(1920, 60) + const Offset(1, 0),
        const Offset(250, 0),
      );

      expect(editor.noteCount, 4, reason: '画笔拖动已选中音符不得新建音符');
      expect(editor.note('a').startTick, 2880, reason: '整组平移');
      expect(editor.note('b').startTick, 3360, reason: '多选未被清空');
    });

    testWidgets('C13 画笔点空白新建后，紧接着在新音符上拖动不产生第二个音符', (tester) async {
      final editor = await _pumpEditor(tester, _base());
      await editor.useTool('画笔');

      // (tick 2880, pitch 62) 是空白。
      await editor.tapContent(_pt(2880, 62));
      expect(editor.noteCount, 5, reason: '画笔点空白应新建一个音符');
      final created = editor.config.notes.last;
      expect(created.startTick, 2880);
      expect(created.pitch, 62);
      expect(created.durationTicks, _snap);

      await editor.drag(
        _pt(2880, 62) + const Offset(1, 0),
        const Offset(120, 0),
      );

      expect(editor.noteCount, 5, reason: '拖动新建的实现不应再产生第二个音符');
      expect(editor.config.notes.last.startTick, 3360, reason: '新音符应被平移');
      expect(editor.note('a').startTick, 1920);
    });

    testWidgets('C14 画笔模式拖动未选中音符：不移动、不新建', (tester) async {
      final editor = await _pumpEditor(tester, _base());
      await editor.useTool('画笔');

      await editor.drag(
        _pt(2400, 64) + const Offset(1, 0),
        const Offset(250, 0),
      );

      expect(editor.noteCount, 4);
      expect(editor.note('b').startTick, 2400, reason: '未选中音符不得被画笔拖动');
      expect(editor.note('b').pitch, 64);
    });

    testWidgets('C15 空拖动（吸附后位移为 0）不留撤销记录，也不移动音符', (tester) async {
      final editor = await _pumpEditor(tester, _base());

      // 10px = 40 tick，吸附到 0。
      await editor.drag(
        _pt(1920, 60) + const Offset(1, 0),
        const Offset(10, 0),
      );

      expect(editor.note('a').startTick, 1920);
      expect(editor.note('a').pitch, 60);
      expect(
        editor.undoButton.onPressed,
        isNull,
        reason: '抖动/空拖动不得留下“什么都没发生”的撤销记录',
      );
    });

    testWidgets('C16 与其它音符重叠的拖动照常生效、只留一条撤销并提示', (tester) async {
      final editor = await _pumpEditor(tester, _base());

      // a 右移 480 tick 后与 b（2400..2880）重叠 → 允许，按策略只发声一个。
      await editor.drag(
        _pt(1920, 60) + const Offset(1, 0),
        const Offset(120, 0),
      );

      expect(editor.note('a').startTick, 2400, reason: '允许重叠后位移应生效');
      expect(editor.note('a').pitch, 60);
      expect(editor.note('a').durationTicks, 480);
      expect(editor.undoButton.onPressed, isNotNull);
      expect(find.textContaining('已允许重叠'), findsOneWidget);
      await editor.clearSnackBars();

      await tester.tap(find.byTooltip('撤销 Ctrl+Z'));
      await tester.pumpAndSettle();
      expect(editor.note('a').startTick, 1920);
      expect(editor.undoButton.onPressed, isNull, reason: '一次拖动只留一条历史');
    });

    testWidgets('C17 多帧拖动只留一条撤销，撤销后完全回到原位', (tester) async {
      final editor = await _pumpEditor(tester, _base());

      await editor.dragPath(_pt(1920, 60) + const Offset(1, 0), const [
        Offset(100, 0),
        Offset(200, 0),
        Offset(250, 0),
      ]);
      expect(editor.note('a').startTick, 2880);

      await tester.tap(find.byTooltip('撤销 Ctrl+Z'));
      await tester.pumpAndSettle();

      expect(editor.note('a').startTick, 1920);
      expect(editor.note('a').pitch, 60);
      expect(editor.note('a').durationTicks, 480);
      expect(editor.undoButton.onPressed, isNull, reason: '只应有一条历史');
    });

    testWidgets('C18 任意音符都可点选/拖动，点选本身不算数据修改', (tester) async {
      final editor = await _pumpEditor(tester, [
        _n('a', 60, 1920, 480),
        _n('b', 64, 2400, 480),
      ]);

      // 点选不是数据修改：不得产生撤销历史。
      await editor.tapContent(_pt(1920, 60) + const Offset(1, 0));
      expect(editor.undoButton.onPressed, isNull, reason: '点选不应写撤销历史');

      // 被点选的音符可拖动，未选中的音符不受影响。
      await editor.drag(
        _pt(1920, 60) + const Offset(1, 0),
        const Offset(250, 0),
      );
      expect(editor.note('a').startTick, 2880, reason: '任意音符都应可拖动');
      expect(editor.note('b').startTick, 2400, reason: '未选中的音符不得随组移动');

      await tester.tap(find.byTooltip('撤销 Ctrl+Z'));
      await tester.pumpAndSettle();
      expect(editor.note('a').startTick, 1920);
      expect(editor.undoButton.onPressed, isNull);
    });

    testWidgets('C19 删除工具：点击删除音符，撤销可恢复', (tester) async {
      final editor = await _pumpEditor(tester, _base());
      await editor.useTool('删除');

      await editor.tapContent(_pt(1920, 60) + const Offset(1, 0));

      expect(editor.has('a'), isFalse, reason: '删除工具点音符应把它删掉');
      expect(editor.noteCount, 3);
      expect(editor.undoButton.onPressed, isNotNull);

      await tester.tap(find.byTooltip('撤销 Ctrl+Z'));
      await tester.pumpAndSettle();

      expect(editor.has('a'), isTrue, reason: '撤销应恢复被删除的音符');
      expect(editor.note('a').startTick, 1920);
    });

    testWidgets('C20 平移工具：拖动只滚动视口，不移动音符、不记历史', (tester) async {
      final editor = await _pumpEditor(tester, _base());
      await editor.useTool('平移');
      final before = editor.gridOrigin;

      await editor.drag(
        _pt(1920, 60) + const Offset(1, 0),
        const Offset(-100, 0),
      );

      expect(editor.note('a').startTick, 1920, reason: '平移工具不得移动音符');
      expect(editor.note('a').pitch, 60);
      expect(editor.undoButton.onPressed, isNull);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('music-note-grid'))).dx,
        closeTo(before.dx - 100, 1),
        reason: '平移工具应把内容横向滚动 -100px',
      );
    });
    testWidgets('C21 调时值多帧拖动只留一条撤销，撤销后恢复原时长', (tester) async {
      final editor = await _pumpEditor(tester, [
        _n('a', 60, 1920, 480),
        _n('b', 50, 5760, 480),
      ]);

      await editor.dragPath(Offset(_x(2400) - 5, _y(60)), const [
        Offset(50, 0),
        Offset(100, 0),
        Offset(250, 0),
      ]);
      expect(editor.note('a').durationTicks, 1440);
      expect(editor.note('a').startTick, 1920, reason: '调时值期间不应移动');

      await tester.tap(find.byTooltip('撤销 Ctrl+Z'));
      await tester.pumpAndSettle();

      expect(editor.note('a').durationTicks, 480, reason: '撤销应恢复原时长');
      expect(editor.note('a').startTick, 1920);
      expect(editor.undoButton.onPressed, isNull, reason: '一次调时值只应有一条历史');
    });

    testWidgets('C22 调时值先拉长压住相邻音符（允许），继续左拖仍能缩短且只留一条历史', (tester) async {
      final editor = await _pumpEditor(tester, [
        _n('a', 60, 1920, 480),
        _n('b', 64, 2400, 480),
      ]);

      // 第 1 帧 +70px：时长 720（1920..2640）压住 b —— 允许重叠，照常提交。
      // 第 2 帧回到 -120px：时长 120 tick（1920..2040）→ 必须仍能生效。
      final gesture = await editor.press(Offset(_x(2400) - 1, _y(60)));
      await gesture.moveBy(const Offset(70, 0));
      await tester.pump();
      expect(
        editor.note('a').durationTicks,
        720,
        reason: '允许重叠后压住相邻音符的调时值应生效',
      );
      expect(editor.undoButton.onPressed, isNotNull, reason: '真实改数据后应有撤销历史');

      await gesture.moveBy(const Offset(-190, 0));
      await tester.pump();
      expect(editor.note('a').durationTicks, 120, reason: '允许重叠后继续缩短应生效');
      await gesture.up();
      await tester.pump();
      await editor.clearSnackBars();

      expect(editor.note('a').startTick, 1920, reason: '调时值期间不应移动');
      expect(editor.note('a').pitch, 60);
      expect(editor.note('b').durationTicks, 480, reason: 'b 不应被改动');

      await tester.tap(find.byTooltip('撤销 Ctrl+Z'));
      await tester.pumpAndSettle();
      expect(editor.note('a').durationTicks, 480);
      expect(
        editor.undoButton.onPressed,
        isNull,
        reason: '整段手势只应有一条历史',
      );
    });

    testWidgets('C23 调时值多帧都停在原时长：不写历史', (tester) async {
      final editor = await _pumpEditor(tester, [
        _n('a', 60, 1920, 480),
        _n('b', 64, 2400, 480),
      ]);

      // 两帧都吸附回原时长 480 tick（±15px 内）：从未真正改数据。
      await editor.dragPath(Offset(_x(2400) - 1, _y(60)), const [
        Offset(10, 0),
        Offset(15, 0),
      ]);

      expect(editor.note('a').durationTicks, 480, reason: '吸附回原时长，不应变化');
      expect(editor.note('a').startTick, 1920);
      expect(editor.undoButton.onPressed, isNull, reason: '未真正改数据不得留下撤销记录');
    });

    testWidgets('C24 组平移回到原位：只留一条撤销历史', (tester) async {
      final editor = await _pumpEditor(tester, _base());
      await _marqueeAB(editor);

      final gesture = await editor.press(_pt(1920, 60) + const Offset(1, 0));
      await gesture.moveBy(const Offset(250, 0));
      await tester.pump();
      expect(editor.note('a').startTick, 2880, reason: '前置条件：拖出去时确实改过数据');

      await gesture.moveBy(const Offset(-248, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(editor.note('a').startTick, 1920, reason: '指针回到按下点，整组应归位');
      expect(editor.note('b').startTick, 2400, reason: '整组归位，相对相位不变');

      await tester.tap(find.byTooltip('撤销 Ctrl+Z'));
      await tester.pumpAndSettle();
      expect(editor.note('a').startTick, 1920);
      expect(editor.note('b').startTick, 2400);
      expect(
        editor.undoButton.onPressed,
        isNull,
        reason: '一次拖动只应有一条历史（该条目内容与当前状态等价，见 C27）',
      );
    });

    testWidgets('C25 死区内多帧抖动：不移动、不写历史', (tester) async {
      final editor = await _pumpEditor(tester, _base());

      // 每一帧都在 ±10px（=40 tick）内，吸附后位移都是 0。
      await editor.dragPath(_pt(1920, 60) + const Offset(1, 0), const [
        Offset(10, 0),
        Offset(-10, 0),
        Offset(5, 0),
      ]);

      expect(editor.note('a').startTick, 1920);
      expect(editor.note('a').pitch, 60);
      expect(
        editor.undoButton.onPressed,
        isNull,
        reason: '多帧抖动从未越出死区，不得产生撤销记录',
      );
    });

    testWidgets('C26 调时值允许越过相邻音符边界（不再拒绝越界帧）', (tester) async {
      final editor = await _pumpEditor(tester, [
        _n('a', 60, 1920, 480),
        _n('b', 64, 2760, 480),
      ]);

      // a 左缘 x=480。第 1 帧光标 x=690 → 时长 840（a 结束于 2760，正好贴住 b）。
      // 第 2 帧光标 x=710 → 时长 960（结束 2880 > 2760）→ 允许，且压住 b。
      final gesture = await editor.press(Offset(_x(2400) - 5, _y(60)));
      await gesture.moveBy(const Offset(95, 0));
      await tester.pump();
      expect(editor.note('a').durationTicks, 840, reason: '贴住相邻音符的时长应被允许');

      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      expect(
        editor.note('a').durationTicks,
        960,
        reason: '允许重叠：越过 b 边界的时长也应生效',
      );
      await gesture.up();
      await tester.pump();

      expect(editor.note('a').endTick, 2880);
      expect(editor.note('a').startTick, 1920);
      expect(editor.note('b').startTick, 2760, reason: 'b 不应被推动');
      expect(find.textContaining('已允许重叠'), findsOneWidget);
      await editor.clearSnackBars();

      await tester.tap(find.byTooltip('撤销 Ctrl+Z'));
      await tester.pumpAndSettle();
      expect(editor.note('a').durationTicks, 480);
      expect(editor.undoButton.onPressed, isNull, reason: '整段手势只应有一条历史');
    });

    testWidgets('C27 【记录用】净位移为 0 的拖动仍消耗一步撤销', (tester) async {
      final editor = await _pumpEditor(tester, _base());

      // 先制造一条真实历史：删除 s。
      await editor.useTool('删除');
      await editor.tapContent(_pt(960, 55) + const Offset(4, 0));
      expect(editor.has('s'), isFalse);

      // 再把 a 拖出去又拖回原位：净位移为 0。
      await editor.useTool('选择');
      await editor.dragPath(_pt(1920, 60) + const Offset(1, 0), const [
        Offset(250, 0),
        Offset(2, 0),
      ]);
      expect(editor.note('a').startTick, 1920, reason: '净位移为 0，音符应回到原位');

      // 第一次撤销：拖动的历史条目与当前状态等价 → 视觉上什么都没发生、按钮仍可用。
      await tester.tap(find.byTooltip('撤销 Ctrl+Z'));
      await tester.pumpAndSettle();
      expect(editor.has('s'), isFalse, reason: '该条目与当前状态等价，撤销是空操作');
      expect(
        editor.undoButton.onPressed,
        isNotNull,
        reason: '删除的历史仍在栈里，按钮应保持可用',
      );

      // 第二次撤销才真正撤销删除。
      await tester.tap(find.byTooltip('撤销 Ctrl+Z'));
      await tester.pumpAndSettle();
      expect(editor.has('s'), isTrue, reason: '第二次撤销恢复删除');
    });

    testWidgets('C28 调时值可与任意音符重叠（不再区分主/参考音符）', (tester) async {
      final editor = await _pumpEditor(tester, [
        _n('a', 60, 1920, 480),
        _n('other', 50, 2400, 480),
      ]);

      // a 右缘 x=600，右移 70px → 时长 720（a 结束 2640）会盖住 other(2400..2880)。
      await editor.drag(Offset(_x(2400) - 1, _y(60)), const Offset(70, 0));

      expect(editor.note('a').durationTicks, 720, reason: '重叠不再被拒绝');
      expect(editor.note('a').endTick, 2640);
      expect(editor.note('a').startTick, 1920);
      expect(editor.note('other').startTick, 2400, reason: '其它音符不得被改动');
      expect(editor.undoButton.onPressed, isNotNull);
      expect(find.textContaining('已允许重叠'), findsOneWidget);
      await editor.clearSnackBars();
    });

    testWidgets('C29 既有重叠文档：拖出去再拖回原点可以恢复', (tester) async {
      final editor = await _pumpEditor(tester, [
        // MIDI 导入会保留原时长，导入的工程里区间可以本来就重叠。
        _n('x', 60, 1920, 960), // 1920..2880
        _n('y', 64, 2400, 480), // 2400..2880，与 x 重叠
      ]);

      final gesture = await editor.press(_pt(1920, 60) + const Offset(1, 0));
      await gesture.moveBy(const Offset(250, 0));
      await tester.pump();
      expect(editor.note('x').startTick, 2880, reason: '前置条件：脱离重叠后可以移动');

      // 指针回到按下点：允许重叠后必须能拖回原点（原「已知限制」已消除）。
      await gesture.moveBy(const Offset(-248, 0));
      await tester.pump();
      expect(editor.note('x').startTick, 1920, reason: '允许重叠后拖回原点应生效');
      await gesture.up();
      await tester.pump();
      expect(editor.undoButton.onPressed, isNotNull);
    });
  });

  group('X 缺陷探针（首轮实测失败 → 修复后转为回归护栏）', () {
    testWidgets('X1 拖出去再拖回按下点，音符应回到原 tick', (tester) async {
      final editor = await _pumpEditor(tester, _base());
      final observed = <String, int>{};

      final gesture = await editor.press(_pt(1920, 60) + const Offset(1, 0));
      await gesture.moveBy(const Offset(250, 0));
      await tester.pump();
      observed['拖到 +250px'] = editor.note('a').startTick;

      // 指针回到按下点 +2px：位移吸附为 0，按“相对按下点位移”的语义音符应回到原位。
      await gesture.moveBy(const Offset(-248, 0));
      await tester.pump();
      observed['回到 +2px'] = editor.note('a').startTick;

      // 控制组：继续左移到 -40px（吸附 -120 tick），证明指针事件一直有派发。
      await gesture.moveBy(const Offset(-42, 0));
      await tester.pump();
      observed['继续到 -40px'] = editor.note('a').startTick;
      await gesture.up();
      await tester.pump();

      expect(observed['拖到 +250px'], 2880, reason: '前置条件：+250px 应吸附到 960 tick');
      expect(
        observed['继续到 -40px'],
        1800,
        reason: '前置条件：-40px 应吸附到 -120 tick，说明指针事件持续派发',
      );
      expect(
        observed['回到 +2px'],
        1920,
        reason:
            '位移吸附为 0 时音符应回到原位（实现自己声明“位移量始终相对按下位置计算”）；'
            '实测序列 $observed，音符停在上一次非零位移处，'
            '松手后音符与抓取点的相对位置会漂移最多一个任意大的位移',
      );
    });

    testWidgets('X2 右缘调时值允许与其它音符重叠，裁决结果与灰色显示一致', (tester) async {
      final editor = await _pumpEditor(tester, _base());

      // 按在 a 右缘内 1px（命中区 10px），右移 70px。
      await editor.drag(Offset(_x(2400) - 1, _y(60)), const Offset(70, 0));

      final a = editor.note('a');
      expect(a.startTick, 1920, reason: '调时值不应改 startTick');
      expect(a.pitch, 60, reason: '调时值不应改 pitch');
      expect(a.durationTicks, 720, reason: '允许重叠，调时值照常生效');
      expect(MusicTimeline.overlapCount(editor.config), 1);
      // 界面显示 a 到 2640，但单音裁决只让 b 在 2400 接管：
      // a 的 2400..2640 在卷帘里显示为灰色（不发声），播放/生成代码也一致。
      final spans = MusicTimeline.soundingSpans(editor.config);
      final aSpan = spans.firstWhere((span) => span.noteId == 'a');
      expect(aSpan.startTick, 1920);
      expect(aSpan.endTick, 2400, reason: 'a 被 b 打断，发声到 b 的起点为止');
      expect(
        spans.where((span) => span.noteId == 'b').single.startTick,
        2400,
      );
      expect(find.textContaining('已允许重叠'), findsOneWidget);
      await editor.clearSnackBars();
    });

    testWidgets('X3 指针被系统取消后不得残留拖动状态', (tester) async {
      final editor = await _pumpEditor(tester, _base());

      final first = await editor.press(_pt(1920, 60) + const Offset(1, 0));
      await first.moveBy(const Offset(250, 0));
      await tester.pump();
      expect(editor.note('a').startTick, 2880, reason: '前置条件：第一次拖动已生效');
      await first.cancel(); // 系统级 PointerCancel（无 onPanCancel 处理）
      await tester.pump();

      await editor.useTool('画笔');
      // 画笔下按住未选中音符 b：契约要求它“只单选、不拖动”。
      await editor.drag(
        _pt(2400, 64) + const Offset(1, 0),
        const Offset(-240, 0),
      );

      expect(editor.note('b').startTick, 2400, reason: '画笔拖动未选中音符不应移动它');
      expect(
        editor.note('a').startTick,
        2880,
        reason:
            '被取消的拖动不应残留 _dragOriginals/_dragAnchorId：'
            '实测第二次手势把 a 平移到了 ${editor.note('a').startTick} tick（pitch ${editor.note('a').pitch}）',
      );
    });

    testWidgets('X4 取消拖动后，框选与多选平移不受前一手势残留影响', (tester) async {
      final editor = await _pumpEditor(tester, _base());

      final first = await editor.press(_pt(1920, 60) + const Offset(1, 0));
      await first.moveBy(const Offset(250, 0));
      await tester.pump();
      expect(editor.note('a').startTick, 2880, reason: '前置条件：第一次拖动已生效');
      await first.cancel();
      await tester.pump();

      // 若 _dragOriginals/_dragAnchorId 残留，这次框选的 onPanUpdate 会走「整组平移」
      // 分支：a 会被平移到别处、选区为空 → 紧随其后的拖动只会带走 b。
      // 状态干净时：框选选中 {a,b}（a 此时在 2880..3360，仍在框选矩形内），
      // 之后拖动 b 应把 a 一起带到 3840。
      await _marqueeAB(editor);
      await editor.drag(
        _pt(2400, 64) + const Offset(1, 0),
        const Offset(250, 0),
      );

      expect(
        editor.note('a').startTick,
        3840,
        reason:
            '框选后多选平移应把 a 一起带走；实测 a=${editor.note('a').startTick} '
            '(pitch ${editor.note('a').pitch})，b=${editor.note('b').startTick}',
      );
      expect(editor.note('b').startTick, 3360);
    });

    testWidgets('X3-control 正常松手后无残留拖动状态（对照组）', (tester) async {
      final editor = await _pumpEditor(tester, _base());

      final first = await editor.press(_pt(1920, 60) + const Offset(1, 0));
      await first.moveBy(const Offset(250, 0));
      await tester.pump();
      await first.up(); // 与 X3 唯一的差别：正常结束
      await tester.pump();

      await editor.useTool('画笔');
      await editor.drag(
        _pt(2400, 64) + const Offset(1, 0),
        const Offset(-240, 0),
      );

      expect(editor.note('b').startTick, 2400);
      expect(editor.note('a').startTick, 2880, reason: '正常松手后状态已清理');
    });
  });
}
