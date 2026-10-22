import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// M3 Expressive 的波浪线性进度条。
///
/// [value] 为 null 时是不确定进度；否则按 determinate 绘制波浪、平轨和
/// 末端 4dp stop 圆点。
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
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
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

  void _syncAnimation() {
    final animate = widget.value == null && !_reduceMotion;
    if (animate) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = .5;
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

  final double? value;
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
      canvas.drawPath(_wave(start, split, mid), paint..color = active);
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
        _wave(segmentStart, segmentEnd, mid),
        paint..color = active,
      );
    }
  }

  Path _wave(double start, double end, double mid) {
    final path = Path()..moveTo(start, mid);
    for (var x = start; x <= end; x += 1) {
      path.lineTo(
        x,
        mid + _amplitude * math.sin((x - start) / _wavelength * 2 * math.pi),
      );
    }
    return path;
  }

  @override
  bool shouldRepaint(_WavyProgressPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.phase != phase ||
      oldDelegate.active != active ||
      oldDelegate.track != track ||
      oldDelegate.rtl != rtl;
}
