import 'dart:ui' show lerpDouble;

import 'package:material_ui/material_ui.dart';

import 'app_theme.dart';

class ConnectedSegment<T> {
  const ConnectedSegment({
    required this.value,
    required this.label,
    this.icon,
    this.tooltip,
    this.enabled = true,
  });

  final T value;
  final String label;
  final IconData? icon;
  final String? tooltip;
  final bool enabled;
}

/// M3 Expressive 的 connected button group：外圈全圆、内圈按尺寸收紧，
/// 选中项在组内形变为完整胶囊。
///
/// 尺寸取 M3E 的 small 档：按钮 40 + 上下各 2dp 内边距 = 44；内圈圆角 8、
/// 图标 20 都与该档位对齐。容器比按钮高 4dp，不能写成 48，否则内部按钮
/// 会变成 44 这种规范里不存在的档位。
class ConnectedButtonGroup<T> extends StatelessWidget {
  const ConnectedButtonGroup({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.height = 44,
    this.innerRadius = AppCorner.sm,
    this.semanticLabel,
  });

  final List<ConnectedSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final double height;
  final double innerRadius;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final base = AppSurface.block.colorOf(scheme);
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Container(
        height: height,
        padding: const EdgeInsets.all(2),
        decoration: ShapeDecoration(color: base, shape: AppShape.full),
        child: Row(
          // 必须撑满：默认 center 会让每段按图标/文字的固有高度收缩，
          // 选中胶囊就只有 20dp 高，浮在组里、与容器边缘疏密不均。
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, segment) in segments.indexed)
              Expanded(
                child: _ConnectedSegmentButton<T>(
                  segment: segment,
                  selected: segment.value == value,
                  first: index == 0,
                  last: index == segments.length - 1,
                  innerRadius: innerRadius,
                  rtl: rtl,
                  base: base,
                  onTap: segment.enabled && segment.value != value
                      ? () => onChanged(segment.value)
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ConnectedSegmentButton<T> extends StatelessWidget {
  const _ConnectedSegmentButton({
    required this.segment,
    required this.selected,
    required this.first,
    required this.last,
    required this.innerRadius,
    required this.rtl,
    required this.base,
    required this.onTap,
  });

  final ConnectedSegment<T> segment;
  final bool selected;
  final bool first;
  final bool last;
  final double innerRadius;
  final bool rtl;
  final Color base;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final startRest = first ? AppCorner.full : innerRadius;
    final endRest = last ? AppCorner.full : innerRadius;
    final foreground = selected
        ? scheme.onPrimary
        : segment.enabled
        ? scheme.onSurfaceVariant
        : scheme.onSurface.withValues(alpha: .38);
    final content = _label(context, foreground);
    return Semantics(
      button: true,
      selected: selected,
      enabled: segment.enabled,
      inMutuallyExclusiveGroup: true,
      label: segment.label,
      excludeSemantics: true,
      child: Tooltip(
        message: segment.tooltip ?? segment.label,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: selected ? 1 : 0),
          duration: AppMotion.fastSpatial(context),
          curve: AppMotion.expressiveFastSpatial,
          builder: (context, amount, child) {
            final start = lerpDouble(startRest, AppCorner.full, amount)!;
            final end = lerpDouble(endRest, AppCorner.full, amount)!;
            final shape = AppShape.of(
              BorderRadius.horizontal(
                left: Radius.circular(rtl ? end : start),
                right: Radius.circular(rtl ? start : end),
              ),
            );
            return Container(
              clipBehavior: Clip.antiAlias,
              decoration: ShapeDecoration(
                color: Color.lerp(base, scheme.primary, amount),
                shape: shape,
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  customBorder: shape,
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: Colors.transparent,
                  onTap: onTap,
                  child: child,
                ),
              ),
            );
          },
          child: content,
        ),
      ),
    );
  }

  Widget _label(BuildContext context, Color foreground) {
    final text = Text(
      segment.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppText.cta(context).copyWith(color: foreground),
    );
    final icon = segment.icon;
    if (icon == null) {
      return Center(child: text);
    }
    if (segment.label.isEmpty) {
      return Center(
        child: Icon(icon, size: AppButton.iconSize, color: foreground),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 6,
        children: [
          Icon(icon, size: AppButton.iconSize, color: foreground),
          Flexible(child: text),
        ],
      ),
    );
  }
}
