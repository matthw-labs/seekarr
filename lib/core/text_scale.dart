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

  /// Ceiling for compact chrome that must stay on one line.
  ///
  /// A strip of pills with connectors between them, or a bar of destinations,
  /// cannot reflow: past a point the only options are to clip or to elide, and
  /// eliding a two-word label destroys it. So this kind of chrome follows the
  /// reading size to 1.3× and stops — the value the floating navigation bar has
  /// always used, promoted to a token now that the import station bar needs the
  /// same guarantee.
  static const double singleLineChromeMaxScaleFactor = 1.3;

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

  /// Share of a grid cell's height that is text, used by [aspectRatio].
  ///
  /// The tiles this is applied to are an icon, a label and a value line: most of
  /// the height moves with the reading size, but not all of it.
  static const double _textShareOfCell = 0.7;

  /// A `childAspectRatio` that grows the cell taller as text grows.
  ///
  /// `GridView`'s ratio is fixed while its labels are not, so a tile tuned at
  /// the default reading size clips its own text at an accessibility size.
  /// Lowering the ratio makes each cell taller by roughly the amount the text
  /// gained.
  static double aspectRatio(
    BuildContext context, {
    required double base,
    double maxScaleFactor = defaultMaxScaleFactor,
  }) {
    final scaler = clampedScalerOf(context, maxScaleFactor: maxScaleFactor);
    // Growth of one body line, relative to its unscaled size.
    final growth = scaler.scale(14.0) / 14.0;
    if (growth <= 1) return base;
    return base / (1 + ((growth - 1) * _textShareOfCell));
  }
}
