// 教材第 5 章《工程机器人与高级构型》的软件截图生成器。
//
// ⚠️ 手动运行，刻意放在 `tool/` 下：`flutter test` 默认只收集 `test/`，所以
// 本文件不会进入 CI，也不会在普通单元测试里跑。
//
// 运行命令（仓库根目录）：
//
//     flutter test tool/book_screenshots_test.dart
//
// 每次运行都会**覆盖以下已跟踪（tracked）图片**，提交前请逐张人工复核：
//
//     book/image/ch05/5-1-chassis-off.png
//     book/image/ch05/5-2-pwm-pins.png
//     book/image/ch05/5-3-mecanum-actions.png
//     book/image/ch05/5-4-mecanum-preview.png
//     book/image/ch05/5-5-arm-actions.png
//     book/image/ch05/5-6-arm-servos.png
//
// 截图内容全部来自真实 Widget 树，不是拼图或占位图：
//   * 示例工程从 `book/examples/` 读取，先断言 ProjectValidator 零 error；
//   * ProviderScope 注入静态 AppState 与假部署控制器，渲染真正的 WizardScreen；
//   * 按 1440 逻辑宽度、2 倍逻辑像素比排版，用 RepaintBoundary.toImage 以
//     2078 / 1440 的比例导出 2078px 宽的 PNG（与第 2 章截图一致）；
//   * 文本字体用仓库内打包的 Noto Sans SC 子集与 JetBrains Mono，图标用
//     MaterialIcons，避免 flutter test 默认 Ahem 字体把中文渲染成方块。
//
// 维护提示：页面高度（logicalHeight）与滚动位置按当前 UI 调好；改动向导页
// 布局后需要重跑并逐张检查，必要时调整高度或滚动目标。

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
import 'package:pieblock_app/src/wizard_screen.dart';
import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_toolchain/models.dart';

/// 截图排版使用的逻辑宽度；与正文版心比例一起决定导出分辨率。
const double _logicalWidth = 1440;

/// 导出 PNG 的物理宽度：与 `book/image/ch02/` 的截图保持同一比例。
const double _pixelWidth = 2078;

/// 截图输出目录（相对仓库根目录）。
const String _outputDirectory = 'book/image/ch05';

/// 教材第 5 章的示例工程目录。
const String _exampleDirectory = 'book/examples';

/// 读取一个示例工程；文件缺失时直接失败（依赖任务板 task-4 的产出）。
ProjectDocument _loadExample(String fileName) {
  final file = File('$_exampleDirectory/$fileName');
  if (!file.existsSync()) {
    fail('缺少示例工程 ${file.path}：请先完成生成示例工程的任务再跑截图。');
  }
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map) {
    fail('${file.path} 不是合法的 JSON 对象。');
  }
  return ProjectDocument.fromJson(Map<String, Object?>.from(decoded));
}

/// 示例工程必须先通过校验：截图里出现红色校验面板说明示例被改坏了。
void _expectExampleValid(String fileName, ProjectDocument document) {
  final issues = ProjectValidator.validate(document.config);
  final errors = issues
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

/// 加载一个字体家族；支持一次注册多个字重/字形文件。
Future<void> _loadFontFamily(String family, List<String> assetPaths) async {
  final loader = FontLoader(family);
  for (final path in assetPaths) {
    loader.addFont(_loadFontBytes(path));
  }
  await loader.load();
}

/// 读字体字节。正常走测试资源包（pubspec 已声明），读不到时退回文件系统，
/// 让 `flutter test tool/...` 在资源包未就绪的环境里也能跑。
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

/// 注册与应用一致的字体族，否则测试环境会用 Ahem 把中文画成方块。
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
  // 表达式/代码输入框在 pubspec 之外还依赖通用 `monospace` 家族。
  await _loadFontFamily('monospace', <String>[
    'assets/fonts/JetBrainsMonoNL-Regular.ttf',
  ]);
  // 不加载 MaterialIcons 的话，界面里的图标会退化成空白方块。
  await _loadFontFamily('MaterialIcons', <String>[
    'fonts/MaterialIcons-Regular.otf',
  ]);
}

/// 与 `lib/main.dart` 的浅色主题完全一致，保证截图和真实应用同一观感。
ThemeData _bookTheme() => buildAppTheme(
  brightness: Brightness.light,
  fontFamily: 'PieBlockSans',
  fontFamilyFallback: const <String>['PieBlockSymbols'],
  scaffoldBackgroundColor: const Color(0xfff6f8fa),
);

/// 静态 AppState 注入：截图只读，不允许向导页把「保存」落到真实磁盘。
class _StaticAppController extends AppController {
  _StaticAppController(this._initial);

  final AppState _initial;

  @override
  AppState build() => _initial;
}

/// 部署控制器假实现：截图不涉及烧录，所有动作都是空实现。
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

/// 在指定逻辑高度下渲染向导页，返回截图用的 RepaintBoundary key。
Future<GlobalKey> _pumpBookApp(
  WidgetTester tester, {
  required ProjectDocument document,
  required int step,
  required int logicalHeight,
}) async {
  // 1440×H 逻辑窗口：物理像素翻倍、devicePixelRatio 为 2，等价于一个
  // 1440 逻辑宽的高分屏窗口。
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = Size(_logicalWidth * 2, logicalHeight * 2);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final boundaryKey = GlobalKey(debugLabel: 'book-screenshot-$step-$logicalHeight');
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
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
          deployControllerProvider.overrideWith(_FakeDeployController.new),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'PIE-Block',
          theme: _bookTheme(),
          home: const WizardScreen(),
        ),
      ),
    ),
  );
  await _settle(tester);
  return boundaryKey;
}

/// 等动画结束，并把真实异步的图片解码推进完（资源图片在 fake async 里不会
/// 自己完成，需要 runAsync 走一段真实时间）。
Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 120)),
  );
  await tester.pumpAndSettle();
}

/// 把 RepaintBoundary 导出成 2078px 宽的 PNG 并写入 `book/image/ch05/`。
Future<void> _saveScreenshot(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String fileName,
) async {
  final renderObject = boundaryKey.currentContext?.findRenderObject();
  expect(
    renderObject,
    isA<RenderRepaintBoundary>(),
    reason: '截图根节点必须是已挂载的 RepaintBoundary',
  );
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
      if (data == null) {
        throw StateError('PNG 编码失败：toByteData 返回 null');
      }
      pngBytes = data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  });

  final file = File('$_outputDirectory/$fileName');
  // 注意：widget 测试运行在 fake async 区，await dart:io 的异步写盘可能永远
  // 不完成；PNG 已在 runAsync 里编码好，这里用同步 I/O 落盘。
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(pngBytes, flush: true);
  debugPrint('已生成 ${file.path}（$width×$height）');
  expect(width, _pixelWidth.round(), reason: '导出宽度必须是 2078px');
}

/// 页面的外层滚动容器：`_PageFrame` 的 SingleChildScrollView。
Finder _pageScrollView() => find.byType(SingleChildScrollView).first;

/// 直接滚到页面底部（动作映射页下半部分用）。
Future<void> _scrollPageToBottom(WidgetTester tester) async {
  final scrollable = find
      .descendant(
        of: _pageScrollView(),
        matching: find.byType(Scrollable),
      )
      .first;
  final position = tester.state<ScrollableState>(scrollable).position;
  position.jumpTo(position.maxScrollExtent);
  await tester.pumpAndSettle();
}

/// 跑一个截图用例：打开真实阴影（金色截图默认关闭）并在结束后恢复，
/// 否则测试框架的「调试变量未复位」断言会失败。
void _screenshotTest(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    debugDisableShadows = false;
    try {
      await body(tester);
    } finally {
      debugDisableShadows = true;
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProjectDocument mecanum;
  late ProjectDocument arm;

  setUpAll(() async {
    await _loadBookFonts();
    mecanum = _loadExample('mecanum4.pieproj');
    arm = _loadExample('arm2dof.pieproj');
    _expectExampleValid('mecanum4.pieproj', mecanum);
    _expectExampleValid('arm2dof.pieproj', arm);
  });

  _screenshotTest('5-1 遥控器与底盘：关闭预制底盘', (tester) async {
    final key = await _pumpBookApp(
      tester,
      document: mecanum,
      step: 0,
      logicalHeight: 900,
    );
    await _saveScreenshot(tester, key, '5-1-chassis-off.png');
  });

  _screenshotTest('5-2 PWM 与引脚：PWMB 10000Hz、P74–P77 平滑电机', (tester) async {
    final key = await _pumpBookApp(
      tester,
      document: mecanum,
      step: 1,
      logicalHeight: 1000,
    );
    await _saveScreenshot(tester, key, '5-2-pwm-pins.png');
  });

  _screenshotTest('5-3 动作映射：四轮麦轮前 3 行', (tester) async {
    final key = await _pumpBookApp(
      tester,
      document: mecanum,
      step: 3,
      logicalHeight: 1200,
    );
    // 不滚动：画面就是页面顶部，保证 vx / vy / P74 三行完整可见。
    await _saveScreenshot(tester, key, '5-3-mecanum-actions.png');
  });

  _screenshotTest('5-4 检查与摘要：试算表达式 LY=-2047 四轮 10000', (tester) async {
    final key = await _pumpBookApp(
      tester,
      document: mecanum,
      step: 4,
      logicalHeight: 1100,
    );

    final previewButton = find.text('试算表达式');
    await tester.dragUntilVisible(
      previewButton,
      _pageScrollView(),
      const Offset(0, -250),
    );
    await tester.pumpAndSettle();
    expect(previewButton, findsOneWidget);
    await tester.tap(previewButton);
    await tester.pumpAndSettle();
    expect(find.text('表达式试算'), findsOneWidget);

    // 轴输入顺序固定为 LX、LY、RX、RY，第二个 Slider 就是 LY。
    final lySlider = find.byType(Slider).at(1);
    await tester.drag(lySlider, const Offset(-1000, 0));
    await tester.pumpAndSettle();
    expect(find.text('-2047'), findsWidgets);
    expect(
      find.text('10000'),
      findsNWidgets(4),
      reason: 'LY=-2047 时四个轮子都应输出 10000',
    );
    await _settle(tester);

    await _saveScreenshot(tester, key, '5-4-mecanum-preview.png');
  });

  _screenshotTest('5-5 动作映射：机械臂上半部分变量行', (tester) async {
    final key = await _pumpBookApp(
      tester,
      document: arm,
      step: 3,
      logicalHeight: 1200,
    );
    // 不滚动：从上往下依次是 x、y、r2、c2 等中间量。
    await _saveScreenshot(tester, key, '5-5-arm-actions.png');
  });

  _screenshotTest('5-6 动作映射：机械臂 q1/q2 与主舵机输出', (tester) async {
    final key = await _pumpBookApp(
      tester,
      document: arm,
      step: 3,
      logicalHeight: 1200,
    );
    // 先按清单检查表达式行，再滚到页面底部取「下半部分」。
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('modes.0.actions.9.expression')),
      _pageScrollView(),
      const Offset(0, -250),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('modes.0.actions.9.expression')),
      findsOneWidget,
    );
    await _scrollPageToBottom(tester);
    await _settle(tester);
    await _saveScreenshot(tester, key, '5-6-arm-servos.png');
  });
}
