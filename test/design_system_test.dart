import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart'
    hide MaterialShapes, RoundedPolygon;
import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:pieblock_app/src/design/app_card.dart';
import 'package:pieblock_app/src/design/app_theme.dart';
import 'package:pieblock_app/src/design/connected_button_group.dart';
import 'package:pieblock_app/src/design/press_scale.dart';
import 'package:pieblock_app/src/design/shape_badge.dart';
import 'package:pieblock_app/src/design/wavy_progress_indicator.dart';

void main() {
  test('AppCorner 使用 M3E 十级圆角刻度', () {
    expect(
      [
        AppCorner.none,
        AppCorner.xs,
        AppCorner.sm,
        AppCorner.md,
        AppCorner.lg,
        AppCorner.lgIncreased,
        AppCorner.xl,
        AppCorner.xlIncreased,
        AppCorner.xxl,
      ],
      [0, 4, 8, 12, 16, 20, 28, 32, 48],
    );
  });

  test('主题把圆角、对话框和按钮形变映射到组件', () {
    final theme = buildAppTheme(brightness: Brightness.dark);
    final cardShape = theme.cardTheme.shape! as RoundedSuperellipseBorder;
    expect(
      cardShape.borderRadius.resolve(TextDirection.ltr).topLeft.x,
      AppCorner.lg,
    );
    final dialogShape = theme.dialogTheme.shape! as RoundedSuperellipseBorder;
    expect(
      dialogShape.borderRadius.resolve(TextDirection.ltr).topLeft.x,
      AppCorner.xl,
    );
    final buttonStyle = theme.filledButtonTheme.style!;
    final rest =
        buttonStyle.shape!.resolve(<WidgetState>{})!
            as RoundedSuperellipseBorder;
    final pressed =
        buttonStyle.shape!.resolve(<WidgetState>{WidgetState.pressed})!
            as RoundedSuperellipseBorder;
    expect(
      rest.borderRadius.resolve(TextDirection.ltr).topLeft.x,
      AppCorner.full,
    );
    expect(
      pressed.borderRadius.resolve(TextDirection.ltr).topLeft.x,
      AppCorner.md,
    );
    expect(buttonStyle.animationDuration, AppMotion.fastSpatialDuration);
  });

  testWidgets('ConnectedButtonGroup 点击后回调新选择', (tester) async {
    var value = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(brightness: Brightness.dark),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: ConnectedButtonGroup<int>(
                segments: const [
                  ConnectedSegment(value: 0, label: '规则', icon: Icons.rule),
                  ConnectedSegment(value: 1, label: '全局', icon: Icons.language),
                ],
                value: value,
                onChanged: (next) => value = next,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('全局'));
    await tester.pump();
    expect(value, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('WavyProgressIndicator 提供百分比语义', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(brightness: Brightness.dark),
        home: const Scaffold(
          body: SizedBox(
            width: 300,
            child: WavyProgressIndicator(value: .47, semanticLabel: '烧录进度'),
          ),
        ),
      ),
    );
    final node = tester.getSemantics(find.byType(WavyProgressIndicator));
    expect(node.value, '47%');
    semantics.dispose();
  });

  testWidgets('减少动态效果时 WavyProgressIndicator 不启动无限动画', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(brightness: Brightness.dark),
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: SizedBox(
              width: 300,
              child: WavyProgressIndicator(semanticLabel: '编译进度'),
            ),
          ),
        ),
      ),
    );
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('PressScale 按下时把缩放目标切到 1.03', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(brightness: Brightness.dark),
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Center(
              child: PressScale(child: SizedBox.square(dimension: 80)),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PressScale)),
    );
    await tester.pump();
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      1.03,
    );
    await gesture.up();
  });

  testWidgets('AppCard 英雄变体使用 Extra large 圆角', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(brightness: Brightness.dark),
        home: const Scaffold(
          body: AppCard(
            variant: AppCardVariant.hero,
            child: SizedBox(width: 200, height: 100),
          ),
        ),
      ),
    );
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(AppCard),
        matching: find.byType(Container),
      ),
    );
    final shape = (container.decoration! as ShapeDecoration).shape;
    final radius = (shape as RoundedSuperellipseBorder).borderRadius.resolve(
      TextDirection.ltr,
    );
    expect(radius.topLeft.x, AppCorner.xl);
  });

  testWidgets('ShapeBadge 绘制装饰形状但不进入语义树', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(brightness: Brightness.dark),
        home: Scaffold(
          body: ShapeBadge(
            shape: MaterialShapes.cookie6Sided,
            color: const Color(0xff02acc0),
            size: 56,
          ),
        ),
      ),
    );
    expect(find.byType(ShapeBadge), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('.')), findsNothing);
    semantics.dispose();
  });
}
