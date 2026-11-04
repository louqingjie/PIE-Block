// 1.8.0-beta.1 新功能 GIF 的原始帧生成器。
//
// ⚠️ 手动运行，刻意放在 `tool/` 下：`flutter test` 默认只收集 `test/`。
//
// 运行命令（仓库根目录）：
//
//     flutter test tool/beta_gif_frames_test.dart
//
// 输出到 `.tmp/beta_gifs/raw/`（不进入版本库）：
//   * `*.png`：真实 Widget 树导出的界面帧；
//   * `*.json`：同一帧里关键控件的逻辑坐标，供合帧脚本画高亮与光标。
//
// 用法参照 `tool/book_screenshots_test.dart`：ProviderScope 注入静态 AppState
// 与假部署控制器，字体显式加载，避免中文渲染成方块。

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pieblock_app/src/asm_preview_controller.dart';
import 'package:pieblock_app/src/controller.dart';
import 'package:pieblock_app/src/deploy_controller.dart';
import 'package:pieblock_app/src/design/app_theme.dart';
import 'package:pieblock_app/src/wizard_screen.dart';
import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_toolchain/models.dart';

const double _logicalWidth = 1440;
const double _exportRatio = 1.5;
const String _outputDirectory = '.tmp/beta_gifs/raw';
const String _exampleDirectory = 'book/examples';

class _PreviewController extends AppController {
  _PreviewController(this._initial);

  final AppState _initial;

  @override
  AppState build() => _initial;

  /// 截图不应触碰磁盘：直接改内存状态，跳过自动保存计时器。
  @override
  void updateConfig(ProjectConfig config) {
    final document = state.document;
    if (document == null) return;
    state = state.copyWith(
      document: document.copyWith(config: config),
      clearMessage: true,
      clearPendingField: true,
    );
  }
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

class _FakeAsmPreviewController extends AsmPreviewController {
  @override
  AsmPreviewState build() => const AsmPreviewState();
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

Future<void> _loadFonts() async {
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

ThemeData _theme() => buildAppTheme(
  brightness: Brightness.light,
  fontFamily: 'PieBlockSans',
  fontFamilyFallback: const <String>['PieBlockSymbols'],
  scaffoldBackgroundColor: const Color(0xfff6f8fa),
);

ProjectDocument _loadExample(String fileName) {
  final file = File('$_exampleDirectory/$fileName');
  if (!file.existsSync()) {
    fail('缺少示例工程 ${file.path}');
  }
  final decoded = jsonDecode(file.readAsStringSync());
  return ProjectDocument.fromJson(Map<String, Object?>.from(decoded as Map));
}

ProjectDocument _engineerDocument({
  required PwmGroupConfig pwm,
  List<ActionMapping> actions = const [],
  List<ActionTable> actionTables = const [],
  int modeCount = 1,
}) {
  final base = _loadExample('arm2dof.pieproj');
  return base.copyWith(
    config: EngineerConfig(
      remote: const RemoteConfig(),
      chassis: const ChassisConfig(enabled: false),
      pwm: pwm,
      modeCount: modeCount,
      switchStrategy: SwitchStrategy.cycle,
      modeSwitchKey: '↑',
      modes: [
        EngineerModeConfig(
          preserveChassis: false,
          actions: actions,
          actionTables: actionTables,
        ),
      ],
    ),
  );
}

/// 1440 逻辑宽、指定高度的窗口，渲染真实向导页。
Future<GlobalKey> _pumpApp(
  WidgetTester tester, {
  required ProjectDocument document,
  required int step,
  required double logicalHeight,
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = Size(_logicalWidth * 2, logicalHeight * 2);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final boundaryKey = GlobalKey(debugLabel: 'beta-gif-$step-$logicalHeight');
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _PreviewController(
              AppState(
                document: document,
                step: step,
                maxVisitedStep: 6,
                saveStatus: SaveStatus.saved,
                themeMode: ThemeMode.light,
              ),
            ),
          ),
          deployControllerProvider.overrideWith(_FakeDeployController.new),
          asmPreviewControllerProvider.overrideWith(
            _FakeAsmPreviewController.new,
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'PIE-Block',
          theme: _theme(),
          home: const WizardScreen(),
        ),
      ),
    ),
  );
  await _settle(tester);
  return boundaryKey;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 120)),
  );
  await tester.pumpAndSettle();
}

/// 导出 PNG，并把关键控件矩形写成同名 JSON；坐标是 1440 逻辑宽下的像素。
Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name, {
  Map<String, Finder> rects = const {},
  double logicalHeight = 0,
}) async {
  final renderObject = boundaryKey.currentContext?.findRenderObject();
  expect(renderObject, isA<RenderRepaintBoundary>());
  final boundary = renderObject! as RenderRepaintBoundary;
  expect(boundary.debugNeedsPaint, isFalse);

  late final Uint8List pngBytes;
  late final int width;
  late final int height;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _exportRatio);
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

  final file = File('$_outputDirectory/$name.png');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(pngBytes, flush: true);

  final rectJson = <String, List<double>>{};
  for (final entry in rects.entries) {
    final finder = entry.value;
    if (finder.evaluate().isEmpty) continue;
    final rect = tester.getRect(finder.first);
    rectJson[entry.key] = [
      rect.left,
      rect.top,
      rect.width,
      rect.height,
    ].map((v) => (v * 1000).round() / 1000).toList();
  }
  final meta = <String, Object?>{
    'name': name,
    'logicalWidth': _logicalWidth,
    'logicalHeight': logicalHeight,
    'pixelWidth': width,
    'pixelHeight': height,
    'rects': rectJson,
  };
  File('$_outputDirectory/$name.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(meta),
  );
  debugPrint('已生成 ${file.path}（$width×$height）');
}

Finder _pageScrollable() => find
    .descendant(
      of: find.byType(SingleChildScrollView).first,
      matching: find.byType(Scrollable),
    )
    .first;

Finder _actionsScrollable() => find
    .descendant(
      of: find.byType(ReorderableListView),
      matching: find.byType(Scrollable),
    )
    .first;

void _gifTest(
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

// ---------------------------------------------------------------------------
// 工程配置：动作表演示
// ---------------------------------------------------------------------------

const _tableId = 'demo-table';

ProjectDocument _tableDocument() => _engineerDocument(
  pwm: PwmGroupConfig(
    pwma: PwmFrequency.hz50,
    pwmb: PwmFrequency.hz10000,
    pinRoles: const {
      'P60': PinRole.unused,
      'P62': PinRole.unused,
      'P64': PinRole.unused,
      'P66': PinRole.unused,
      'P74': PinRole.motor,
      'P75': PinRole.motor,
      'P76': PinRole.unused,
      'P77': PinRole.unused,
      'MP03': PinRole.servo,
      'MP74': PinRole.servo,
    },
    servoMids: const {'MP03': 0, 'MP74': 0},
    servoMaxLimits: const {'MP03': 90, 'MP74': 90},
    servoMinLimits: const {'MP03': -90, 'MP74': -90},
    pinNotes: const {'MP03': '工程一级舵机', 'MP74': '工程二级舵机'},
  ),
  actionTables: [
    ActionTable(
      id: _tableId,
      key: 'A',
      previousKey: 'D',
      steps: 4,
      rows: const [
        ActionTableRow(pin: 'MP03', values: [-90, -30, 30, 90]),
        ActionTableRow(pin: 'MP74', values: [0, 45, 0, -45]),
        ActionTableRow(pin: 'P74', values: [0, 3000, 6000, 3000]),
      ],
    ),
  ],
);

// ---------------------------------------------------------------------------
// 工程配置：摩擦轮覆盖全部输出脚
// ---------------------------------------------------------------------------

ProjectDocument _frictionDocument({required bool extended}) => _engineerDocument(
  pwm: PwmGroupConfig(
    pwma: PwmFrequency.hz50,
    pwmb: PwmFrequency.hz50,
    pinRoles: {
      'P60': extended ? PinRole.friction : PinRole.unused,
      'P62': extended ? PinRole.friction : PinRole.unused,
      'P64': PinRole.friction,
      'P66': PinRole.friction,
      'P74': extended ? PinRole.friction : PinRole.unused,
      'P75': extended ? PinRole.friction : PinRole.unused,
      'P76': PinRole.unused,
      'P77': PinRole.unused,
      'MP03': PinRole.servo,
      'MP74': PinRole.servo,
    },
    servoMids: const {'MP03': 0, 'MP74': 0},
    servoMaxLimits: const {'MP03': 90, 'MP74': 90},
    servoMinLimits: const {'MP03': -90, 'MP74': -90},
    frictionMaxDuties: const {
      'P60': 800,
      'P62': 800,
      'P64': 800,
      'P66': 800,
      'P74': 800,
      'P75': 800,
    },
    pinNotes: const {'MP03': '工程一级舵机'},
  ),
);

// ---------------------------------------------------------------------------
// 工程配置：带符号转速
// ---------------------------------------------------------------------------

ProjectDocument _signedSpeedDocument() => _engineerDocument(
  pwm: PwmGroupConfig(
    pwma: PwmFrequency.hz50,
    pwmb: PwmFrequency.hz10000,
    pinRoles: const {
      'P60': PinRole.unused,
      'P62': PinRole.unused,
      'P64': PinRole.unused,
      'P66': PinRole.unused,
      'P74': PinRole.motor,
      'P75': PinRole.motor,
      'P76': PinRole.unused,
      'P77': PinRole.unused,
      'MP03': PinRole.servo,
      'MP74': PinRole.servo,
    },
    servoMids: const {'MP03': 0, 'MP74': 0},
    servoMaxLimits: const {'MP03': 90, 'MP74': 90},
    servoMinLimits: const {'MP03': -90, 'MP74': -90},
    pinNotes: const {'MP03': '工程一级舵机'},
  ),
  actions: [
    ActionMapping(
      id: 'demo-forward',
      key: 'B',
      outputKind: ActionOutputKind.pin,
      pin: 'P74',
      mode: ControlMode.direct,
      parameter: 6000,
    ),
    ActionMapping(
      id: 'demo-reverse',
      key: 'C',
      outputKind: ActionOutputKind.pin,
      pin: 'P74',
      mode: ControlMode.direct,
      parameter: -6000,
    ),
  ],
);

// ---------------------------------------------------------------------------
// 工程配置：引脚备注
// ---------------------------------------------------------------------------

ProjectDocument _noteDocument({String? note}) => _engineerDocument(
  pwm: PwmGroupConfig(
    pwma: PwmFrequency.hz50,
    pwmb: PwmFrequency.hz10000,
    pinRoles: const {
      'P60': PinRole.unused,
      'P62': PinRole.unused,
      'P64': PinRole.unused,
      'P66': PinRole.unused,
      'P74': PinRole.motor,
      'P75': PinRole.motor,
      'P76': PinRole.unused,
      'P77': PinRole.unused,
      'MP03': PinRole.servo,
      'MP74': PinRole.servo,
    },
    servoMids: const {'MP03': 0, 'MP74': 0},
    servoMaxLimits: const {'MP03': 90, 'MP74': 90},
    servoMinLimits: const {'MP03': -90, 'MP74': -90},
    pinNotes: {'MP03': ?note},
  ),
  actions: [
    ActionMapping(
      id: 'demo-note-action',
      key: 'E',
      outputKind: ActionOutputKind.pin,
      pin: 'MP03',
      mode: ControlMode.direct,
      parameter: 0,
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadFonts);

  _gifTest('动作表：展开并定位档位列', (tester) async {
    final key = await _pumpApp(
      tester,
      document: _tableDocument(),
      step: 3,
      logicalHeight: 1240,
    );
    // 已有动作表默认收起，先展开。
    final expand = find.byTooltip('展开动作表');
    if (expand.evaluate().isNotEmpty) {
      await tester.tap(expand.first);
      await tester.pumpAndSettle();
    }
    final card = find.byKey(const ValueKey('action-table-card-$_tableId'));
    if (card.evaluate().isEmpty) {
      await tester.dragUntilVisible(
        find.text('添加动作表'),
        _actionsScrollable(),
        const Offset(0, -260),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('展开动作表').first);
      await tester.pumpAndSettle();
    }
    await tester.dragUntilVisible(
      find.text('档 4'),
      _actionsScrollable(),
      const Offset(0, -180),
    );
    await _settle(tester);
    await _capture(
      tester,
      key,
      '01-action-table',
      logicalHeight: 1240,
      rects: {
        'card': find.byKey(const ValueKey('action-table-card-$_tableId')),
        'table': find.byType(Table),
        'key': find.byKey(const ValueKey('modes.0.action_tables.0.key')),
        'prev': find.byKey(const ValueKey('modes.0.action_tables.0.prev_key')),
        'gear1': find.text('档 1'),
        'gear2': find.text('档 2'),
        'gear3': find.text('档 3'),
        'gear4': find.text('档 4'),
        'pinMP03': find.byKey(
          const ValueKey('modes.0.action_tables.0.rows.0.pin'),
        ),
        'pinMP74': find.byKey(
          const ValueKey('modes.0.action_tables.0.rows.1.pin'),
        ),
        'pinP64': find.byKey(
          const ValueKey('modes.0.action_tables.0.rows.2.pin'),
        ),
      },
    );
  });

  _gifTest('摩擦轮：改造前的引脚角色', (tester) async {
    final key = await _pumpApp(
      tester,
      document: _frictionDocument(extended: false),
      step: 1,
      logicalHeight: 1180,
    );
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('pwm.pin_roles.MP03')),
      _pageScrollable(),
      const Offset(0, -200),
    );
    await _settle(tester);
    await _capture(
      tester,
      key,
      '02-friction-before',
      logicalHeight: 1180,
      rects: {
        'p60': find.byKey(const ValueKey('pwm.pin_roles.P60')),
        'p62': find.byKey(const ValueKey('pwm.pin_roles.P62')),
        'p64': find.byKey(const ValueKey('pwm.pin_roles.P64')),
        'section': find.text('引脚输出角色'),
      },
    );
  });

  _gifTest('摩擦轮：P60 下拉展开', (tester) async {
    final key = await _pumpApp(
      tester,
      document: _frictionDocument(extended: false),
      step: 1,
      logicalHeight: 1180,
    );
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('pwm.pin_roles.MP03')),
      _pageScrollable(),
      const Offset(0, -200),
    );
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('pwm.pin_roles.P60')));
    await tester.pumpAndSettle();
    await _capture(
      tester,
      key,
      '02-friction-menu',
      logicalHeight: 1180,
      rects: {
        'p60': find.byKey(const ValueKey('pwm.pin_roles.P60')),
        'frictionItem': find.text('摩擦轮').last,
      },
    );
  });

  _gifTest('摩擦轮：扩展后的引脚角色', (tester) async {
    final key = await _pumpApp(
      tester,
      document: _frictionDocument(extended: true),
      step: 1,
      logicalHeight: 1180,
    );
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('pwm.pin_roles.MP03')),
      _pageScrollable(),
      const Offset(0, -200),
    );
    await _settle(tester);
    await _capture(
      tester,
      key,
      '02-friction-after',
      logicalHeight: 1180,
      rects: {
        'p60': find.byKey(const ValueKey('pwm.pin_roles.P60')),
        'p62': find.byKey(const ValueKey('pwm.pin_roles.P62')),
        'p74': find.byKey(const ValueKey('pwm.pin_roles.P74')),
        'p75': find.byKey(const ValueKey('pwm.pin_roles.P75')),
        'duty': find.text('满油 duty'),
      },
    );
  });

  _gifTest('带符号转速：正转与反转两行', (tester) async {
    final key = await _pumpApp(
      tester,
      document: _signedSpeedDocument(),
      step: 3,
      logicalHeight: 1000,
    );
    await _capture(
      tester,
      key,
      '03-signed-speed',
      logicalHeight: 1000,
      rects: {
        'row1': find.byKey(const ValueKey('demo-forward#0')),
        'row2': find.byKey(const ValueKey('demo-reverse#0')),
        'value1': find.byKey(const ValueKey('modes.0.actions.0.parameter')),
        'value2': find.byKey(const ValueKey('modes.0.actions.1.parameter')),
        'pin1': find.byKey(const ValueKey('modes.0.actions.0.pin')),
        'pin2': find.byKey(const ValueKey('modes.0.actions.1.pin')),
        'input1': find.byKey(const ValueKey('modes.0.actions.0.key')),
        'input2': find.byKey(const ValueKey('modes.0.actions.1.key')),
      },
    );
  });

  _gifTest('引脚备注：输入备注', (tester) async {
    final key = await _pumpApp(
      tester,
      document: _noteDocument(),
      step: 1,
      logicalHeight: 1180,
    );
    final field = find.byKey(const ValueKey('pwm.pin_notes.MP03'));
    await tester.dragUntilVisible(
      field,
      _pageScrollable(),
      const Offset(0, -200),
    );
    await _settle(tester);
    await _capture(
      tester,
      key,
      '04-notes-empty',
      logicalHeight: 1180,
      rects: {'note': field},
    );
    await tester.tap(field);
    await tester.pumpAndSettle();
    for (final text in ['工', '工程', '工程一', '工程一级', '工程一级舵', '工程一级舵机']) {
      await tester.enterText(field, text);
      await tester.pump();
      await _capture(
        tester,
        key,
        '04-notes-${text.length}',
        logicalHeight: 1180,
        rects: {'note': field},
      );
    }
    await tester.pumpAndSettle();
  });

  _gifTest('引脚备注：动作映射下拉显示备注', (tester) async {
    final key = await _pumpApp(
      tester,
      document: _noteDocument(note: '工程一级舵机'),
      step: 3,
      logicalHeight: 1000,
    );
    await _capture(
      tester,
      key,
      '04-notes-mapping-closed',
      logicalHeight: 1000,
      rects: {'pin': find.byKey(const ValueKey('modes.0.actions.0.pin'))},
    );
    await tester.tap(find.byKey(const ValueKey('modes.0.actions.0.pin')));
    await tester.pumpAndSettle();
    await _capture(
      tester,
      key,
      '04-notes-mapping-menu',
      logicalHeight: 1000,
      rects: {
        'pin': find.byKey(const ValueKey('modes.0.actions.0.pin')),
        'item': find.text('MP03（工程一级舵机）'),
      },
    );
  });
}
