import 'package:material_ui/material_ui.dart';

/// 官方 W.PIE 学生创新实验室标识。
///
/// 浅色主题使用去除白底后的透明彩色原图，深色主题使用同形状的白色单通道
/// 版本；两套资源由官方标识生成，裁切与宽高比完全一致，切换主题时布局不会
/// 跳动，也不需要额外的底板来遮挡原图内部的白底留白。
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      dark
          ? 'assets/images/wpie-logo-dark.png'
          : 'assets/images/wpie-logo-light.png',
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      semanticLabel: semanticLabel,
    );
  }
}

/// 完整标识顶部裁出的 W.PIE 词标，用于高度受限的窄屏步骤栏。
///
/// 浅色 / 深色两套词标与完整标识使用同一份裁切结果，只改变颜色通道。
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      dark
          ? 'assets/images/wpie-wordmark-dark.png'
          : 'assets/images/wpie-wordmark-light.png',
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      semanticLabel: semanticLabel,
    );
  }
}
