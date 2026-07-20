import 'package:flutter/material.dart';

/// A minimal filled sparkline for a single numeric series.
class Sparkline extends StatelessWidget {
  final List<double> values;
  final Color color;
  final double height;

  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.height = 40,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _SparklinePainter(values, color)),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _SparklinePainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var min = values.first;
    var max = values.first;
    for (final v in values) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    final range = (max - min).abs() < 1e-9 ? 1.0 : (max - min);
    final dx = size.width / (values.length - 1);

    double y(double v) => size.height - ((v - min) / range) * size.height;

    final path = Path()..moveTo(0, y(values.first));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(i * dx, y(values[i]));
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.15));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values || old.color != color;
}
