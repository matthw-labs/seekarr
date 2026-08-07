import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/service_theme.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/duration_format.dart';
import 'package:seekarr/core/widgets/status_badge.dart';
import 'package:seekarr/features/release_search/domain/release_search_job.dart';
import 'package:seekarr/features/release_search/domain/release_search_target.dart';
import 'package:seekarr/features/release_search/presentation/release_search_jobs_provider.dart';

/// Job state on a row that has room for a few words.
///
/// Used on a season header. Renders nothing without a job for **exactly** this
/// target — a season does not light up because one of its episodes is being
/// searched, and vice versa, because a readout repeated down the hierarchy is
/// what makes a detail page unreadable.
class ReleaseSearchRowChip extends ConsumerWidget {
  const ReleaseSearchRowChip({super.key, required this.target});

  final ReleaseSearchTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = ref.watch(jobForTargetProvider(target));
    if (job == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final remaining = job.grabWindowRemaining(DateTime.now());

    final (label, tone) = switch (job.status) {
      ReleaseSearchJobStatus.queued => ('Queued', StatusTone.neutral),
      ReleaseSearchJobStatus.running => ('Searching', StatusTone.info),
      ReleaseSearchJobStatus.completed =>
        job.releaseCount == 0
            ? ('None found', StatusTone.neutral)
            : (
                remaining == null
                    ? '${job.releaseCount}'
                    : '${job.releaseCount} · ${formatWindowRemaining(remaining)}',
                remaining != null && remaining <= const Duration(minutes: 5)
                    ? StatusTone.warning
                    : StatusTone.success,
              ),
      ReleaseSearchJobStatus.failed => ('Stopped', StatusTone.error),
      ReleaseSearchJobStatus.expired => ('Expired', StatusTone.neutral),
    };

    final toneColor = statusToneColor(colors, tone);
    final isNeutral = tone == StatusTone.neutral;

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 108),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isNeutral
              ? Colors.transparent
              : toneColor.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isNeutral
                ? colors.outlineVariant
                : toneColor.withValues(alpha: 0.28),
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall
              ?.weight(FontWeight.w600)
              .tabular
              .copyWith(
                color: isNeutral
                    ? colors.onSurfaceVariant
                    // Measured against the composite of tint over surface, not
                    // against the tone alone.
                    : ServiceTheme.onTint(
                        toneColor,
                        surface: colors.surface,
                        tintAlpha: 0.16,
                      ),
              ),
        ),
      ),
    );
  }
}

/// Job state on a row with no room for words.
///
/// An 8 pt tone dot, which is a size judgment rather than a borrowed precedent:
/// DESIGN.md reserves its 8 pt dots for the poster rail and the merged Recently
/// Added rail, and the latter explicitly forbids borrowing its argument. The dot
/// is paired with a spoken label, because a colour is not information.
class ReleaseSearchRowDot extends ConsumerWidget {
  const ReleaseSearchRowDot({super.key, required this.target});

  final ReleaseSearchTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = ref.watch(jobForTargetProvider(target));
    if (job == null) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;
    final tone = releaseSearchTone(job);
    final spoken = switch (job.status) {
      ReleaseSearchJobStatus.queued => 'search queued',
      ReleaseSearchJobStatus.running => 'searching',
      ReleaseSearchJobStatus.completed =>
        job.releaseCount == 0
            ? 'no releases found'
            : '${job.releaseCount} releases found',
      ReleaseSearchJobStatus.failed => 'search stopped',
      ReleaseSearchJobStatus.expired => 'releases expired',
    };

    return Semantics(
      label: spoken,
      child: Padding(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tone == StatusTone.neutral
                ? colors.onSurfaceVariant
                : statusToneColor(colors, tone),
          ),
        ),
      ),
    );
  }
}
