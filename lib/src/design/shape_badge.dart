import 'package:material_ui/material_ui.dart'
    hide MaterialShapes, RoundedPolygon;
import 'package:material_new_shapes/material_new_shapes.dart';

final _shapePaths = Expando<Path>();

Path _pathOf(RoundedPolygon shape) => _shapePaths[shape] ??= shape.toPath();

/// 用 [MaterialShapes] 画一个装饰性形状底座。
///
/// M3E 要求抽象形状只用于装饰，不承载语义，因此这里默认排除读屏。
class ShapeBadge extends StatelessWidget {
  const ShapeBadge({
    super.key,
    required this.shape,
    required this.color,
    required this.size,
    this.rotation = 0,
    this.child,
  });

  final RoundedPolygon shape;
  final Color color;
  final double size;

  /// 只旋转形状本身，[child] 保持直立。
  final double rotation;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        painter: ShapePainter(
          path: _pathOf(shape),
          color: color,
          rotation: rotation,
        ),
        child: SizedBox.square(
          dimension: size,
          child: child == null ? null : Center(child: child),
        ),
      ),
    );
  }
}

/// [MaterialShapes] 归一化在单位正方形内，这里把它铺满目标尺寸。
class ShapePainter extends CustomPainter {
  const ShapePainter({
    required this.path,
    required this.color,
    this.rotation = 0,
  });

  final Path path;
  final Color color;
  final double rotation;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..rotate(rotation)
      ..scale(size.width, size.height)
      ..translate(-0.5, -0.5)
      ..drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(ShapePainter oldDelegate) =>
      oldDelegate.path != path ||
      oldDelegate.color != color ||
      oldDelegate.rotation != rotation;
}
