// 音乐卷帘音符拖动行为的回归测试（对应 lib/src/music_editor.dart 的冻结契约）。
//
// 几何事实（见 lib/src/music_editor.dart，默认 zoom=1、ticksPerQuarter=480）：
//   行高 18、琴键宽 72、事件栏高 48、每四分音符 120px、默认吸附 1/16（120 tick）。
//   音符矩形 left = tick/480*120，top = (127-pitch)*18+1，宽 = max(8, duration/480*120)，
//   高 16；命中判定外扩 2px。控件 ValueKey('music-note-grid') 是包着 CustomPaint 的
//   GestureDetector，局部坐标即“内容坐标”，与滚动裁剪无关：
//   global = tester.getTopLeft(grid) + 局部坐标。
//
// 手势说明：网格外面还套着横向/纵向 SingleChildScrollView，它们的拖动识别器默认
// 不接受鼠标指针（ScrollBehavior.dragDevices 不含 mouse），因此测试统一用
// PointerDeviceKind.mouse 让网格自己的 pan 识别器赢得手势竞技场（鼠标 pan slop
// 只有 2px）。多数用例的按下点取音符左边界，这样“相对按下点位移”的吸附结果与
// 抓取偏移无关；T7/T8/T11 反过来刻意按在右缘附近，用来区分“调时值”与“整组平移”。
// `drag` 先走 4px 唤醒 pan，`dragOnce` 则一次到位（实现用
// dragStartBehavior.down，首个 pending delta 会经 acceptGesture→_checkDrag
// 作为一次 update 派发出来）。

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pieblock_app/src/controller.dart';
import 'package:pieblock_app/src/music_editor.dart';
import 'package:pieblock_app/src/music_preview.dart';
import 'package:pieblock_core/pieblock_core.dart';

const double _rowHeight = 18;
const double _pixelsPerQuarter = 120;
const int _ticksPerQuarter = 480;
const int _snapTicks = 120;

double _tickX(int tick) => tick / _ticksPerQuarter * _pixelsPerQuarter;

double _rowCenterY(int pitch) => (127 - pitch) * _rowHeight + _rowHeight / 2;

/// 内容坐标：音高 [pitch] 所在行的中点、时刻 [tick] 的左边界。
Offset _gridPoint(int tick, int pitch) =>
    Offset(_tickX(tick), _rowCenterY(pitch));

/// 内容坐标：从音符左边界向内偏移 [dx] 的按下点。
Offset _pressPoint(int startTick, int pitch, double dx) =>
    Offset(_tickX(startTick) + dx, _rowCenterY(pitch));

/// 内容坐标：按住音符右缘内侧 [inset] 像素处（默认落在 10px 调时值命中区内）。
Offset _rightEdgePoint(int endTick, int pitch, {double inset = 5}) =>
    Offset(_tickX(endTick) - inset, _rowCenterY(pitch));

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

/// 固定文档的 AppController 子类。
///
/// 这里只保留测试需要的最小行为：`updateConfig` 直接落在 state 上。真实实现会
/// 调度一个 500ms 的保存 Timer，测试里没有真实路径也没有必要留下 pending timer。
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

ProjectDocument _dragDocument() {
  final source = ProjectDocument.create('拖动测试', ProjectKind.music);
  return source.copyWith(
    config: MusicConfig(
      sourceName: 'drag.mid',
      trackName: 'Melody',
      notes: const [
        // a: x 480..600，pitch 60 行中心 y=1215，左边界可安全按住（非右缘改时长区）
        MusicNote(id: 'a', pitch: 60, startTick: 1920, durationTicks: 480),
        // b: x 600..720，pitch 64 行中心 y=1143；a+b 相隔一个 1/4 拍
        MusicNote(id: 'b', pitch: 64, startTick: 2400, durationTicks: 480),
        // c: x 60..180，pitch 55 行中心 y=1305，靠近 0 tick 便于验证左向夹取
        MusicNote(id: 'c', pitch: 55, startTick: 240, durationTicks: 480),
      ],
    ),
  );
}

/// 短音符文档：60 tick 只有 15px 宽（x 240..255），用来验证调时值命中区随宽度
/// 收缩（min(10, max(3, width*0.25)) = 3.75px）后，短音符左侧仍留得下整体拖动区。
ProjectDocument _shortNoteDocument() {
  final source = ProjectDocument.create('短音符测试', ProjectKind.music);
  return source.copyWith(
    config: MusicConfig(
      sourceName: 'short.mid',
      notes: const [
        MusicNote(id: 'short', pitch: 67, startTick: 960, durationTicks: 60),
        MusicNote(id: 'far', pitch: 60, startTick: 1920, durationTicks: 480),
      ],
    ),
  );
}

/// 测试用脚手架：把 tester 与网格坐标换算、手势动作、配置读取包在一起。
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

  int get noteCount => config.notes.length;

  Offset get gridOrigin =>
      tester.getTopLeft(find.byKey(const ValueKey('music-note-grid')));

  Future<void> useTool(String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  /// 用鼠标指针在网格的 [down]（内容坐标）按下，先走 4px 唤醒 pan，再累计移动到
  /// [total] 后抬手。
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

  /// 单步大位移：一次 moveBy 直接到位，模拟“快速拖动”。
  Future<void> dragOnce(Offset down, Offset total) async {
    final gesture = await tester.startGesture(
      gridOrigin + down,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(total);
    await tester.pump();
    await gesture.up();
    await tester.pump();
  }

  Future<void> tapContent(Offset point) async {
    await tester.tapAt(gridOrigin + point);
    await tester.pump();
  }
}

IconButton _undoButton(WidgetTester tester) => tester.widget<IconButton>(
  find.ancestor(
    of: find.byTooltip('撤销 Ctrl+Z'),
    matching: find.byType(IconButton),
  ),
);

Future<_Editor> _pumpEditor(
  WidgetTester tester, {
  ProjectDocument? document,
}) async {
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  tester.view.devicePixelRatio = 1;
  // 宽度 >= 600 才会显示“画笔/选择”等文字标签。
  tester.view.physicalSize = const Size(1100, 800);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appControllerProvider.overrideWith(
          () => _StaticProjectController(document ?? _dragDocument()),
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

void main() {
  testWidgets('T1 选择模式拖动音符会按吸附位移同时改音高与时刻，时长不变', (tester) async {
    final editor = await _pumpEditor(tester);

    // 内容坐标位移 (250, -36)：250px = 1000 tick，吸附到 960 tick（2 个 1/4 拍）；
    // -36px = 向上 2 行 = 升高 2 个半音。
    await editor.drag(_gridPoint(1920, 60), const Offset(250, -36));

    final a = editor.note('a');
    expect(a.startTick, 1920 + 960, reason: '250px 位移应吸附到 960 tick');
    expect(a.pitch, 62, reason: '上移 36px 应升高 2 个半音');
    expect(a.durationTicks, 480, reason: '拖动不改变时长');
    expect(editor.note('b').startTick, 2400, reason: '单音符拖动不应影响其他音符');
    expect(editor.note('b').pitch, 64);
    expect(editor.noteCount, 3);
  });

  testWidgets('T2 框选两个主音符后拖动其一，整组按同一位移平移且时长不变', (tester) async {
    final editor = await _pumpEditor(tester);

    // 空白处起框，圈住 a(x480..600/y1207..1223) 与 b(x600..720/y1135..1151)。
    await editor.drag(const Offset(440, 1080), const Offset(300, 160));
    await editor.drag(_gridPoint(1920, 60), const Offset(250, -36));

    expect(editor.note('a').startTick, 2880);
    expect(editor.note('a').pitch, 62);
    expect(editor.note('b').startTick, 3360, reason: '整组应按相同位移平移');
    expect(editor.note('b').pitch, 66, reason: '整组应按相同音高位移平移');
    expect(editor.note('a').durationTicks, 480);
    expect(editor.note('b').durationTicks, 480);
    expect(editor.note('c').startTick, 240, reason: '框选之外的音符不应移动');
    expect(editor.noteCount, 3);
  });

  testWidgets('T3 画笔模式下拖动已选中音符会整组平移且不新建音符', (tester) async {
    final editor = await _pumpEditor(tester);

    await editor.drag(const Offset(440, 1080), const Offset(300, 160));
    await editor.useTool('画笔');
    await editor.drag(_gridPoint(1920, 60), const Offset(250, -36));

    expect(editor.note('a').startTick, 2880);
    expect(editor.note('a').pitch, 62);
    expect(editor.note('b').startTick, 3360);
    expect(editor.note('b').pitch, 66);
    expect(editor.noteCount, 3, reason: '画笔下拖动已选中音符不应新建音符');
  });

  testWidgets('T4a 画笔模式点击空白处仍按原逻辑新建音符', (tester) async {
    final editor = await _pumpEditor(tester);
    await editor.useTool('画笔');

    // (tick 2880, pitch 62) 处是空白：b 在 pitch 64 行、x<=720，不与本行重叠。
    await editor.tapContent(_gridPoint(2880, 62));

    expect(editor.noteCount, 4, reason: '画笔点空白应新建音符');
    final created = editor.config.notes.last;
    expect(created.startTick, 2880, reason: '新建时刻应对齐 1/16 吸附网格');
    expect(created.pitch, 62);
    expect(created.durationTicks, _snapTicks);
    expect(editor.note('a').startTick, 1920, reason: '新建不应移动已有音符');
    expect(editor.note('b').startTick, 2400);
  });

  testWidgets('T4b 画笔模式在未选中音符上拖动不会移动音符也不新建', (tester) async {
    final editor = await _pumpEditor(tester);
    await editor.useTool('画笔');

    await editor.drag(_gridPoint(2400, 64), const Offset(250, -36));

    expect(editor.note('b').startTick, 2400, reason: '画笔下拖动未选中音符不应移动它');
    expect(editor.note('b').pitch, 64);
    expect(editor.noteCount, 3, reason: '在已有音符上拖动不应新建音符');
  });

  testWidgets('T5a 向左拖过头时 startTick 夹取到 0', (tester) async {
    final editor = await _pumpEditor(tester);

    // c 起于 240 tick（x=60），左移 120px（-480 tick）会越过 0。
    await editor.drag(_gridPoint(240, 55), const Offset(-120, 0));

    expect(editor.note('c').startTick, 0, reason: '越界时刻应夹取到 0');
    expect(editor.note('c').pitch, 55, reason: '纯水平拖动不应改音高');
    expect(editor.note('c').durationTicks, 480);
  });

  testWidgets('T5b 向上拖过头时音高夹取到 127', (tester) async {
    final editor = await _pumpEditor(tester);

    await editor.drag(_gridPoint(240, 55), const Offset(0, -3000));

    expect(editor.note('c').pitch, 127, reason: '音高上界为 127');
    expect(editor.note('c').startTick, 240, reason: '纵向拖动不应改时刻');
    expect(editor.note('c').durationTicks, 480);
  });

  testWidgets('T5c 向下拖过头时音高夹取到 1', (tester) async {
    final editor = await _pumpEditor(tester);

    await editor.drag(_gridPoint(240, 55), const Offset(0, 3000));

    expect(editor.note('c').pitch, 1, reason: '音高下界为 1');
    expect(editor.note('c').startTick, 240);
    expect(editor.note('c').durationTicks, 480);
  });

  testWidgets('T5d 拖到其他主音符所在时段时本帧不动', (tester) async {
    final editor = await _pumpEditor(tester);

    // a(1920..2400) 右移 480 tick 后正好是 b(2400..2880)，与主音符重叠应被拒绝。
    await editor.drag(_gridPoint(1920, 60), const Offset(120, 0));

    expect(editor.note('a').startTick, 1920, reason: '与主音符重叠的位移应被拒绝');
    expect(editor.note('a').pitch, 60);
    expect(editor.note('b').startTick, 2400);
    expect(editor.noteCount, 3);
  });

  testWidgets('T6 一次拖动只产生一条撤销历史，撤销后回到原位', (tester) async {
    final editor = await _pumpEditor(tester);
    expect(_undoButton(tester).onPressed, isNull, reason: '初始不应有可撤销历史');

    await editor.drag(_gridPoint(1920, 60), const Offset(250, -36));
    expect(editor.note('a').startTick, 2880);
    expect(_undoButton(tester).onPressed, isNotNull);

    await tester.tap(find.byTooltip('撤销 Ctrl+Z'));
    await tester.pumpAndSettle();

    expect(editor.note('a').startTick, 1920, reason: '撤销应回到拖动前的位置');
    expect(editor.note('a').pitch, 60);
    expect(editor.note('a').durationTicks, 480);
    expect(_undoButton(tester).onPressed, isNull, reason: '一次拖动只应留下一条撤销历史');
  });

  testWidgets('T7 单选时按住右缘 10px 内仍是调时值，不改时刻与音高', (tester) async {
    final editor = await _pumpEditor(tester);

    // c 宽 120px，调时值命中区 = min(10, 120*0.25) = 10px；
    // 按住距右缘 5px 处（x=175）右拖 120px。
    await editor.drag(_rightEdgePoint(720, 55), const Offset(120, 0));

    expect(editor.note('c').durationTicks, 960, reason: '按住右缘拖动应改时长');
    expect(editor.note('c').startTick, 240, reason: '调时值不应移动时刻');
    expect(editor.note('c').pitch, 55, reason: '调时值不应改音高');
    expect(editor.note('a').startTick, 1920, reason: '调时值不应影响其他音符');
    expect(editor.note('b').startTick, 2400);
    expect(editor.noteCount, 3);
  });

  testWidgets('T8 多选时按住右缘仍是整组平移，时长不变', (tester) async {
    final editor = await _pumpEditor(tester);

    await editor.drag(const Offset(440, 1080), const Offset(300, 160));
    // 同一个右缘位置（距 a 右缘 5px），但选中数 >= 2：必须整组平移而不是调时值。
    await editor.drag(_rightEdgePoint(2400, 60), const Offset(250, -36));

    expect(editor.note('a').startTick, 2880);
    expect(editor.note('a').pitch, 62);
    expect(editor.note('a').durationTicks, 480, reason: '多选时右缘不应进入调时值');
    expect(editor.note('b').startTick, 3360);
    expect(editor.note('b').pitch, 66);
    expect(editor.note('b').durationTicks, 480);
    expect(editor.noteCount, 3);
  });

  testWidgets('T9 画笔模式下快速单步大位移拖动已选中音符仍整组平移', (tester) async {
    final editor = await _pumpEditor(tester);

    await editor.drag(const Offset(440, 1080), const Offset(300, 160));
    await editor.useTool('画笔');

    // 一次 moveBy 直接到位、没有唤醒步：验证“按下前已选中”的 Listener 快照，
    // 以及 dragStartBehavior.down 会把首个 pending delta 派发成一次 update。
    await editor.dragOnce(_gridPoint(1920, 60), const Offset(250, -36));

    expect(editor.note('a').startTick, 2880);
    expect(editor.note('a').pitch, 62);
    expect(editor.note('b').startTick, 3360);
    expect(editor.note('b').pitch, 66);
    expect(editor.noteCount, 3, reason: '画笔快速拖动不应新建音符');
  });

  testWidgets('T10 空拖动（未越过吸附阈值）不产生撤销历史', (tester) async {
    final editor = await _pumpEditor(tester);

    // 10px = 40 tick，吸附后位移为 0、音高也不变：整次拖动没有改动任何数据。
    await editor.drag(_gridPoint(1920, 60), const Offset(10, 0));

    expect(editor.note('a').startTick, 1920, reason: '吸附后位移为 0，音符不动');
    expect(editor.note('a').pitch, 60);
    expect(editor.note('a').durationTicks, 480);
    expect(
      _undoButton(tester).onPressed,
      isNull,
      reason: '空拖动不应写入一条“什么都没发生”的撤销记录',
    );
  });

  testWidgets('T11 短音符左半侧可以整体拖动，时长不变', (tester) async {
    final editor = await _pumpEditor(tester, document: _shortNoteDocument());

    // 60 tick 的音符只有 15px 宽（x 240..255）：调时值命中区 =
    // min(10, max(3, 15*0.25)) = 3.75px。按在 x=246（距右缘 9px）必须走平移；
    // 若是旧的固定 10px 命中区，这里会被误判成调时值。
    await editor.drag(_pressPoint(960, 67, 6), const Offset(120, -36));

    final short = editor.note('short');
    expect(short.startTick, 960 + 480, reason: '120px 位移应吸附到 480 tick');
    expect(short.pitch, 69);
    expect(short.durationTicks, 60, reason: '短音符左半侧拖动不应被当成调时值');
    expect(editor.note('far').startTick, 1920, reason: '其他音符不应移动');
    expect(editor.noteCount, 2);
  });
}
