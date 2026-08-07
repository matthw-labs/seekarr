import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/widgets/selection_pills.dart';
import 'package:seekarr/core/widgets/shimmer_placeholder.dart';
import 'package:seekarr/features/activity/presentation/activity_screen.dart';
import 'package:seekarr/features/activity/presentation/widgets/activity_tab.dart';
import 'package:seekarr/features/activity/presentation/widgets/requests_list.dart';
import 'package:seekarr/features/activity/presentation/widgets/wanted_tab.dart';
import 'package:seekarr/features/discover/data/seerr_service.dart';
import 'package:seekarr/features/onboarding/data/onboarding_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/discover/domain/models/seerr_request.dart';
import 'package:seekarr/features/discover/presentation/discover_provider.dart';
import 'package:seekarr/features/movies/data/radarr_service.dart';
import 'package:seekarr/features/music/data/lidarr_service.dart';
import 'package:seekarr/features/series/data/sonarr_service.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/settings_scope.dart';

void main() {
  testWidgets('renders requests screen for discover', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          requestsProvider.overrideWith((ref) async => <SeerrRequest>[]),
        ],
        child: const MaterialApp(
          home: ActivityScreen(serviceType: ServiceType.discover),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Requests'), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(ActivityTab), findsNothing);
    expect(find.byType(WantedTab), findsNothing);
    expect(find.text('No requests yet'), findsOneWidget);
  });

  testWidgets('renders tabbed activity screen for movies', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          radarrServiceProvider.overrideWith((ref) => FakeRadarrService()),
        ],
        child: const MaterialApp(
          home: ActivityScreen(serviceType: ServiceType.movies),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Movies Activity'), findsOneWidget);
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Wanted'), findsOneWidget);
    expect(find.byType(ActivityTab), findsOneWidget);

    await tester.tap(find.text('Wanted'));
    await tester.pumpAndSettle();

    expect(find.byType(WantedTab), findsOneWidget);
  });

  testWidgets('renders global activity with sections, grouping and filter', (
    tester,
  ) async {
    final scope = await settingsScope(configured: activityServiceKeys);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => scope.prefs),
          secureSettingsStoreProvider.overrideWith((ref) => scope.secureStore),
          initialSettingsProvider.overrideWith((ref) => scope.settings),
          initialOnboardingCompletedProvider.overrideWith((ref) => true),
          requestsProvider.overrideWith(
            (ref) async => const [
              SeerrRequest(
                id: 1,
                status: RequestStatus.approved,
                media: RequestMedia(title: 'Shogun'),
                createdAt: '2026-04-03T09:05:00Z',
                type: 'tv',
                requestedBy: RequestedBy(id: 1, displayName: 'sarah'),
              ),
            ],
          ),
          seerrServiceProvider.overrideWith((ref) => FakeSeerrService()),
          radarrServiceProvider.overrideWith(
            (ref) => _ActivityRadarrService(
              queue: const [
                {
                  'title': 'Furiosa.2024.2160p.WEB-DL-GROUP',
                  'status': 'downloading',
                  'size': 100,
                  'sizeleft': 25,
                  'movie': {'title': 'Furiosa', 'year': 2024},
                },
              ],
              history: const [
                {
                  'sourceTitle': 'Dune.Part.Two.2024',
                  'eventType': 'downloadImported',
                  'date': '2026-04-02T11:18:00Z',
                  'movie': {'title': 'Dune: Part Two', 'year': 2024},
                },
              ],
              missing: const [
                {'title': 'Kingdom of the Planet of the Apes'},
              ],
            ),
          ),
          sonarrServiceProvider.overrideWith((ref) => FakeSonarrService()),
          lidarrServiceProvider.overrideWith((ref) => FakeLidarrService()),
        ],
        child: const MaterialApp(home: GlobalActivityScreen()),
      ),
    );

    await tester.pumpAndSettle();

    // Three clear top-level sections replace the old seven tabs.
    expect(find.text('Activity'), findsWidgets);
    for (final label in ['Now', 'History', 'Wanted']) {
      expect(find.text(label), findsOneWidget);
    }

    // "Now" merges active downloads (queue) with current requests, grouped by
    // service.
    expect(find.text('Furiosa'), findsOneWidget);
    expect(find.text('Shogun'), findsOneWidget);
    expect(
      find.textContaining('Furiosa.2024.2160p.WEB-DL-GROUP'),
      findsOneWidget,
    );

    // Switch to the Wanted section.
    await tester.tap(find.text('Wanted'));
    await tester.pumpAndSettle();

    expect(find.text('Kingdom of the Planet of the Apes'), findsOneWidget);
    expect(find.text('Furiosa'), findsNothing);
  });

  testWidgets('the Now bucket pills the two directions of traffic, not the '
      'service axis', (tester) async {
    final scope = await settingsScope(configured: activityServiceKeys);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => scope.prefs),
          secureSettingsStoreProvider.overrideWith((ref) => scope.secureStore),
          initialSettingsProvider.overrideWith((ref) => scope.settings),
          initialOnboardingCompletedProvider.overrideWith((ref) => true),
          requestsProvider.overrideWith((ref) async => const <SeerrRequest>[]),
          seerrServiceProvider.overrideWith((ref) => FakeSeerrService()),
          radarrServiceProvider.overrideWith((ref) => FakeRadarrService()),
          sonarrServiceProvider.overrideWith((ref) => FakeSonarrService()),
          lidarrServiceProvider.overrideWith((ref) => FakeLidarrService()),
        ],
        child: const MaterialApp(home: GlobalActivityScreen()),
      ),
    );

    await tester.pumpAndSettle();

    // "Now" used to carry an `All / Queue / Requests` pill row directly above the
    // service strip, and those two controls filtered the same axis: "Requests"
    // selects Seerr's rows and "Queue" selects the three \*arrs', which is exactly
    // what picking a service in the strip does. Two stacked rows filtering one
    // axis is what made the header read as a single confusing bank. Those pills
    // are still gone, and must stay gone.
    expect(find.text('Queue'), findsNothing);
    expect(find.text('Requests'), findsNothing);

    // The row is back, but on a genuinely different axis: ingress against egress.
    // A download and a playback are two record types no service filter reaches
    // one from the other, which is exactly the bar the surviving pills elsewhere
    // had to clear. The bucket previously showed no row at all only because it
    // held one type — and its label was "All", which was never true of a bucket
    // that carried only the incoming half.
    expect(find.byType(SelectionPills<int>), findsOneWidget);
    expect(find.text('Downloading'), findsOneWidget);
    expect(find.text('Streaming'), findsOneWidget);
    expect(find.text('All'), findsNothing);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    // History keeps its pills, because a blocklist entry is a different *record
    // type* — a second axis no service filter can reach.
    expect(find.byType(SelectionPills<int>), findsOneWidget);
    expect(find.text('Blocklist'), findsOneWidget);
  });

  testWidgets('buckets are swipeable, not just tappable', (tester) async {
    final scope = await settingsScope(configured: activityServiceKeys);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => scope.prefs),
          secureSettingsStoreProvider.overrideWith((ref) => scope.secureStore),
          initialSettingsProvider.overrideWith((ref) => scope.settings),
          initialOnboardingCompletedProvider.overrideWith((ref) => true),
          requestsProvider.overrideWith((ref) async => const <SeerrRequest>[]),
          seerrServiceProvider.overrideWith((ref) => FakeSeerrService()),
          radarrServiceProvider.overrideWith((ref) => FakeRadarrService()),
          sonarrServiceProvider.overrideWith((ref) => FakeSonarrService()),
          lidarrServiceProvider.overrideWith((ref) => FakeLidarrService()),
        ],
        child: const MaterialApp(home: GlobalActivityScreen()),
      ),
    );

    await tester.pumpAndSettle();

    // The point of moving the buckets into a `TabBar`: the previous
    // `SegmentedButton` had no gesture at all, so on a phone every bucket change
    // was a deliberate reach for a small target.
    await tester.fling(find.byType(TabBarView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.byType(SelectionPills<int>), findsOneWidget);
    expect(find.text('Blocklist'), findsOneWidget);
  });

  testWidgets('a poll tick refreshes in place instead of blanking the list', (
    tester,
  ) async {
    // Regression: the bucket read `feedAsync.asData?.value`, which is null
    // while a provider is *reloading* — and the "Now" bucket bumps
    // `activityRefreshVersionProvider` every 15 seconds, which every feed
    // provider watches. So on every tick the whole list was replaced by
    // shimmer, the service strip's counts fell back to a dash, and the
    // hairline "refreshing" bar the screen carries could never appear.
    final scope = await settingsScope(configured: activityServiceKeys);
    // The second fetch is held open on purpose: an in-flight reload is the
    // whole state under test, and a fake that answers instantly never renders
    // one.
    final radarr = _GatedRadarrService(
      queue: const [
        {
          'title': 'Furiosa.2024.2160p.WEB-DL-GROUP',
          'status': 'downloading',
          'size': 100,
          'sizeleft': 25,
          'movie': {'title': 'Furiosa', 'year': 2024},
        },
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => scope.prefs),
          secureSettingsStoreProvider.overrideWith((ref) => scope.secureStore),
          initialSettingsProvider.overrideWith((ref) => scope.settings),
          initialOnboardingCompletedProvider.overrideWith((ref) => true),
          requestsProvider.overrideWith((ref) async => const <SeerrRequest>[]),
          seerrServiceProvider.overrideWith((ref) => FakeSeerrService()),
          radarrServiceProvider.overrideWith((ref) => radarr),
          sonarrServiceProvider.overrideWith((ref) => FakeSonarrService()),
          lidarrServiceProvider.overrideWith((ref) => FakeLidarrService()),
        ],
        child: const MaterialApp(home: GlobalActivityScreen()),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Furiosa'), findsOneWidget);

    // Drive the real mechanism: the 15s poll timer, not a hand-rolled bump.
    await tester.pump(const Duration(seconds: 16));
    expect(radarr.queueCalls, greaterThan(1));

    // Mid-reload the previous feed is still on screen …
    expect(find.text('Furiosa'), findsOneWidget);
    // … and it is *not* the skeleton, which is what the user used to get.
    expect(find.byType(ShimmerList), findsNothing);
    // The strip still knows how many rows there are, rather than shrugging.
    expect(find.text('–'), findsNothing);
    // And the hairline refresh bar — dead code until now, because the flag that
    // gates it could never be true — is the thing that says "updating".
    expect(
      tester
          .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .any((bar) => bar.value == null),
      isTrue,
    );

    // Let the refetch land; the row survives that too, and the bar goes away.
    radarr.release();
    await tester.pumpAndSettle();
    expect(find.text('Furiosa'), findsOneWidget);
    expect(find.byType(ShimmerList), findsNothing);
    expect(
      tester
          .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .any((bar) => bar.value == null),
      isFalse,
    );
  });

  testWidgets('tapping a request pushes the requests screen with a way back', (
    tester,
  ) async {
    // Regression: this row used to call `context.go`. `/activity/:type` is a
    // root-navigator route *outside* the ShellRoute, so it has no bottom nav bar
    // of its own — and `go` replaces the stack rather than pushing onto it, which
    // left `Navigator.canPop()` false and the app bar with no back entry to imply
    // a leading button from. Tapping a request stranded the user on the requests
    // list with no nav bar and no back: a dead end.
    final scope = await settingsScope(configured: activityServiceKeys);

    final router = GoRouter(
      initialLocation: '/activity',
      routes: [
        GoRoute(
          path: '/activity',
          builder: (context, state) => const GlobalActivityScreen(),
        ),
        GoRoute(
          path: '/activity/:type',
          builder: (context, state) => ActivityScreen(
            serviceType: ServiceType.values.firstWhere(
              (e) => e.name == state.pathParameters['type'],
              orElse: () => ServiceType.movies,
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => scope.prefs),
          secureSettingsStoreProvider.overrideWith((ref) => scope.secureStore),
          initialSettingsProvider.overrideWith((ref) => scope.settings),
          initialOnboardingCompletedProvider.overrideWith((ref) => true),
          requestsProvider.overrideWith(
            (ref) async => const [
              SeerrRequest(
                id: 1,
                status: RequestStatus.approved,
                media: RequestMedia(title: 'Shogun'),
                createdAt: '2026-04-03T09:05:00Z',
                type: 'tv',
                requestedBy: RequestedBy(id: 1, displayName: 'sarah'),
              ),
            ],
          ),
          seerrServiceProvider.overrideWith((ref) => FakeSeerrService()),
          radarrServiceProvider.overrideWith((ref) => FakeRadarrService()),
          sonarrServiceProvider.overrideWith((ref) => FakeSonarrService()),
          lidarrServiceProvider.overrideWith((ref) => FakeLidarrService()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Shogun'), findsOneWidget);

    await tester.tap(find.text('Shogun'));
    await tester.pumpAndSettle();

    // Arrived, and the route below is still on the stack.
    expect(find.byType(RequestsList), findsOneWidget);
    expect(router.canPop(), isTrue);

    // And there is a visible way back, because the app bar can imply one.
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byType(GlobalActivityScreen), findsOneWidget);
  });
}

/// Answers the first queue fetch immediately and holds every later one open
/// until [release], so a test can inspect the screen mid-reload.
class _GatedRadarrService extends FakeRadarrService {
  _GatedRadarrService({required this.queue});

  final List<dynamic> queue;
  final Completer<List<dynamic>> _gate = Completer<List<dynamic>>();
  int queueCalls = 0;

  void release() {
    if (!_gate.isCompleted) _gate.complete(queue);
  }

  @override
  Future<List<dynamic>> getQueue({Map<String, dynamic>? queryParameters}) {
    queueCalls++;
    return queueCalls == 1 ? Future.value(queue) : _gate.future;
  }
}

class _ActivityRadarrService extends FakeRadarrService {
  _ActivityRadarrService({
    this.queue = const [],
    this.history = const [],
    this.missing = const [],
  });

  final List<dynamic> queue;
  final List<dynamic> history;
  final List<dynamic> missing;

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => queue;

  @override
  Future<List<dynamic>> getHistory({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async => history;

  @override
  Future<List<dynamic>> getAllHistory({
    Map<String, dynamic>? queryParameters,
  }) async => history;

  @override
  Future<List<dynamic>> getMissing({int page = 1, int pageSize = 20}) async =>
      missing;

  @override
  Future<List<dynamic>> getAllMissing() async => missing;
}
