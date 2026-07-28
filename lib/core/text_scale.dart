import 'package:flutter/widgets.dart';

/// Helpers for laying out fixed-size boxes that contain scalable text.
///
/// A hard-coded height around a `Text` is the most common Dynamic Type bug in
/// this app's shape of UI: the poster rails, KPI cards and status cards all
/// pair a fixed-size image with one or two lines of label. At the default
/// reading size the constant fits; at an accessibility size the label overflows
/// and Flutter paints its overflow stripe over the content.
///
/// Rather than remove the constants — the image half genuinely is fixed — grow
/// the box by exactly the amount the text grew.
class TextScaleMetrics {
  TextScaleMetrics._();

  /// Ceiling applied when growing a compact box.
  ///
  /// Compact chrome (a 96pt-wide poster tile) cannot usefully track an
  /// accessibility scale of 3x; past this the label ellipsises instead, which is
  /// still legible and still not clipped.
  static const double defaultMaxScaleFactor = 1.6;

  /// The reading scale used for compact boxes, clamped to
  /// [defaultMaxScaleFactor].
  static TextScaler clampedScalerOf(
    BuildContext context, {
    double maxScaleFactor = defaultMaxScaleFactor,
  }) => MediaQuery.textScalerOf(context).clamp(maxScaleFactor: maxScaleFactor);

  /// Height for a box whose [base] height includes [textHeight] worth of text at
  /// the default reading size.
  ///
  /// Returns [base] plus however much that text grew, so the fixed part (an
  /// image, a chart) keeps its size while the label gets the room it needs.
  ///
  /// ```dart
  /// // 138pt poster + 4pt gap + ~34pt of title/subtitle
  /// height: TextScaleMetrics.boxHeight(context, base: 176, textHeight: 34)
  /// ```
  static double boxHeight(
    BuildContext context, {
    required double base,
    required double textHeight,
    double maxScaleFactor = defaultMaxScaleFactor,
  }) {
    final scaler = clampedScalerOf(context, maxScaleFactor: maxScaleFactor);
    final grown = scaler.scale(textHeight);
    final delta = grown - textHeight;
    return delta > 0 ? base + delta : base;
  }
}
