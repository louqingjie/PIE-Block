import 'package:material_ui/material_ui.dart';

import 'app_theme.dart';

/// 按下时轻微放大、松开时回弹。
///
/// 只改变绘制矩阵，不影响布局和命中测试；「减少动态效果」时瞬时完成。
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    this.enabled = true,
    this.scale = 1.03,
    required this.child,
  });

  final bool enabled;
  final double scale;
  final Widget child;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  var _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1,
        duration: AppMotion.fastSpatial(context),
        curve: AppMotion.expressiveFastSpatial,
        child: widget.child,
      ),
    );
  }
}
