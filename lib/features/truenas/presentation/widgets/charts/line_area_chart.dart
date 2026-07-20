import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// One named series for [LineAreaChart].
class ChartSeries {
  final String label;
  final Color color;

  /// Points as (x, y). x is typically a timestamp; only relative order matters.
  final List<Offset> points;

  const ChartSeries({
    required this.label,
    required this.color,
    required this.points,
  });
}

/// A multi-series line chart with a light grid and a legend. Values are
/// normalized across all series to a shared y-range.
class LineAreaChart extends StatelessWidget {
  final List<ChartSeries> series;
  final String Function(double value)? valueFormatter;
  final double height;

  const LineAreaChart({
    super.key,
    required this.series,
    this.valueFormatter,
    this.height = 180,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasData = series.any((s) => s.points.length > 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: hasData
              ? CustomPaint(
                  painter: _LineChartPainter(
                    series: series,
                    gridColor: colorScheme.outlineVariant.withValues(
                      alpha: 0.4,
                    ),
                    labelColor: colorScheme.onSurfaceVariant,
                    valueFormatter: valueFormatter,
                    textDirection: Directionality.of(context),
                  ),
                )
              : Center(
                  child: Text(
                    'No data',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final s in series)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: s.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(s.label, style: theme.textTheme.labelSmall),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<ChartSeries> series;
  final Color gridColor;
  final Color labelColor;
  final String Function(double value)? valueFormatter;
  final TextDirection textDirection;

  _LineChartPainter({
    required this.series,
    required this.gridColor,
    required this.labelColor,
    required this.valueFormatter,
    required this.textDirection,
  });

  @override
  void paint(Canvas canvas, Size size) {
    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final s in series) {
      for (final p in s.points) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dy > maxY) maxY = p.dy;
      }
    }
    if (!minX.isFinite || !maxX.isFinite) return;
    if (minY == maxY) {
      maxY += 1;
      minY -= 1;
    }
    final rangeX = (maxX - minX).abs() < 1e-9 ? 1.0 : (maxX - minX);
    final rangeY = (maxY - minY).abs() < 1e-9 ? 1.0 : (maxY - minY);

    const leftPad = 44.0;
    const bottomPad = 4.0;
    final plotW = size.width - leftPad;
    final plotH = size.height - bottomPad;

    // Horizontal grid + y-axis labels (4 divisions).
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = plotH * i / 4;
      canvas.drawLine(Offset(leftPad, y), Offset(size.width, y), gridPaint);
      final value = maxY - rangeY * i / 4;
      final label = valueFormatter?.call(value) ?? value.toStringAsFixed(0);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: labelColor, fontSize: 10),
        ),
        textDirection: textDirection,
      )..layout(maxWidth: leftPad - 4);
      tp.paint(canvas, Offset(leftPad - tp.width - 4, y - tp.height / 2));
    }

    double px(double x) => leftPad + ((x - minX) / rangeX) * plotW;
    double py(double y) => ((maxY - y) / rangeY) * plotH;

    for (final s in series) {
      if (s.points.length < 2) continue;
      final path = Path()..moveTo(px(s.points.first.dx), py(s.points.first.dy));
      for (var i = 1; i < s.points.length; i++) {
        path.lineTo(px(s.points[i].dx), py(s.points[i].dy));
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = s.color,
      );
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.gridColor != gridColor ||
      old.labelColor != labelColor ||
      !_seriesEquals(old.series, series);

  /// Content comparison of two series lists: reference equality would repaint
  /// on every rebuild since a fresh list is built each time.
  static bool _seriesEquals(List<ChartSeries> a, List<ChartSeries> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].label != b[i].label ||
          a[i].color != b[i].color ||
          !listEquals(a[i].points, b[i].points)) {
        return false;
      }
    }
    return true;
  }
}
