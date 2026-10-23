import 'package:material_ui/material_ui.dart';

import 'app_card.dart';

/// 官方 W.PIE 学生创新实验室标识。
///
/// 原图背景透明，但笔画内部保留了不透明白色留白；直接放到深色主题上会
/// 出现白斑，深灰色的「首都师范大学 / 学生创新实验室」也会看不清。因此
/// 标识始终放在纯白卡片上，白色留白与卡片融为一体，品牌配色保持原样。
class WpieLogo extends StatelessWidget {
  const WpieLogo({
    super.key,
    this.height = 96,
    this.semanticLabel = '首都师范大学学生创新实验室',
  });

  /// 图片显示高度；完整标识有三行文字，低于约 80 逻辑像素时最后一行会
  /// 难以辨认，需要更小时请改用 [WpieWordmark]。
  final double height;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      variant: AppCardVariant.hero,
      color: Colors.white,
      padding: EdgeInsets.all(height >= 80 ? 10 : 6),
      child: Image.asset(
        'assets/images/wpie-logo.png',
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        semanticLabel: semanticLabel,
      ),
    );
  }
}

/// 完整标识顶部裁出的 W.PIE 词标，用于高度受限的窄屏步骤栏。
///
/// 词标由 `assets/images/wpie-logo.png` 的顶部 W.PIE 区域合成白底后生成，
/// 完整标识仍然是 `assets/images/wpie-logo.png`；两者不是两套独立素材。
class WpieWordmark extends StatelessWidget {
  const WpieWordmark({
    super.key,
    this.height = 28,
    this.semanticLabel = 'W.PIE 标识',
  });

  final double height;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      variant: AppCardVariant.dense,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Image.asset(
        'assets/images/wpie-wordmark.png',
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        semanticLabel: semanticLabel,
      ),
    );
  }
}
