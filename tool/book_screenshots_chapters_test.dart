// 教材第 1、3、4、6、7、8、9、10 章的软件截图生成器。
//
// ⚠️ 手动运行，刻意放在 `tool/` 下：`flutter test` 默认只收集 `test/`。
//
// 运行命令（仓库根目录）：
//
//     flutter test tool/book_screenshots_chapters_test.dart
//
// 与 `tool/book_screenshots_test.dart`（第 5 章）同一套做法：
//   * 示例工程从 `book/examples/` 读取，先断言 ProjectValidator 零 error；
//   * ProviderScope 注入静态 AppState，渲染真实的 WizardScreen / HomeScreen；
//   * 按 1440 逻辑宽度、2 倍像素比导出 2078px 宽的 PNG；
//   * 字体与图标显式加载，避免测试环境把中文画成方块。
//
// 维护提示：页面高度与滚动目标按当前 UI 调好；改动向导页布局后需要重跑并
// 逐张检查。

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pieblock_app/src/controller.dart';
import 'package:pieblock_app/src/deploy_controller.dart';
import 'package:pieblock_app/src/design/app_theme.dart';
import 'package:pieblock_app/src/home_screen.dart';
import 'package:pieblock_app/src/recent_project.dart';
import 'package:pieblock_app/src/wizard_screen.dart';
import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_toolchain/models.dart';

const double _logicalWidth = 1440;
const double _pixelWidth = 2078;

const String _exampleDirectory = 'book/examples';
const String _imageRoot = 'book/image';

class _StaticAppController extends AppController {
  _StaticAppController(this._initial);

  final AppState _initial;

  @override
  AppState build() => _initial;
}

class _FakeDeployController extends DeployController {
  @override
  DeployState build() => const DeployState();

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

Future<ProjectDocument> _loadExample(String fileName) async {
  final file = File('$_exampleDirectory/$fileName');
  expect(file.existsSync(), isTrue, reason: '缺少示例工程 ${file.path}');
  final decoded = jsonDecode(file.readAsStringSync());
  return ProjectDocument.fromJson(
    Map<String, Object?>.from(decoded as Map),
  );
}

void _expectNoErrors(String fileName, ProjectDocument document) {
  final errors = ProjectValidator.validate(document.config)
      .where((issue) => issue.severity == IssueSeverity.error)
      .toList();
  expect(
    errors,
    isEmpty,
    reason:
        '$_exampleDirectory/$fileName 校验未通过：'
        '${errors.map((issue) => '${issue.fieldPath} ${issue.message}').join('；')}',
  );
}

Future<void> _loadFontFamily(String family, List<String> assetPaths) async {
  final loader = FontLoader(family);
  for (final path in assetPaths) {
    loader.addFont(_loadFontBytes(path));
  }
  await loader.load();
}

Future<ByteData> _loadFontBytes(String assetPath) async {
  try {
    return await rootBundle.load(assetPath);
  } catch (_) {
    final file = File(assetPath);
    if (!file.existsSync()) rethrow;
    final bytes = await file.readAsBytes();
    return ByteData.sublistView(bytes);
  }
}

Future<void> _loadBookFonts() async {
  await _loadFontFamily('PieBlockSans', <String>[
    'assets/fonts/NotoSansSC-Regular-subset.ttf',
  ]);
  await _loadFontFamily('PieBlockSymbols', <String>[
    'assets/fonts/NotoSansSC-Symbols-subset.ttf',
  ]);
  await _loadFontFamily('PieBlockMono', <String>[
    'assets/fonts/JetBrainsMonoNL-Regular.ttf',
    'assets/fonts/JetBrainsMonoNL-Italic.ttf',
    'assets/fonts/JetBrainsMonoNL-Bold.ttf',
    'assets/fonts/JetBrainsMonoNL-BoldItalic.ttf',
  ]);
  await _loadFontFamily('monospace', <String>[
    'assets/fonts/JetBrainsMonoNL-Regular.ttf',
  ]);
  await _loadFontFamily('MaterialIcons', <String>[
    'fonts/MaterialIcons-Regular.otf',
  ]);
}

ThemeData _bookTheme() => buildAppTheme(
  brightness: Brightness.light,
  fontFamily: 'PieBlockSans',
  fontFamilyFallback: const <String>['PieBlockSymbols'],
  scaffoldBackgroundColor: const Color(0xfff6f8fa),
);

Future<GlobalKey> _pump(
  WidgetTester tester, {
  required Widget child,
  required int logicalHeight,
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = Size(_logicalWidth * 2, logicalHeight * 2);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final boundaryKey = GlobalKey(debugLabel: 'book-screenshot');
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: ProviderScope(
        overrides: [
          deployControllerProvider.overrideWith(_FakeDeployController.new),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'PIE-Block',
          theme: _bookTheme(),
          home: child,
        ),
      ),
    ),
  );
  await _settle(tester);
  return boundaryKey;
}

/// 打开一个示例工程的向导页（step 为步骤下标，见 controller.dart 的 stepIds）。
Future<GlobalKey> _pumpWizard(
  WidgetTester tester, {
  required ProjectDocument document,
  required int step,
  required int logicalHeight,
}) => _pump(
  tester,
  logicalHeight: logicalHeight,
  child: ProviderScope(
    overrides: [
      appControllerProvider.overrideWith(
        () => _StaticAppController(
          AppState(
            document: document,
            step: step,
            maxVisitedStep: step,
            saveStatus: SaveStatus.saved,
            themeMode: ThemeMode.light,
          ),
        ),
      ),
    ],
    child: const WizardScreen(),
  ),
);

/// 渲染首页；最近项目直接放进 AppState，文件名与 book/examples 一致。
Future<GlobalKey> _pumpHome(
  WidgetTester tester, {
  required List<RecentProject> recentProjects,
  required int logicalHeight,
}) => _pump(
  tester,
  logicalHeight: logicalHeight,
  child: ProviderScope(
    overrides: [
      appControllerProvider.overrideWith(
        () => _StaticAppController(
          AppState(
            document: null,
            step: 0,
            maxVisitedStep: 0,
            saveStatus: SaveStatus.saved,
            themeMode: ThemeMode.light,
            recentProjects: recentProjects,
          ),
        ),
      ),
    ],
    child: const HomeScreen(),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 120)),
  );
  await tester.pumpAndSettle();
}

Future<void> _saveScreenshot(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String relativePath,
) async {
  final renderObject = boundaryKey.currentContext?.findRenderObject();
  expect(renderObject, isA<RenderRepaintBoundary>());
  final boundary = renderObject! as RenderRepaintBoundary;
  expect(boundary.debugNeedsPaint, isFalse, reason: '截图前必须完成绘制');

  late final Uint8List pngBytes;
  late final int width;
  late final int height;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _pixelWidth / _logicalWidth);
    try {
      width = image.width;
      height = image.height;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('PNG 编码失败');
      pngBytes = data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  });

  final file = File('$_imageRoot/$relativePath');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(pngBytes, flush: true);
  debugPrint('已生成 ${file.path}（$width×$height）');
  expect(width, _pixelWidth.round(), reason: '导出宽度必须是 2078px');
}

Finder _pageScrollView() => find.byType(SingleChildScrollView).first;

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.dragUntilVisible(target, _pageScrollView(), const Offset(0, -250));
  await tester.pumpAndSettle();
}

void _screenshotTest(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    debugDisableShadows = false;
    // 测试环境默认平台是 android，会让烧录页等页面显示移动端文案；
    // 教材截图统一按 Linux 桌面端渲染。
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      debugDisableShadows = true;
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProjectDocument infantry;
  late ProjectDocument debug;
  late ProjectDocument music;

  setUpAll(() async {
    await _loadBookFonts();
    infantry = await _loadExample('infantry-standard.pieproj');
    debug = await _loadExample('debug-checklist.pieproj');
    music = await _loadExample('music-twinkle.pieproj');
    _expectNoErrors('infantry-standard.pieproj', infantry);
    _expectNoErrors('debug-checklist.pieproj', debug);
    _expectNoErrors('music-twinkle.pieproj', music);
  });

  _screenshotTest('1-1 首页', (tester) async {
    final key = await _pumpHome(tester, recentProjects: const [], logicalHeight: 760);
    await _saveScreenshot(tester, key, 'ch01/1-1-home.png');
  });

  _screenshotTest('3-1 遥控器与底盘：通道与死区', (tester) async {
    final key = await _pumpWizard(
      tester,
      document: infantry,
      step: 0,
      logicalHeight: 1000,
    );
    await _saveScreenshot(tester, key, 'ch03/3-1-remote-top.png');
  });

  _screenshotTest('3-2 遥控器与底盘：单轮方向与速度', (tester) async {
    final key = await _pumpWizard(
      tester,
      document: infantry,
      step: 0,
      logicalHeight: 1000,
    );
    await _scrollTo(tester, find.byKey(const ValueKey('chassis.turn_reversed')));
    await _settle(tester);
    await _saveScreenshot(tester, key, 'ch03/3-2-remote-chassis.png');
  });

  _screenshotTest('4-1 配置执行机构：云台与拨弹', (tester) async {
    final key = await _pumpWizard(
      tester,
      document: infantry,
      step: 1,
      logicalHeight: 1100,
    );
    await _saveScreenshot(tester, key, 'ch04/4-1-mechanism.png');
  });

  _screenshotTest('4-2 控制与摩擦轮：按键分配', (tester) async {
    final key = await _pumpWizard(
      tester,
      document: infantry,
      step: 2,
      logicalHeight: 1100,
    );
    await _saveScreenshot(tester, key, 'ch04/4-2-controls.png');
  });

  _screenshotTest('6-1 调试测试序列：前几项', (tester) async {
    final key = await _pumpWizard(
      tester,
      document: debug,
      step: 0,
      logicalHeight: 1100,
    );
    await _saveScreenshot(tester, key, 'ch06/6-1-debug-tests.png');
  });

  _screenshotTest('6-2 调试测试序列：摩擦轮项', (tester) async {
    final key = await _pumpWizard(
      tester,
      document: debug,
      step: 0,
      logicalHeight: 1100,
    );
    // 测试序列页是 ReorderableListView（fill 布局），没有外层的
    // SingleChildScrollView，需要直接滚列表本身。
    final scrollable = find
        .descendant(
          of: find.byType(ReorderableListView),
          matching: find.byType(Scrollable),
        )
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(position.maxScrollExtent);
    await _settle(tester);
    await _saveScreenshot(tester, key, 'ch06/6-2-debug-friction.png');
  });

  _screenshotTest('7-1 音乐编辑器：钢琴卷帘', (tester) async {
    final key = await _pumpWizard(
      tester,
      document: music,
      step: 0,
      logicalHeight: 900,
    );
    await _saveScreenshot(tester, key, 'ch07/7-1-music-editor.png');
  });

  _screenshotTest('8-1 检查与摘要：错误与警告', (tester) async {
    final key = await _pumpWizard(
      tester,
      document: infantry,
      step: 3,
      logicalHeight: 1100,
    );
    await _saveScreenshot(tester, key, 'ch08/8-1-review.png');
  });

  _screenshotTest('8-2 生成代码页', (tester) async {
    final key = await _pumpWizard(
      tester,
      document: infantry,
      step: 4,
      logicalHeight: 1100,
    );
    await _saveScreenshot(tester, key, 'ch08/8-2-generated-code.png');
  });

  _screenshotTest('9-1 烧录页', (tester) async {
    final key = await _pumpWizard(
      tester,
      document: infantry,
      step: 5,
      logicalHeight: 1000,
    );
    await _saveScreenshot(tester, key, 'ch09/9-1-deploy.png');
  });

  _screenshotTest('10-1 首页最近项目', (tester) async {
    final root = Directory.current.path;
    String examplePath(String name) => '$root/book/examples/$name';
    final key = await _pumpHome(
      tester,
      recentProjects: [
        RecentProject(
          path: examplePath('infantry-standard.pieproj'),
          kind: ProjectKind.infantry,
        ),
        RecentProject(
          path: examplePath('mecanum4.pieproj'),
          kind: ProjectKind.engineer,
        ),
        RecentProject(
          path: examplePath('debug-checklist.pieproj'),
          kind: ProjectKind.debug,
        ),
        RecentProject(
          path: examplePath('music-twinkle.pieproj'),
          kind: ProjectKind.music,
        ),
      ],
      logicalHeight: 900,
    );
    await _settle(tester);
    await _saveScreenshot(tester, key, 'ch10/10-1-home-recent.png');
  });
}
