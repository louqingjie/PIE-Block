import 'package:material_ui/material_ui.dart';

import '../motion.dart';

/// 产品品牌色：欢迎页的青蓝与珊瑚粉。
///
/// 主题的 primary 由青蓝派生，secondary 由珊瑚粉派生，避免动态配色
/// 把主色旋转到与品牌无关的色相。
abstract final class AppBrand {
  static const cyan = Color(0xff02acc0);
  static const coral = Color(0xffef685d);
  static const onCyan = Color(0xff00363d);
  static const onCoral = Color(0xff3d0b08);
}

/// M3 Expressive 的十级圆角刻度。
///
/// 数值与 Material 3 的 corner radius scale 一致，避免各页面再自行写
/// 8 / 10 / 14 / 18 这类不一致的圆角。
abstract final class AppCorner {
  static const double none = 0;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double lgIncreased = 20;
  static const double xl = 28;
  static const double xlIncreased = 32;
  static const double xxl = 48;
  static const double full = 1000;
}

abstract final class AppRadius {
  static const BorderRadius none = BorderRadius.zero;
  static const BorderRadius xs = BorderRadius.all(
    Radius.circular(AppCorner.xs),
  );
  static const BorderRadius sm = BorderRadius.all(
    Radius.circular(AppCorner.sm),
  );
  static const BorderRadius md = BorderRadius.all(
    Radius.circular(AppCorner.md),
  );
  static const BorderRadius lg = BorderRadius.all(
    Radius.circular(AppCorner.lg),
  );
  static const BorderRadius xl = BorderRadius.all(
    Radius.circular(AppCorner.xl),
  );
  static const BorderRadius full = BorderRadius.all(
    Radius.circular(AppCorner.full),
  );

  static BorderRadius all(double corner) => BorderRadius.circular(corner);

  static BorderRadius top(double corner) =>
      BorderRadius.vertical(top: Radius.circular(corner));

  static BorderRadius vertical({
    double top = AppCorner.none,
    double bottom = AppCorner.none,
  }) => BorderRadius.vertical(
    top: Radius.circular(top),
    bottom: Radius.circular(bottom),
  );
}

/// 统一使用 FlClash 同款的连续曲率圆角。
///
/// M3 的 shape scale 只规定圆角尺寸，连续曲率属于准则允许的「自定义形状
/// 家族」，用于让大圆角看起来更软、更接近 M3E 的观感。
abstract final class AppShape {
  static const RoundedSuperellipseBorder none = RoundedSuperellipseBorder();
  static const RoundedSuperellipseBorder xs = RoundedSuperellipseBorder(
    borderRadius: AppRadius.xs,
  );
  static const RoundedSuperellipseBorder sm = RoundedSuperellipseBorder(
    borderRadius: AppRadius.sm,
  );
  static const RoundedSuperellipseBorder md = RoundedSuperellipseBorder(
    borderRadius: AppRadius.md,
  );
  static const RoundedSuperellipseBorder lg = RoundedSuperellipseBorder(
    borderRadius: AppRadius.lg,
  );
  static const RoundedSuperellipseBorder xl = RoundedSuperellipseBorder(
    borderRadius: AppRadius.xl,
  );
  static const RoundedSuperellipseBorder full = RoundedSuperellipseBorder(
    borderRadius: AppRadius.full,
  );
  static const CircleBorder circle = CircleBorder();

  static RoundedSuperellipseBorder all(double corner) =>
      RoundedSuperellipseBorder(borderRadius: AppRadius.all(corner));

  static RoundedSuperellipseBorder top(double corner) =>
      RoundedSuperellipseBorder(borderRadius: AppRadius.top(corner));

  static RoundedSuperellipseBorder of(BorderRadius borderRadius) =>
      RoundedSuperellipseBorder(borderRadius: borderRadius);
}

/// 表面层级：page → card → block → inset，越往里越亮（深色）或越深（浅色）。
enum AppSurface {
  page,
  card,
  block,
  inset;

  AppSurface get next => switch (this) {
    page => card,
    card => block,
    block || inset => inset,
  };

  Color colorOf(ColorScheme colorScheme) {
    final dark = colorScheme.brightness == Brightness.dark;
    return switch (this) {
      page => dark ? colorScheme.surface : colorScheme.surfaceContainer,
      card => dark ? colorScheme.surfaceContainer : colorScheme.surfaceBright,
      block =>
        dark ? colorScheme.surfaceContainerHigh : colorScheme.surfaceContainer,
      inset => colorScheme.surfaceContainerHighest,
    };
  }
}

/// M3E Web 换算表给出的曲线与时长。
///
/// Flutter 端 M3E 的 spring token 尚未内置，按官方 Web 换算表用曲线实现，
/// 并统一经 [m3Duration] 处理「减少动态效果」。
abstract final class AppMotion {
  static const Cubic expressiveFastSpatial = Cubic(0.42, 1.67, 0.21, 0.90);
  static const Cubic expressiveDefaultSpatial = Cubic(0.38, 1.21, 0.22, 1.00);
  static const Cubic expressiveFastEffects = Cubic(0.31, 0.94, 0.34, 1.00);
  static const Cubic expressiveDefaultEffects = Cubic(0.34, 0.80, 0.34, 1.00);
  static const Cubic standardFastSpatial = Cubic(0.27, 1.06, 0.18, 1.00);

  static const Duration fastSpatialDuration = Duration(milliseconds: 350);
  static const Duration defaultSpatialDuration = Duration(milliseconds: 500);
  static const Duration fastEffectsDuration = Duration(milliseconds: 150);
  static const Duration defaultEffectsDuration = Duration(milliseconds: 200);

  static Duration fastSpatial(BuildContext context) =>
      m3Duration(context, fastSpatialDuration);

  static Duration defaultSpatial(BuildContext context) =>
      m3Duration(context, defaultSpatialDuration);

  static Duration fastEffects(BuildContext context) =>
      m3Duration(context, fastEffectsDuration);

  static Duration defaultEffects(BuildContext context) =>
      m3Duration(context, defaultEffectsDuration);
}

/// M3E 的 emphasized 类型级在 Flutter 的 TextTheme 里没有直接对应项，
/// 用更重的字重和更紧的字距近似。
abstract final class AppText {
  static TextStyle _emphasized(TextStyle? base, FontWeight weight) =>
      (base ?? const TextStyle()).copyWith(fontWeight: weight);

  static TextStyle pageTitle(BuildContext context) => _emphasized(
    Theme.of(context).textTheme.headlineMedium,
    FontWeight.w800,
  ).copyWith(letterSpacing: -0.4);

  static TextStyle sectionTitle(BuildContext context) =>
      _emphasized(Theme.of(context).textTheme.titleLarge, FontWeight.w700);

  static TextStyle cardTitle(BuildContext context) =>
      _emphasized(Theme.of(context).textTheme.titleMedium, FontWeight.w700);

  static TextStyle cta(BuildContext context) =>
      _emphasized(Theme.of(context).textTheme.labelLarge, FontWeight.w700);

  static TextStyle count(BuildContext context) => _emphasized(
    Theme.of(context).textTheme.labelLarge,
    FontWeight.w700,
  ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  static TextStyle label(BuildContext context) =>
      Theme.of(context).textTheme.labelMedium ?? const TextStyle();

  static TextStyle body(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
}

/// M3 没有 warning / success 角色，这里给出成对的可访问色，替换裸
/// `Colors.orange` / `Colors.green`，保证深浅色下都有足够对比度。
abstract final class AppStatusColors {
  static Color ok(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0xff7fd99a)
      : const Color(0xff1b5e20);

  static Color okContainer(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xff17351f)
      : const Color(0xffd7f5dd);

  static Color onOkContainer(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xffd7f5dd)
      : const Color(0xff0b2e11);

  static Color warn(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0xffffb74d)
      : const Color(0xff8a4b00);

  static Color warnContainer(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xff3e2a00)
      : const Color(0xffffe0b2);

  static Color onWarnContainer(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xffffe0b2)
      : const Color(0xff2e1500);
}

/// 全局主题：把 M3E 的圆角、表面层级、按钮形变与进度配色一次性映射到
/// Material 组件主题，页面只负责内容，不再重复写 shape。
ThemeData buildAppTheme({
  required Brightness brightness,
  String? fontFamily,
  List<String>? fontFamilyFallback,
  Color? scaffoldBackgroundColor,
}) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppBrand.cyan,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    scaffoldBackgroundColor: scaffoldBackgroundColor,
  );

  OutlinedBorder buttonShape(Set<WidgetState> states) =>
      states.contains(WidgetState.pressed) ? AppShape.md : AppShape.full;

  const buttonAnimation = AppMotion.fastSpatialDuration;
  final buttonStyle = ButtonStyle(
    shape: WidgetStateProperty.resolveWith(buttonShape),
    animationDuration: buttonAnimation,
    tapTargetSize: MaterialTapTargetSize.padded,
  );

  return base.copyWith(
    appBarTheme: AppBarThemeData(
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: AppSurface.card.colorOf(colorScheme),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: AppShape.lg,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surfaceContainerHigh,
      elevation: 0,
      shape: AppShape.xl,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colorScheme.surfaceContainerLow,
      elevation: 0,
      shape: AppShape.top(AppCorner.xl),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colorScheme.inverseSurface,
      contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
      behavior: SnackBarBehavior.floating,
      shape: AppShape.sm,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: ShapeDecoration(
        color: colorScheme.inverseSurface,
        shape: AppShape.sm,
      ),
      textStyle: TextStyle(color: colorScheme.onInverseSurface),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colorScheme.surfaceContainerHigh,
      selectedColor: colorScheme.secondaryContainer,
      side: BorderSide.none,
      shape: AppShape.sm,
      labelStyle: base.textTheme.labelMedium,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colorScheme.surfaceContainerHigh,
      elevation: 2,
      shape: AppShape.md,
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(
          colorScheme.surfaceContainerHigh,
        ),
        shape: const WidgetStatePropertyAll(AppShape.md),
      ),
    ),
    bannerTheme: MaterialBannerThemeData(
      backgroundColor: colorScheme.errorContainer,
      contentTextStyle: TextStyle(color: colorScheme.onErrorContainer),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: AppRadius.md,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadius.md,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadius.md,
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
    textButtonTheme: TextButtonThemeData(style: buttonStyle),
    outlinedButtonTheme: OutlinedButtonThemeData(style: buttonStyle),
    elevatedButtonTheme: ElevatedButtonThemeData(style: buttonStyle),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(AppShape.circle),
        animationDuration: buttonAnimation,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 1,
      shape: AppShape.lg,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: AppSurface.block.colorOf(colorScheme),
      indicatorColor: colorScheme.secondaryContainer,
      indicatorShape: AppShape.full,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppSurface.block.colorOf(colorScheme),
      indicatorColor: colorScheme.secondaryContainer,
      indicatorShape: AppShape.full,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colorScheme.primary,
      linearTrackColor: colorScheme.secondaryContainer,
      borderRadius: AppRadius.full,
    ),
    listTileTheme: ListTileThemeData(shape: AppShape.md, minTileHeight: 48),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colorScheme.primary
            : colorScheme.surfaceContainerHighest,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
  );
}
