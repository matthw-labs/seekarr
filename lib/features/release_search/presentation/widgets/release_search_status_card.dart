import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/utils/duration_format.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/features/release_search/domain/release_search_job.dart';
import 'package:seekarr/features/release_search/domain/release_search_target.dart';
import 'package:seekarr/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:seekarr/features/release_search/presentation/release_search_sheet.dart';

/// Job state where the intent is formed.
///
/// Not an explanation, which is why it does not duplicate the other three homes:
/// this is **state at the point of intent**. The detail page already owns the
/// right idiom — `MediaPrimaryAction` carries a `consequence` sentence, the line
/// that says what an action will do — so a live job rewrites that sentence rather
/// than adding chrome of its own.
///
/// Renders nothing when there is no job, and matches **only the exact target**:
/// an episode row does not light up because its season is being searched, because
/// a readout duplicated at three levels is what makes a detail page unreadable.
class ReleaseSearchStatusCard extends ConsumerWidget {
  const ReleaseSearchStatusCard({super.key, required this.target});

  final ReleaseSearchTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = ref.watch(jobForTargetProvider(target));
    if (job == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final now = DateTime.now();
    final remaining = job.grabWindowRemaining(now);

    final (headline, consequence) = switch (job.status) {
      ReleaseSearchJobStatus.queued => (
        'Queued',
        'Waiting for a slot — nothing has been sent to your indexers yet.',
      ),
      ReleaseSearchJobStatus.running => (
        'Searching · ${formatElapsed(job.elapsedAt(now))}',
        'Running while Seekarr is open. Tap to watch it, or find it in '
            'Activity.',
      ),
      ReleaseSearchJobStatus.completed =>
        job.releaseCount == 0
            ? (
                'No releases found',
                'Your indexers answered — nothing matched. Searching again is '
                    'safe.',
              )
            : (
                '${job.releaseCount} release'
                    '${job.releaseCount == 1 ? '' : 's'}'
                    '${remaining == null ? '' : ' · ${formatWindowRemaining(remaining)}'}',
                'Found earlier and still grabbable. Tap to pick one — no new '
                    'search needed.',
              ),
      ReleaseSearchJobStatus.failed => (
        job.failure?.headline ?? 'The search stopped',
        job.failure?.diagnosis ?? 'Searching again is safe.',
      ),
      ReleaseSearchJobStatus.expired => (
        '${job.releaseCount} release'
            '${job.releaseCount == 1 ? '' : 's'} · expired',
        'These are no longer grabbable. Searching again will fetch a fresh '
            'list.',
      ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard.filled(
        backgroundColor: colors.surfaceContainerHigh,
        semanticLabel: '$headline. $consequence',
        excludeChildSemantics: true,
        onTap: () => ReleaseSearchSheet.show(
          context: context,
          ref: ref,
          jobId: job.id,
          target: target,
          reusedResults: job.status == ReleaseSearchJobStatus.completed,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (job.status == ReleaseSearchJobStatus.running)
                  const Padding(
                    padding: EdgeInsets.only(right: AppSpacing.sm),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                Expanded(
                  child: Text(headline, style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              consequence,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
