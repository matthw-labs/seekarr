import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/release_search/domain/release_search_job.dart';
import 'package:cupola/features/release_search/domain/release_search_reach.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:cupola/features/release_search/presentation/release_search_sheet.dart';
import 'package:cupola/features/release_search/presentation/release_searches_body.dart';
import 'package:cupola/features/release_search/presentation/widgets/release_search_job_card.dart';
import 'package:cupola/features/release_search/presentation/widgets/release_search_status_card.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

final _season = ReleaseSearchTarget.season(
  seriesId: 1,
  seasonNumber: 2,
  label: 'Severance · Season 2',
);

ReleaseSearchJob _job({
  required ReleaseSearchJobStatus status,
  int releaseCount = 0,
  Duration elapsed = Duration.zero,
  DateTime? finishedAt,
  ReleaseSearchFailure? failure,
  ReleaseSearchTarget? target,
}) {
  return ReleaseSearchJob(
    id: 'rs-1',
    target: target ?? _season,
    status: status,
    startedAt: DateTime.utc(2026, 8, 5, 9),
    finishedAt: finishedAt,
    releases: List.generate(releaseCount, (i) => {'guid': 'g$i'}),
    elapsed: elapsed,
    failure: failure,
  );
}

/// A clock the test moves by hand, so the 30-minute grab window can be crossed
/// without waiting for it. Same shape as the one in release_search_jobs_test.
class _FakeClock {
  DateTime value = DateTime.utc(2026, 8, 5, 9);
  DateTime call() => value;
  void advance(Duration d) => value = value.add(d);
}

Widget _host(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      theme: AppTheme.darkTheme(),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('ReleaseSearchJobCard', () {
    testWidgets('a queued job says it has not started', (tester) async {
      await tester.pumpWidget(
        _host(
          ReleaseSearchJobCard(
            job: _job(status: ReleaseSearchJobStatus.queued),
            now: DateTime.utc(2026, 8, 5, 9),
            queuePosition: 1,
          ),
        ),
      );

      expect(find.text('Queued'), findsOneWidget);
      expect(find.textContaining('1 ahead'), findsOneWidget);
    });

    testWidgets('a running job shows no elapsed clock in the list', (
      tester,
    ) async {
      // Deliberate: once the search is off screen the ticking figure answers
      // nothing actionable, and sharing the trailing slot with the countdown
      // made one position mean two opposite things.
      await tester.pumpWidget(
        _host(
          ReleaseSearchJobCard(
            job: _job(
              status: ReleaseSearchJobStatus.running,
              elapsed: const Duration(minutes: 1, seconds: 12),
            ),
            now: DateTime.utc(2026, 8, 5, 9),
          ),
        ),
      );

      expect(find.text('Searching'), findsOneWidget);
      expect(find.text('1:12'), findsNothing);
    });

    testWidgets('a fresh window reads in minutes with a unit', (tester) async {
      final finished = DateTime.utc(2026, 8, 5, 9);
      await tester.pumpWidget(
        _host(
          ReleaseSearchJobCard(
            job: _job(
              status: ReleaseSearchJobStatus.completed,
              releaseCount: 14,
              finishedAt: finished,
            ),
            now: finished.add(const Duration(minutes: 3)),
          ),
        ),
      );

      expect(find.text('14 releases'), findsOneWidget);
      // Never a bare `27:00`, which would be indistinguishable from elapsed.
      expect(find.text('27m'), findsOneWidget);
    });

    testWidgets('zero releases states the answer without a count', (
      tester,
    ) async {
      final finished = DateTime.utc(2026, 8, 5, 9);
      await tester.pumpWidget(
        _host(
          ReleaseSearchJobCard(
            job: _job(
              status: ReleaseSearchJobStatus.completed,
              finishedAt: finished,
            ),
            now: finished,
          ),
        ),
      );

      expect(find.text('No releases found'), findsOneWidget);
    });

    testWidgets('an expired job drains rather than alarming', (tester) async {
      final finished = DateTime.utc(2026, 8, 5, 9);
      await tester.pumpWidget(
        _host(
          ReleaseSearchJobCard(
            job: _job(
              status: ReleaseSearchJobStatus.expired,
              releaseCount: 14,
              finishedAt: finished,
            ),
            now: finished.add(const Duration(minutes: 31)),
          ),
        ),
      );

      expect(find.text('Expired'), findsOneWidget);
      expect(find.textContaining('expired'), findsWidgets);
    });

    testWidgets(
      'a failed job shows the diagnosis, and the exception under it',
      (tester) async {
        await tester.pumpWidget(
          _host(
            ReleaseSearchJobCard(
              job: _job(
                status: ReleaseSearchJobStatus.failed,
                failure: const ReleaseSearchFailure(
                  kind: ReleaseSearchFailureKind.gatewayTimeout,
                  headline:
                      'Your reverse proxy closed the connection after 1:02.',
                  diagnosis: 'Sonarr is probably still searching.',
                  detail: 'HTTP 502 · nginx',
                ),
              ),
              now: DateTime.utc(2026, 8, 5, 9),
              expandVerdict: true,
            ),
          ),
        );

        expect(find.textContaining('reverse proxy closed'), findsOneWidget);
        expect(
          find.text('Sonarr is probably still searching.'),
          findsOneWidget,
        );
        // Present, because a self-hoster can act on it — but demoted, never the
        // message.
        expect(find.text('HTTP 502 · nginx'), findsOneWidget);
      },
    );

    testWidgets('the card speaks one sentence, and controls keep their own', (
      tester,
    ) async {
      final finished = DateTime.utc(2026, 8, 5, 9);
      await tester.pumpWidget(
        _host(
          ReleaseSearchJobCard(
            job: _job(
              status: ReleaseSearchJobStatus.completed,
              releaseCount: 3,
              finishedAt: finished,
            ),
            now: finished,
            onSearchAgain: () {},
          ),
        ),
      );

      final semantics = tester.getSemantics(
        find.bySemanticsLabel(RegExp('3 releases found on Sonarr')),
      );
      expect(semantics, isNotNull);
      // The in-card control is still reachable rather than swallowed.
      expect(find.widgetWithText(TextButton, 'Search again'), findsOneWidget);
    });
  });

  group('Activity › Searching', () {
    testWidgets('the empty state teaches the affordance by name', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const ReleaseSearchesBody(bottomPadding: 0)),
      );
      await tester.pump();

      expect(find.text('No searches running'), findsOneWidget);
      expect(
        find.textContaining(ReleaseSearchHandoffCopy.action),
        findsOneWidget,
        reason: 'the empty state must name the button it is pointing at',
      );
    });

    testWidgets('lists every job, newest first', (tester) async {
      final container = ProviderContainer();
      final notifier = container.read(releaseSearchJobsProvider.notifier);
      notifier.configure(runner: (_, __) => Completer<List<dynamic>>().future);
      notifier.start(_season);
      notifier.start(
        ReleaseSearchTarget.movie(movieId: 9, label: 'Dune: Part Two'),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const Scaffold(body: ReleaseSearchesBody(bottomPadding: 0)),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Dune: Part Two'), findsOneWidget);
      expect(find.text('Severance · Season 2'), findsOneWidget);
      expect(find.byType(ReleaseSearchJobCard), findsAtLeastNWidgets(2));

      await tester.pumpWidget(const SizedBox());
      container.dispose();
    });
  });

  group('ReleaseSearchSheet grabbing an expired list', () {
    /// Drives a job to `expired` with releases on it, then mounts the sheet
    /// watching that job.
    Future<({ProviderContainer container, String jobId})> pumpExpiredSheet(
      WidgetTester tester,
    ) async {
      final clock = _FakeClock();
      // The sheet watches `releaseSearchReachProvider`, whose settings chain
      // reaches SharedPreferences — overridden here so the test stays offline.
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(releaseSearchJobsProvider.notifier);

      final completer = Completer<List<dynamic>>();
      notifier.configure(now: clock.call, runner: (_, __) => completer.future);

      final job = notifier.start(_season);
      completer.complete([
        {'guid': 'g0', 'indexerId': 3, 'title': 'Severance.S02.2160p'},
      ]);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      clock.advance(const Duration(minutes: 31));
      notifier.refreshWindows();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: Scaffold(
              body: ReleaseSearchSheet(
                jobId: job.id,
                target: _season,
                scrollController: ScrollController(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (container: container, jobId: job.id);
    }

    /// Taps the row's grab button and confirms the shared sheet's own
    /// "Download this?" dialog, which is what hands control to `_grab`.
    ///
    /// Deliberately not `pumpAndSettle` past that confirmation: from there the
    /// grabbing row spins on an indeterminate indicator, so nothing ever
    /// settles while the grab is in flight.
    Future<void> tapGrab(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Grab Release').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('cancelling the search-again prompt claims no download', (
      tester,
    ) async {
      // The whole point of the ReleaseGrabAbandoned signal. `_grab` returns
      // without grabbing on both non-grab outcomes of this prompt, and
      // InteractiveSearchSheet reads a normal return as "grabbed" — so this
      // used to pop the sheet under a green "Download started" for a user who
      // had just pressed Cancel.
      await pumpExpiredSheet(tester);

      await tapGrab(tester);
      expect(find.text('Search again for this release?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Download started'), findsNothing);
      expect(find.byType(ReleaseSearchSheet), findsOneWidget);
      // Not reported as a failure either — the prompt already said why.
      expect(find.byType(SnackBar), findsNothing);
      // Re-armed rather than dead: the row can be grabbed again.
      expect(find.byTooltip('Grab Release'), findsOneWidget);
    });

    testWidgets('the prompt promises a search and only a search', (
      tester,
    ) async {
      // The copy is the contract here: accepting re-runs the search and grabs
      // nothing, so nothing in the dialog may say otherwise. It used to be
      // titled "Search again to grab this?" over a "Search & grab" button,
      // which described a re-grab the code has no hook for.
      await pumpExpiredSheet(tester);

      await tapGrab(tester);

      expect(
        find.textContaining('grab the release from the new list'),
        findsOneWidget,
      );
      expect(find.text('Run the search'), findsOneWidget);
      expect(find.textContaining('Search & grab'), findsNothing);
    });

    testWidgets('accepting it starts a fresh search, not a download', (
      tester,
    ) async {
      // The other non-grab outcome: the sheet re-points at a brand new job and
      // the user watches it run. Nothing was grabbed, so nothing may be
      // claimed.
      final (:container, :jobId) = await pumpExpiredSheet(tester);

      await tapGrab(tester);
      await tester.tap(find.text('Run the search'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Download started'), findsNothing);
      expect(find.byType(ReleaseSearchSheet), findsOneWidget);

      // The expired job was replaced by a brand new search rather than grabbed
      // from. (The stub runner answers instantly, so the replacement is already
      // finished here — the id is what says a second pass actually happened.)
      final jobs = container.read(releaseSearchJobsProvider);
      expect(jobs, hasLength(1));
      expect(jobs.single.id, isNot(jobId));
    });
  });

  group('ReleaseSearchStatusCard', () {
    testWidgets('renders nothing when the target has no job', (tester) async {
      await tester.pumpWidget(_host(ReleaseSearchStatusCard(target: _season)));
      expect(find.byType(Card), findsNothing);
      expect(find.textContaining('Searching'), findsNothing);
    });

    testWidgets('a running job rewrites the consequence sentence', (
      tester,
    ) async {
      final container = ProviderContainer();
      final notifier = container.read(releaseSearchJobsProvider.notifier);
      notifier.configure(runner: (_, __) => Completer<List<dynamic>>().future);
      notifier.start(_season);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: Scaffold(body: ReleaseSearchStatusCard(target: _season)),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Searching'), findsOneWidget);
      expect(
        find.textContaining('Running while Cupola is open'),
        findsOneWidget,
        reason: 'the phase-accurate promise, not an OS background',
      );

      await tester.pumpWidget(const SizedBox());
      container.dispose();
    });

    testWidgets('state appears only at the granularity it was launched', (
      tester,
    ) async {
      final container = ProviderContainer();
      final notifier = container.read(releaseSearchJobsProvider.notifier);
      notifier.configure(runner: (_, __) => Completer<List<dynamic>>().future);
      notifier.start(_season);

      // An episode inside the searching season must stay silent: a readout
      // duplicated at three levels is what makes a detail page unreadable.
      final episode = ReleaseSearchTarget.episode(
        episodeId: 44,
        seriesId: 1,
        seasonNumber: 2,
        label: 'Severance · S02E04',
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: Scaffold(body: ReleaseSearchStatusCard(target: episode)),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Searching'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      container.dispose();
    });
  });

  group('the handoff promise', () {
    test('the label names the mechanism, not a location', () {
      // The defect this guards: a permanent button reading "Continue in
      // background" while Phase 1 only keeps the search alive in-app.
      expect(ReleaseSearchHandoffCopy.action, 'Keep searching');
      expect(
        ReleaseSearchHandoffCopy.action.toLowerCase(),
        isNot(contains('background')),
      );
    });

    test(
      'explainerBody and confirmation agree about what survives, for every reach',
      () {
        // Two functions, not two constants — because under ADR-5 they were two
        // hard-coded strings that quietly drifted apart (one saying "runs while
        // Cupola is open", the other "running in the background", for the same
        // build), and that drift was the most dangerous defect in the design.
        // ADR-6 makes the split three-way (a certificate trusted only inside
        // Cupola also cannot survive leaving the app), so the guard now checks
        // every value of ReleaseSearchReach rather than one hard-coded pair.
        for (final reach in ReleaseSearchReach.values) {
          final body = ReleaseSearchHandoffCopy.explainerBody(reach);
          final confirmation = ReleaseSearchHandoffCopy.confirmation(reach);
          final survivesLeavingTheApp =
              reach == ReleaseSearchReach.beyondTheApp;

          expect(
            body.toLowerCase().contains('while cupola is open'),
            !survivesLeavingTheApp,
            reason:
                '$reach: explainerBody claims "while Cupola is open" iff the '
                'search does NOT survive leaving the app.',
          );
          expect(
            confirmation.toLowerCase().contains('background'),
            survivesLeavingTheApp,
            reason:
                '$reach: confirmation claims the background iff the search '
                'actually survives leaving the app — the exact pairing whose '
                'absence let the two strings drift apart before ADR-6.',
          );
        }
      },
    );

    test('the empty-state hint never promises an OS background', () {
      expect(
        ReleaseSearchHandoffCopy.emptyStateHint,
        contains(ReleaseSearchHandoffCopy.action),
      );
      expect(
        ReleaseSearchHandoffCopy.emptyStateHint.toLowerCase(),
        isNot(contains('while you do something else')),
        reason: 'that phrasing promises an OS background Phase 1 does not have',
      );
    });
  });
}
