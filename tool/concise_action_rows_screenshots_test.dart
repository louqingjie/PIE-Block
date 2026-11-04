// 《PIE-Block 软件与应用（简明版）》第 4 章动作行截图生成器。
//
// 运行命令（仓库根目录）：
//
//     flutter test tool/concise_action_rows_screenshots_test.dart
//
// 生成以下图片：
//     book/image/ch04/4-2-mecanum-rows-top.png
//     book/image/ch04/4-3-mecanum-rows-bottom.png
//     book/image/ch04/4-4-omni4-rows.png
//
// 书中使用裁剪后的输出行图片；生成原图后执行：
//     python -c "from PIL import Image; \
//       Image.open('book/image/ch04/4-3-mecanum-rows-bottom.png') \
//         .crop((330,1010,2078,2360)) \
//         .save('book/image/ch04/4-3-mecanum-outputs-crop.png'); \
//       Image.open('book/image/ch04/4-4-omni4-rows.png') \
//         .crop((330,1010,2078,2360)) \
//         .save('book/image/ch04/4-4-omni4-outputs-crop.png')"

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

const double _logicalWidth = 1440;
const double _pixelWidth = 2078;
const String _imageRoot = 'book/image';
const String _exampleDirectory = 'book/examples';

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

ProjectDocument _loadExample(String fileName) {
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

Future<GlobalKey> _pumpWizard(
  WidgetTester tester, {
  required ProjectDocument document,
  required int step,
  required int logicalHeight,
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = Size(_logicalWidth * 2, logicalHeight * 2);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();

  final boundaryKey = GlobalKey(debugLabel: 'concise-action-rows');
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: ProviderScope(
        key: UniqueKey(),
        overrides: [
          deployControllerProvider.overrideWith(_FakeDeployController.new),
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
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'PIE-Block',
          theme: _bookTheme(),
          home: const WizardScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 120)),
  );
  await tester.pumpAndSettle();
  return boundaryKey;
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
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _pixelWidth / _logicalWidth);
    try {
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
  debugPrint('已生成 ${file.path}');
}

ProjectDocument _withActions(
  ProjectDocument base,
  List<ActionMapping> actions,
) {
  final engineer = base.config as EngineerConfig;
  final mode = engineer.modes.first.copyWith(actions: actions);
  return base.copyWith(config: engineer.copyWith(modes: [mode]));
}

List<ActionMapping> _bindingAndCalculationRows() => [
  ActionMapping(
    inputKind: ActionInputKind.remote,
    key: 'LY',
    outputKind: ActionOutputKind.integer,
    variableName: 'joyY',
  ),
  ActionMapping(
    inputKind: ActionInputKind.remote,
    key: 'LX',
    outputKind: ActionOutputKind.integer,
    variableName: 'joyX',
  ),
  ActionMapping(
    inputKind: ActionInputKind.remote,
    key: '←',
    outputKind: ActionOutputKind.integer,
    variableName: 'keyLeft',
  ),
  ActionMapping(
    inputKind: ActionInputKind.remote,
    key: '→',
    outputKind: ActionOutputKind.integer,
    variableName: 'keyRight',
  ),
  ActionMapping(
    inputKind: ActionInputKind.unspecified,
    outputKind: ActionOutputKind.integer,
    variableName: 'forward',
    expression: '-joyY',
  ),
  ActionMapping(
    inputKind: ActionInputKind.unspecified,
    outputKind: ActionOutputKind.integer,
    variableName: 'left',
    expression: 'joyX',
  ),
  ActionMapping(
    inputKind: ActionInputKind.unspecified,
    outputKind: ActionOutputKind.integer,
    variableName: 'turn',
    expression: '(keyLeft-keyRight)*1000',
  ),
];

ActionMapping _wheelRow(String pin, String expression) => ActionMapping(
  inputKind: ActionInputKind.unspecified,
  outputKind: ActionOutputKind.pin,
  pin: pin,
  expression: expression,
);

List<ActionMapping> _mecanumRows() => [
  ..._bindingAndCalculationRows(),
  _wheelRow('P74', '(forward-left-turn)*10000/2047'),
  _wheelRow('P75', '(forward+left+turn)*10000/2047'),
  _wheelRow('P76', '(forward+left-turn)*10000/2047'),
  _wheelRow('P77', '(forward-left+turn)*10000/2047'),
];

List<ActionMapping> _omni4Rows() => [
  ..._bindingAndCalculationRows(),
  _wheelRow('P74', '(-0.707*forward+0.707*left+turn)*10000/2047'),
  _wheelRow('P75', '(-0.707*forward-0.707*left+turn)*10000/2047'),
  _wheelRow('P76', '(0.707*forward-0.707*left+turn)*10000/2047'),
  _wheelRow('P77', '(0.707*forward+0.707*left+turn)*10000/2047'),
];

Future<void> _scrollToBottom(WidgetTester tester) async {
  final scrollView = find.byType(SingleChildScrollView).first;
  final lastField = find.byType(TextField).last;
  await tester.dragUntilVisible(lastField, scrollView, const Offset(0, -300));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('动作行填写截图', (tester) async {
    debugDisableShadows = false;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await _loadBookFonts();

      final base = _loadExample('mecanum4.pieproj');

      final mecanum = _withActions(base, _mecanumRows());
      _expectNoErrors('mecanum4.pieproj（分层行）', mecanum);
      var key = await _pumpWizard(
        tester,
        document: mecanum,
        step: 3,
        logicalHeight: 1400,
      );
      await _saveScreenshot(tester, key, 'ch04/4-2-mecanum-rows-top.png');
      key = await _pumpWizard(
        tester,
        document: mecanum,
        step: 3,
        logicalHeight: 1800,
      );
      await _scrollToBottom(tester);
      await _saveScreenshot(tester, key, 'ch04/4-3-mecanum-rows-bottom.png');

      final omni4 = _withActions(base, _omni4Rows());
      _expectNoErrors('omni4（分层行）', omni4);
      key = await _pumpWizard(
        tester,
        document: omni4,
        step: 3,
        logicalHeight: 1800,
      );
      await _scrollToBottom(tester);
      await _saveScreenshot(tester, key, 'ch04/4-4-omni4-rows.png');
    } finally {
      debugDefaultTargetPlatformOverride = null;
      debugDisableShadows = true;
    }
  });
}
