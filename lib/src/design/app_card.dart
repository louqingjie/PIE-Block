import 'package:material_ui/material_ui.dart';

import 'app_theme.dart';

enum AppCardVariant {
  /// 信息密集的表单 / 列表容器，停在 M3 的 Large 级。
  dense,

  /// 首页动作卡等稀疏的英雄容器，可用 Extra large。
  hero,

  /// 卡片内部的嵌套块，按「外圆角 − 内边距」取内圆角。
  block,
}

/// M3E 语气的内容容器：用表面色调而不是描边分层。
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    this.variant = AppCardVariant.dense,
    this.padding = const EdgeInsets.all(24),
    this.color,
    this.onTap,
    this.semanticLabel,
    this.clipBehavior = Clip.none,
    required this.child,
  });

  final AppCardVariant variant;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final Clip clipBehavior;
  final Widget child;

  double get radius => switch (variant) {
    AppCardVariant.dense => AppCorner.lg,
    AppCardVariant.hero => AppCorner.xl,
    AppCardVariant.block => AppCorner.md,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = AppShape.all(radius);
    final fill =
        color ??
        (variant == AppCardVariant.block
            ? AppSurface.block.colorOf(scheme)
            : AppSurface.card.colorOf(scheme));
    final content = Padding(padding: padding, child: child);
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Container(
        clipBehavior: clipBehavior,
        decoration: ShapeDecoration(color: fill, shape: shape),
        child: Material(
          type: MaterialType.transparency,
          child: onTap == null
              ? content
              : InkWell(customBorder: shape, onTap: onTap, child: content),
        ),
      ),
    );
  }
}
