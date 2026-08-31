import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pieblock_app/main.dart';
import 'package:pieblock_app/src/controller.dart';
import 'package:pieblock_app/src/deploy_controller.dart';
import 'package:pieblock_app/src/home_screen.dart';
import 'package:pieblock_app/src/music_editor.dart';
import 'package:pieblock_app/src/music_preview.dart';
import 'package:pieblock_app/src/wizard_screen.dart';
import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_toolchain/pieblock_toolchain.dart';
import 'package:re_editor/re_editor.dart';

class _FakeProjectFileDialogs extends ProjectFileDialogs {
  _FakeProjectFileDialogs({this.savePath});

  final String? savePath;
  int openCalls = 0;
  int saveCalls = 0;

  @override
  Future<String?> chooseProjectToOpen() async {
    openCalls += 1;
    return null;
  }

  @override
  Future<String?> chooseProjectSavePath({
    required String suggestedName,
    String? initialDirectory,
  }) async {
    saveCalls += 1;
    return savePath;
  }
}

class _InfantryStartController extends AppController {
  @override
  AppState build() => AppState(
    document: ProjectDocument.create('步兵测试', ProjectKind.infantry),
    saveStatus: SaveStatus.saved,
  );
}

class _PageTransitionController extends AppController {
  @override
  AppState build() => const AppState();

  void enterEditor() {
    state = AppState(
      document: ProjectDocument.create('动画测试', ProjectKind.infantry),
      saveStatus: SaveStatus.saved,
    );
  }

  void leaveEditor() => state = state.copyWith(clearProject: true);
}

class _InfantryControlsController extends AppController {
  @override
  AppState build() => AppState(
    document: _infantryDocument(),
    step: 2,
    maxVisitedStep: 2,
    saveStatus: SaveStatus.saved,
  );
}

class _ConfiguredMechanismController extends AppController {
  _ConfiguredMechanismController(this.document);
  final ProjectDocument document;

  @override
  AppState build() => AppState(
    document: document,
    step: 1,
    maxVisitedStep: 1,
    saveStatus: SaveStatus.saved,
  );
}

class _ConfiguredRemoteController extends AppController {
  _ConfiguredRemoteController(this.document);
  final ProjectDocument document;

  @override
  AppState build() =>
      AppState(document: document, saveStatus: SaveStatus.saved);
}

class _GeneratedCodeController extends AppController {
  @override
  AppState build() => AppState(
    document: _infantryDocument(),
    step: 4,
    maxVisitedStep: 4,
    saveStatus: SaveStatus.saved,
  );
}

class _StaticProjectController extends AppController {
  _StaticProjectController(this.document, this.step);

  final ProjectDocument document;
  final int step;

  @override
  AppState build() => AppState(
    document: document,
    step: step,
    maxVisitedStep: step,
    saveStatus: SaveStatus.saved,
  );
}

class _FakeDeployController extends DeployController {
  @override
  DeployState build() => DeployState(
    artifact: BuildArtifact(
      hexPath: 'firmware.hex',
      hexSha256: 'hex',
      fingerprint: 'fingerprint',
      sourceSha256: 'source',
      compiler: CompilerKind.sdcc,
      compilerFingerprint: 'sdcc-test',
      templateVersion: 'test',
      builtAt: DateTime(2026),
      byteCount: 1024,
      warningCount: 0,
    ),
  );

  @override
  Future<void> prepare(
    ProjectConfig config,
    CompilerKind compiler, {
    String? keilRoot,
  }) async {}

  @override
  Future<void> refreshDevices() async {}

  @override
  void cancelAll() {}
}

class _FakeMusicPreview implements MusicPreviewService {
  Completer<void>? playGate;
  int _request = 0;
  int? auditionPitch;
  final auditionedPitches = <int>[];
  int stopPitchCalls = 0;
  @override
  bool paused = false;
  @override
  bool playing = false;
  @override
  Duration position = Duration.zero;
  @override
  Future<void> dispose() async {}
  @override
  Future<void> play(MusicConfig config, {required bool looping}) async {
    final request = ++_request;
    await playGate?.future;
    if (request != _request) return;
    playing = true;
  }

  @override
  Future<void> stop() async {
    _request++;
    playing = false;
    position = Duration.zero;
    await stopPitch();
  }

  @override
  Future<void> startPitch(int midiPitch) async {
    auditionPitch = midiPitch;
    auditionedPitches.add(midiPitch);
  }

  @override
  Future<void> stopPitch() async {
    auditionPitch = null;
    stopPitchCalls++;
  }

  @override
  Future<void> togglePause() async {
    paused = !paused;
  }
}

ProjectDocument _infantryDocument() {
  final source = ProjectDocument.create('步兵测试', ProjectKind.infantry);
  return source.copyWith(
    config: InfantryConfig(
      remote: const RemoteConfig(channel: 36, deadzone: 100),
      chassis: const ChassisConfig(
        leftFront: WheelConfig('P74 P24', Direction.forward),
        leftRear: WheelConfig('P75 P25', Direction.forward),
        rightFront: WheelConfig('P76 P26', Direction.reverse),
        rightRear: WheelConfig('P77 P27', Direction.reverse),
        normalSpeed: 4000,
        sprintSpeed: 8000,
      ),
      feederPin: 'P60',
      feederDirection: Direction.forward,
      yawDrive: DriveType.servo,
      yawPin: 'MP74',
      yawDirection: Direction.forward,
      yawMidOffset: 0,
      pitchDrive: DriveType.servo,
      pitchPin: 'MP03',
      pitchDirection: Direction.forward,
      pitchMidOffset: 0,
      arrowBehavior: ArrowBehavior.other,
      feedMode: FeedMode.blockingOpenLoop,
      triggerKey: 'E',
      triggerSpeed: 6000,
      triggerTimeMs: 250,
      frictionMode: FrictionMode.brushlessEsc,
      frictionKey: 'A',
      frictionUpKey: 'B',
      frictionDownKey: 'C',
      frictionMaxDuty: 800,
      frictionStep: 100,
    ),
  );
}

ProjectDocument _infantryPinConflictDocument({bool shared = false}) {
  final source = _infantryDocument();
  final config = source.config as InfantryConfig;
  return source.copyWith(
    config: config.copyWith(
      frictionMode: FrictionMode.disabled,
      chassis: config.chassis.copyWith(
        leftFront: const WheelConfig('P62 P63', Direction.forward),
        leftRear: shared
            ? const WheelConfig('P62 P63', Direction.forward)
            : config.chassis.leftRear,
      ),
    ),
  );
}

InfantryConfig _currentInfantry(WidgetTester tester) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(WizardScreen)),
  );
  return container.read(appControllerProvider).document!.config
      as InfantryConfig;
}

ProjectDocument _engineerDocument() {
  final source = ProjectDocument.create('工程测试', ProjectKind.engineer);
  return source.copyWith(
    config: EngineerConfig(
      pwm: PwmGroupConfig(
        pwma: PwmFrequency.hz50,
        pwmb: PwmFrequency.hz10000,
        pinRoles: const {'P60': PinRole.motor},
      ),
      modeCount: 1,
      modes: [
        EngineerModeConfig(preserveChassis: true, actions: [ActionMapping()]),
      ],
    ),
  );
}

ProjectDocument _debugDocument() {
  final source = ProjectDocument.create('调试测试', ProjectKind.debug);
  return source.copyWith(
    config: DebugConfig(
      tests: [
        const DebugTestItem(
          pin: 'P64',
          enabled: true,
          driveType: DebugDriveType.friction,
          direction: Direction.forward,
          value: 750,
        ),
        for (final pin in debugPins.where((pin) => pin != 'P64'))
          DebugTestItem(pin: pin),
      ],
    ),
  );
}

ProjectDocument _musicDocument() {
  final source = ProjectDocument.create('音乐测试', ProjectKind.music);
  return source.copyWith(
    config: MusicConfig(
      sourceName: 'test.mid',
      trackName: 'Melody',
      notes: const [
        MusicNote(id: 'main', pitch: 60, startTick: 0, durationTicks: 480),
        MusicNote(
          id: 'reference',
          pitch: 67,
          startTick: 0,
          durationTicks: 480,
          primary: false,
        ),
        MusicNote(id: 'later', pitch: 64, startTick: 5760, durationTicks: 480),
      ],
    ),
  );
}

void main() {
  testWidgets('启动页展示两个项目入口', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PieBlockApp()));
    await tester.pumpAndSettle();
    expect(find.text('新建机器人项目'), findsOneWidget);
    expect(find.text('打开已有项目'), findsOneWidget);
    expect(find.textContaining('RoboMaster'), findsOneWidget);
    expect(find.bySemanticsLabel('首都师范大学'), findsOneWidget);
  });

  testWidgets('从启动页进入编辑页时播放横向揭示动画', (tester) async {
    late _PageTransitionController controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => controller = _PageTransitionController(),
          ),
        ],
        child: const PieBlockApp(),
      ),
    );
    await tester.pumpAndSettle();

    const backdropKey = ValueKey('home-page-transition-backdrop');
    const editorKey = ValueKey('editor-page-transition');
    controller.enterEditor();
    await tester.pump();
    expect(find.byKey(backdropKey), findsOneWidget);
    expect(find.byKey(editorKey), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(editorKey),
        matching: find.byType(SlideTransition),
      ),
      findsWidgets,
    );
    expect(
      find.ancestor(of: find.byKey(editorKey), matching: find.byType(ClipRect)),
      findsWidgets,
    );

    // 转场树中不再包含全屏淡入或首页缩放：在背景与编辑页到转场 Stack 的
    // 祖先链上不得出现 Opacity、FadeTransition 或 Transform 节点。
    final stackElement = tester.element(
      find
          .ancestor(of: find.byKey(backdropKey), matching: find.byType(Stack))
          .first,
    );
    bool hasFadeOrScale(Element start) {
      var result = false;
      start.visitAncestorElements((element) {
        if (identical(element, stackElement)) return false;
        final widget = element.widget;
        if (widget is Opacity ||
            widget is FadeTransition ||
            widget is Transform) {
          result = true;
          return false;
        }
        return true;
      });
      return result;
    }

    expect(
      hasFadeOrScale(tester.element(find.byKey(backdropKey))),
      isFalse,
      reason: '首页背景不应再有全屏淡入或缩放节点',
    );
    expect(
      hasFadeOrScale(tester.element(find.byKey(editorKey))),
      isFalse,
      reason: '编辑页不应再有全屏淡入节点',
    );

    // 编辑页从右侧约 2.5% 偏移滑入（测试窗口逻辑宽度 800）。
    final editorFinder = find.byKey(editorKey);
    expect(tester.getTopLeft(editorFinder).dx, closeTo(800 * .025, 0.5));
    // 先空泵一帧启动动画节拍，再推进到动画中段。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    final halfwayDx = tester.getTopLeft(editorFinder).dx;
    expect(halfwayDx, greaterThan(0));
    expect(halfwayDx, lessThan(800 * .025));

    // 动画进行中首页背景保持存在，结束后被卸载。
    expect(find.byKey(backdropKey), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(backdropKey), findsNothing);
    expect(find.text('动画测试'), findsOneWidget);
    expect(tester.getTopLeft(editorFinder).dx, 0);
  });

  testWidgets('动画中途返回首页不残留编辑页', (tester) async {
    late _PageTransitionController controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => controller = _PageTransitionController(),
          ),
        ],
        child: const PieBlockApp(),
      ),
    );
    await tester.pumpAndSettle();

    const backdropKey = ValueKey('home-page-transition-backdrop');
    const editorKey = ValueKey('editor-page-transition');
    controller.enterEditor();
    await tester.pump();
    expect(find.byKey(backdropKey), findsOneWidget);

    controller.leaveEditor();
    await tester.pump();
    expect(find.byKey(backdropKey), findsNothing);
    expect(find.byKey(editorKey), findsNothing);
    expect(find.text('新建机器人项目'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(editorKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('系统减少动态效果时直接展示编辑页', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    late _PageTransitionController controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => controller = _PageTransitionController(),
          ),
        ],
        child: const PieBlockApp(),
      ),
    );
    await tester.pumpAndSettle();

    controller.enterEditor();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('home-page-transition-backdrop')),
      findsNothing,
    );
    expect(find.text('动画测试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('首页和新建项目弹窗在 360 宽度下完整显示', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    await tester.pumpWidget(const ProviderScope(child: PieBlockApp()));
    await tester.pumpAndSettle();

    expect(find.text('新建机器人项目'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('新建项目'));
    await tester.pumpAndSettle();
    expect(find.text('浏览'), findsOneWidget);
    expect(find.text('调试'), findsOneWidget);
    expect(find.text('音乐'), findsOneWidget);
    expect(find.text('创建项目'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('调试向导展示可排序十路测试和动态摩擦轮字段', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _StaticProjectController(_debugDocument(), 0),
          ),
          deployControllerProvider.overrideWith(_FakeDeployController.new),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: const WizardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('调试测试序列'), findsOneWidget);
    expect(find.byIcon(Icons.drag_indicator), findsNWidgets(10));
    expect(find.text('目标值'), findsOneWidget);
    expect(find.text('测试时长'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('音乐向导展示原生钢琴卷帘和响应式编辑工具', (tester) async {
    final preview = _FakeMusicPreview();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _StaticProjectController(_musicDocument(), 0),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(body: MusicEditorPage(previewService: preview)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('导入 MIDI'), findsOneWidget);
    expect(find.text('导出 MIDI'), findsOneWidget);
    expect(find.text('画笔'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('播放'));
    await tester.pump();
    expect(preview.playing, isTrue);
    await tester.tap(find.byTooltip('停止'));
    await tester.pump();
    expect(preview.playing, isFalse);
  });

  testWidgets('音乐卷帘冻结表头琴键、显示滚动条并默认定位 C4', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 800);
    final preview = _FakeMusicPreview();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _StaticProjectController(_musicDocument(), 0),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: MusicEditorPage(previewService: preview)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollbar = tester.widget<Scrollbar>(
      find.byKey(const ValueKey('music-horizontal-scrollbar')),
    );
    expect(scrollbar.thumbVisibility, isTrue);
    expect(scrollbar.trackVisibility, isTrue);
    expect(find.text('逐页跟随'), findsOneWidget);

    final scrollables = tester.widgetList<Scrollable>(find.byType(Scrollable));
    final horizontal = scrollables.firstWhere(
      (scrollable) => scrollable.axisDirection == AxisDirection.right,
    );
    final vertical = scrollables.firstWhere(
      (scrollable) => scrollable.axisDirection == AxisDirection.down,
    );
    final horizontalState = tester.state<ScrollableState>(
      find.byWidget(horizontal),
    );
    final verticalState = tester.state<ScrollableState>(
      find.byWidget(vertical),
    );
    expect(verticalState.position.pixels, greaterThan(500));

    final header = find.byKey(const ValueKey('music-header-lane'));
    final piano = find.byKey(const ValueKey('music-piano-keys'));
    expect(find.byKey(const ValueKey('music-header-clip')), findsOneWidget);
    expect(find.byKey(const ValueKey('music-piano-clip')), findsOneWidget);
    final editorRect = tester.getRect(find.byType(MusicEditorPage));
    final toolbarRect = tester.getRect(
      find.byKey(const ValueKey('music-toolbar-panel')),
    );
    expect(toolbarRect.left, editorRect.left);
    expect(toolbarRect.right, editorRect.right);
    final headerOrigin = tester.getTopLeft(header);
    final pianoOrigin = tester.getTopLeft(piano);
    horizontalState.position.jumpTo(horizontalState.position.maxScrollExtent);
    verticalState.position.jumpTo(verticalState.position.pixels + 100);
    await tester.pump();
    expect(tester.getTopLeft(header), headerOrigin);
    expect(tester.getTopLeft(piano), pianoOrigin);
  });

  testWidgets('音乐卷帘在 360 宽度下保持冻结区域和跟随控件可用', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _StaticProjectController(_musicDocument(), 0),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: MusicEditorPage(previewService: _FakeMusicPreview()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('music-header-lane')), findsOneWidget);
    expect(find.byKey(const ValueKey('music-piano-keys')), findsOneWidget);
    expect(find.text('导入 MIDI'), findsNothing);
    expect(find.text('导出 MIDI'), findsNothing);
    expect(find.text('画笔'), findsNothing);
    expect(find.text('循环预览'), findsNothing);
    expect(find.text('固定视窗'), findsNothing);
    expect(find.text('逐页跟随'), findsNothing);
    expect(find.text('固定跟随'), findsNothing);
    expect(find.byTooltip('导入 MIDI'), findsOneWidget);
    expect(find.byTooltip('导出 MIDI'), findsOneWidget);
    expect(find.byTooltip('画笔'), findsOneWidget);
    expect(find.byTooltip('循环预览'), findsOneWidget);
    expect(find.byTooltip('固定视窗'), findsOneWidget);
    expect(find.byTooltip('速度事件（1）'), findsOneWidget);
    expect(find.byTooltip('拍号事件（1）'), findsOneWidget);
    await tester.tap(find.byTooltip('画笔'));
    await tester.tap(find.byTooltip('固定视窗'));
    await tester.tap(find.byTooltip('速度事件（1）'));
    await tester.pumpAndSettle();
    expect(find.text('添加速度事件'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('音乐工具栏按完整宽度 599 和 600 切换图标模式', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;

    Future<void> pumpAt(double width) async {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appControllerProvider.overrideWith(
              () => _StaticProjectController(_musicDocument(), 0),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: MusicEditorPage(previewService: _FakeMusicPreview()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpAt(599);
    expect(
      tester.getSize(find.byKey(const ValueKey('music-toolbar-panel'))).width,
      599,
    );
    expect(find.text('导入 MIDI'), findsNothing);
    expect(find.byTooltip('导入 MIDI'), findsOneWidget);

    await pumpAt(600);
    expect(
      tester.getSize(find.byKey(const ValueKey('music-toolbar-panel'))).width,
      600,
    );
    expect(find.text('导入 MIDI'), findsOneWidget);
    expect(find.text('固定跟随'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('宽屏向导裁剪音乐事件栏并将工具栏扩展到钢琴上方', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 800);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _StaticProjectController(_musicDocument(), 0),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                const SizedBox(width: 260),
                Expanded(
                  child: MusicEditorPage(previewService: _FakeMusicPreview()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editorRect = tester.getRect(find.byType(MusicEditorPage));
    final pianoRect = tester.getRect(
      find.byKey(const ValueKey('music-piano-keys')),
    );
    final headerClipRect = tester.getRect(
      find.byKey(const ValueKey('music-header-clip')),
    );
    final toolbarRect = tester.getRect(
      find.byKey(const ValueKey('music-toolbar-panel')),
    );
    expect(editorRect.left, 260);
    expect(headerClipRect.left, pianoRect.right);
    expect(toolbarRect.left, editorRect.left);
    expect(toolbarRect.right, editorRect.right);

    final horizontal = tester
        .widgetList<Scrollable>(find.byType(Scrollable))
        .firstWhere(
          (scrollable) => scrollable.axisDirection == AxisDirection.right,
        );
    final horizontalState = tester.state<ScrollableState>(
      find.byWidget(horizontal),
    );
    horizontalState.position.jumpTo(horizontalState.position.maxScrollExtent);
    await tester.pump();
    expect(
      tester.getRect(find.byKey(const ValueKey('music-header-clip'))),
      headerClipRect,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('钢琴按住发声、滑动换音并在松开时停止', (tester) async {
    final preview = _FakeMusicPreview();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _StaticProjectController(_musicDocument(), 0),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: MusicEditorPage(previewService: preview)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pianoRect = tester.getRect(
      find.byKey(const ValueKey('music-piano-keys')),
    );
    final gesture = await tester.startGesture(pianoRect.center);
    await tester.pump();
    expect(preview.auditionedPitches.last, 60);
    await gesture.moveBy(const Offset(0, -18));
    await tester.pump();
    expect(preview.auditionedPitches.last, 61);
    await gesture.up();
    await tester.pump();
    expect(preview.auditionPitch, isNull);
    expect(preview.stopPitchCalls, greaterThan(0));
  });

  testWidgets('加载中停止会作废播放请求', (tester) async {
    final preview = _FakeMusicPreview()..playGate = Completer<void>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _StaticProjectController(_musicDocument(), 0),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: MusicEditorPage(previewService: preview)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('播放'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byTooltip('停止'));
    await tester.pump();
    preview.playGate!.complete();
    await tester.pumpAndSettle();
    expect(preview.playing, isFalse);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('播放视窗支持固定、逐页和当前播放头锚定跟随', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 800);
    final preview = _FakeMusicPreview();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _StaticProjectController(_musicDocument(), 0),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: MusicEditorPage(previewService: preview)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final horizontal = tester
        .widgetList<Scrollable>(find.byType(Scrollable))
        .firstWhere(
          (scrollable) => scrollable.axisDirection == AxisDirection.right,
        );
    final horizontalState = tester.state<ScrollableState>(
      find.byWidget(horizontal),
    );

    await tester.tap(find.byTooltip('播放'));
    await tester.pump();
    preview.position = const Duration(seconds: 5);
    await tester.pump(const Duration(milliseconds: 60));
    expect(horizontalState.position.pixels, greaterThan(0));

    await tester.tap(find.text('固定视窗'));
    await tester.pump();
    horizontalState.position.jumpTo(0);
    preview.position = const Duration(seconds: 6);
    await tester.pump(const Duration(milliseconds: 60));
    expect(horizontalState.position.pixels, 0);

    await tester.tap(find.text('固定跟随'));
    await tester.pump();
    final viewportCenter = horizontalState.position.viewportDimension / 2;
    final playheadAtSixSeconds = 12 * 120.0;
    expect(
      playheadAtSixSeconds - horizontalState.position.pixels,
      closeTo(viewportCenter, 1),
    );
    preview.position = const Duration(milliseconds: 5500);
    await tester.pump(const Duration(milliseconds: 60));
    final playheadAtFiveAndHalfSeconds = 11 * 120.0;
    expect(
      playheadAtFiveAndHalfSeconds - horizontalState.position.pixels,
      closeTo(viewportCenter, 1),
    );
    await tester.tap(find.byTooltip('停止'));
    await tester.pump();
  });

  testWidgets('新建项目可浏览保存位置', (tester) async {
    final dialogs = _FakeProjectFileDialogs(
      savePath: r'C:\projects\机器人.pieproj',
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: HomeScreen(fileDialogs: dialogs)),
      ),
    );

    await tester.tap(find.text('新建项目'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('浏览'));
    await tester.pumpAndSettle();

    expect(dialogs.saveCalls, 1);
    expect(find.text(r'C:\projects\机器人.pieproj'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('打开项目直接调用文件浏览器', (tester) async {
    final dialogs = _FakeProjectFileDialogs();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: HomeScreen(fileDialogs: dialogs)),
      ),
    );

    await tester.tap(find.text('打开项目'));
    await tester.pumpAndSettle();

    expect(dialogs.openCalls, 1);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('步兵向导含编译烧录步骤且配置页不显示主题按钮', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(_InfantryStartController.new),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 / 6'), findsOneWidget);
    expect(find.text('PWM 与引脚'), findsNothing);
    expect(find.byTooltip('切换主题'), findsNothing);
  });

  testWidgets('非宽屏向导统一使用步骤下拉栏', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    for (final width in const [360.0, 600.0, 1099.0]) {
      tester.view.physicalSize = Size(width, 700);
      await tester.pumpWidget(
        ProviderScope(
          key: ValueKey(width),
          overrides: [
            appControllerProvider.overrideWith(_InfantryStartController.new),
          ],
          child: const MaterialApp(home: WizardScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
      expect(find.text('当前步骤 · 1 / 6'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('空白配置先不报错，点击下一步后显示未填项', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(_InfantryStartController.new),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('尚未填写'), findsNothing);
    expect(find.textContaining('尚未选择'), findsNothing);
    expect(find.textContaining('本页有'), findsNothing);

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.textContaining('尚未填写'), findsWidgets);
    expect(find.textContaining('尚未选择'), findsWidgets);
    expect(find.text('1 / 6'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1500));
  });

  testWidgets('已选配置产生冲突时立即报错', (tester) async {
    final source = _infantryDocument();
    final config = source.config as InfantryConfig;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _ConfiguredRemoteController(
              source.copyWith(
                config: config.copyWith(
                  chassis: config.chassis.copyWith(
                    rightFront: const WheelConfig('P74 P24', Direction.reverse),
                  ),
                ),
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('不能跨侧共用同一 IO'), findsWidgets);
  });

  testWidgets('错误显示在字段和问题栏并阻止下一步', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(_InfantryStartController.new),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '126');
    await tester.pumpAndSettle();
    expect(find.text('遥控器通道号必须在 0–125 之间'), findsWidgets);

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 6'), findsOneWidget);
    expect(find.textContaining('请修正标红的配置'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1500));
  });

  testWidgets('所有数值输入框可连续输入且不会丢失焦点', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(_InfantryStartController.new),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> enterOneCharacterAtATime(Finder field, String text) async {
      await tester.ensureVisible(field);
      await tester.tap(field);
      for (var length = 1; length <= text.length; length += 1) {
        tester.testTextInput.enterText(text.substring(0, length));
        await tester.pump();
        expect(tester.testTextInput.isVisible, isTrue);
        expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);
      }
      expect(find.descendant(of: field, matching: find.text(text)), findsOne);
    }

    await enterOneCharacterAtATime(
      find.byKey(const ValueKey('remote.channel')),
      '36',
    );
    await enterOneCharacterAtATime(
      find.byKey(const ValueKey('remote.deadzone')),
      '100',
    );
    await enterOneCharacterAtATime(
      find.byKey(const ValueKey('chassis.normal_speed')),
      '4000',
    );
    await enterOneCharacterAtATime(
      find.byKey(const ValueKey('chassis.sprint_speed')),
      '8000',
    );
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('步兵控制键只有数字按键并包含 LC RC', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(_InfantryControlsController.new),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('高级设置'), findsOneWidget);
    expect(find.text('禁用蜂鸣器反馈'), findsOneWidget);
    final trigger = find.byType(DropdownButtonFormField<String>).first;
    await tester.ensureVisible(trigger);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(find.text('LC'), findsOneWidget);
    expect(find.text('RC'), findsOneWidget);
    expect(find.text('LX'), findsNothing);
    expect(find.text('LY'), findsNothing);

    final maxDutyTop = tester.getTopLeft(find.text('最大占空比')).dy;
    final stepTop = tester.getTopLeft(find.text('每次调速步长')).dy;
    expect((maxDutyTop - stepTop).abs(), lessThan(1));
  });

  testWidgets('摩擦轮禁用后拨弹引脚菜单释放 P64/P66', (tester) async {
    final source = _infantryDocument();
    final config = source.config as InfantryConfig;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _ConfiguredMechanismController(
              source.copyWith(
                config: config.copyWith(frictionMode: FrictionMode.disabled),
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final feeder = find.byType(DropdownButtonFormField<String>).first;
    await tester.ensureVisible(feeder);
    await tester.tap(feeder);
    await tester.pumpAndSettle();
    expect(find.text('P64'), findsOneWidget);
    expect(find.text('P66'), findsOneWidget);
  });

  testWidgets('被摩擦轮占用的 IO 可选择并显式关闭摩擦轮', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _ConfiguredMechanismController(_infantryDocument()),
          ),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final feeder = find.byType(DropdownButtonFormField<String>).first;
    await tester.ensureVisible(feeder);
    await tester.tap(feeder);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.lock_outline), findsNothing);
    expect(find.textContaining('摩擦轮（固定）占用'), findsWidgets);

    await tester.tap(find.textContaining('P64 · 摩擦轮（固定）占用').last);
    await tester.pumpAndSettle();
    expect(find.text('P64 已被占用'), findsOneWidget);
    expect(find.text('关闭摩擦轮并占用'), findsOneWidget);
    await tester.tap(find.text('关闭摩擦轮并占用'));
    await tester.pumpAndSettle();

    final config = _currentInfantry(tester);
    expect(config.feederPin, 'P64');
    expect(config.frictionMode, FrictionMode.disabled);
    expect(config.frictionMaxDuty, 800);
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('占用引脚可交换、抢占或取消', (tester) async {
    Future<void> pumpConflict() async {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            appControllerProvider.overrideWith(
              () => _ConfiguredMechanismController(
                _infantryPinConflictDocument(),
              ),
            ),
          ],
          child: const MaterialApp(home: WizardScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> chooseOccupiedP62() async {
      final feeder = find.byKey(const ValueKey('mechanism.feeder_pin'));
      await tester.ensureVisible(feeder);
      await tester.tap(feeder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('P62 · 左前轮占用').last);
      await tester.pumpAndSettle();
      expect(find.text('P62 已被占用'), findsOneWidget);
    }

    await pumpConflict();
    await chooseOccupiedP62();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(_currentInfantry(tester).feederPin, 'P60');

    await chooseOccupiedP62();
    await tester.tap(find.text('交换引脚'));
    await tester.pumpAndSettle();
    var config = _currentInfantry(tester);
    expect(config.feederPin, 'P62');
    expect(config.chassis.leftFront.pin, 'P60 P61');
    await tester.pump(const Duration(milliseconds: 600));

    await pumpConflict();
    await chooseOccupiedP62();
    await tester.tap(find.text('占用并解除原分配'));
    await tester.pumpAndSettle();
    config = _currentInfantry(tester);
    expect(config.feederPin, 'P62');
    expect(config.chassis.leftFront.pin, isNull);
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('步兵引脚可明确设为未分配', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _ConfiguredMechanismController(_infantryDocument()),
          ),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final feeder = find.byKey(const ValueKey('mechanism.feeder_pin'));
    await tester.ensureVisible(feeder);
    await tester.tap(feeder);
    await tester.pumpAndSettle();
    await tester.tap(find.text('未分配').last);
    await tester.pumpAndSettle();

    expect(_currentInfantry(tester).feederPin, isNull);
    expect(
      find.descendant(of: feeder, matching: find.text('未分配')),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('启用摩擦轮前确认解除 P64/P66 占用', (tester) async {
    final source = _infantryDocument();
    final config = source.config as InfantryConfig;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _StaticProjectController(
              source.copyWith(
                config: config.copyWith(
                  frictionMode: FrictionMode.disabled,
                  feederPin: 'P64',
                ),
              ),
              2,
            ),
          ),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final friction = find.byKey(const ValueKey('controls.friction_mode'));
    await tester.ensureVisible(friction);
    await tester.tap(friction);
    await tester.pumpAndSettle();
    await tester.tap(find.text('无刷电调').last);
    await tester.pumpAndSettle();
    expect(find.text('P64/P66 已被占用'), findsOneWidget);
    expect(find.textContaining('拨弹电机'), findsOneWidget);
    await tester.tap(find.text('解除占用并启用'));
    await tester.pumpAndSettle();

    final result = _currentInfantry(tester);
    expect(result.frictionMode, FrictionMode.brushlessEsc);
    expect(result.feederPin, isNull);
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('紧凑布局显示共享占用组并可完成交换', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _ConfiguredMechanismController(
              _infantryPinConflictDocument(shared: true),
            ),
          ),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final feeder = find.byKey(const ValueKey('mechanism.feeder_pin'));
    await tester.ensureVisible(feeder);
    await tester.tap(feeder);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('P62 · 左前轮、左后轮占用').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('左前轮、左后轮'), findsOneWidget);
    await tester.tap(find.text('交换引脚'));
    await tester.pumpAndSettle();

    final result = _currentInfantry(tester);
    expect(result.feederPin, 'P62');
    expect(result.chassis.leftFront.pin, 'P60 P61');
    expect(result.chassis.leftRear.pin, 'P60 P61');
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('拨弹与摩擦轮条件字段按模式显隐', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(_InfantryControlsController.new),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('单发时长'), findsOneWidget);
    expect(find.text('最大占空比'), findsOneWidget);

    await tester.tap(find.text('阻塞开环单发'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('目视闭环连续拨弹').last);
    await tester.pumpAndSettle();
    expect(find.text('单发时长'), findsNothing);

    await tester.ensureVisible(find.text('无刷电调'));
    await tester.tap(find.text('无刷电调'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不使用').last);
    await tester.pumpAndSettle();
    expect(find.text('最大占空比'), findsNothing);
    expect(find.text('每次调速步长'), findsNothing);
  });

  testWidgets('IDE 代码预览支持 C 高亮、行号和跨行选择', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
        }
        if (call.method == 'Clipboard.getData') {
          return <String, Object?>{'text': clipboardText};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(_GeneratedCodeController.new),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final editorFinder = find.byKey(const ValueKey('generated-code-editor'));
    final editor = tester.widget<CodeEditor>(editorFinder);
    expect(editor.readOnly, isTrue);
    expect(editor.wordWrap, isFalse);
    expect(editor.chunkAnalyzer, isA<NonCodeChunkAnalyzer>());
    expect(
      find.byKey(const ValueKey('generated-code-line-numbers')),
      findsOneWidget,
    );

    final syntax = editor.style!.codeTheme!;
    expect(syntax.languages, contains('c'));
    expect(syntax.theme['keyword'], isNot(syntax.theme['string']));
    expect(syntax.theme['comment'], isNot(syntax.theme['number']));
    expect(syntax.theme, contains('meta'));

    final controller = editor.controller!;
    final originalCode = controller.text;
    controller.selection = const CodeLineSelection(
      baseIndex: 0,
      baseOffset: 0,
      extentIndex: 2,
      extentOffset: 4,
    );
    expect(controller.selectedText.split('\n'), hasLength(3));
    expect(controller.selectedText, isNot(contains('   1  ')));

    await tester.ensureVisible(editorFinder);
    await tester.pumpAndSettle();
    editor.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(clipboardText, controller.selectedText);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(clipboardText, originalCode);

    clipboardText = '不应写入的内容';
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(controller.text, originalCode);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('代码搜索显示匹配计数并支持 Ctrl+F', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(_GeneratedCodeController.new),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final search = find.byKey(const ValueKey('code-search-field'));
    await tester.enterText(search, 'void');
    await tester.pump();
    final count = tester.widget<Text>(
      find.byKey(const ValueKey('code-search-count')),
    );
    expect(count.data, matches(RegExp(r'\d+ / [1-9]\d*')));
    expect(find.byTooltip('上一个匹配'), findsOneWidget);
    expect(find.byTooltip('下一个匹配'), findsOneWidget);

    final editor = find.byKey(const ValueKey('generated-code-editor'));
    await tester.ensureVisible(editor);
    await tester.pumpAndSettle();
    tester.widget<CodeEditor>(editor).focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('代码预览在响应式尺寸和双主题下无布局异常', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    for (final size in const [
      Size(1600, 900),
      Size(1100, 700),
      Size(600, 800),
      Size(412, 915),
      Size(360, 640),
    ]) {
      for (final brightness in Brightness.values) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appControllerProvider.overrideWith(_GeneratedCodeController.new),
            ],
            child: MaterialApp(
              theme: ThemeData(brightness: brightness, useMaterial3: true),
              home: const WizardScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CodeEditor), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    }
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('向导在响应式尺寸和双主题下无布局异常', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    for (final size in const [
      Size(1600, 900),
      Size(1100, 700),
      Size(600, 800),
      Size(412, 915),
      Size(360, 640),
    ]) {
      for (final brightness in Brightness.values) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appControllerProvider.overrideWith(
                _InfantryControlsController.new,
              ),
            ],
            child: MaterialApp(
              theme: ThemeData(brightness: brightness, useMaterial3: true),
              home: const WizardScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('窄屏覆盖工程 PWM、动作映射、检查和烧录页面', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    final engineer = _engineerDocument();
    final infantry = _infantryDocument();
    final pages = [
      (engineer, 1, 'PWM 与引脚角色'),
      (engineer, 3, '动作映射'),
      (infantry, 3, '检查与配置摘要'),
      (infantry, 5, '编译与烧录'),
    ];

    for (final brightness in Brightness.values) {
      for (final page in pages) {
        await tester.pumpWidget(
          ProviderScope(
            key: ValueKey('${brightness.name}-${page.$2}-${page.$3}'),
            overrides: [
              appControllerProvider.overrideWith(
                () => _StaticProjectController(page.$1, page.$2),
              ),
              deployControllerProvider.overrideWith(_FakeDeployController.new),
            ],
            child: MaterialApp(
              theme: ThemeData(brightness: brightness, useMaterial3: true),
              home: const WizardScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(page.$3), findsWidgets);
        expect(find.byType(DropdownButtonFormField<int>), findsWidgets);
        expect(tester.takeException(), isNull);
        if (page.$3 == '编译与烧录') {
          final flash = find.text('烧录当前固件');
          await tester.ensureVisible(flash);
          await tester.tap(flash);
          await tester.pumpAndSettle();
          expect(find.text('烧录主控板前请确认'), findsOneWidget);
          expect(find.byType(Image), findsNWidgets(2));
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
        }
      }
    }
  });
}
