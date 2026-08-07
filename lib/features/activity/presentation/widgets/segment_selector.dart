import 'package:flutter/material.dart';

import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/widgets/selection_pills.dart';

enum ActivitySegment {
  queue('Queue'),
  history('History'),
  blocklist('Blocklist');

  final String label;

  const ActivitySegment(this.label);
}

enum WantedSegment {
  missing('Missing'),
  cutoffUnmet('Cutoff Unmet');

  final String label;

  const WantedSegment(this.label);
}

/// The per-service Activity segment selector, pinned to the top of its scroll
/// view.
///
/// Now a thin sliver wrapper over [SelectionPills]. It used to be a
/// `SegmentedButton`, which meant the feature expressed one taxonomy through
/// three different controls — this, a second `SegmentedButton` on the global
/// screen, and a hand-rolled chip row beneath that one. Queue/History/Blocklist
/// is the same choice wherever it appears, so it now looks the same too.
///
/// The header's extent is **derived from the reading size** rather than constant.
/// Both `minExtent` and `maxExtent` used to be a flat `56.0` wrapped around a
/// control made of text, so at an accessibility reading size the label outgrew
/// the box and Flutter painted its overflow stripe across the selector — the
/// exact failure The Grown Box Rule exists to prevent, on a pinned header the
/// user cannot scroll away from.
class ActivitySegmentSelector<T extends Enum> extends StatelessWidget {
  /// Height at the default reading size: a 48pt pill plus its 8pt bottom gap.
  static const double _baseHeight = 56.0;

  /// The part of that height which scales — one `labelMedium` line.
  ///
  /// Unmoved by the type ramp, and checked rather than assumed: `SelectionPills`
  /// labels its pills `labelMedium`, a label role, and the app root's
  /// `DefaultTextHeightBehavior` keeps the new leading off a block's first
  /// ascent and last descent — so one line still measures what it always did.
  /// The pill is floored at its 48pt touch target anyway, which the label and
  /// its `sm` padding sit well inside, so 56 still clears both.
  static const double _labelHeight = 16.0;

  final List<T> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final String Function(T) labelBuilder;

  const ActivitySegmentSelector({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    required this.labelBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _ActivitySegmentHeaderDelegate<T>(
        // Resolved here, where there is a context: `minExtent` and `maxExtent` are
        // plain getters on the delegate and cannot read one themselves.
        extent: TextScaleMetrics.boxHeight(
          context,
          base: _baseHeight,
          textHeight: _labelHeight,
        ),
        segments: segments,
        selected: selected,
        onChanged: onChanged,
        labelBuilder: labelBuilder,
      ),
    );
  }
}

class _ActivitySegmentHeaderDelegate<T extends Enum>
    extends SliverPersistentHeaderDelegate {
  final double extent;
  final List<T> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final String Function(T) labelBuilder;

  const _ActivitySegmentHeaderDelegate({
    required this.extent,
    required this.segments,
    required this.selected,
    required this.onChanged,
    required this.labelBuilder,
  });

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      // Opaque on purpose: this header is pinned over scrolling content, so
      // without a surface of its own the rows would read through it.
      color: Theme.of(context).colorScheme.surface,
      child: SelectionPills<T>(
        values: segments,
        selected: selected,
        labelBuilder: labelBuilder,
        onSelected: onChanged,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _ActivitySegmentHeaderDelegate<T> oldDelegate) {
    return extent != oldDelegate.extent ||
        selected != oldDelegate.selected ||
        segments != oldDelegate.segments ||
        labelBuilder != oldDelegate.labelBuilder ||
        onChanged != oldDelegate.onChanged;
  }
}
