import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/rating_source.dart';
import 'package:cupola/features/discover/presentation/discover_detail_extras_provider.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart'
    as radarr;
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart'
    as sonarr;
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_services.dart' as shared;
import '../../../test_helpers/model_builders.dart';

void main() {
  group('discoverDetailExtrasProvider', () {
    ProviderContainer createContainer({
      required SettingsModel settings,
      _FakeRadarr? radarrService,
      _FakeSonarr? sonarrService,
    }) {
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => settings),
          if (radarrService != null)
            radarrServiceProvider.overrideWith((ref) => radarrService),
          if (sonarrService != null)
            sonarrServiceProvider.overrideWith((ref) => sonarrService),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('returns movie library status when Radarr finds the media', () async {
      final container = createContainer(
        settings: const SettingsModel(
          radarrUrl: 'https://radarr.example.com',
          radarrApiKey: 'radarr-key',
        ),
        radarrService: _FakeRadarr(movieByTmdbId: buildMovie(tmdbId: 123)),
      );

      final result = await container.read(
        discoverDetailExtrasProvider((
          mediaId: 123,
          mediaType: 'movie',
          tvdbId: null,
          voteAverage: 7.2,
        )).future,
      );

      expect(result.isInLibrary, isTrue);
      expect(result.libraryCheckDone, isTrue);
      expect(result.lookupRatings, isNull);
    });

    test('returns false when movie is missing from Radarr', () async {
      final container = createContainer(
        settings: const SettingsModel(
          radarrUrl: 'https://radarr.example.com',
          radarrApiKey: 'radarr-key',
        ),
        radarrService: _FakeRadarr(movieByTmdbId: null),
      );

      final result = await container.read(
        discoverDetailExtrasProvider((
          mediaId: 999,
          mediaType: 'movie',
          tvdbId: null,
          voteAverage: 7.2,
        )).future,
      );

      expect(result.isInLibrary, isFalse);
      expect(result.libraryCheckDone, isTrue);
    });

    test(
      'performs Sonarr library lookup for tv when configured with tvdbId',
      () async {
        final sonarrService = _FakeSonarr(seriesByTvdbId: buildSeries());
        final container = createContainer(
          settings: const SettingsModel(
            sonarrUrl: 'https://sonarr.example.com',
            sonarrApiKey: 'sonarr-key',
          ),
          sonarrService: sonarrService,
        );

        final result = await container.read(
          discoverDetailExtrasProvider((
            mediaId: 456,
            mediaType: 'tv',
            tvdbId: 555,
            voteAverage: 8.0,
          )).future,
        );

        expect(result.isInLibrary, isTrue);
        expect(result.libraryCheckDone, isTrue);
        expect(result.lookupRatings, isNull);
        expect(sonarrService.getSeriesByTvdbIdCallCount, 1);
      },
    );

    test('gracefully handles tv media without a tvdb id', () async {
      final sonarrService = _FakeSonarr(seriesByTvdbId: buildSeries());
      final container = createContainer(
        settings: const SettingsModel(
          sonarrUrl: 'https://sonarr.example.com',
          sonarrApiKey: 'sonarr-key',
        ),
        sonarrService: sonarrService,
      );

      final result = await container.read(
        discoverDetailExtrasProvider((
          mediaId: 456,
          mediaType: 'tv',
          tvdbId: null,
          voteAverage: null,
        )).future,
      );

      expect(result.isInLibrary, isNull);
      expect(result.libraryCheckDone, isFalse);
      expect(result.lookupRatings, isNull);
      expect(sonarrService.getSeriesByTvdbIdCallCount, 0);
      expect(sonarrService.lookupSeriesCallCount, 0);
    });

    test('skips service calls when Radarr is not configured', () async {
      final radarrService = _FakeRadarr(movieByTmdbId: buildMovie());
      final container = createContainer(
        settings: const SettingsModel(),
        radarrService: radarrService,
      );

      final result = await container.read(
        discoverDetailExtrasProvider((
          mediaId: 123,
          mediaType: 'movie',
          tvdbId: null,
          voteAverage: null,
        )).future,
      );

      expect(result.isInLibrary, isNull);
      expect(result.libraryCheckDone, isFalse);
      expect(result.lookupRatings, isNull);
      expect(radarrService.getMovieByTmdbIdCallCount, 0);
      expect(radarrService.lookupMoviesCallCount, 0);
    });

    test('loads fallback ratings when voteAverage is missing', () async {
      final radarrService = _FakeRadarr(
        movieByTmdbId: buildMovie(),
        lookupResults: [
          buildMovie(
            ratings: const [
              RatingSource(name: 'TMDB', value: 8.1, votes: 200, icon: 'TMDB'),
            ],
          ),
        ],
      );
      final container = createContainer(
        settings: const SettingsModel(
          radarrUrl: 'https://radarr.example.com',
          radarrApiKey: 'radarr-key',
        ),
        radarrService: radarrService,
      );

      final result = await container.read(
        discoverDetailExtrasProvider((
          mediaId: 123,
          mediaType: 'movie',
          tvdbId: null,
          voteAverage: null,
        )).future,
      );

      expect(result.lookupRatings, isNotNull);
      expect(result.lookupRatings, hasLength(1));
      final rating = result.lookupRatings!.single;
      expect(rating.name, 'TMDB');
      expect(rating.value, 8.1);
      expect(radarrService.lookupMoviesCallCount, 1);
    });

    test('loads tv fallback ratings when voteAverage is missing', () async {
      final sonarrService = _FakeSonarr(
        seriesByTvdbId: buildSeries(),
        lookupResults: [
          buildSeries(
            ratings: const [
              RatingSource(
                name: 'TVDB',
                value: 8.4,
                votes: 145000,
                icon: 'TVDB',
              ),
            ],
          ),
        ],
      );
      final container = createContainer(
        settings: const SettingsModel(
          sonarrUrl: 'https://sonarr.example.com',
          sonarrApiKey: 'sonarr-key',
        ),
        sonarrService: sonarrService,
      );

      final result = await container.read(
        discoverDetailExtrasProvider((
          mediaId: 456,
          mediaType: 'tv',
          tvdbId: 555,
          voteAverage: null,
        )).future,
      );

      expect(result.isInLibrary, isTrue);
      expect(result.lookupRatings, hasLength(1));
      expect(result.lookupRatings!.single.name, 'TVDB');
      expect(result.lookupRatings!.single.value, 8.4);
      expect(sonarrService.getSeriesByTvdbIdCallCount, 1);
      expect(sonarrService.lookupSeriesCallCount, 1);
    });

    test('returns false when series is not found in Sonarr', () async {
      final sonarrService = _FakeSonarr(seriesByTvdbId: null);
      final container = createContainer(
        settings: const SettingsModel(
          sonarrUrl: 'https://sonarr.example.com',
          sonarrApiKey: 'sonarr-key',
        ),
        sonarrService: sonarrService,
      );

      final result = await container.read(
        discoverDetailExtrasProvider((
          mediaId: 456,
          mediaType: 'tv',
          tvdbId: 555,
          voteAverage: 8.0,
        )).future,
      );

      expect(result.isInLibrary, isFalse);
      expect(result.libraryCheckDone, isTrue);
      expect(sonarrService.getSeriesByTvdbIdCallCount, 1);
    });

    test('skips Sonarr library lookup when Sonarr is not configured', () async {
      final sonarrService = _FakeSonarr(seriesByTvdbId: buildSeries());
      final container = createContainer(
        settings: const SettingsModel(),
        sonarrService: sonarrService,
      );

      final result = await container.read(
        discoverDetailExtrasProvider((
          mediaId: 456,
          mediaType: 'tv',
          tvdbId: 555,
          voteAverage: 8.0,
        )).future,
      );

      expect(result.isInLibrary, isNull);
      expect(result.libraryCheckDone, isFalse);
      expect(sonarrService.getSeriesByTvdbIdCallCount, 0);
    });

    test(
      'skips fallback ratings when voteAverage is already present',
      () async {
        final radarrService = _FakeRadarr(
          movieByTmdbId: buildMovie(),
          lookupResults: [
            buildMovie(
              ratings: const [
                RatingSource(
                  name: 'TMDB',
                  value: 8.1,
                  votes: 200,
                  icon: 'TMDB',
                ),
              ],
            ),
          ],
        );
        final container = createContainer(
          settings: const SettingsModel(
            radarrUrl: 'https://radarr.example.com',
            radarrApiKey: 'radarr-key',
          ),
          radarrService: radarrService,
        );

        final result = await container.read(
          discoverDetailExtrasProvider((
            mediaId: 123,
            mediaType: 'movie',
            tvdbId: null,
            voteAverage: 7.5,
          )).future,
        );

        expect(result.lookupRatings, isNull);
        expect(radarrService.lookupMoviesCallCount, 0);
      },
    );

    test('falls back cleanly when a service throws', () async {
      final container = createContainer(
        settings: const SettingsModel(
          radarrUrl: 'https://radarr.example.com',
          radarrApiKey: 'radarr-key',
        ),
        radarrService: _FakeRadarr(
          throwOnGetMovieByTmdbId: true,
          throwOnLookupMovies: true,
        ),
      );

      final result = await container.read(
        discoverDetailExtrasProvider((
          mediaId: 123,
          mediaType: 'movie',
          tvdbId: null,
          voteAverage: null,
        )).future,
      );

      expect(result.isInLibrary, isNull);
      expect(result.libraryCheckDone, isTrue);
      expect(result.lookupRatings, isNull);
    });

    test('falls back cleanly when Sonarr lookup throws', () async {
      final sonarrService = _FakeSonarr(
        throwOnGetSeriesByTvdbId: true,
        throwOnLookupSeries: true,
      );
      final container = createContainer(
        settings: const SettingsModel(
          sonarrUrl: 'https://sonarr.example.com',
          sonarrApiKey: 'sonarr-key',
        ),
        sonarrService: sonarrService,
      );

      final result = await container.read(
        discoverDetailExtrasProvider((
          mediaId: 456,
          mediaType: 'tv',
          tvdbId: 555,
          voteAverage: null,
        )).future,
      );

      expect(result.isInLibrary, isNull);
      expect(result.libraryCheckDone, isTrue);
      expect(result.lookupRatings, isNull);
      expect(sonarrService.getSeriesByTvdbIdCallCount, 1);
      expect(sonarrService.lookupSeriesCallCount, 1);
    });
  });
}

class _FakeRadarr extends shared.FakeRadarrService {
  _FakeRadarr({
    this.movieByTmdbId,
    this.lookupResults = const <radarr.RadarrMovie>[],
    this.throwOnGetMovieByTmdbId = false,
    this.throwOnLookupMovies = false,
  });

  final radarr.RadarrMovie? movieByTmdbId;
  final List<radarr.RadarrMovie> lookupResults;
  final bool throwOnGetMovieByTmdbId;
  final bool throwOnLookupMovies;

  int getMovieByTmdbIdCallCount = 0;
  int lookupMoviesCallCount = 0;

  @override
  Future<radarr.RadarrMovie?> getMovieByTmdbId(int tmdbId) async {
    getMovieByTmdbIdCallCount += 1;
    if (throwOnGetMovieByTmdbId) throw Exception('radarr lookup failed');
    return movieByTmdbId;
  }

  @override
  Future<List<radarr.RadarrMovie>> lookupMovies(
    String term, {
    CancelToken? cancelToken,
  }) async {
    lookupMoviesCallCount += 1;
    if (throwOnLookupMovies) throw Exception('radarr ratings lookup failed');
    return lookupResults;
  }
}

class _FakeSonarr extends shared.FakeSonarrService {
  _FakeSonarr({
    this.seriesByTvdbId,
    this.lookupResults = const <sonarr.SonarrSeries>[],
    this.throwOnGetSeriesByTvdbId = false,
    this.throwOnLookupSeries = false,
  });

  final sonarr.SonarrSeries? seriesByTvdbId;
  final List<sonarr.SonarrSeries> lookupResults;
  final bool throwOnGetSeriesByTvdbId;
  final bool throwOnLookupSeries;

  int getSeriesByTvdbIdCallCount = 0;
  int lookupSeriesCallCount = 0;

  @override
  Future<sonarr.SonarrSeries?> getSeriesByTvdbId(int tvdbId) async {
    getSeriesByTvdbIdCallCount += 1;
    if (throwOnGetSeriesByTvdbId) throw Exception('sonarr lookup failed');
    return seriesByTvdbId;
  }

  @override
  Future<List<sonarr.SonarrSeries>> lookupSeries(
    String term, {
    CancelToken? cancelToken,
  }) async {
    lookupSeriesCallCount += 1;
    if (throwOnLookupSeries) throw Exception('sonarr ratings lookup failed');
    return lookupResults;
  }
}
