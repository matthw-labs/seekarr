import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import '../../../test_helpers/reel_finders.dart';

void main() {
  testWidgets('shows not-configured message when Bazarr is not configured', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
        child: const MaterialApp(home: BazarrScreen()),
      ),
    );

    // Bazarr's private "is not configured yet." card was the fifth copy of this
    // state and now renders the shared `NotConfiguredPlaceholder`, so the
    // asserted strings are the shared widget's voice ("isn't set up" / "Open
    // Settings"). The invariant the test is actually about — an unconfigured
    // Bazarr shows the placeholder and a way to go fix it — is unchanged, and
    // asserting the widget type as well pins it to the shared implementation.
    expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
    expect(find.textContaining("isn't set up"), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
  });

  testWidgets('the not-configured button opens the Bazarr settings page', (
    tester,
  ) async {
    // The only thing that distinguishes `NotConfiguredPlaceholder.forService`
    // from the generic constructor is where its button lands — both paint the
    // same title and the same "Open Settings" label, so every assertion above
    // stays green if the deep link degrades to the Settings root. The private
    // card this replaced went straight to Bazarr's own form; that is the part
    // worth pinning.
    final router = GoRouter(
      initialLocation: '/services/bazarr',
      routes: [
        GoRoute(
          path: '/services/bazarr',
          builder: (context, state) => const BazarrScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SizedBox.shrink(),
          routes: [
            GoRoute(
              path: 'service/:service',
              builder: (context, state) => const SizedBox.shrink(),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.tap(find.text('Open Settings'));
    await tester.pumpAndSettle();

    expect(
      router.state.uri.toString(),
      '/settings/service/${ServiceKey.bazarr.routeParam}',
    );
  });

  testWidgets('shows dashboard with badges and wanted list', (tester) async {
    final badges = const BazarrBadges(
      episodes: 12,
      movies: 4,
      providers: 3,
      status: true,
      sonarrSignalR: true,
      radarrSignalR: false,
      announcements: 0,
    );

    final wantedItems = const [
      BazarrWantedItem(
        seriesTitle: 'Foundation',
        episodeNumber: '1x02',
        episodeTitle: 'The Emperor',
        sonarrSeriesId: 11,
        sonarrEpisodeId: 22,
        missingLanguages: [
          BazarrSubtitleLanguage(code2: 'en', name: 'English'),
          BazarrSubtitleLanguage(code2: 'es', name: 'Spanish'),
        ],
      ),
      BazarrWantedItem(
        title: 'Dune',
        radarrId: 7,
        sceneName: 'Dune.2021',
        missingLanguages: [
          BazarrSubtitleLanguage(code2: 'it', name: 'Italian'),
        ],
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => const SettingsModel(
              bazarrUrl: 'http://bazarr.local',
              bazarrApiKey: 'key',
            ),
          ),
          bazarrBadgesProvider.overrideWith((ref) async => badges),
          bazarrDashboardWantedProvider.overrideWith(
            (ref) async => wantedItems,
          ),
          bazarrDashboardHistoryProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: BazarrScreen()),
      ),
    );

    // Let futures resolve
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // Stat row
    expect(findLine('16'), findsOneWidget);
    expect(findLine('12'), findsOneWidget);
    expect(findLine('4'), findsOneWidget);
    expect(findLine('3'), findsOneWidget);

    // Wanted list
    expect(find.text('Foundation'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.textContaining('EN, ES'), findsOneWidget);

    // Section headers
    expect(find.text('Wanted Subtitles'), findsOneWidget);
    expect(find.text('Recent Activity'), findsOneWidget);

    // CTA
    expect(find.text('Add Provider'), findsOneWidget);
  });

  testWidgets('shows empty state when no wanted items exist', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => const SettingsModel(
              bazarrUrl: 'http://bazarr.local',
              bazarrApiKey: 'key',
            ),
          ),
          bazarrBadgesProvider.overrideWith(
            (ref) async => const BazarrBadges(
              episodes: 0,
              movies: 0,
              providers: 0,
              status: false,
              sonarrSignalR: false,
              radarrSignalR: false,
              announcements: 0,
            ),
          ),
          bazarrDashboardWantedProvider.overrideWith((ref) async => const []),
          bazarrDashboardHistoryProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: BazarrScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('0'), findsWidgets);
    expect(find.textContaining('No wanted subtitles'), findsOneWidget);
  });

  testWidgets('renders recent activity with parsed action and language code', (
    tester,
  ) async {
    const history = [
      BazarrHistoryItem(
        kind: BazarrHistoryKind.episode,
        title: 'Foundation',
        subtitle: 'The Emperor',
        languageLabel: 'en',
        provider: 'OpenSubtitles',
        actionCode: 1,
        timestamp: '2 days ago',
        parsedTimestamp: '06/03/26 21:15:00',
      ),
      BazarrHistoryItem(
        kind: BazarrHistoryKind.movie,
        title: 'Dune: Part Two',
        subtitle: 'upgraded subtitle',
        languageLabel: 'it',
        provider: 'Subscene',
        actionCode: 2,
        timestamp: '5 days ago',
        parsedTimestamp: '05/30/26 09:42:00',
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => const SettingsModel(
              bazarrUrl: 'http://bazarr.local',
              bazarrApiKey: 'key',
            ),
          ),
          bazarrBadgesProvider.overrideWith(
            (ref) async => const BazarrBadges(
              episodes: 12,
              movies: 4,
              providers: 3,
              status: true,
              sonarrSignalR: true,
              radarrSignalR: false,
              announcements: 0,
            ),
          ),
          bazarrDashboardWantedProvider.overrideWith((ref) async => const []),
          bazarrDashboardHistoryProvider.overrideWith((ref) async => history),
        ],
        child: const MaterialApp(home: BazarrScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Foundation'), findsOneWidget);
    expect(find.text('Dune: Part Two'), findsOneWidget);
    expect(find.text('DOWNLOADED'), findsOneWidget);
    expect(find.text('UPGRADED'), findsOneWidget);
    expect(find.textContaining('en · OpenSubtitles'), findsOneWidget);
    expect(find.textContaining('it · Subscene'), findsOneWidget);
  });

  testWidgets('shows retryable error state when wanted fails', (tester) async {
    // Drives the real BazarrScreen. The previous version of this test built a
    // hand-rolled replica of `_ErrorRetry` inside its own body and tapped that
    // — it stayed green with the widget it names deleted, which is worse than
    // no coverage because it hides the gap from a coverage report.
    var wantedLoads = 0;

    await tester.pumpWidget(
      ProviderScope(
        // Riverpod 3 re-runs a failed provider on its own exponential backoff
        // (200 ms and up), which would count as a "retry" here without anyone
        // tapping anything. Off, so the only thing that can re-run the load is
        // the button under test.
        retry: (_, _) => null,
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => const SettingsModel(
              bazarrUrl: 'http://bazarr.local',
              bazarrApiKey: 'key',
            ),
          ),
          bazarrBadgesProvider.overrideWith(
            (ref) async => const BazarrBadges(
              episodes: 0,
              movies: 0,
              providers: 0,
              status: false,
              sonarrSignalR: false,
              radarrSignalR: false,
              announcements: 0,
            ),
          ),
          bazarrDashboardWantedProvider.overrideWith((ref) async {
            wantedLoads++;
            throw Exception('bazarr is down');
          }),
          bazarrDashboardHistoryProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: BazarrScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(wantedLoads, 1);
    expect(find.text('Failed to load wanted subtitles'), findsOneWidget);

    // The retry has to re-run the failed load, not merely exist.
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(wantedLoads, 2);
    expect(find.text('Failed to load wanted subtitles'), findsOneWidget);
  });
}
