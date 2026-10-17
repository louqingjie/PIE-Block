import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pieblock_app/main.dart';
import 'package:pieblock_app/src/asm_preview_controller.dart';
import 'package:pieblock_app/src/controller.dart';
import 'package:pieblock_app/src/debug_cue_preview.dart';
import 'package:pieblock_app/src/deploy_controller.dart';
import 'package:pieblock_app/src/home_screen.dart';
import 'package:pieblock_app/src/platform/document_io.dart';
import 'package:pieblock_app/src/platform/file_export.dart';
import 'package:pieblock_app/src/platform/udev_rule.dart';
import 'package:pieblock_app/src/music_editor.dart';
import 'package:pieblock_app/src/music_preview.dart';
import 'package:pieblock_app/src/project_templates.dart';
import 'package:pieblock_app/src/recent_project.dart';
import 'package:pieblock_app/src/udev_rule_controller.dart';
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
  Future<SelectedDocument?> chooseProjectToOpen() async {
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

/// 有界推进若干帧。导出对话框里输入框等控件会持续调度帧，`pumpAndSettle`
/// 可能一直等不到「完全静止」；这里固定推进这么多帧，足够弹窗动画与
/// 异步写盘完成，又不会把测试拖到超时。
Future<void> _pumpFrames(WidgetTester tester, {int frames = 12}) async {
  for (var index = 0; index < frames; index += 1) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// 导出对话框的假文档层：只记录调用，按需返回路径或抛错，避免测试真的写盘。
class _FakeExportDocumentIo extends AppDocumentIo {
  _FakeExportDocumentIo({this.savePath, this.error});

  final String? savePath;
  final Object? error;
  int createCalls = 0;
  String? lastSuggestedName;
  Uint8List? lastBytes;
  List<String> lastExtensions = const [];
  String? lastWritePath;
  Uint8List? lastWriteBytes;

  @override
  Future<void> write(String reference, Uint8List bytes) async {
    lastWritePath = reference;
    lastWriteBytes = bytes;
  }

  @override
  Future<String?> create({
    required String suggestedName,
    required String mimeType,
    Uint8List? bytes,
    String? initialDirectory,
    List<String> extensions = const [],
  }) async {
    createCalls += 1;
    lastSuggestedName = suggestedName;
    lastBytes = bytes;
    lastExtensions = extensions;
    final failure = error;
    if (failure != null) throw failure;
    return savePath;
  }
}

/// 记录 createProject 收到的参数，避免测试真的写盘。
class _CapturingCreateController extends AppController {
  ProjectConfig? template;
  ProjectKind? kind;
  int createCalls = 0;

  @override
  AppState build() => const AppState();

  @override
  Future<bool> createProject(
    String path,
    String name,
    ProjectKind kind, {
    ProjectConfig? template,
  }) async {
    createCalls += 1;
    this.kind = kind;
    this.template = template;
    return true;
  }
}

class _InfantryStartController extends AppController {  @override
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
  _GeneratedCodeController({ProjectDocument? document})
    : document = document ?? _infantryDocument();

  final ProjectDocument document;

  @override
  AppState build() {
    final step = codeStep(document.kind);
    return AppState(
      document: document,
      step: step,
      maxVisitedStep: step,
      saveStatus: SaveStatus.saved,
    );
  }
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

/// 首页「最近项目」的静态夹具：每条记录携带项目类型，最后一条模拟类型
/// 未知的旧数据（补读失败），应退回通用文档图标。
class _RecentProjectsController extends AppController {
  @override
  AppState build() => const AppState(
    recentProjects: [
      RecentProject(path: r'C:\projects\1.pieproj', kind: ProjectKind.infantry),
      RecentProject(
        path: r'C:\projects\engineer.pieproj',
        kind: ProjectKind.engineer,
      ),
      RecentProject(
        path: r'C:\projects\debug.pieproj',
        kind: ProjectKind.debug,
      ),
      RecentProject(
        path: r'C:\projects\music.pieproj',
        kind: ProjectKind.music,
      ),
      RecentProject(path: r'C:\projects\unknown.pieproj'),
    ],
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

/// 链接后列表文件（`main.rst`）的固定样例：前 40 列是地址 / 机器码 / 周期 /
/// 行号，之后才是汇编正文或 C 锚点。用它可以断言不改动前缀列。
const _rstSample = '''
                                      1 ;--------------------------------------------------------
                                      5 \t.module main
      FE008C 7E 71 82         [12]  158 \tmov\tr7, dpl
                                    200 ;\tC:\\tmp\\main.c:66: PWM_SET_Frequency(BUZZER_CH, frequency, BUZZER_DUTY_ON);
      FF0007 9A FE 08 5F      [12]  131 \tecall\t_main
''';

AsmPreviewState _readyAsmState(String code) =>
    AsmPreviewState(
      activity: AsmPreviewActivity.ready,
      sourceCode: code,
      listing: _rstSample,
    );

/// 记录调用次数的假控制器：用来断言「进页面不编译、只有点汇编才编译」。
class _FakeAsmPreviewController extends AsmPreviewController {
  _FakeAsmPreviewController(this.initial, {this.listing = _rstSample});

  final AsmPreviewState initial;

  /// compile / recompile 之后进入的「已就绪」内容。
  final String? listing;
  int compileCount = 0;
  int recompileCount = 0;

  @override
  AsmPreviewState build() => initial;

  @override
  Future<void> compile(ProjectConfig config) async {
    compileCount += 1;
    final value = listing;
    if (value == null) return;
    state = AsmPreviewState(
      activity: AsmPreviewActivity.ready,
      sourceCode: CodeGenerator.generate(config),
      listing: value,
    );
  }

  @override
  Future<void> recompile(ProjectConfig config) async {
    recompileCount += 1;
  }
}

class _FakeUdevRuleController extends UdevRuleController {
  _FakeUdevRuleController({required this.installed});

  bool installed;

  @override
  UdevRuleState build() => UdevRuleState(installed: installed);

  @override
  void refresh() {}

  @override
  Future<UdevInstallResult> install() async {
    installed = true;
    const result = UdevInstallResult(UdevInstallOutcome.success);
    state = const UdevRuleState(installed: true, lastResult: result);
    return result;
  }
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

class _FakeDebugCuePreview implements DebugCuePreviewService {
  final played = <List<DebugCueNote>>[];
  int stopCalls = 0;
  int disposeCalls = 0;

  @override
  Future<void> play(List<DebugCueNote> notes) async {
    played.add(notes);
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
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
      yawActuators: const [
        AxisActuator(
          drive: DriveType.servo,
          pin: 'MP74',
          direction: Direction.forward,
          midOffset: 0,
        ),
      ],
      pitchActuators: const [
        AxisActuator(
          drive: DriveType.servo,
          pin: 'MP03',
          direction: Direction.forward,
          midOffset: 0,
        ),
      ],
      arrowBehavior: ArrowBehavior.other,
      feedMode: FeedMode.blockingOpenLoop,
      triggerKey: 'E',
      triggerSpeed: 6000,
      triggerTimeMs: 250,
      frictionMode: FrictionMode.brushlessEsc,
      frictionKey: 'A',
      frictionUpKey: 'B',
      frictionDownKey: 'C',
      frictionP64MaxDuty: 800,
      frictionP66MaxDuty: 700,
      frictionLevelStep: 10,
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

ProjectDocument _engineerServoButtonDocument() {
  final source = _engineerDocument();
  final config = source.config as EngineerConfig;
  return source.copyWith(
    config: config.copyWith(
      pwm: config.pwm.copyWith(
        pinRoles: const {'P60': PinRole.servo, 'P62': PinRole.motor},
        servoMids: const {'P60': 0, 'MP03': 0, 'MP74': 0},
      ),
      modes: [
        EngineerModeConfig(
          preserveChassis: true,
          actions: [
            ActionMapping(
              key: 'A',
              direction: Direction.forward,
              mode: ControlMode.direct,
              parameter: 30,
              pin: 'P60',
            ),
            ActionMapping(
              key: 'RX',
              direction: Direction.forward,
              mode: ControlMode.direct,
              parameter: 30,
              pin: 'MP03',
            ),
            ActionMapping(
              key: 'B',
              direction: Direction.forward,
              mode: ControlMode.direct,
              parameter: 4000,
              pin: 'P62',
            ),
          ],
        ),
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
          value: 800,
        ),
        const DebugTestItem(
          pin: 'P66',
          enabled: true,
          driveType: DebugDriveType.friction,
          direction: Direction.forward,
          value: 700,
        ),
        for (final pin in debugPins.where(
          (pin) => pin != 'P64' && pin != 'P66',
        ))
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
    expect(find.text('模板工程'), findsOneWidget);
    expect(find.text('创建项目'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('首页隐藏桌面自动滚动条且保持可滚动', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 400);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const scrollKey = ValueKey('home-scroll-view');
    final scrollView = find.byKey(scrollKey);
    final scrollable = find.descendant(
      of: scrollView,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    expect(find.byType(Scrollbar), findsNothing);

    await tester.drag(scrollView, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('调试向导展示可排序十路测试和动态摩擦轮字段', (tester) async {
    // 试听面板默认用 flutter_soloud，测试里没有原生动态库，必须注入假实现。
    final preview = _FakeDebugCuePreview();
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
          home: WizardScreen(debugCuePreview: preview),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('调试测试序列'), findsOneWidget);
    expect(find.byIcon(Icons.drag_indicator), findsNWidgets(10));
    // 摩擦轮项直接填目标占空比；页面上不再有独立的 P64/P66 满油上限字段。
    expect(find.text('最大占空比'), findsNWidgets(2));
    expect(find.text('油门'), findsNothing);
    expect(find.text('P64 最大占空比'), findsNothing);
    expect(find.text('P66 最大占空比'), findsNothing);
    expect(find.text('测试时长'), findsNothing);
    expect(tester.takeException(), isNull);

    // 页面顶部原有的三条说明 banner 已删除，不再出现这些文案。
    expect(find.textContaining('机械装车前请先完成舵机归中'), findsNothing);
    expect(find.textContaining('每项提示是一句'), findsNothing);
    expect(find.textContaining('至少有一项摩擦轮测试'), findsNothing);

    // 收尾旋律与它的「全部完成」按钮已移除，也没有风格开关；逐项试听按钮保留。
    expect(find.widgetWithText(OutlinedButton, '全部完成'), findsNothing);
    expect(find.text('标准'), findsNothing);
    expect(find.text('紧凑'), findsNothing);

    // 「第 1 项」把整条曲线交给试听实现，再点一次是停止播放。
    final stepButton = find.widgetWithText(OutlinedButton, '第 1 项');
    await tester.ensureVisible(stepButton);
    await tester.pumpAndSettle();
    await tester.tap(stepButton);
    await tester.pump();
    expect(preview.played, hasLength(1));
    // DebugCueNote 没有值相等语义，按「音高 + 时值」逐段比对同一条曲线。
    List<(int?, int)> curve(List<DebugCueNote> notes) => [
      for (final note in notes) (note.frequencyHz, note.durationMs),
    ];
    final played = preview.played.single;
    expect(curve(played), curve(DebugCues.step(1)));

    await tester.tap(stepButton);
    await tester.pump();
    expect(preview.stopCalls, 1);

    // 等按钮复位的计时器跑完，再离场：退出调试页时释放试听实现。
    await tester.pump(
      Duration(milliseconds: DebugCues.durationMs(played) + 200),
    );
    await tester.pumpWidget(const SizedBox());
    expect(preview.disposeCalls, 1);
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
    // 断言的是桌面行为（把完整路径写回输入框），需固定平台；
    // 否则 flutter_test 默认平台为 Android，会走文档选择器分支。
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
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
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('新建项目时项目名称与文件名双向同步', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final dialogs = _FakeProjectFileDialogs(
      savePath: r'C:\projects\射手.pieproj',
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: HomeScreen(fileDialogs: dialogs)),
      ),
    );
    await tester.tap(find.text('新建项目'));
    await tester.pumpAndSettle();

    final nameField = find.byType(TextField).at(0);
    final pathField = find.byType(TextField).at(1);

    // 改保存位置里的文件名，项目名称跟着变。
    await tester.enterText(pathField, r'C:\projects\old.pieproj');
    await tester.pump();
    expect(tester.widget<TextField>(nameField).controller!.text, 'old');

    // 改项目名称，保存位置里的文件名跟着变，目录保持不变。
    await tester.enterText(nameField, '我的机器人');
    await tester.pump();
    expect(
      tester.widget<TextField>(pathField).controller!.text,
      r'C:\projects\我的机器人.pieproj',
    );

    // 通过「浏览」选定的文件也会把名称同步回来。
    await tester.tap(find.text('浏览'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(nameField).controller!.text, '射手');
    expect(
      tester.widget<TextField>(pathField).controller!.text,
      r'C:\projects\射手.pieproj',
    );

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android 选中文档后名称回填，改名不改系统文档引用', (tester) async {
    // Android 的保存位置来自只读的系统文档选择器，不能按文本框内容重命名。
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final dialogs = _FakeProjectFileDialogs(
      savePath: 'content://documents/robot.pieproj',
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: HomeScreen(fileDialogs: dialogs)),
      ),
    );
    await tester.tap(find.text('新建项目'));
    await tester.pumpAndSettle();

    final nameField = find.byType(TextField).at(0);
    final pathField = find.byType(TextField).at(1);
    await tester.tap(find.text('浏览'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(nameField).controller!.text, 'robot');
    expect(
      tester.widget<TextField>(pathField).controller!.text,
      'robot.pieproj',
    );

    await tester.enterText(nameField, '新名字');
    await tester.pump();
    expect(
      tester.widget<TextField>(pathField).controller!.text,
      'robot.pieproj',
    );

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('模板工程开关默认关闭，打开前必须先确认', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _CapturingCreateController(),
          ),
        ],
        child: MaterialApp(
          home: HomeScreen(fileDialogs: _FakeProjectFileDialogs()),
        ),
      ),
    );
    await tester.tap(find.text('新建项目'));
    await tester.pumpAndSettle();

    final toggle = find.descendant(
      of: find.byKey(const ValueKey('new_project.template')),
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(toggle).value, isFalse);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('确认使用模板工程？'), findsOneWidget);
    expect(find.text('以后不再显示此提示'), findsOneWidget);
    // 确认之前开关不能已经打开，否则劝阻就没有拦截效果。
    expect(tester.widget<Switch>(toggle).value, isFalse);

    await tester.tap(find.text('返回空白项目'));
    await tester.pumpAndSettle();
    expect(find.text('确认使用模板工程？'), findsNothing);
    expect(tester.widget<Switch>(toggle).value, isFalse);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.text('我已了解，继续使用模板'));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(toggle).value, isTrue);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('勾选不再提示后，同一弹窗内再开关不再弹确认', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    late _CapturingCreateController controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => controller = _CapturingCreateController(),
          ),
        ],
        child: MaterialApp(
          home: HomeScreen(fileDialogs: _FakeProjectFileDialogs()),
        ),
      ),
    );
    await tester.tap(find.text('新建项目'));
    await tester.pumpAndSettle();
    final toggle = find.descendant(
      of: find.byKey(const ValueKey('new_project.template')),
      matching: find.byType(Switch),
    );

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.text('以后不再显示此提示'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我已了解，继续使用模板'));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(toggle).value, isTrue);
    expect(controller.state.suppressTemplateGuide, isTrue);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('确认使用模板工程？'), findsNothing);
    expect(tester.widget<Switch>(toggle).value, isTrue);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('打开开关后按当前所选类型预填配置，关闭时不预填', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    late _CapturingCreateController controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => controller = _CapturingCreateController(),
          ),
        ],
        child: MaterialApp(
          home: HomeScreen(
            fileDialogs: _FakeProjectFileDialogs(
              savePath: r'C:\projects\机器人.pieproj',
            ),
            templates: ProjectTemplates(
              loader: (assetPath) => rootBundle.loadString(assetPath),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('新建项目'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('浏览'));
    await tester.pumpAndSettle();

    // 开关保持关闭时创建：走原来的空白项目路径。
    await tester.tap(find.text('创建项目'));
    await tester.pumpAndSettle();
    expect(controller.createCalls, 1);
    expect(controller.template, isNull);

    await tester.tap(find.text('新建项目'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('浏览'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('工程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建项目'));
    await tester.pumpAndSettle();
    expect(controller.createCalls, 2);
    expect(controller.template, isNull);

    // 打开开关并确认，切到工程后模板应跟随当前类型而不是停留在步兵。
    await tester.tap(find.text('新建项目'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('浏览'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('new_project.template')),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('我已了解，继续使用模板'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('调试'));
    await tester.pumpAndSettle();
    // 切换类型不应该把已确认过的开关关掉，也不应该重新弹提示。
    expect(find.text('确认使用模板工程？'), findsNothing);
    await tester.tap(find.text('创建项目'));
    await tester.pumpAndSettle();

    expect(controller.createCalls, 3);
    expect(controller.kind, ProjectKind.debug);
    final template = controller.template;
    expect(template, isA<DebugConfig>());
    expect(
      ProjectValidator.validate(template!)
          .where((issue) => issue.severity == IssueSeverity.error),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
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

  testWidgets('最近项目按项目类型显示对应图标', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(_RecentProjectsController.new),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // 与「新建项目」分段按钮同一套图标：步兵游戏手柄、工程机械臂、调试
    // 烧杯、音乐钢琴；类型未知的旧数据退回通用文档图标。
    expect(find.byIcon(Icons.sports_esports), findsOneWidget);
    expect(find.byIcon(Icons.precision_manufacturing), findsOneWidget);
    expect(find.byIcon(Icons.science_outlined), findsOneWidget);
    expect(find.byIcon(Icons.piano), findsOneWidget);
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    final recentCard = find.byKey(const ValueKey('home.recent-projects'));
    expect(recentCard, findsOneWidget);
    expect(
      find.descendant(of: recentCard, matching: find.byType(ListTile)),
      findsNWidgets(5),
    );
    expect(tester.takeException(), isNull);
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

  testWidgets('底盘速度过低显示警告但不阻止下一步', (tester) async {
    final source = _infantryDocument();
    final config = source.config as InfantryConfig;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _ConfiguredRemoteController(
              source.copyWith(
                config: config.copyWith(
                  chassis: config.chassis.copyWith(normalSpeed: 3999),
                ),
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('普通速度低于 4000，底盘移动速度可能变慢'), findsWidgets);
    expect(find.text('冲刺速度低于 9000，底盘移动速度可能变慢'), findsWidgets);
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 6'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('摇杆死区过大显示警告但不阻止下一步', (tester) async {
    final source = _infantryDocument();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _ConfiguredRemoteController(source),
          ),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final deadzone = find.byKey(const ValueKey('remote.deadzone'));
    await tester.enterText(deadzone, '501');
    await tester.pumpAndSettle();
    expect(find.text('摇杆死区大于 500，可能影响操控灵敏度'), findsNothing);
    expect(
      find.descendant(of: deadzone, matching: find.byIcon(Icons.warning_amber)),
      findsNothing,
    );

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('摇杆死区大于 500，可能影响操控灵敏度'), findsWidgets);
    expect(
      find.descendant(of: deadzone, matching: find.byIcon(Icons.warning_amber)),
      findsOneWidget,
    );
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 6'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('步兵可反转左右转向并在摘要显示', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _ConfiguredRemoteController(_infantryDocument()),
          ),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final turnSwitch = find.byKey(const ValueKey('chassis.turn_reversed'));
    expect(tester.widget<SwitchListTile>(turnSwitch).value, isFalse);
    await tester.ensureVisible(turnSwitch);
    await tester.pumpAndSettle();
    await tester.tap(turnSwitch);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(WizardScreen)),
    );
    final config =
        container.read(appControllerProvider).document!.config
            as InfantryConfig;
    expect(config.chassis.turnReversed, isTrue);
    container.read(appControllerProvider.notifier).goToStep(3);
    await tester.pumpAndSettle();
    expect(find.text('左右转向：反向'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('工程项目共用左右转向反向设置', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _ConfiguredRemoteController(_engineerDocument()),
          ),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final turnSwitch = find.byKey(const ValueKey('chassis.turn_reversed'));
    await tester.ensureVisible(turnSwitch);
    await tester.pumpAndSettle();
    await tester.tap(turnSwitch);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WizardScreen)),
    );
    final config =
        container.read(appControllerProvider).document!.config
            as EngineerConfig;
    expect(config.chassis.turnReversed, isTrue);
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('工程引脚角色按硬件能力限制并可修正非法旧值', (tester) async {
    final source = _engineerDocument();
    final sourceConfig = source.config as EngineerConfig;
    final document = source.copyWith(
      config: sourceConfig.copyWith(
        pwm: sourceConfig.pwm.copyWith(
          pinRoles: {...sourceConfig.pwm.pinRoles, 'P64': PinRole.motor},
        ),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _StaticProjectController(document, 1),
          ),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    DropdownButton<PinRole> field(String pin) =>
        tester.widget<DropdownButton<PinRole>>(
          find.descendant(
            of: find.byKey(ValueKey('pwm.pin_roles.$pin')),
            matching: find.byType(DropdownButton<PinRole>),
          ),
        );
    List<PinRole?> roles(String pin) =>
        field(pin).items!.map((item) => item.value).toList();

    expect(roles('P60'), const [
      PinRole.motor,
      PinRole.servo,
      PinRole.jitterMotor,
      PinRole.unused,
    ]);
    expect(roles('P64'), const [
      PinRole.motor,
      PinRole.servo,
      PinRole.friction,
      PinRole.unused,
    ]);
    expect(roles('P74'), const [
      PinRole.motor,
      PinRole.servo,
      PinRole.jitterMotor,
      PinRole.unused,
    ]);
    expect(roles('MP03'), const [PinRole.servo]);
    expect(field('MP03').onChanged, isNull);

    final unsupported = field('P64').items!
        .singleWhere((item) => item.value == PinRole.motor);
    expect(unsupported.enabled, isFalse);
    expect((unsupported.child as Text).data, '平滑电机（当前配置，不支持）');
    expect(find.textContaining('P64 不支持平滑电机'), findsWidgets);

    final p64 = find.byKey(const ValueKey('pwm.pin_roles.P64'));
    await tester.ensureVisible(p64);
    await tester.tap(p64);
    await tester.pumpAndSettle();
    await tester.tap(find.text('摩擦轮').last);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(WizardScreen)),
    );
    final updated =
        container.read(appControllerProvider).document!.config
            as EngineerConfig;
    expect(updated.pwm.pinRoles['P64'], PinRole.friction);
    expect(find.textContaining('P64 不支持平滑电机'), findsNothing);
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('工程按键舵机显示直接单次持续及对应参数规则', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _StaticProjectController(_engineerServoButtonDocument(), 3),
          ),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    DropdownButton<ControlMode> modeField(int actionIndex) =>
        tester.widget<DropdownButton<ControlMode>>(
          find.descendant(
            of: find.byKey(ValueKey('modes.0.actions.$actionIndex.mode')),
            matching: find.byType(DropdownButton<ControlMode>),
          ),
        );
    List<ControlMode?> modes(int actionIndex) =>
        modeField(actionIndex).items!.map((item) => item.value).toList();

    expect(modes(0), const [
      ControlMode.direct,
      ControlMode.single,
      ControlMode.continuous,
    ]);
    final direct = modeField(0).items!
        .singleWhere((item) => item.value == ControlMode.direct);
    expect(direct.enabled, isTrue);
    expect((direct.child as Text).data, '直接');
    expect(modes(1), const [ControlMode.direct, ControlMode.incremental]);
    expect(modes(2), const [ControlMode.direct]);

    String? parameterLabel() => tester
        .widget<TextField>(
          find.descendant(
            of: find.byKey(const ValueKey('modes.0.actions.0.parameter')),
            matching: find.byType(TextField),
          ),
        )
        .decoration
        ?.labelText;
    expect(parameterLabel(), '目标角度 °');
    expect(find.text('控制方式与输入类型或 IO 输出角色不匹配'), findsNothing);

    final mode = find.byKey(const ValueKey('modes.0.actions.0.mode'));
    await tester.ensureVisible(mode);
    await tester.tap(mode);
    await tester.pumpAndSettle();
    await tester.tap(find.text('单次').last);
    await tester.pumpAndSettle();

    final parameter = find.byKey(const ValueKey('modes.0.actions.0.parameter'));
    await tester.ensureVisible(parameter);
    expect(parameterLabel(), '灵敏度 °/周期');
    await tester.enterText(parameter, '10.01');
    await tester.pumpAndSettle();
    expect(find.text('舵机角度变化速度可能过快'), findsNothing);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('舵机角度变化速度可能过快'), findsWidgets);

    await tester.enterText(parameter, '1.23');
    await tester.pumpAndSettle();
    await tester.enterText(parameter, '1.234');
    await tester.pumpAndSettle();
    final editable = tester.widget<EditableText>(
      find.descendant(of: parameter, matching: find.byType(EditableText)),
    );
    expect(editable.controller.text, '1.23');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(WizardScreen)),
    );
    final updated =
        container.read(appControllerProvider).document!.config
            as EngineerConfig;
    expect(updated.modes.first.actions.first.mode, ControlMode.single);
    expect(updated.modes.first.actions.first.parameter, 1.23);
    await tester.pump(const Duration(milliseconds: 600));
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

    final channel = find.byKey(const ValueKey('remote.channel'));
    await tester.enterText(channel, '126');
    await tester.pumpAndSettle();
    expect(find.text('遥控器通道号必须在 0–125 之间'), findsNothing);
    expect(
      find.descendant(of: channel, matching: find.byIcon(Icons.error_outline)),
      findsNothing,
    );

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('遥控器通道号必须在 0–125 之间'), findsWidgets);
    expect(
      find.descendant(of: channel, matching: find.byIcon(Icons.error_outline)),
      findsOneWidget,
    );
    expect(find.text('1 / 6'), findsOneWidget);
    expect(find.textContaining('请修正标红的配置'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1500));
  });

  testWidgets('切换数值输入框后显示旧字段问题并隐藏当前字段问题', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _ConfiguredRemoteController(_infantryDocument()),
          ),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final channel = find.byKey(const ValueKey('remote.channel'));
    final deadzone = find.byKey(const ValueKey('remote.deadzone'));
    await tester.enterText(channel, '126');
    await tester.pumpAndSettle();
    expect(find.text('遥控器通道号必须在 0–125 之间'), findsNothing);

    await tester.enterText(deadzone, '2048');
    await tester.pumpAndSettle();
    expect(find.text('遥控器通道号必须在 0–125 之间'), findsWidgets);
    expect(find.text('摇杆死区必须在 0–2047 之间'), findsNothing);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('摇杆死区必须在 0–2047 之间'), findsWidgets);
    await tester.pump(const Duration(milliseconds: 600));
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

    final maxDutyTop = tester.getTopLeft(find.text('P64 最大占空比')).dy;
    final p66MaxDutyTop = tester.getTopLeft(find.text('P66 最大占空比')).dy;
    final stepTop = tester.getTopLeft(find.text('每次油门步长')).dy;
    expect((maxDutyTop - p66MaxDutyTop).abs(), lessThan(1));
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
    expect(config.frictionP64MaxDuty, 800);
    expect(config.frictionP66MaxDuty, 700);
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('云台轴可添加第二个执行器并分配 IO', (tester) async {
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

    final addButtons = find.widgetWithText(TextButton, '添加执行器');
    expect(addButtons, findsNWidgets(2));
    await tester.ensureVisible(addButtons.last);
    await tester.tap(addButtons.last);
    await tester.pumpAndSettle();

    var config = _currentInfantry(tester);
    expect(config.pitchActuators, hasLength(2));
    expect(config.pitchActuators.last.drive, DriveType.servo);
    expect(find.text('执行器 2'), findsOneWidget);

    final secondPin = find.byKey(const ValueKey('gimbal.pitch.1.pin'));
    await tester.ensureVisible(secondPin);
    await tester.tap(secondPin);
    await tester.pumpAndSettle();
    await tester.tap(find.text('P62').last);
    await tester.pumpAndSettle();

    config = _currentInfantry(tester);
    expect(config.pitchActuators.last.pin, 'P62');
    expect(config.pitchActuators.first.pin, 'MP03');
    expect(
      ProjectValidator.validate(config)
          .where((i) => i.fieldPath == 'gimbal.pitch.1.pin'),
      isEmpty,
    );
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('云台轴执行器可删除到留空并解除必填', (tester) async {
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

    final deleteButtons = find.byTooltip('删除执行器');
    expect(deleteButtons, findsNWidgets(2));
    await tester.ensureVisible(deleteButtons.last);
    await tester.tap(deleteButtons.last);
    await tester.pumpAndSettle();

    expect(find.text('未配置执行器；该轴可以留空。'), findsOneWidget);
    final config = _currentInfantry(tester);
    expect(config.pitchActuators, isEmpty);
    expect(config.yawActuators, hasLength(1));
    expect(
      ProjectValidator.validate(config)
          .where((i) => i.fieldPath.startsWith('gimbal.pitch')),
      isEmpty,
    );
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
    expect(find.textContaining('当前占用者为 拨弹电机'), findsOneWidget);
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

  testWidgets('反向拨弹键默认为不使用且可分配给数字键', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(_InfantryControlsController.new),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final reverse = find.byKey(const ValueKey('controls.reverse_feed_key'));
    await tester.ensureVisible(reverse);
    expect(
      find.descendant(of: reverse, matching: find.text('不使用')),
      findsOneWidget,
    );
    expect(_currentInfantry(tester).reverseFeedKey, isNull);

    await tester.tap(reverse);
    await tester.pumpAndSettle();
    expect(find.text('D'), findsOneWidget);
    await tester.tap(find.text('D').last);
    await tester.pumpAndSettle();

    expect(_currentInfantry(tester).reverseFeedKey, 'D');
    expect(
      find.descendant(of: reverse, matching: find.text('D')),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('反向拨弹键与扳机键重名时提示冲突', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(_InfantryControlsController.new),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final reverse = find.byKey(const ValueKey('controls.reverse_feed_key'));
    await tester.ensureVisible(reverse);
    await tester.tap(reverse);
    await tester.pumpAndSettle();
    await tester.tap(find.text('E').last);
    await tester.pumpAndSettle();

    expect(_currentInfantry(tester).reverseFeedKey, 'E');
    expect(find.textContaining('不能使用同一按键'), findsWidgets);
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
    expect(find.text('P64 最大占空比'), findsOneWidget);
    expect(find.text('P66 最大占空比'), findsOneWidget);
    expect(find.text('每次油门步长'), findsOneWidget);

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
    expect(find.text('P64 最大占空比'), findsNothing);
    expect(find.text('P66 最大占空比'), findsNothing);
    expect(find.text('每次油门步长'), findsNothing);
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
          asmPreviewControllerProvider.overrideWith(
            () => _FakeAsmPreviewController(const AsmPreviewState()),
          ),
          deployControllerProvider.overrideWith(_FakeDeployController.new),
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
    expect(editor.style!.fontFamily, 'PieBlockMono');
    expect(
      editor.style!.fontFamilyFallback,
      containsAll(<String>[
        'PieBlockSans',
        'Noto Sans CJK SC',
        'Source Han Sans SC',
        'WenQuanYi Micro Hei Mono',
      ]),
    );
    final lineNumbers = tester.widget<DefaultCodeLineNumber>(
      find.byKey(const ValueKey('generated-code-line-numbers')),
    );
    expect(lineNumbers.textStyle!.fontFamily, 'PieBlockMono');
    expect(lineNumbers.focusedTextStyle!.fontFamily, 'PieBlockMono');
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

  testWidgets('生成代码页默认只有 C，点「汇编」才构建并显示 main.rst', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugDefaultTargetPlatformOverride = null;
    });
    final document = _musicDocument();
    final code = CodeGenerator.generate(document.config);
    final fake = _FakeAsmPreviewController(const AsmPreviewState());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _GeneratedCodeController(document: document),
          ),
          asmPreviewControllerProvider.overrideWith(() => fake),
          deployControllerProvider.overrideWith(_FakeDeployController.new),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // 进页面只有 C，一次编译都没发起。
    expect(find.text('main.c'), findsOneWidget);
    expect(find.text('main.rst'), findsNothing);
    expect(fake.compileCount, 0);
    final cEditor = tester.widget<CodeEditor>(
      find.byKey(const ValueKey('generated-code-editor')),
    );
    expect(cEditor.style!.codeTheme!.languages, contains('c'));
    expect(cEditor.controller!.text, code);

    // 点右上角「汇编」才编译，并展示链接后的列表原文。
    await tester.tap(find.text('汇编'));
    await tester.pumpAndSettle();
    expect(fake.compileCount, 1);
    expect(find.text('main.rst'), findsOneWidget);
    expect(find.text('main.c'), findsNothing);
    final listingEditor = tester.widget<CodeEditor>(
      find.byKey(const ValueKey('generated-code-editor')),
    );
    expect(listingEditor.style!.codeTheme!.languages, contains('asm'));
    expect(listingEditor.controller!.text, _rstSample);
    expect(
      listingEditor.controller!.text,
      contains(r'ecall\t_main'.replaceAll(r'\t', '\t')),
    );
    expect(listingEditor.controller!.text, contains(';'));

    // 切回 C 不触发新编译；再切回汇编命中的是已有结果，同样不再编译。
    await tester.tap(find.text('C 代码'));
    await tester.pumpAndSettle();
    expect(fake.compileCount, 1);
    expect(find.text('main.c'), findsOneWidget);
    expect(
      tester
          .widget<CodeEditor>(
            find.byKey(const ValueKey('generated-code-editor')),
          )
          .controller!
          .text,
      code,
    );
    await tester.tap(find.text('汇编'));
    await tester.pumpAndSettle();
    expect(fake.compileCount, 1);
    expect(find.text('main.rst'), findsOneWidget);

    // 行号回到 1..N：不再有对照视图那套「补空行 + 真实行号」。
    final numbers = tester.widget<DefaultCodeLineNumber>(
      find.byKey(const ValueKey('generated-code-line-numbers')),
    );
    expect(numbers.customLineIndex2Text, isNull);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('导出对话框的「浏览」打开系统文件管理器并回填路径', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final directory = Directory.systemTemp.createTempSync('pieblock-export-');
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      directory.deleteSync(recursive: true);
    });
    final target = '${directory.path}${Platform.pathSeparator}main.c';
    final dialogs = _FakeExportDocumentIo(savePath: target);
    bool? exported;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  exported = await exportGeneratedText(
                    context,
                    suggestedName: 'main.c',
                    text: 'int main(void) { return 0; }\n',
                    documentIo: dialogs,
                  );
                },
                child: const Text('另存为'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('另存为'));
    await _pumpFrames(tester);
    expect(find.text('导出 main.c'), findsOneWidget);
    expect(find.byKey(const ValueKey('export-browse')), findsOneWidget);

    // 点「浏览」：走系统保存对话框，把选中的完整路径回填到输入框。
    await tester.tap(find.byKey(const ValueKey('export-browse')));
    await _pumpFrames(tester);
    expect(dialogs.createCalls, 1);
    expect(dialogs.lastSuggestedName, 'main.c');
    expect(dialogs.lastExtensions, ['c']);
    expect(dialogs.lastBytes, isNull, reason: '桌面只选位置，不在这里写盘');
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('export-path-field')))
          .controller!
          .text,
      target,
    );

    // 「导出」按回填的路径落盘并关闭对话框。
    await tester.tap(find.text('导出').last);
    await _pumpFrames(tester);
    expect(exported, isTrue);
    expect(dialogs.lastWritePath, target);
    expect(
      utf8.decode(dialogs.lastWriteBytes!),
      'int main(void) { return 0; }\n',
    );
    expect(find.text('导出 main.c'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android 的导出走系统文档选择器直接落盘', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final dialogs = _FakeExportDocumentIo(
      savePath: 'content://documents/main.c',
    );
    bool? exported;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  exported = await exportGeneratedText(
                    context,
                    suggestedName: 'main.c',
                    text: 'int main(void) { return 0; }\n',
                    documentIo: dialogs,
                  );
                },
                child: const Text('另存为'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('另存为'));
    await _pumpFrames(tester);
    // SAF 没有可输入的路径，输入框只读，两个按钮都走系统选择器。
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('export-path-field')))
          .readOnly,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('export-browse')));
    await _pumpFrames(tester);
    expect(dialogs.createCalls, 1);
    expect(dialogs.lastBytes, isNotNull, reason: 'SAF 直接写入内容');
    expect(exported, isTrue);
    expect(find.text('导出 main.c'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('「浏览」打不开文件管理器时给出提示且不关闭对话框', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final dialogs = _FakeExportDocumentIo(error: StateError('没有可用的文件管理器'));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => exportGeneratedText(
                  context,
                  suggestedName: 'main.c',
                  text: 'int main(void) {}',
                  documentIo: dialogs,
                ),
                child: const Text('另存为'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('另存为'));
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey('export-browse')));
    await _pumpFrames(tester);
    expect(find.textContaining('无法打开文件管理器'), findsOneWidget);
    expect(find.text('导出 main.c'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('汇编构建中显示全屏等待遮罩与阶段文案', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _GeneratedCodeController(document: _musicDocument()),
          ),
          asmPreviewControllerProvider.overrideWith(
            () => _FakeAsmPreviewController(
              const AsmPreviewState(
                activity: AsmPreviewActivity.compiling,
                progress: '正在链接 BUZZER_MUSIC_GENERATED.hex…',
              ),
            ),
          ),
          deployControllerProvider.overrideWith(_FakeDeployController.new),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('正在构建汇编列表…'), findsOneWidget);
    expect(find.text('正在链接 BUZZER_MUSIC_GENERATED.hex…'), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('汇编列表构建失败时汇编栏给出原因并可重新编译', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 900);
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final fake = _FakeAsmPreviewController(
      const AsmPreviewState(
        activity: AsmPreviewActivity.failed,
        message: '网页版不提供汇编列表，请在桌面版查看',
      ),
      listing: null,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _GeneratedCodeController(document: _musicDocument()),
          ),
          asmPreviewControllerProvider.overrideWith(() => fake),
          deployControllerProvider.overrideWith(_FakeDeployController.new),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // C 栏照常可用，且没有发起编译。
    expect(fake.compileCount, 0);
    expect(find.byKey(const ValueKey('generated-code-editor')), findsOneWidget);

    // 切到汇编：显示失败原因，并给「重新编译」入口。
    await tester.tap(find.text('汇编'));
    await tester.pumpAndSettle();
    expect(fake.compileCount, 1);
    expect(find.text('网页版不提供汇编列表，请在桌面版查看'), findsOneWidget);
    expect(find.text('重新编译'), findsOneWidget);
    expect(find.byKey(const ValueKey('generated-code-editor')), findsNothing);

    await tester.tap(find.text('重新编译'));
    await tester.pumpAndSettle();
    expect(fake.recompileCount, 1);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('窄屏下 C 与汇编同样在单栏里切换，文本与行号整栏换掉', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(560, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final document = _musicDocument();
    final code = CodeGenerator.generate(document.config);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _GeneratedCodeController(document: document),
          ),
          asmPreviewControllerProvider.overrideWith(
            () => _FakeAsmPreviewController(_readyAsmState(code)),
          ),
          deployControllerProvider.overrideWith(_FakeDeployController.new),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // 默认显示 C，点「汇编」切到列表；结果已在缓存里，不再编译。
    expect(find.byKey(const ValueKey('generated-code-editor')), findsOneWidget);
    expect(find.text('main.rst'), findsNothing);
    await tester.tap(find.text('汇编'));
    await tester.pumpAndSettle();
    expect(find.text('main.rst'), findsOneWidget);

    // 切栏必须整栏换掉：内容和行号都是列表自己的，不能沿用 C 栏的编辑器状态。
    final listingEditor = tester.widget<CodeEditor>(
      find.byKey(const ValueKey('generated-code-editor')),
    );
    expect(listingEditor.controller!.text, _rstSample);
    expect(listingEditor.controller!.text, contains('ecall'));
    expect(listingEditor.controller!.text, isNot(contains('#include')));
    final numbers = tester.widget<DefaultCodeLineNumber>(
      find.byKey(const ValueKey('generated-code-line-numbers')),
    );
    expect(numbers.customLineIndex2Text, isNull);

    // 切回 C 同样要还原 C 的文本。
    await tester.tap(find.text('C 代码'));
    await tester.pumpAndSettle();
    final cEditor = tester.widget<CodeEditor>(
      find.byKey(const ValueKey('generated-code-editor')),
    );
    expect(cEditor.controller!.text, code);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('代码搜索显示匹配计数并支持 Ctrl+F', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(_GeneratedCodeController.new),
          asmPreviewControllerProvider.overrideWith(
            () => _FakeAsmPreviewController(const AsmPreviewState()),
          ),
          deployControllerProvider.overrideWith(_FakeDeployController.new),
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
    final document = _musicDocument();
    final code = CodeGenerator.generate(document.config);
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
            key: ValueKey('${size.width}-${brightness.name}'),
            overrides: [
              appControllerProvider.overrideWith(
                () => _StaticProjectController(document, 2),
              ),
              asmPreviewControllerProvider.overrideWith(
                () => _FakeAsmPreviewController(_readyAsmState(code)),
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
        expect(find.byType(CodeEditor), findsWidgets);
        expect(find.text('main.c'), findsOneWidget);
        expect(tester.takeException(), isNull);
        // 任何宽度都只有一个代码区，右上角是「C 代码 / 汇编」切换器。
        final toggle = find.text('汇编');
        expect(toggle, findsOneWidget);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(find.text('main.rst'), findsOneWidget);
        expect(find.text('main.c'), findsNothing);
        expect(find.byType(CodeEditor), findsWidgets);
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
      (infantry, 5, '烧录'),
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
        if (page.$3 == '烧录') {
          // USB-HID 烧录入口目前仅在 Windows/Android 提供（Linux 见
          // wizard_screen 的平台门控），其余平台断言“仅编译”入口存在。
          if (Platform.isWindows || Platform.isAndroid) {
            final flash = find.text('烧录当前固件');
            await tester.ensureVisible(flash);
            await tester.tap(flash);
            await tester.pumpAndSettle();
            expect(find.text('烧录主控板前请确认'), findsOneWidget);
            expect(find.byType(Image), findsNWidgets(2));
            expect(tester.takeException(), isNull);
            await tester.tap(find.text('取消'));
            await tester.pumpAndSettle();
          } else {
            final buildOnly = find.text('仅编译');
            await tester.ensureVisible(buildOnly);
            expect(buildOnly, findsWidgets);
            expect(tester.takeException(), isNull);
          }
        }
      }
    }
  });

  testWidgets('Linux 缺 udev 规则时显示安装入口，安装成功后消失', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _StaticProjectController(_infantryDocument(), 5),
          ),
          deployControllerProvider.overrideWith(_FakeDeployController.new),
          udevRuleControllerProvider.overrideWith(
            () => _FakeUdevRuleController(installed: false),
          ),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final installButton = find.widgetWithText(OutlinedButton, '安装 udev 规则');
    await tester.ensureVisible(installButton);
    expect(installButton, findsOneWidget);

    await tester.tap(installButton);
    await tester.pumpAndSettle();
    // 确认对话框
    final confirm = find.widgetWithText(FilledButton, '安装');
    expect(confirm, findsOneWidget);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(find.textContaining('udev 规则已安装'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '安装 udev 规则'), findsNothing);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('非 Linux 平台不显示 udev 安装入口', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _StaticProjectController(_infantryDocument(), 5),
          ),
          deployControllerProvider.overrideWith(_FakeDeployController.new),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('安装 udev 规则'), findsNothing);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
