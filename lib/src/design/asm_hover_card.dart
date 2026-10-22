import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../asm_glossary.dart';
import 'app_theme.dart';

/// 汇编字段的悬停说明卡片。
///
/// 卡片整体不接收指针事件：悬停说明只是补充阅读，不应该抢走编辑器上的
/// 选择与滚动，指针移到卡片上时等同于离开原字段。
class AsmHoverCard extends StatelessWidget {
  const AsmHoverCard({super.key, required this.token, required this.data});

  /// 代码里的原文，用于卡片抬头。
  final String token;

  final AsmHoverData data;

  static const double maxWidth = 380;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: ShapeDecoration(
        color: scheme.surfaceContainerHigh,
        shape: AppShape.md,
        shadows: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: .22),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  _displayToken,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'PieBlockMono',
                    color: scheme.primary,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: ShapeDecoration(
                  color: scheme.secondaryContainer,
                  shape: AppShape.xs,
                ),
                child: Text(
                  data.kindLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(data.title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            data.description,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
          ),
          if (data.detail != null) ...[
            const SizedBox(height: 6),
            Text(
              data.detail!,
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 列表前缀这类字段原文是一整行空白加机器码，压成单行再显示。
  String get _displayToken {
    final collapsed = token.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (collapsed.isEmpty) return data.title;
    return collapsed.length <= 48
        ? collapsed
        : '${collapsed.substring(0, 47)}…';
  }
}

/// 把卡片摆在字段旁边：优先放在下方，放不下就翻到上方，水平方向夹紧在
/// 可视范围内。[anchor] 是字段在屏幕上的矩形。
class AsmHoverCardLayout extends SingleChildLayoutDelegate {
  const AsmHoverCardLayout({
    required this.anchor,
    this.margin = 8,
    this.gap = 6,
  });

  final Rect anchor;
  final double margin;
  final double gap;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.min(
          AsmHoverCard.maxWidth,
          constraints.maxWidth - margin * 2,
        ),
        maxHeight: constraints.maxHeight - margin * 2,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final below = anchor.bottom + gap;
    final above = anchor.top - gap - childSize.height;
    final double y;
    if (below + childSize.height <= size.height - margin) {
      y = below;
    } else if (above >= margin) {
      y = above;
    } else {
      y = math.max(margin, size.height - margin - childSize.height);
    }
    final x = math.min(
      math.max(anchor.left, margin),
      math.max(margin, size.width - margin - childSize.width),
    );
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(AsmHoverCardLayout oldDelegate) =>
      oldDelegate.anchor != anchor ||
      oldDelegate.margin != margin ||
      oldDelegate.gap != gap;
}
