import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/features/discover/presentation/discover_navigation_utils.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_services.dart' as shared;
import '../../../test_helpers/model_builders.dart';

void main() {
  group('openMediaInService', () {
    testWidgets('navigates to movie detail and calls dismissSheet', (
      tester,
    ) async {
      final radarrService = _FakeRadarr(movie: buildMovie(id: 7));
      final result = ValueNotifier<bool?>(null);
      var dismissCount = 0;

      await _pumpHarness(
        tester,
        settings: const SettingsModel(
          radarrUrl: 'https://radarr.example.com',
          radarrApiKey: 'key',
        ),
        radarrService: radarrService,
        onPressed: (context, ref) async {
          result.value = await openMediaInService(
            context: context,
            ref: ref,
            mediaType: 'movie',
            tmdbId: 123,
            dismissSheet: () => dismissCount += 1,
          );
        },
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(result.value, isTrue);
      expect(dismissCount, 1);
      expect(radarrService.getMovieByTmdbIdCallCount, 1);
      expect(find.text('movie:7'), findsOneWidget);
    });

    testWidgets('shows configuration dialog by default', (tester) async {
      final result = ValueNotifier<bool?>(null);

      await _pumpHarness(
        tester,
        settings: const SettingsModel(),
        onPressed: (context, ref) async {
          result.value = await openMediaInService(
            context: context,
            ref: ref,
            mediaType: 'movie',
            tmdbId: 123,
          );
        },
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(result.value, isFalse);
      expect(find.text('Radarr Not Configured'), findsOneWidget);
      expect(
        find.text('Please configure Radarr in Settings to use this feature.'),
        findsOneWidget,
      );
    });

    testWidgets('can skip configuration alert and use custom movie message', (
      tester,
    ) async {
      final result = ValueNotifier<bool?>(null);

      await _pumpHarness(
        tester,
        settings: const SettingsModel(),
        radarrService: _FakeRadarr(),
        onPressed: (context, ref) async {
          result.value = await openMediaInService(
            context: context,
            ref: ref,
            mediaType: 'movie',
            tmdbId: 123,
            showConfigurationAlert: false,
            movieNotFoundMessage: 'Movie not found in Radarr',
          );
        },
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(result.value, isFalse);
      expect(find.text('Radarr Not Configured'), findsNothing);
      expect(find.text('Movie not found in Radarr'), findsOneWidget);
    });

    testWidgets('can skip configuration alert and use custom series message', (
      tester,
    ) async {
      final result = ValueNotifier<bool?>(null);

      await _pumpHarness(
        tester,
        settings: const SettingsModel(),
        sonarrService: _FakeSonarr(),
        onPressed: (context, ref) async {
          result.value = await openMediaInService(
            context: context,
            ref: ref,
            mediaType: 'tv',
            tmdbId: 123,
            tvdbId: 555,
            showConfigurationAlert: false,
            seriesNotFoundMessage: 'Series not found in Sonarr',
          );
        },
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(result.value, isFalse);
      expect(find.text('Sonarr Not Configured'), findsNothing);
      expect(find.text('Series not found in Sonarr'), findsOneWidget);
    });
  });
}

Future<void> _pumpHarness(
  WidgetTester tester, {
  required Future<void> Function(BuildContext context, WidgetRef ref) onPressed,
  required SettingsModel settings,
  _FakeRadarr? radarrService,
  _FakeSonarr? sonarrService,
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: Consumer(
              builder: (context, ref, child) => ElevatedButton(
                onPressed: () => onPressed(context, ref),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/services/radarr/movie/:id',
        builder: (context, state) =>
            Text('movie:${state.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/services/sonarr/series/:id',
        builder: (context, state) =>
            Text('series:${state.pathParameters['id']}'),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSettingsProvider.overrideWith((ref) => settings),
        if (radarrService != null)
          radarrServiceProvider.overrideWith((ref) => radarrService),
        if (sonarrService != null)
          sonarrServiceProvider.overrideWith((ref) => sonarrService),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeRadarr extends shared.FakeRadarrService {
  _FakeRadarr({this.movie});

  final RadarrMovie? movie;
  int getMovieByTmdbIdCallCount = 0;

  @override
  Future<RadarrMovie?> getMovieByTmdbId(int tmdbId) async {
    getMovieByTmdbIdCallCount += 1;
    return movie;
  }
}

class _FakeSonarr extends shared.FakeSonarrService {
  @override
  Future<SonarrSeries?> getSeriesByTvdbId(int tvdbId) async => null;
}
