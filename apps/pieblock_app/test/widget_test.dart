import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pieblock_app/main.dart';
import 'package:pieblock_app/src/controller.dart';
import 'package:pieblock_app/src/deploy_controller.dart';
import 'package:pieblock_app/src/home_screen.dart';
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

void main() {
  testWidgets('启动页展示两个项目入口', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PieBlockApp()));
    await tester.pumpAndSettle();
    expect(find.text('新建机器人项目'), findsOneWidget);
    expect(find.text('打开已有项目'), findsOneWidget);
    expect(find.textContaining('RoboMaster'), findsOneWidget);
    expect(find.bySemanticsLabel('首都师范大学'), findsOneWidget);
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

  testWidgets('被摩擦轮占用的 IO 使用锁定视觉', (tester) async {
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
    expect(find.byIcon(Icons.lock_outline), findsWidgets);
    expect(find.textContaining('摩擦轮（固定）占用'), findsWidgets);
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
