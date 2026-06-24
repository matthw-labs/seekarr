import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/api/api_client.dart';
import 'package:seekarr/features/bazarr/data/bazarr_service.dart';
import 'package:seekarr/features/bazarr/presentation/bazarr_provider.dart';
import 'package:seekarr/features/bazarr/domain/models/bazarr_models.dart';
import 'package:seekarr/features/movies/data/radarr_service.dart';
import 'package:seekarr/features/movies/domain/models/radarr_movie.dart';
import 'package:seekarr/features/music/data/lidarr_service.dart';
import 'package:seekarr/features/music/domain/models/lidarr_album.dart';
import 'package:seekarr/features/music/domain/models/lidarr_artist.dart';
import 'package:seekarr/features/series/data/sonarr_service.dart';
import 'package:seekarr/features/services/domain/service_summary.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/model_builders.dart';

void main() {
  group('serviceSummaryProvider', () {
    test('returns offline summary when service is not configured', () async {
      final container = _container();

      final summary = await container.read(
        serviceSummaryProvider(ServiceKey.radarr).future,
      );

      expect(summary.service, ServiceKey.radarr);
      expect(summary.status, ServiceSummaryStatus.offline);
      expect(summary.host, isEmpty);
      expect(summary.countLabel, 'Offline');
    });

    test('returns online summary with version and item count', () async {
      final container = _container(
        settings: const SettingsModel(
          radarrUrl: 'http://radarr.local:7878',
          radarrApiKey: 'key',
        ),
        statusClient: _StatusClient({'version': '5.4.6'}),
        radarrService: _MoviesRadarrService([buildMovie(title: 'Dune')]),
      );

      final summary = await container.read(
        serviceSummaryProvider(ServiceKey.radarr).future,
      );

      expect(summary.status, ServiceSummaryStatus.online);
      expect(summary.host, 'radarr.local:7878');
      expect(summary.versionLabel, 'v5.4.6');
      expect(summary.countLabel, '1 movie');
    });

    test('returns offline summary when status endpoint fails', () async {
      final container = _container(
        settings: const SettingsModel(
          radarrUrl: 'http://radarr.local:7878',
          radarrApiKey: 'key',
        ),
        statusClient: _ThrowingStatusClient(),
        radarrService: _MoviesRadarrService([buildMovie(title: 'Dune')]),
      );

      final summary = await container.read(
        serviceSummaryProvider(ServiceKey.radarr).future,
      );

      expect(summary.status, ServiceSummaryStatus.offline);
      expect(summary.host, 'radarr.local:7878');
      expect(summary.countLabel, 'Offline');
    });

    test('keeps service online when only item count fails', () async {
      final container = _container(
        settings: const SettingsModel(
          radarrUrl: 'http://radarr.local:7878',
          radarrApiKey: 'key',
        ),
        statusClient: _StatusClient({'version': '5.4.6'}),
        radarrService: _ThrowingMoviesRadarrService(),
      );

      final summary = await container.read(
        serviceSummaryProvider(ServiceKey.radarr).future,
      );

      expect(summary.status, ServiceSummaryStatus.online);
      expect(summary.versionLabel, 'v5.4.6');
      expect(summary.countLabel, 'Summary unavailable');
    });
  });

  group('serviceSummaryProvider Bazarr', () {
    test('reads bazarr_version from the nested data envelope', () async {
      final container = _container(
        settings: const SettingsModel(
          bazarrUrl: 'http://bazarr.local:6767',
          bazarrApiKey: 'key',
        ),
        statusClient: _StatusClient({
          'data': {'bazarr_version': '1.4.5'},
        }),
        bazarrService: FakeBazarrService()
          ..badges = const BazarrBadges(
            episodes: 0,
            movies: 0,
            providers: 0,
            status: false,
            sonarrSignalR: false,
            radarrSignalR: false,
            announcements: 0,
          ),
      );

      final summary = await container.read(
        serviceSummaryProvider(ServiceKey.bazarr).future,
      );

      expect(summary.status, ServiceSummaryStatus.online);
      expect(summary.host, 'bazarr.local:6767');
      expect(summary.versionLabel, 'v1.4.5');
      expect(summary.countLabel, '0 subtitles');
    });

    test('totals wanted badges across episodes and movies', () async {
      final container = _container(
        settings: const SettingsModel(
          bazarrUrl: 'http://bazarr.local:6767',
          bazarrApiKey: 'key',
        ),
        statusClient: _StatusClient({
          'data': {'bazarr_version': '1.4.5'},
        }),
        bazarrService: FakeBazarrService()
          ..badges = const BazarrBadges(
            episodes: 12,
            movies: 4,
            providers: 3,
            status: true,
            sonarrSignalR: true,
            radarrSignalR: true,
            announcements: 0,
          ),
      );

      final summary = await container.read(
        serviceSummaryProvider(ServiceKey.bazarr).future,
      );

      expect(summary.countLabel, '16 subtitles');
    });
  });

  group('servicesQueueProvider', () {
    test(
      'combines Radarr and Sonarr queue items with media-first hierarchy',
      () async {
        final container = _container(
          radarrService: _QueueRadarrService([
            {
              'title': 'Furiosa.2024.2160p.WEB-DL-GROUP',
              'status': 'downloading',
              'size': 100,
              'sizeleft': 25,
              'movie': {'title': 'Furiosa', 'year': 2024},
              'quality': {
                'quality': {'name': 'WEB-DL 1080p'},
              },
            },
          ]),
          sonarrService: _QueueSonarrService([
            {
              'title': 'The.Boys.S04E07.1080p.WEB-DL-GROUP',
              'status': 'downloading',
              'size': 200,
              'sizeleft': 100,
              'series': {'title': 'The Boys'},
              'episode': {'seasonNumber': 4, 'episodeNumber': 7},
              'trackedDownloadStatus': 'warning',
              'statusMessages': ['Unable to Import Automatically'],
            },
            {
              'title': 'Shogun',
              'series': {'title': 'Shogun'},
            },
            {'title': 'Slow Horses'},
          ]),
        );

        final items = await container.read(servicesQueueProvider.future);

        expect(items, hasLength(3));
        expect(items[0].service, ServiceKey.radarr);
        expect(items[0].title, 'Furiosa');
        expect(items[0].subtitle, contains('Furiosa.2024.2160p.WEB-DL-GROUP'));
        expect(items[0].progress, 0.75);
        expect(items[1].service, ServiceKey.sonarr);
        expect(items[1].title, 'The Boys');
        expect(
          items[1].subtitle,
          contains('The.Boys.S04E07.1080p.WEB-DL-GROUP'),
        );
        expect(items[1].progress, 0.5);
        expect(items[2].title, 'Shogun');
        expect(items.map((item) => item.title), isNot(contains('Slow Horses')));
      },
    );

    test('keeps queue available when one service fails', () async {
      final container = _container(
        radarrService: _ThrowingRadarrService(),
        sonarrService: _QueueSonarrService([
          {'title': 'Shogun', 'size': 100, 'sizeleft': 0},
        ]),
      );

      final items = await container.read(servicesQueueProvider.future);

      expect(items, hasLength(1));
      expect(items.single.service, ServiceKey.sonarr);
      expect(items.single.title, 'Shogun');
    });
  });

  group('queued membership providers', () {
    test('extracts queued movie ids from Radarr queue items', () async {
      final container = _container(
        radarrService: _QueueRadarrService([
          {
            'movie': {'id': 10, 'title': 'Dune'},
          },
          {'movieId': 11},
          {'movieId': 0},
          'ignored',
        ]),
      );

      final ids = await container.read(radarrQueuedMovieIdsProvider.future);

      expect(ids, {10, 11});
    });

    test('extracts queued series ids from Sonarr queue items', () async {
      final container = _container(
        sonarrService: _QueueSonarrService([
          {
            'series': {'id': 20, 'title': 'The Boys'},
          },
          {'seriesId': 21},
          {'seriesId': -1},
        ]),
      );

      final ids = await container.read(sonarrQueuedSeriesIdsProvider.future);

      expect(ids, {20, 21});
    });

    test(
      'resolves queued Lidarr artists from direct and album matches',
      () async {
        final container = _container(
          lidarrService: _QueueLidarrService(
            items: [
              {
                'artist': {'id': 30, 'artistName': 'Direct Artist'},
              },
              {'albumId': 40},
            ],
            artists: [
              buildArtist(
                id: 31,
                artistName: 'Album Match',
                statistics: const {'albumCount': 1},
              ),
              buildArtist(
                id: 32,
                artistName: 'Other Artist',
                statistics: const {'albumCount': 1},
              ),
            ],
            albumsByArtist: {
              31: [buildAlbum(id: 40, title: 'Brat')],
              32: [buildAlbum(id: 99, title: 'Other Album')],
            },
          ),
        );

        final ids = await container.read(lidarrQueuedArtistIdsProvider.future);

        expect(ids, {30, 31});
      },
    );
  });
}

ProviderContainer _container({
  SettingsModel settings = const SettingsModel(),
  RadarrService? radarrService,
  SonarrService? sonarrService,
  LidarrService? lidarrService,
  BazarrService? bazarrService,
  ApiClient? statusClient,
}) {
  final container = ProviderContainer(
    overrides: [
      currentSettingsProvider.overrideWith((ref) => settings),
      if (statusClient != null)
        serviceStatusClientFactoryProvider.overrideWith(
          (ref) =>
              ({required String baseUrl, required String apiKey}) =>
                  statusClient,
        ),
      radarrServiceProvider.overrideWith(
        (ref) => radarrService ?? FakeRadarrService(),
      ),
      sonarrServiceProvider.overrideWith(
        (ref) => sonarrService ?? FakeSonarrService(),
      ),
      lidarrServiceProvider.overrideWith(
        (ref) => lidarrService ?? FakeLidarrService(),
      ),
      bazarrServiceProvider.overrideWith(
        (ref) => bazarrService ?? FakeBazarrService(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

class _MoviesRadarrService extends FakeRadarrService {
  _MoviesRadarrService(this.movies);

  final List<RadarrMovie> movies;

  @override
  Future<List<RadarrMovie>> getMovies() async => movies;
}

class _ThrowingMoviesRadarrService extends FakeRadarrService {
  @override
  Future<List<RadarrMovie>> getMovies() async =>
      throw Exception('movies failed');
}

class _QueueRadarrService extends FakeRadarrService {
  _QueueRadarrService(this.items);

  final List<dynamic> items;

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => items;
}

class _ThrowingRadarrService extends FakeRadarrService {
  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => throw Exception('Radarr failed');
}

class _QueueSonarrService extends FakeSonarrService {
  _QueueSonarrService(this.items);

  final List<dynamic> items;

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => items;
}

class _QueueLidarrService extends FakeLidarrService {
  _QueueLidarrService({
    required this.items,
    required this.artists,
    required this.albumsByArtist,
  });

  final List<dynamic> items;
  final List<LidarrArtist> artists;
  final Map<int, List<LidarrAlbum>> albumsByArtist;

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => items;

  @override
  Future<List<LidarrArtist>> getArtists() async => artists;

  @override
  Future<List<LidarrAlbum>> getAlbums(int artistId) async =>
      albumsByArtist[artistId] ?? const [];
}

class _StatusClient extends ApiClient {
  _StatusClient(this.data)
    : super(baseUrl: 'https://status.example.com', apiKey: 'key');

  final Map<String, dynamic> data;

  @override
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: data,
    );
  }

  @override
  void close({bool force = false}) {}
}

class _ThrowingStatusClient extends ApiClient {
  _ThrowingStatusClient()
    : super(baseUrl: 'https://status.example.com', apiKey: 'key');

  @override
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    throw Exception('status failed');
  }

  @override
  void close({bool force = false}) {}
}
