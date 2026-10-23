import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// M3 Expressive 的波浪线性进度条。
///
/// [value] 为 null 时是不确定进度；否则按 determinate 绘制波浪、平轨和
/// 末端 4dp stop 圆点。
///
/// 波形相位由时间驱动，与 [value] 无关：即使进度停在原地，波峰也会继续
/// 向右流动（一个波长每秒，对齐 M3E 的默认波速），只有填充长度受 [value]
/// 控制。这样单个文件编译耗时较长时，进度条不会看起来像卡死。系统开启
/// 「减少动态效果」时相位冻结。
class WavyProgressIndicator extends StatefulWidget {
  const WavyProgressIndicator({
    super.key,
    this.value,
    this.semanticLabel,
    this.color,
    this.trackColor,
    this.height = 16,
  });

  final double? value;
  final String? semanticLabel;
  final Color? color;
  final Color? trackColor;
  final double height;

  @override
  State<WavyProgressIndicator> createState() => _WavyProgressIndicatorState();
}

class _WavyProgressIndicatorState extends State<WavyProgressIndicator>
    with SingleTickerProviderStateMixin {
  /// 一个波长走一秒，对齐 M3E 的默认波速（waveSpeed = wavelength）。
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );
  var _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncAnimation();
  }

  @override
  void didUpdateWidget(WavyProgressIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _syncAnimation();
  }

  /// 动画只跟「能不能动」有关，不跟进度值有关：determinate 也要持续流动，
  /// 否则进度停在同一格时整条进度条会静止。跑满时振幅已收敛为平线，没有
  /// 继续重绘的必要。
  void _syncAnimation() {
    if (_reduceMotion || widget.value == 1) {
      // 保留当前相位，避免定格瞬间跳一下。
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = widget.value?.clamp(0.0, 1.0);
    final semanticsValue = value == null ? null : '${(value * 100).round()}%';
    return Semantics(
      label: widget.semanticLabel,
      value: semanticsValue,
      child: ExcludeSemantics(
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => CustomPaint(
              painter: _WavyProgressPainter(
                value: value,
                phase: _controller.value,
                active: widget.color ?? scheme.primary,
                track: widget.trackColor ?? scheme.secondaryContainer,
                rtl: Directionality.of(context) == TextDirection.rtl,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WavyProgressPainter extends CustomPainter {
  const _WavyProgressPainter({
    required this.value,
    required this.phase,
    required this.active,
    required this.track,
    required this.rtl,
  });

  static const _stroke = 4.0;
  static const _amplitude = 3.0;
  static const _wavelength = 12.0;
  static const _gap = 6.0;
  static const _stop = 4.0;
  static const _inset = 4.0;
  static const _tau = 2 * math.pi;

  final double? value;

  /// 0..1 的相位，随时间线性推进，走完一圈等于一个波长。
  final double phase;
  final Color active;
  final Color track;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= _inset * 2) return;
    canvas.save();
    if (rtl) {
      canvas
        ..translate(size.width, 0)
        ..scale(-1, 1);
    }
    final start = _inset;
    final end = size.width - _inset;
    final mid = size.height / 2;
    final paint = Paint()
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final value = this.value;
    if (value != null) {
      _paintDeterminate(canvas, start, end, mid, value, paint);
    } else {
      _paintIndeterminate(canvas, start, end, mid, paint);
    }
    canvas.restore();
  }

  void _paintDeterminate(
    Canvas canvas,
    double start,
    double end,
    double mid,
    double value,
    Paint paint,
  ) {
    final split = start + (end - start) * value;
    if (value > 0) {
      canvas.drawPath(
        _wave(start, split, mid, _amplitude * _amplitudeRamp(value)),
        paint..color = active,
      );
    }
    final trackStart = value > 0 ? split + _gap : start;
    if (trackStart < end - _stop - _gap) {
      canvas.drawLine(
        Offset(trackStart, mid),
        Offset(end - _stop - _gap, mid),
        paint..color = track,
      );
    }
    if (value < 1) {
      canvas.drawCircle(
        Offset(end - _stop / 2, mid),
        _stop / 2,
        Paint()..color = active,
      );
    }
  }

  void _paintIndeterminate(
    Canvas canvas,
    double start,
    double end,
    double mid,
    Paint paint,
  ) {
    final span = (end - start) * .35;
    final travel = end - start + span;
    final head = start - span + travel * phase;
    final segmentStart = math.max(start, head);
    final segmentEnd = math.min(end, head + span);
    canvas.drawLine(Offset(start, mid), Offset(end, mid), paint..color = track);
    if (segmentEnd > segmentStart) {
      canvas.drawPath(
        _wave(segmentStart, segmentEnd, mid, _amplitude),
        paint..color = active,
      );
    }
  }

  /// M3E 的振幅在两端收敛到 0：10% 之前和 95% 之后是平线，中间才是满振幅。
  /// 参考实现按时间对振幅做缓动，这里按进度线性过渡，观感一致且不必额外
  /// 维护动画状态。
  double _amplitudeRamp(double value) {
    const edge = .05;
    if (value <= .1 || value >= .95) return 0;
    if (value < .1 + edge) return (value - .1) / edge;
    if (value > .95 - edge) return (.95 - value) / edge;
    return 1;
  }

  /// 行波：波形锚定在 [start]，相位随时间推进。填充变长时波峰不会跟着
  /// 拉伸，只是右侧不断延伸；进度停住时波峰继续向右流动。
  Path _wave(double start, double end, double mid, double amplitude) {
    final path = Path();
    if (amplitude <= 0) {
      return path
        ..moveTo(start, mid)
        ..lineTo(end, mid);
    }
    path.moveTo(start, mid + amplitude * _sine(0));
    for (var x = start + 1; x < end; x += 1) {
      path.lineTo(x, mid + amplitude * _sine(x - start));
    }
    return path..lineTo(end, mid + amplitude * _sine(end - start));
  }

  /// `sin(kx - ωt)`：相位越大，波峰越靠右。
  double _sine(double distance) =>
      math.sin(distance / _wavelength * _tau - phase * _tau);

  @override
  bool shouldRepaint(_WavyProgressPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.phase != phase ||
      oldDelegate.active != active ||
      oldDelegate.track != track ||
      oldDelegate.rtl != rtl;
}
