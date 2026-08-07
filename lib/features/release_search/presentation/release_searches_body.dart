import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/widgets/app_empty_state.dart';
import 'package:seekarr/features/release_search/domain/release_search_job.dart';
import 'package:seekarr/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:seekarr/features/release_search/presentation/release_search_sheet.dart';
import 'package:seekarr/features/release_search/presentation/widgets/release_search_job_card.dart';

/// Keeps the windows honest while the section is on screen.
///
/// Watcher-scoped on purpose, following `activityNowPollingProvider`: the ticker
/// runs only while something is watching it and dies with the last watcher, so a
/// section the user has navigated away from is not re-rendering once a second.
final releaseSearchTickProvider = Provider.autoDispose<void>((ref) {
  final timer = Timer.periodic(const Duration(seconds: 10), (_) {
    ref.read(releaseSearchJobsProvider.notifier).refreshWindows();
  });
  ref.onDispose(timer.cancel);
});

/// Activity › Now › **Searching**.
///
/// The gerund completes the grammar of the bucket it joins, where the siblings
/// are Downloading and Streaming — and Now is where live things go. Completed
/// searches stay because their *window* is still live even once the search is
/// not.
class ReleaseSearchesBody extends ConsumerWidget {
  const ReleaseSearchesBody({super.key, required this.bottomPadding});

  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(releaseSearchTickProvider);
    final jobs = ref.watch(releaseSearchJobsProvider);
    final now = DateTime.now();

    if (jobs.isEmpty) {
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xxl,
          AppSpacing.lg,
          bottomPadding,
        ),
        child: const AppEmptyState(
          icon: Icons.travel_explore_rounded,
          title: 'No searches running',
          // Teaches the affordance rather than only reporting the absence.
          message: ReleaseSearchHandoffCopy.emptyStateHint,
        ),
      );
    }

    // Queue positions are 1-based and counted oldest-first, which is the order
    // the manager actually starts them in.
    final queued = jobs
        .where((j) => j.status == ReleaseSearchJobStatus.queued)
        .toList()
        .reversed
        .toList();

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        bottomPadding,
      ),
      itemCount: jobs.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final job = jobs[index];
        final queueIndex = queued.indexWhere((j) => j.id == job.id);
        return ReleaseSearchJobCard(
          job: job,
          now: now,
          queuePosition: queueIndex <= 0 ? null : queueIndex,
          expandVerdict: true,
          onTap: () => ReleaseSearchSheet.show(
            context: context,
            ref: ref,
            jobId: job.id,
            target: job.target,
            reusedResults: job.status == ReleaseSearchJobStatus.completed,
          ),
          onCancel: () =>
              ref.read(releaseSearchJobsProvider.notifier).cancel(job.id),
          onSearchAgain: () => ref
              .read(releaseSearchJobsProvider.notifier)
              .searchAgain(job.target),
          onDismiss: () =>
              ref.read(releaseSearchJobsProvider.notifier).dismiss(job.id),
        );
      },
    );
  }
}
