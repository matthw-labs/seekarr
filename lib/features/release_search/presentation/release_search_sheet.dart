import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/duration_format.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/interactive_search_sheet.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/features/release_search/domain/release_search_job.dart';
import 'package:cupola/features/release_search/domain/release_search_reach.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/release_search/presentation/release_search_entry.dart';
import 'package:cupola/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:cupola/features/release_search/presentation/widgets/release_search_job_card.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Copy for the handoff, in one place.
///
/// The label names the **mechanism**, not a location: the search survives
/// leaving the sheet but not always leaving the app, so "Continue in
/// background" would promise an OS background reach this instance may not
/// have. [explainerBody] and [confirmation] are functions of
/// [ReleaseSearchReach] rather than constants for exactly the reason this
/// class's own history warns about: they used to be two hard-coded strings
/// that quietly drifted apart — one saying "runs while Cupola is open", the
/// other "running in the background" — for the same build, because neither
/// knew which transport it was describing. A pinned origin makes the split
/// three-way, so the fix is the same fix: derive both from the one value
/// that actually knows.
class ReleaseSearchHandoffCopy {
  const ReleaseSearchHandoffCopy._();

  static const action = 'Keep searching';
  static const explainerTitle = "This one's taking a while.";

  static String explainerBody(ReleaseSearchReach reach) => switch (reach) {
    ReleaseSearchReach.beyondTheApp =>
      'Keep it running and pick the release up later in Activity. Survives '
          'leaving the app.',
    ReleaseSearchReach.whileOpenTrustedCert =>
      'Keep it running and pick the release up later in Activity. Runs '
          'while Cupola is open — background search cannot see the '
          'certificate trusted for this instance, so it needs the app to '
          'stay in front.',
    ReleaseSearchReach.whileOpenCleartext =>
      'Keep it running and pick the release up later in Activity. Runs '
          'while Cupola is open — this instance is reached over plain '
          'http, where a background search could be redirected into '
          'handing its API key to another host. Switching it to https '
          'restores background search.',
    ReleaseSearchReach.whileOpen =>
      'Keep it running and pick the release up later in Activity. Runs '
          'while Cupola is open.',
  };

  static String confirmation(ReleaseSearchReach reach) =>
      reach == ReleaseSearchReach.beyondTheApp
      ? "Running in the background. You'll find it in Activity."
      : "Still running. You'll find it in Activity — keep Cupola open "
            'until it finishes.';

  static const emptyStateHint =
      'Start an interactive search and tap $action to move around the app '
      'without losing it.';
}

/// The sheet, observing a job rather than owning a fetch.
///
/// The important inversion: this is no longer where an in-flight search lives.
/// The job manager owns it, so dismissing the sheet stops watching rather than
/// stopping the work — which is the whole point of the feature.
class ReleaseSearchSheet extends ConsumerStatefulWidget {
  const ReleaseSearchSheet({
    super.key,
    required this.jobId,
    required this.target,
    required this.scrollController,
    this.adoptedFrom,
    this.reusedResults = false,
  });

  final String jobId;
  final ReleaseSearchTarget target;
  final ScrollController scrollController;

  /// Set when this sheet is watching a search the user did not just start —
  /// because adopting one without a word is work they cannot see.
  final String? adoptedFrom;

  /// Set when the releases came from the results cache rather than a new search.
  final bool reusedResults;

  static Future<void> show({
    required BuildContext context,
    required WidgetRef ref,
    required String jobId,
    required ReleaseSearchTarget target,
    String? adoptedFrom,
    bool reusedResults = false,
  }) {
    return AppBottomSheet.showScrollable<void>(
      context: context,
      title: 'Releases',
      subtitle: target.label,
      icon: Icons.travel_explore_rounded,
      accent: target.service.accent,
      showClose: true,
      initialSize: 0.75,
      minSize: 0.5,
      maxSize: 0.95,
      builder: (context, scrollController) => ReleaseSearchSheet(
        jobId: jobId,
        target: target,
        scrollController: scrollController,
        adoptedFrom: adoptedFrom,
        reusedResults: reusedResults,
      ),
    );
  }

  @override
  ConsumerState<ReleaseSearchSheet> createState() => _ReleaseSearchSheetState();
}

class _ReleaseSearchSheetState extends ConsumerState<ReleaseSearchSheet> {
  /// Set while the handoff confirmation is showing, just before the sheet leaves.
  bool _handingOff = false;

  /// Dismissed for this sheet once the user acknowledges it.
  bool _explainerDismissed = false;

  late String _jobId = widget.jobId;

  @override
  void initState() {
    super.initState();
    // Opening the results is what clears this job's share of the badge — not
    // visiting the section, which would zero a count for searches nobody read.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final job = _job;
      if (job != null && job.status == ReleaseSearchJobStatus.completed) {
        ref.read(releaseSearchJobsProvider.notifier).markResultsOpened(_jobId);
      }
    });
  }

  ReleaseSearchJob? get _job {
    final jobs = ref.read(releaseSearchJobsProvider);
    for (final job in jobs) {
      if (job.id == _jobId) return job;
    }
    return null;
  }

  void _handOff() {
    HapticFeedback.selectionClick();
    setState(() => _handingOff = true);
    // The row promotes into the card the user will look for, the destination
    // badge lights, and only then does the sheet leave — showing them the object
    // and its home before sending them away from it.
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  Future<void> _grab(String guid, int indexerId) async {
    final job = _job;
    final expired = job?.status == ReleaseSearchJobStatus.expired;
    if (expired) {
      // Neither branch below grabs anything, and `InteractiveSearchSheet` reads
      // a normal return as "grabbed" — so returning silently closed the sheet
      // under a green "Download started" for a user who had just cancelled, or
      // who was about to watch a fresh search run. [ReleaseGrabAbandoned] is
      // how a callback says it declined: the row re-arms, the sheet stays open
      // and nothing is claimed.
      final proceed = await _confirmExpiredGrab(job!);
      if (!proceed) throw const ReleaseGrabAbandoned();
      if (!mounted) throw const ReleaseGrabAbandoned();
      final fresh = ref
          .read(releaseSearchJobsProvider.notifier)
          .searchAgain(widget.target);
      setState(() => _jobId = fresh.id);
      throw const ReleaseGrabAbandoned();
    }
    await ref.read(releaseGrabberProvider)(
      widget.target.service,
      guid,
      indexerId,
    );
  }

  /// Never silent: the dialog names the cost, the target and the likely wait.
  ///
  /// It also names what accepting actually does, which is only half of what the
  /// user asked for. Accepting re-runs the search and nothing else — the guid
  /// they tapped belongs to a list the service has already dropped, and there
  /// is no re-grab hook to carry it into the next pass — so the copy promises a
  /// search and hands the grab back to them. It used to say *"Search & grab"*,
  /// which turned the abandoned grab into a broken promise instead of an
  /// explained one.
  Future<bool> _confirmExpiredGrab(ReleaseSearchJob job) async {
    final lastRun = job.elapsed;
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Search again for this release?',
      message:
          '${widget.target.service.title} no longer has this release list, so '
          'nothing on it can be grabbed. Cupola will run the search on your '
          'indexers again — grab the release from the new list when it lands.'
          '${lastRun == Duration.zero ? '' : ' It took ${formatElapsed(lastRun)} last time.'}',
      // Not plain "Search again": the results body behind this dialog already
      // has a button with that label.
      confirmLabel: 'Run the search',
    );
    return result.confirmed;
  }

  @override
  Widget build(BuildContext context) {
    // Watched, not read: the sheet re-renders as the job it observes moves.
    ref.watch(releaseSearchJobsProvider);
    final job = _job;

    if (job == null) {
      return const _SheetMessage(
        title: 'That search is gone',
        message:
            'It was cancelled or cleared while this sheet was open. Searching '
            'again is safe.',
      );
    }

    final reach = ref.watch(releaseSearchReachProvider(job.target.service));

    if (_handingOff) return _HandoffConfirmation(job: job, reach: reach);

    return switch (job.status) {
      ReleaseSearchJobStatus.queued => _QueuedBody(job: job, onCancel: _cancel),
      ReleaseSearchJobStatus.running => _RunningBody(
        job: job,
        reach: reach,
        adoptedFrom: widget.adoptedFrom,
        showExplainer: !_explainerDismissed,
        onDismissExplainer: () => setState(() => _explainerDismissed = true),
        onHandOff: _handOff,
        onCancel: _cancel,
      ),
      ReleaseSearchJobStatus.failed => _FailedBody(
        job: job,
        onSearchAgain: _searchAgain,
      ),
      ReleaseSearchJobStatus.completed ||
      ReleaseSearchJobStatus.expired => _ResultsBody(
        job: job,
        reusedResults: widget.reusedResults,
        scrollController: widget.scrollController,
        onGrab: _grab,
        onSearchAgain: _searchAgain,
      ),
    };
  }

  void _cancel() {
    ref.read(releaseSearchJobsProvider.notifier).cancel(_jobId);
    Navigator.of(context).maybePop();
  }

  void _searchAgain() {
    HapticFeedback.selectionClick();
    final fresh = ref
        .read(releaseSearchJobsProvider.notifier)
        .searchAgain(widget.target);
    setState(() => _jobId = fresh.id);
  }
}

/// Waiting for a slot. A first-class state: the user is told the search has not
/// started, rather than shown a spinner that is lying.
class _QueuedBody extends StatelessWidget {
  const _QueuedBody({required this.job, required this.onCancel});

  final ReleaseSearchJob job;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Queued', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Another search is using the slot. This one starts as soon as it '
            'frees — nothing has been sent to your indexers yet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onCancel,
              child: const Text('Cancel this search'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The instrument, now with a way out that keeps the work.
///
/// Owns its own one-second tick, because it is the only place an elapsed clock is
/// drawn. A timer in the job manager would keep the whole tree dirty for as long
/// as any search ran — which no `pumpAndSettle` could ever outlast.
class _RunningBody extends StatefulWidget {
  const _RunningBody({
    required this.job,
    required this.reach,
    required this.showExplainer,
    required this.onDismissExplainer,
    required this.onHandOff,
    required this.onCancel,
    this.adoptedFrom,
  });

  final ReleaseSearchJob job;
  final ReleaseSearchReach reach;
  final bool showExplainer;
  final VoidCallback onDismissExplainer;
  final VoidCallback onHandOff;
  final VoidCallback onCancel;
  final String? adoptedFrom;

  /// Below this a clock is noise on a search about to answer anyway.
  static const readoutAfter = Duration(seconds: 3);

  /// Past this the search is slow enough that the exit is worth offering.
  static const handoffAfter = Duration(seconds: 6);

  @override
  State<_RunningBody> createState() => _RunningBodyState();
}

class _RunningBodyState extends State<_RunningBody> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final elapsed = job.elapsedAt(DateTime.now());
    final showElapsed = elapsed >= _RunningBody.readoutAfter;
    final showHandoff = elapsed >= _RunningBody.handoffAfter;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  container: true,
                  label: showElapsed
                      ? 'Searching for releases. '
                            '${formatElapsedForSpeech(elapsed)} elapsed.'
                      : 'Searching for releases.',
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            'Searching for releases…',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (showElapsed)
                          Text(
                            formatElapsed(elapsed),
                            style: theme.textTheme.bodySmall?.tabular.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: widget.onCancel,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
        if (widget.adoptedFrom != null)
          _Disclosure(
            'Already searching ${widget.adoptedFrom}, started '
            '${formatElapsed(elapsed)} ago. This will cover it.',
          ),
        // Unrolled into its own space rather than popping in and shoving the
        // skeleton down under the thumb.
        AnimatedSize(
          duration: AppAnimation.durationMd,
          curve: AppAnimation.emphasizedCurve,
          alignment: Alignment.topCenter,
          child: showHandoff
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: _HandoffOffer(
                    reach: widget.reach,
                    showExplainer: widget.showExplainer,
                    onDismissExplainer: widget.onDismissExplainer,
                    onHandOff: widget.onHandOff,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        Expanded(
          child: ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            itemCount: 5,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ShimmerPlaceholder(
                height: 104,
                borderRadius: AppRadius.borderRadiusMd,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HandoffOffer extends StatelessWidget {
  const _HandoffOffer({
    required this.reach,
    required this.showExplainer,
    required this.onDismissExplainer,
    required this.onHandOff,
  });

  final ReleaseSearchReach reach;
  final bool showExplainer;
  final VoidCallback onDismissExplainer;
  final VoidCallback onHandOff;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (!showExplainer) {
      return Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: onHandOff,
          child: const Text(ReleaseSearchHandoffCopy.action),
        ),
      );
    }

    return AppCard.outlined(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ReleaseSearchHandoffCopy.explainerTitle,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            ReleaseSearchHandoffCopy.explainerBody(reach),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Wraps rather than overflows: two buttons plus a reading-size label do
          // not fit one line on a narrow sheet, and the trailing action is the one
          // that must never be clipped.
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              TextButton(
                onPressed: onDismissExplainer,
                child: const Text('Got it'),
              ),
              FilledButton(
                onPressed: onHandOff,
                child: const Text(ReleaseSearchHandoffCopy.action),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The focal moment: the running row becomes the card the user will look for.
///
/// A container transform rather than a cross-fade — the row and the card are the
/// same object at two densities — so the identity never fades and only the
/// geometry moves.
class _HandoffConfirmation extends StatelessWidget {
  const _HandoffConfirmation({required this.job, required this.reach});

  final ReleaseSearchJob job;
  final ReleaseSearchReach reach;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final card = Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReleaseSearchJobCard(job: job, now: DateTime.now()),
          const SizedBox(height: AppSpacing.md),
          Text(
            ReleaseSearchHandoffCopy.confirmation(reach),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    if (reduceMotion) return card;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppAnimation.durationLg,
      curve: AppAnimation.emphasizedCurve,
      builder: (context, t, child) =>
          Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
      child: card,
    );
  }
}

class _FailedBody extends StatelessWidget {
  const _FailedBody({required this.job, required this.onSearchAgain});

  final ReleaseSearchJob job;
  final VoidCallback onSearchAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failure = job.failure;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            failure?.headline ?? 'The search stopped.',
            style: theme.textTheme.titleMedium,
          ),
          if (failure != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              failure.diagnosis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (failure.detail != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                failure.detail!,
                style: theme.textTheme.labelSmall?.mono.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.75,
                  ),
                ),
              ),
            ],
          ],
          const SizedBox(height: AppSpacing.lg),
          // After a gateway cut the connection the server is probably still
          // searching, so the retry is offered without emphasis and the reason
          // not to take it is already in the diagnosis above.
          Align(
            alignment: Alignment.centerLeft,
            child: failure?.retryIsHarmful ?? false
                ? TextButton(
                    onPressed: onSearchAgain,
                    child: const Text('Search again anyway'),
                  )
                : FilledButton(
                    onPressed: onSearchAgain,
                    child: const Text('Search again'),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The release list, with its shelf life on the header.
class _ResultsBody extends StatelessWidget {
  const _ResultsBody({
    required this.job,
    required this.reusedResults,
    required this.scrollController,
    required this.onGrab,
    required this.onSearchAgain,
  });

  final ReleaseSearchJob job;
  final bool reusedResults;
  final ScrollController scrollController;
  final Future<void> Function(String guid, int indexerId) onGrab;
  final VoidCallback onSearchAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final expired = job.status == ReleaseSearchJobStatus.expired;
    final remaining = job.grabWindowRemaining(DateTime.now());

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                expired
                    // Drained, not alarmed: a window closing is normal for this
                    // product, so it reads as unlit rather than as a fault.
                    ? 'This list is no longer grabbable. '
                          '${job.target.service.title} only keeps found releases '
                          'for 30 minutes.'
                    : reusedResults
                    ? 'Found earlier and still grabbable'
                          '${remaining == null ? '' : ' for ${formatWindowRemaining(remaining)}'}'
                          ' — no new search needed.'
                    : 'Grabbable for '
                          '${formatWindowRemaining(remaining ?? Duration.zero)}.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (expired) ...[
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onSearchAgain,
                    child: const Text('Search again'),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: Opacity(
            // Expired releases stay readable but stop inviting a tap.
            opacity: expired ? 0.6 : 1,
            child: InteractiveSearchSheet(
              releases: job.releases ?? const [],
              title: job.target.label,
              onGrabRelease: onGrab,
              scrollController: scrollController,
            ),
          ),
        ),
      ],
    );
  }
}

class _Disclosure extends StatelessWidget {
  const _Disclosure(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SheetMessage extends StatelessWidget {
  const _SheetMessage({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
