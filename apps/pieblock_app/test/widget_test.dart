import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pieblock_app/main.dart';
import 'package:pieblock_app/src/controller.dart';
import 'package:pieblock_app/src/home_screen.dart';
import 'package:pieblock_app/src/wizard_screen.dart';
import 'package:pieblock_core/pieblock_core.dart';

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
    document: ProjectDocument.create('步兵测试', ProjectKind.infantry),
    step: 2,
    maxVisitedStep: 2,
    saveStatus: SaveStatus.saved,
  );
}

class _InfantryMechanismController extends AppController {
  @override
  AppState build() => AppState(
    document: ProjectDocument.create('步兵测试', ProjectKind.infantry),
    step: 1,
    maxVisitedStep: 1,
    saveStatus: SaveStatus.saved,
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

  testWidgets('步兵向导为五步且配置页不显示主题按钮', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(_InfantryStartController.new),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 / 5'), findsOneWidget);
    expect(find.text('PWM 与引脚'), findsNothing);
    expect(find.byTooltip('切换主题'), findsNothing);
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
    expect(find.text('1 / 5'), findsOneWidget);
    expect(find.textContaining('请修正标红的配置'), findsOneWidget);
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

  testWidgets('步兵拨弹引脚菜单排除固定摩擦轮口', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(_InfantryMechanismController.new),
        ],
        child: const MaterialApp(home: WizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final feeder = find.byType(DropdownButtonFormField<String>).first;
    await tester.ensureVisible(feeder);
    await tester.tap(feeder);
    await tester.pumpAndSettle();
    expect(find.text('P64'), findsNothing);
    expect(find.text('P66'), findsNothing);
  });

  testWidgets('向导在三种桌面尺寸和双主题下无布局异常', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    for (final size in const [
      Size(1600, 900),
      Size(1280, 720),
      Size(1100, 700),
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
}
