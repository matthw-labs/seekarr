import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:seekarr/core/theme.dart';

/// A 270° radial gauge for a single 0..1 value (e.g. CPU load, pool usage).
class RadialGauge extends StatelessWidget {
  final double value;
  final String valueLabel;
  final String caption;
  final Color color;
  final double size;

  const RadialGauge({
    super.key,
    required this.value,
    required this.valueLabel,
    required this.caption,
    required this.color,
    this.size = 120,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RadialGaugePainter(
          value: value.clamp(0, 1).toDouble(),
          color: color,
          trackColor: colorScheme.surfaceContainerHighest,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                valueLabel,
                style: theme.textTheme.titleLarge!
                    .weight(FontWeight.w700)
                    .tabular,
              ),
              Text(
                caption,
                // The caption carries a reading too (used memory, load
                // window), so it gets the same locked digits as the value.
                style: theme.textTheme.labelSmall!.tabular.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadialGaugePainter extends CustomPainter {
  final double value;
  final Color color;
  final Color trackColor;

  _RadialGaugePainter({
    required this.value,
    required this.color,
    required this.trackColor,
  });

  static const double _startAngle = math.pi * 0.75; // 135°
  static const double _sweep = math.pi * 1.5; // 270°

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (math.min(size.width, size.height) - stroke) / 2;
    final arcRect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawArc(arcRect, _startAngle, _sweep, false, trackPaint);

    final valuePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(arcRect, _startAngle, _sweep * value, false, valuePaint);
  }

  @override
  bool shouldRepaint(_RadialGaugePainter old) =>
      old.value != value || old.color != color || old.trackColor != trackColor;
}
