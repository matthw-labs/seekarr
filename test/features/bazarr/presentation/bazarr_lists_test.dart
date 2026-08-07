import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/features/bazarr/data/bazarr_service.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_library_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_movie_detail_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_series_detail_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_wanted_screen.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_bazarr_service.dart';

const _settings = SettingsModel(
  bazarrUrl: 'http://bazarr.local',
  bazarrApiKey: 'key',
);

Widget _wrap({required Widget child, required BazarrService service}) {
  return ProviderScope(
    overrides: [
      currentSettingsProvider.overrideWith((ref) => _settings),
      bazarrServiceProvider.overrideWith((ref) => service),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('BazarrWantedScreen shows tabs and renders wanted items', (
    tester,
  ) async {
    final fake = FakeBazarrService()
      ..wantedEpisodesResult = const BazarrPagedResult(
        data: [
          BazarrWantedItem(
            seriesTitle: 'Foundation',
            episodeTitle: 'The Emperor',
            episodeNumber: '1x01',
            sonarrSeriesId: 7,
            missingLanguages: [BazarrSubtitleLanguage(code2: 'en')],
          ),
        ],
        total: 1,
      );

    await tester.pumpWidget(
      _wrap(child: const BazarrWantedScreen(), service: fake),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Wanted Subtitles'), findsOneWidget);
    expect(find.text('Episodes'), findsOneWidget);
    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Foundation'), findsOneWidget);
    expect(find.textContaining('The Emperor'), findsOneWidget);
  });

  testWidgets('BazarrWantedScreen shows empty state when nothing is wanted', (
    tester,
  ) async {
    final fake = FakeBazarrService();
    await tester.pumpWidget(
      _wrap(child: const BazarrWantedScreen(), service: fake),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('No wanted subtitles'), findsOneWidget);
  });

  testWidgets('BazarrWantedScreen shows retryable error when the call fails', (
    tester,
  ) async {
    final fake = FakeBazarrService()..throwOnCall = Exception('boom');
    await tester.pumpWidget(
      _wrap(child: const BazarrWantedScreen(), service: fake),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Failed to load wanted episodes'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('BazarrLibraryScreen shows tabs and renders series entries', (
    tester,
  ) async {
    final fake = FakeBazarrService()
      ..seriesResult = const BazarrPagedResult(
        data: [
          BazarrSeries(
            sonarrSeriesId: 1,
            title: 'Foundation',
            year: 2021,
            monitored: true,
          ),
        ],
        total: 1,
      );

    await tester.pumpWidget(
      _wrap(child: const BazarrLibraryScreen(), service: fake),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Series'), findsOneWidget);
    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Foundation'), findsOneWidget);
  });

  testWidgets(
    'BazarrLibraryScreen shows empty state when no items are present',
    (tester) async {
      final fake = FakeBazarrService();
      await tester.pumpWidget(
        _wrap(child: const BazarrLibraryScreen(), service: fake),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('No items found'), findsOneWidget);
    },
  );

  testWidgets('BazarrLibraryScreen shows retryable error when the call fails', (
    tester,
  ) async {
    final fake = FakeBazarrService()..throwOnCall = Exception('boom');
    await tester.pumpWidget(
      _wrap(child: const BazarrLibraryScreen(), service: fake),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Failed to load library'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets(
    'BazarrLibraryScreen tapping a series row navigates to the series detail',
    (tester) async {
      const series = BazarrSeries(
        sonarrSeriesId: 7,
        title: 'Foundation',
        year: 2021,
        monitored: true,
      );
      final fake = FakeBazarrService()
        ..seriesResult = const BazarrPagedResult(data: [series], total: 1)
        ..seriesByIdOverride = series;

      final router = GoRouter(
        initialLocation: '/services/bazarr/library',
        routes: [
          GoRoute(
            path: '/services/bazarr/library',
            builder: (context, state) => const BazarrLibraryScreen(),
          ),
          GoRoute(
            path: '/services/bazarr/series/:id',
            builder: (context, state) => BazarrSeriesDetailScreen(
              sonarrSeriesId: int.parse(state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/services/bazarr/movie/:id',
            builder: (context, state) => BazarrMovieDetailScreen(
              radarrId: int.parse(state.pathParameters['id']!),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentSettingsProvider.overrideWith((ref) => _settings),
            bazarrServiceProvider.overrideWith((ref) => fake),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      // Tap the series row.
      await tester.tap(find.text('Foundation'));
      await tester.pumpAndSettle();

      expect(find.byType(BazarrSeriesDetailScreen), findsOneWidget);
      expect(router.state.uri.path, '/services/bazarr/series/7');
    },
  );

  testWidgets(
    'BazarrLibraryScreen tapping a movie row navigates to the movie detail',
    (tester) async {
      const movie = BazarrMovie(
        radarrId: 12,
        title: 'Inception',
        year: 2010,
        monitored: true,
      );
      final fake = FakeBazarrService()
        ..moviesResult = const BazarrPagedResult(data: [movie], total: 1)
        ..movieByIdOverride = movie;

      final router = GoRouter(
        initialLocation: '/services/bazarr/library',
        routes: [
          GoRoute(
            path: '/services/bazarr/library',
            builder: (context, state) => const BazarrLibraryScreen(),
          ),
          GoRoute(
            path: '/services/bazarr/series/:id',
            builder: (context, state) => BazarrSeriesDetailScreen(
              sonarrSeriesId: int.parse(state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/services/bazarr/movie/:id',
            builder: (context, state) => BazarrMovieDetailScreen(
              radarrId: int.parse(state.pathParameters['id']!),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentSettingsProvider.overrideWith((ref) => _settings),
            bazarrServiceProvider.overrideWith((ref) => fake),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to the Movies tab.
      await tester.tap(find.text('Movies'));
      await tester.pumpAndSettle();

      // Tap the movie row.
      await tester.tap(find.textContaining('Inception'));
      await tester.pumpAndSettle();

      expect(find.byType(BazarrMovieDetailScreen), findsOneWidget);
      expect(router.state.uri.path, '/services/bazarr/movie/12');
    },
  );
}
