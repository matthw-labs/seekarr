import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_elevation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/reel_motion.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/reel_line.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';

/// A premium horizontal rail of KPI "stat cards" shown at the top of a service
/// page. Replaces the ad-hoc per-service stat rows with one shared component.
///
/// Feed it an [AsyncValue] of KPIs; it renders a shimmer rail while loading and
/// collapses to nothing on error or when there are no metrics (KPIs are
/// supplementary — they should never show an error state of their own).
class ServiceKpiPeek extends StatelessWidget {
  final AsyncValue<List<ServiceKpi>> kpis;

  /// Service accent used for values/icons when a KPI doesn't override it.
  final Color accent;

  final EdgeInsetsGeometry padding;

  const ServiceKpiPeek({
    super.key,
    required this.kpis,
    required this.accent,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.xs,
      AppSpacing.lg,
      AppSpacing.md,
    ),
  });

  static const double _height = 78;

  @override
  Widget build(BuildContext context) {
    // The card is all text (a value line and a label line), so the rail has to
    // follow the reading size or both get clipped.
    //
    // `textHeight` is the share of [_height] that is text, and it survived the
    // type ramp's new per-role leading untouched: the root
    // `DefaultTextHeightBehavior` keeps a text block's outer edges on Inter's
    // natural metrics, so leading only opens the gaps *between* lines and a
    // single line measures exactly what it always did. Both lines here are
    // single lines. Re-derive this only if the card gains wrapping text.
    final railHeight = TextScaleMetrics.boxHeight(
      context,
      base: _height,
      textHeight: 34,
    );
    return kpis.when(
      loading: () => _rail(
        context: context,
        height: railHeight,
        children: List.generate(4, (_) => const _KpiSkeletonCard()),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return _rail(
          context: context,
          height: railHeight,
          children: [
            for (final kpi in items) _KpiCard(kpi: kpi, fallbackAccent: accent),
          ],
        );
      },
    );
  }

  Widget _rail({
    required BuildContext context,
    required List<Widget> children,
    required double height,
  }) {
    return SizedBox(
      height: height,
      // The grown box and the clamped scaler are one mechanism. [boxHeight]
      // stops growing at `TextScaleMetrics.defaultMaxScaleFactor`, so the cards
      // have to *paint* at that same ceiling — otherwise the rail is frozen at
      // 1.6x while the text keeps growing, which measured a real
      // `RenderFlex overflowed by 32 pixels` at a 3.0x reading size on every
      // service dashboard.
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaleMetrics.clampedScalerOf(context)),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: padding,
          itemCount: children.length,
          separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (_, index) => children[index],
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final ServiceKpi kpi;
  final Color fallbackAccent;

  const _KpiCard({required this.kpi, required this.fallbackAccent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = kpi.accent ?? fallbackAccent;

    final card = Container(
      constraints: const BoxConstraints(minWidth: 92),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: AppElevation.level1(colorScheme),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(kpi.icon, size: 14, color: accent),
              const SizedBox(width: AppSpacing.xs),
              // The instrument readout, and the one number on a dashboard that
              // is worth watching change — a library total ticking up after an
              // import, a queue count draining. Safe to roll because the card is
              // `minWidth`, not a fixed width, inside a horizontally scrolling
              // rail: a wider value makes the card wider instead of overflowing,
              // and no ellipsis is being relied on here to save it.
              ReelLine(
                kpi.value,
                options: ReelMotion.figure,
                style: theme.textTheme.titleMedium!
                    .weight(FontWeight.w800)
                    .tabular
                    .copyWith(color: colorScheme.onSurface, height: 1.1),
                fallbackMaxLines: 1,
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            kpi.label.toUpperCase(),
            maxLines: 1,
            style: AppTheme.eyebrow(colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );

    if (kpi.onTap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: AppRadius.borderRadiusMd,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          kpi.onTap!();
        },
        borderRadius: AppRadius.borderRadiusMd,
        child: card,
      ),
    );
  }
}

class _KpiSkeletonCard extends StatelessWidget {
  const _KpiSkeletonCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 100,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerPlaceholder.text(width: 44, height: 16),
          const SizedBox(height: 6),
          ShimmerPlaceholder.text(width: 64, height: 9),
        ],
      ),
    );
  }
}
