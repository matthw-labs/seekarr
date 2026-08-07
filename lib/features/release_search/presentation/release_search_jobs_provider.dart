import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/release_search/domain/release_search_job.dart';
import 'package:cupola/features/release_search/domain/release_search_reach.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Runs a release search for a target and returns the raw release maps.
///
/// Injected rather than resolved here so the manager stays free of every arr
/// service: the entry point that owns the call sites already holds the right
/// service, and a test can drive the manager with a plain function.
typedef ReleaseSearchRunner =
    Future<List<dynamic>> Function(
      ReleaseSearchTarget target,
      CancelToken cancelToken,
    );

/// Resolves how far a search on [ServiceKey] can travel — see
/// [ReleaseSearchReach]. Injected the same way [ReleaseSearchRunner] is: the
/// entry point that owns settings configures it once, so the manager stays
/// free of knowing about certificates or reach beyond a key.
typedef ReleaseSearchReachResolver =
    ReleaseSearchReach Function(ServiceKey service);

/// How many searches may run at once by default.
///
/// Two, not more, and this is a courtesy rather than a performance choice: the
/// premise of the whole feature is that the user's indexers are slow and
/// rate-limited, so the manager would rather make a search wait than make a
/// second one compete with it.
const kDefaultSearchConcurrency = 2;

/// Owns every background release search for the session.
///
/// A [Notifier] and deliberately **not** a `FutureProvider`: Riverpod 3 re-runs
/// a failed provider on an exponential backoff, which here would silently fire
/// fresh searches at rate-limited indexers with nobody watching. Ownership also
/// has to outlive the sheet — today an in-flight search dies when the modal is
/// dismissed, because the sheet's `State` is its only owner.
///
/// In-memory only: persistence across process death arrives with Phase 2.
final releaseSearchJobsProvider =
    NotifierProvider<ReleaseSearchJobsNotifier, List<ReleaseSearchJob>>(
      ReleaseSearchJobsNotifier.new,
    );

/// The job whose releases have finished but not yet been looked at — what the
/// Activity badge counts.
final unseenReleaseSearchCountProvider = Provider<int>((ref) {
  final jobs = ref.watch(releaseSearchJobsProvider);
  return jobs
      .where(
        (j) => j.status == ReleaseSearchJobStatus.completed && !j.resultsOpened,
      )
      .length;
});

/// The live job for exactly this target, if any.
///
/// Exact match on purpose: §4d of the brief puts job state only at the
/// granularity it was launched at, so an episode row does not light up because
/// its season is being searched. Adoption is a different question, and it is
/// [ReleaseSearchJobsNotifier.activeJobCovering]'s.
final jobForTargetProvider =
    Provider.family<ReleaseSearchJob?, ReleaseSearchTarget>((ref, target) {
      final jobs = ref.watch(releaseSearchJobsProvider);
      for (final job in jobs) {
        if (job.target == target) return job;
      }
      return null;
    });

class ReleaseSearchJobsNotifier extends Notifier<List<ReleaseSearchJob>> {
  /// Cancel tokens for jobs that are running, keyed by job id.
  final Map<String, CancelToken> _tokens = {};

  int _sequence = 0;

  /// Injected so tests can control the clock; production passes nothing.
  DateTime Function() _now = DateTime.now;

  int _concurrency = kDefaultSearchConcurrency;

  Duration _timeout = kReleaseSearchReceiveTimeout;

  ReleaseSearchRunner? _runner;

  /// Defaults to the platform-only answer: unconfigured (as in a test that
  /// never calls [configure]) reads as "nothing pinned", not as a certificate
  /// limitation that was never actually diagnosed.
  ReleaseSearchReachResolver _reachFor = (_) => ReleaseSearchReach.beyondTheApp;

  /// Told about every finished search, so the headroom card can be measured from
  /// real traffic rather than from a probe pretending to be slow.
  void Function(ReleaseSearchJob job)? _onFinished;

  @override
  List<ReleaseSearchJob> build() {
    ref.onDispose(() {
      for (final token in _tokens.values) {
        token.cancel();
      }
      _tokens.clear();
    });
    return const [];
  }

  /// Wires the manager to whatever actually performs a search. Called once by
  /// the entry point that owns the arr services.
  void configure({
    required ReleaseSearchRunner runner,
    ReleaseSearchReachResolver? reachFor,
    int? concurrency,
    Duration? timeout,
    DateTime Function()? now,
    void Function(ReleaseSearchJob job)? onFinished,
  }) {
    _runner = runner;
    if (reachFor != null) _reachFor = reachFor;
    if (onFinished != null) _onFinished = onFinished;
    if (concurrency != null) _concurrency = concurrency.clamp(1, 4);
    if (timeout != null) _timeout = timeout;
    if (now != null) _now = now;
  }

  ReleaseSearchJob? jobById(String id) {
    for (final job in state) {
      if (job.id == id) return job;
    }
    return null;
  }

  /// An active job that would answer [target] — the same target, or one that
  /// covers it.
  ///
  /// This is what makes the search button idempotent: tapping it twice, or
  /// tapping an episode whose season is already being searched, adopts the work
  /// in flight instead of doubling the load on the indexers.
  ReleaseSearchJob? activeJobCovering(ReleaseSearchTarget target) {
    for (final job in state) {
      if (!job.isActive) continue;
      if (job.target == target || target.isCoveredBy(job.target)) return job;
    }
    return null;
  }

  /// A finished job whose releases are still grabbable and would answer
  /// [target] — the read-through cache that saves a redundant pass.
  ReleaseSearchJob? freshResultsFor(ReleaseSearchTarget target) {
    for (final job in state) {
      if (job.status != ReleaseSearchJobStatus.completed) continue;
      if (job.hasExpired(_now())) continue;
      if (job.target == target) return job;
    }
    return null;
  }

  /// Starts a search, or returns the job already doing that work.
  ///
  /// Never starts a second search for work already in flight, and never silently
  /// replaces a fresh result — the caller decides whether to reuse
  /// [freshResultsFor] before asking for a new one.
  ReleaseSearchJob start(ReleaseSearchTarget target) {
    final existing = activeJobCovering(target);
    if (existing != null) return existing;

    final now = _now();
    final job = ReleaseSearchJob(
      id: 'rs-${++_sequence}',
      target: target,
      status: ReleaseSearchJobStatus.queued,
      startedAt: now,
    );
    state = [job, ...state];
    _prune();
    _pump();
    return jobById(job.id) ?? job;
  }

  /// Discards a fresh result and searches again. Explicit, because it costs the
  /// user's indexers another pass.
  ReleaseSearchJob searchAgain(ReleaseSearchTarget target) {
    state = state
        .where((j) => !(j.target == target && !j.isActive))
        .toList(growable: false);
    return start(target);
  }

  void cancel(String jobId) {
    final job = jobById(jobId);
    if (job == null || !job.isActive) return;
    _tokens.remove(jobId)?.cancel();
    _replace(
      job.copyWith(
        status: ReleaseSearchJobStatus.failed,
        finishedAt: _now(),
        failure: const ReleaseSearchFailure(
          kind: ReleaseSearchFailureKind.cancelled,
          headline: 'Search cancelled.',
          diagnosis: 'Nothing was sent to your indexers after you stopped it.',
        ),
      ),
    );
    _pump();
  }

  /// Marks a job's releases as seen, which is what clears its share of the badge.
  ///
  /// Per job rather than per section: clearing on section view would zero a count
  /// for searches the user never actually looked at.
  void markResultsOpened(String jobId) {
    final job = jobById(jobId);
    if (job == null || job.resultsOpened) return;
    _replace(job.copyWith(resultsOpened: true));
  }

  /// Drops a finished job from the list.
  void dismiss(String jobId) {
    final job = jobById(jobId);
    if (job == null || job.isActive) return;
    state = state.where((j) => j.id != jobId).toList(growable: false);
  }

  /// Cancels everything for a service whose connection settings just changed.
  ///
  /// Letting a job finish against a credential the user has replaced would at
  /// best waste an indexer pass and at worst grab against a host they just
  /// pointed somewhere else — so it stops, and it says why.
  void cancelForService(ServiceKey service) {
    for (final job in state.where((j) => j.isActive).toList()) {
      if (job.target.service != service) continue;
      _tokens.remove(job.id)?.cancel();
      _replace(
        job.copyWith(
          status: ReleaseSearchJobStatus.failed,
          finishedAt: _now(),
          failure: ReleaseSearchFailure(
            kind: ReleaseSearchFailureKind.cancelled,
            headline: 'Cancelled — ${service.title}\'s connection changed.',
            diagnosis: 'Searching again will use the settings you just saved.',
          ),
        ),
      );
    }
    _pump();
  }

  /// Records that the app went to the background, so a request that does not
  /// survive it can be blamed on the OS rather than on the user's network.
  void noteBackgrounded() {
    var changed = false;
    final next = state
        .map((job) {
          if (!job.isActive || job.wasBackgrounded) return job;
          changed = true;
          return job.copyWith(wasBackgrounded: true);
        })
        .toList(growable: false);
    if (changed) state = next;
  }

  /// Re-evaluates windows and evicts stale jobs. Called on resume and on tick.
  void refreshWindows() {
    final now = _now();
    var changed = false;
    final next = <ReleaseSearchJob>[];
    for (final job in state) {
      if (job.shouldEvict(now)) {
        changed = true;
        continue;
      }
      if (job.hasExpired(now)) {
        changed = true;
        next.add(job.copyWith(status: ReleaseSearchJobStatus.expired));
        continue;
      }
      // A search queued long enough ago that its results would expire almost
      // immediately is not worth an indexer pass; it is dropped, and it says so.
      if (job.status == ReleaseSearchJobStatus.queued &&
          now.difference(job.startedAt) >= kGrabWindow) {
        changed = true;
        next.add(
          job.copyWith(
            status: ReleaseSearchJobStatus.failed,
            finishedAt: now,
            failure: const ReleaseSearchFailure(
              kind: ReleaseSearchFailureKind.cancelled,
              headline: 'Not started — queued too long ago.',
              diagnosis:
                  'Results found now would expire almost immediately, so the '
                  'search was dropped rather than run.',
            ),
          ),
        );
        continue;
      }
      next.add(job);
    }
    if (changed) state = next;
    _pump();
  }

  // ── internals ───────────────────────────────────────────────────────────

  /// Starts queued jobs up to the concurrency cap.
  void _pump() {
    final runner = _runner;
    if (runner == null) return;

    final running = state
        .where((j) => j.status == ReleaseSearchJobStatus.running)
        .length;
    var slots = _concurrency - running;
    if (slots <= 0) return;

    // Oldest queued first: the list is newest-first, so walk it backwards.
    for (final job in state.reversed.toList()) {
      if (slots == 0) break;
      if (job.status != ReleaseSearchJobStatus.queued) continue;
      // A season search started while one of its episodes is running would ask
      // the same indexers for overlapping releases, which is exactly what the
      // concurrency cap exists to prevent. It waits its turn instead.
      if (_conflictsWithRunning(job)) continue;
      slots--;
      _run(job, runner);
    }
  }

  bool _conflictsWithRunning(ReleaseSearchJob candidate) {
    for (final other in state) {
      if (other.id == candidate.id) continue;
      if (other.status != ReleaseSearchJobStatus.running) continue;
      if (candidate.target.conflictsWith(other.target)) return true;
    }
    return false;
  }

  void _run(ReleaseSearchJob job, ReleaseSearchRunner runner) {
    final token = CancelToken();
    _tokens[job.id] = token;
    final startedAt = _now();
    _replace(
      job.copyWith(
        status: ReleaseSearchJobStatus.running,
        runningSince: startedAt,
      ),
    );

    runner(job.target, token).then(
      (releases) {
        _tokens.remove(job.id);
        final current = jobById(job.id);
        if (current == null || !current.isActive) return;
        final now = _now();
        final finished = current.copyWith(
          status: ReleaseSearchJobStatus.completed,
          releases: releases,
          finishedAt: now,
          elapsed: now.difference(startedAt),
        );
        _replace(finished);
        _onFinished?.call(finished);
        _pump();
      },
      onError: (Object error) {
        _tokens.remove(job.id);
        final current = jobById(job.id);
        // A cancelled job already carries its own verdict; do not overwrite it.
        if (current == null || !current.isActive) return;
        final now = _now();
        final elapsed = now.difference(startedAt);
        final finished = current.copyWith(
          status: ReleaseSearchJobStatus.failed,
          finishedAt: now,
          elapsed: elapsed,
          failure: classifyReleaseSearchFailure(
            error,
            elapsed: elapsed,
            configuredTimeout: _timeout,
            wasBackgrounded: current.wasBackgrounded,
            reach: _reachFor(current.target.service),
          ),
        );
        _replace(finished);
        _onFinished?.call(finished);
        _pump();
      },
    );
  }

  void _replace(ReleaseSearchJob job) {
    state = state.map((j) => j.id == job.id ? job : j).toList(growable: false);
  }

  /// Caps the list, evicting finished jobs before active ones.
  void _prune() {
    if (state.length <= kMaxJobs) return;
    final kept = <ReleaseSearchJob>[];
    final droppable = <ReleaseSearchJob>[];
    for (final job in state) {
      (job.isActive ? kept : droppable).add(job);
    }
    final room = kMaxJobs - kept.length;
    state = [
      ...kept,
      ...droppable.take(room < 0 ? 0 : room),
    ].toList(growable: false);
  }
}
