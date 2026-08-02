import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/router.dart';
import 'package:seekarr/features/discover/data/seerr_service.dart';
import 'package:seekarr/features/discover/presentation/discover_detail_screen.dart';
import 'package:seekarr/features/movies/data/radarr_service.dart';
import 'package:seekarr/features/movies/presentation/movie_detail_screen.dart';
import 'package:seekarr/features/music/data/lidarr_service.dart';
import 'package:seekarr/features/music/presentation/music_detail_screen.dart';
import 'package:seekarr/features/onboarding/data/onboarding_provider.dart';
import 'package:seekarr/features/onboarding/presentation/onboarding_screen.dart';
import 'package:seekarr/features/search/presentation/search_screen.dart';
import 'package:seekarr/features/series/data/sonarr_service.dart';
import 'package:seekarr/features/series/presentation/series_detail_screen.dart';
import 'package:seekarr/features/services/presentation/service_all_screens.dart';
import 'package:seekarr/features/services/presentation/services_screen.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';
import 'package:seekarr/features/settings/presentation/settings_appearance_screen.dart';
import 'package:seekarr/features/settings/presentation/settings_connections_screen.dart';
import 'package:seekarr/features/settings/presentation/service_settings_screen.dart';

import '../test_helpers/fake_services.dart';
import '../test_helpers/model_builders.dart';

void main() {
  group('routerProvider', () {
    testWidgets('starts on services', (tester) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      expect(router.state.uri.toString(), '/services');
      expect(find.byType(ServicesScreen), findsOneWidget);
    });

    testWidgets('starts on onboarding when onboarding is incomplete', (
      tester,
    ) async {
      final container = await _pumpRouter(tester, onboardingCompleted: false);
      final router = container.read(routerProvider);

      expect(router.state.uri.toString(), '/onboarding');
      expect(find.byType(OnboardingScreen), findsOneWidget);
    });

    testWidgets(
      'redirects protected routes to onboarding when onboarding is incomplete',
      (tester) async {
        final container = await _pumpRouter(tester, onboardingCompleted: false);
        final router = container.read(routerProvider);

        router.go('/search');
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), '/onboarding');
        expect(find.byType(OnboardingScreen), findsOneWidget);
        expect(find.byType(SearchScreen), findsNothing);
      },
    );

    testWidgets('redirects to services when onboarding completes', (
      tester,
    ) async {
      final container = await _pumpRouter(tester, onboardingCompleted: false);
      final router = container.read(routerProvider);

      container.read(onboardingCompletedProvider.notifier).state = true;
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), '/services');
      expect(find.byType(ServicesScreen), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
    });

    testWidgets('redirects invalid discover detail ids back to services', (
      tester,
    ) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go('/services/seerr/movie/not-a-number');
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), '/services');
      expect(find.byType(ServicesScreen), findsOneWidget);
      expect(find.byType(DiscoverDetailScreen), findsNothing);
    });

    testWidgets(
      'preserves discover detail default hero tag and posterUrl decoding',
      (tester) async {
        final container = await _pumpRouter(tester);
        final router = container.read(routerProvider);
        const encodedPosterUrl =
            'https%3A%2F%2Fcdn.example.com%2Fposter%20image.jpg';

        router.go('/services/seerr/movie/123?posterUrl=$encodedPosterUrl');
        await tester.pumpAndSettle();

        final screen = tester.widget<DiscoverDetailScreen>(
          find.byType(DiscoverDetailScreen),
        );

        expect(
          router.state.uri.toString(),
          '/services/seerr/movie/123?posterUrl=$encodedPosterUrl',
        );
        expect(screen.mediaId, 123);
        expect(screen.mediaType, 'movie');
        expect(screen.heroTag, 'discover_movie_123');
        expect(
          screen.initialPosterUrl,
          'https://cdn.example.com/poster image.jpg',
        );
      },
    );

    testWidgets(
      'supports deep-linked library detail routes without extras and preserves default hero tags',
      (tester) async {
        final container = await _pumpRouter(tester);
        final router = container.read(routerProvider);

        router.go('/services/radarr/movie/42');
        await tester.pumpAndSettle();

        final movieScreen = tester.widget<MovieDetailScreen>(
          find.byType(MovieDetailScreen),
        );
        expect(movieScreen.heroTag, 'movie_42');
        expect(movieScreen.movieId, 42);
        expect(movieScreen.initialMovie, isNull);

        router.go('/services/sonarr/series/55');
        await tester.pumpAndSettle();

        final seriesScreen = tester.widget<SeriesDetailScreen>(
          find.byType(SeriesDetailScreen),
        );
        expect(seriesScreen.heroTag, 'series_55');
        expect(seriesScreen.seriesId, 55);
        expect(seriesScreen.initialSeries, isNull);

        router.go('/services/lidarr/artist/9');
        await tester.pumpAndSettle();

        final musicScreen = tester.widget<MusicDetailScreen>(
          find.byType(MusicDetailScreen),
        );
        expect(musicScreen.heroTag, 'artist_9');
        expect(musicScreen.artistId, 9);
        expect(musicScreen.initialArtist, isNull);
      },
    );

    testWidgets('redirects invalid library detail ids back to services', (
      tester,
    ) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go(
        '/services/radarr/movie/not-a-number',
        extra: buildMovie(id: 42),
      );
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), '/services');
      expect(find.byType(ServicesScreen), findsOneWidget);
      expect(find.byType(MovieDetailScreen), findsNothing);
    });

    testWidgets(
      'library detail routes ignore wrong-type and mismatched extras instead of redirecting',
      (tester) async {
        final container = await _pumpRouter(tester);
        final router = container.read(routerProvider);

        router.go('/services/radarr/movie/42', extra: buildArtist(id: 9));
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), '/services/radarr/movie/42');
        var movieScreen = tester.widget<MovieDetailScreen>(
          find.byType(MovieDetailScreen),
        );
        expect(movieScreen.movieId, 42);
        expect(movieScreen.initialMovie, isNull);

        router.go('/services/radarr/movie/42', extra: buildMovie(id: 7));
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), '/services/radarr/movie/42');
        movieScreen = tester.widget<MovieDetailScreen>(
          find.byType(MovieDetailScreen),
        );
        expect(movieScreen.movieId, 42);
        expect(movieScreen.initialMovie?.id, 7);
      },
    );

    testWidgets('unknown service settings routes fall back to seerr', (
      tester,
    ) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go('/settings/service/not-a-service');
      await tester.pumpAndSettle();

      final screen = tester.widget<ServiceSettingsScreen>(
        find.byType(ServiceSettingsScreen),
      );

      expect(screen.service, ServiceKey.seerr);
      expect(find.text('Seerr Settings'), findsOneWidget);
    });

    testWidgets('supports appearance and connections settings subroutes', (
      tester,
    ) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go('/settings/appearance');
      await tester.pumpAndSettle();

      expect(find.byType(SettingsAppearanceScreen), findsOneWidget);

      router.go('/settings/connections');
      await tester.pumpAndSettle();

      expect(find.byType(SettingsConnectionsScreen), findsOneWidget);
    });

    testWidgets('the old services settings path redirects to connections', (
      tester,
    ) async {
      // '/settings/services' was the route before the two service lists were
      // merged; a saved deep link should land on the screen that replaced it
      // rather than 404.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go('/settings/services');
      await tester.pumpAndSettle();

      expect(find.byType(SettingsConnectionsScreen), findsOneWidget);
      expect(router.state.uri.toString(), '/settings/connections');
    });

    testWidgets('supports global search route', (tester) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go('/search');
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), '/search');
      expect(find.byType(SearchScreen), findsOneWidget);
    });

    testWidgets('supports service dashboard routes', (tester) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      for (final route in [
        '/services/seerr',
        '/services/radarr',
        '/services/sonarr',
        '/services/lidarr',
      ]) {
        router.go(route);
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), route);
      }
    });

    testWidgets('supports service all-list routes', (tester) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go('/services/seerr/requests');
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), '/services/seerr/requests');
      expect(find.byType(ServiceAllRequestsScreen), findsOneWidget);

      for (final entry in {
        '/services/radarr/media': ServiceKey.radarr,
        '/services/sonarr/media': ServiceKey.sonarr,
        '/services/lidarr/media': ServiceKey.lidarr,
      }.entries) {
        router.go(entry.key);
        await tester.pumpAndSettle();

        expect(
          router.state.uri.toString(),
          '/services/${entry.value.routeParam}',
        );
        expect(find.byType(ServiceAllRequestsScreen), findsNothing);
      }
    });

    testWidgets('legacy top-level routes redirect to services', (tester) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      for (final route in ['/discover', '/movies', '/series', '/music']) {
        router.go(route);
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), '/services');
        expect(find.byType(ServicesScreen), findsOneWidget);
      }
    });

    testWidgets('legacy detail routes redirect to equivalent services routes', (
      tester,
    ) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      const encodedPosterUrl =
          'https%3A%2F%2Fcdn.example.com%2Fposter%20image.jpg';
      router.go('/discover/movie/123?posterUrl=$encodedPosterUrl');
      await tester.pumpAndSettle();

      expect(
        router.state.uri.toString(),
        '/services/seerr/movie/123?posterUrl=$encodedPosterUrl',
      );
      expect(find.byType(DiscoverDetailScreen), findsOneWidget);

      router.go('/movies/42?heroTag=legacy_movie');
      await tester.pumpAndSettle();

      expect(
        router.state.uri.toString(),
        '/services/radarr/movie/42?heroTag=legacy_movie',
      );
      expect(find.byType(MovieDetailScreen), findsOneWidget);

      router.go('/series/55?heroTag=legacy_series');
      await tester.pumpAndSettle();

      expect(
        router.state.uri.toString(),
        '/services/sonarr/series/55?heroTag=legacy_series',
      );
      expect(find.byType(SeriesDetailScreen), findsOneWidget);

      router.go('/music/9?heroTag=legacy_artist');
      await tester.pumpAndSettle();

      expect(
        router.state.uri.toString(),
        '/services/lidarr/artist/9?heroTag=legacy_artist',
      );
      expect(find.byType(MusicDetailScreen), findsOneWidget);
    });
  });
}

Future<ProviderContainer> _pumpRouter(
  WidgetTester tester, {
  SettingsModel settings = const SettingsModel(),
  bool onboardingCompleted = true,
}) async {
  final container = ProviderContainer(
    overrides: [
      initialOnboardingCompletedProvider.overrideWith(
        (ref) => onboardingCompleted,
      ),
      currentSettingsProvider.overrideWith((ref) => settings),
      seerrServiceProvider.overrideWith((ref) => FakeSeerrService()),
      radarrServiceProvider.overrideWith((ref) => FakeRadarrService()),
      sonarrServiceProvider.overrideWith((ref) => FakeSonarrService()),
      lidarrServiceProvider.overrideWith((ref) => FakeLidarrService()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: container.read(routerProvider)),
    ),
  );
  await tester.pumpAndSettle();

  return container;
}
