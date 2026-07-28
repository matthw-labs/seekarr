import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_elevation.dart';
import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/models/service_kpi.dart';
import 'package:seekarr/core/text_scale.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/shimmer_placeholder.dart';

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
    final railHeight = TextScaleMetrics.boxHeight(
      context,
      base: _height,
      textHeight: 34,
    );
    return kpis.when(
      loading: () => _rail(
        height: railHeight,
        children: List.generate(4, (_) => const _KpiSkeletonCard()),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return _rail(
          height: railHeight,
          children: [
            for (final kpi in items) _KpiCard(kpi: kpi, fallbackAccent: accent),
          ],
        );
      },
    );
  }

  Widget _rail({required List<Widget> children, required double height}) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, index) => children[index],
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
              Text(
                kpi.value,
                maxLines: 1,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                  height: 1.1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
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
