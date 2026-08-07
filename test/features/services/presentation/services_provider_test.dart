import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/bazarr/data/bazarr_service.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

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
    });

    test('returns online summary with version', () async {
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
    });

    test('stays online when the library call fails', () async {
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
      // Reachability is settled by the version probe alone. The summary no
      // longer fetches a library count, so a failing library call cannot
      // downgrade it — that whole fetch was removed when the status card that
      // displayed the count gave way to the stack matrix's live signal.
      expect(summary.versionLabel, 'v5.4.6');
    });

    // What this provider watches decides how much of the network it touches:
    // one family entry per service, each opening a connection and waiting out a
    // multi-second timeout. Watching the whole SettingsModel meant every write —
    // a theme toggle included, and a single Save can write twice — re-probed
    // every configured service at once.
    test(
      'an unrelated settings change does not re-probe the service',
      () async {
        final status = _CountingStatusClient();
        final container = _mutableSettingsContainer(
          initial: _secureRadarr,
          statusClient: status,
        );

        await container.read(serviceSummaryProvider(ServiceKey.radarr).future);
        expect(status.calls, 1);

        container
            .read(_settingsHolderProvider.notifier)
            .set(_secureRadarr.copyWith(themeMode: AppThemeMode.light));
        await container.read(serviceSummaryProvider(ServiceKey.radarr).future);

        expect(
          status.calls,
          1,
          reason: 'reachability does not depend on the theme',
        );
      },
    );

    test('trusting a certificate for the origin re-probes the service', () async {
      // The subtlest field in the watched key, and the one whose absence would
      // be worst: answering the trust prompt is precisely the moment the probe
      // can start succeeding, so a summary that did not re-run would sit on
      // "offline" until something else happened to invalidate it.
      final status = _CountingStatusClient();
      final container = _mutableSettingsContainer(
        initial: _secureRadarr,
        statusClient: status,
      );

      await container.read(serviceSummaryProvider(ServiceKey.radarr).future);
      container
          .read(_settingsHolderProvider.notifier)
          .set(
            _secureRadarr.copyWithTrustedCertificate(
              url: _secureRadarr.radarrUrl,
              fingerprint: 'ab:cd:ef',
            ),
          );
      await container.read(serviceSummaryProvider(ServiceKey.radarr).future);

      expect(status.calls, 2);
    });

    test('another service moving does not re-probe this one', () async {
      final status = _CountingStatusClient();
      final container = _mutableSettingsContainer(
        initial: _secureRadarr,
        statusClient: status,
      );

      await container.read(serviceSummaryProvider(ServiceKey.radarr).future);
      container
          .read(_settingsHolderProvider.notifier)
          .set(_secureRadarr.copyWith(sonarrUrl: 'https://sonarr.local:8989'));
      await container.read(serviceSummaryProvider(ServiceKey.radarr).future);

      expect(status.calls, 1);
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
    });
  });

  group('servicesQueueProvider', () {
    // Both arrs configured: the provider now skips any source the user has not
    // set up, so an unconfigured service contributes nothing rather than a
    // failed fetch.
    const _bothArrs = SettingsModel(
      radarrUrl: 'http://radarr.local:7878',
      radarrApiKey: 'key',
      sonarrUrl: 'http://sonarr.local:8989',
      sonarrApiKey: 'key',
    );

    test(
      'combines Radarr and Sonarr queue items with media-first hierarchy',
      () async {
        final container = _container(
          settings: _bothArrs,
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

        // Ordered by progress, closest to landing first, with the two items
        // whose client reported no progress last and in source order.
        expect(items.map((item) => item.title), [
          'Furiosa',
          'The Boys',
          'Shogun',
          'Slow Horses',
        ]);
        expect(items[0].service, ServiceKey.radarr);
        expect(items[0].subtitle, contains('Furiosa.2024.2160p.WEB-DL-GROUP'));
        expect(items[0].progress, 0.75);
        expect(items[1].service, ServiceKey.sonarr);
        expect(items[1].title, 'The Boys');
        expect(
          items[1].subtitle,
          contains('The.Boys.S04E07.1080p.WEB-DL-GROUP'),
        );
        expect(items[1].progress, 0.5);
        expect(items[2].progress, isNull);
        expect(items[3].progress, isNull);
      },
    );

    test('skips a source the user has not configured', () async {
      final container = _container(
        settings: const SettingsModel(
          sonarrUrl: 'http://sonarr.local:8989',
          sonarrApiKey: 'key',
        ),
        // Configured nowhere, so this must never be asked.
        radarrService: _ThrowingRadarrService(),
        sonarrService: _QueueSonarrService([
          {'title': 'Shogun', 'size': 100, 'sizeleft': 0},
        ]),
      );

      final items = await container.read(servicesQueueProvider.future);

      expect(items.single.service, ServiceKey.sonarr);
    });

    test('caps the preview and keeps the closest to landing', () async {
      final container = _container(
        settings: _bothArrs,
        radarrService: _QueueRadarrService([
          for (var index = 0; index < 8; index++)
            {
              'title': 'Release $index',
              'size': 100,
              // Ascending progress, so the last ones added are the furthest
              // along and must be the ones that survive the cap.
              'sizeleft': 100 - (index * 10),
            },
        ]),
      );

      final items = await container.read(servicesQueueProvider.future);

      expect(items, hasLength(servicesQueuePreviewLimit));
      expect(items.first.title, 'Release 7');
      expect(items.last.title, 'Release 3');
    });

    // The provider fans out to seven services at once, so what it watches
    // decides how often the whole stack gets polled. Watching the entire
    // SettingsModel meant a theme-mode toggle — a value no queue can depend on —
    // re-ran all seven fetches.
    test('an unrelated settings change does not re-poll the queue', () async {
      final radarr = _CountingQueueRadarrService();
      final container = _mutableSettingsContainer(
        initial: _bothArrs,
        radarrService: radarr,
      );

      await container.read(servicesQueueProvider.future);
      expect(radarr.calls, 1);

      container
          .read(_settingsHolderProvider.notifier)
          .set(_bothArrs.copyWith(themeMode: AppThemeMode.light));
      await container.read(servicesQueueProvider.future);

      expect(radarr.calls, 1, reason: 'the queue does not depend on the theme');
    });

    test('a change to a source service does re-poll the queue', () async {
      // The other half: narrowing the watch must not make it deaf. Repointing
      // Radarr has to invalidate, or the preview keeps showing the old server's
      // queue.
      final radarr = _CountingQueueRadarrService();
      final container = _mutableSettingsContainer(
        initial: _bothArrs,
        radarrService: radarr,
      );

      await container.read(servicesQueueProvider.future);
      container
          .read(_settingsHolderProvider.notifier)
          .set(_bothArrs.copyWith(radarrUrl: 'http://moved.local:7878'));
      await container.read(servicesQueueProvider.future);

      expect(radarr.calls, 2);
    });

    test('trusting a certificate for a source re-polls the queue', () async {
      // Every field of the watched key has to earn its place, and this is the
      // one a narrowing pass is most likely to drop: the pin is what lets a
      // self-signed host answer at all, so a queue that ignored it would stay
      // empty after the user answered the trust prompt.
      final radarr = _CountingQueueRadarrService();
      final container = _mutableSettingsContainer(
        initial: _secureRadarr,
        radarrService: radarr,
      );

      await container.read(servicesQueueProvider.future);
      expect(radarr.calls, 1);

      container
          .read(_settingsHolderProvider.notifier)
          .set(
            _secureRadarr.copyWithTrustedCertificate(
              url: _secureRadarr.radarrUrl,
              fingerprint: 'ab:cd:ef',
            ),
          );
      await container.read(servicesQueueProvider.future);

      expect(radarr.calls, 2);
    });

    test('keeps queue available when one service fails', () async {
      final container = _container(
        settings: _bothArrs,
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

  group('servicesRecentlyAddedProvider', () {
    // The rail's own rebuild is what is under test, not its sources: the fakes
    // below are static overrides, so a rebuild reuses their cached results and
    // only the identity of the freshly sorted list can tell the two apart.
    test('an unrelated settings change does not rebuild the rail', () async {
      final container = _mutableSettingsContainer(
        initial: _secureRadarr,
        radarrService: _MoviesRadarrService([buildMovie(title: 'Dune')]),
      );

      final first = await container.read(servicesRecentlyAddedProvider.future);
      expect(first, hasLength(1));

      container
          .read(_settingsHolderProvider.notifier)
          .set(_secureRadarr.copyWith(themeMode: AppThemeMode.light));
      final second = await container.read(servicesRecentlyAddedProvider.future);

      expect(
        identical(first, second),
        isTrue,
        reason: 'the rail does not depend on the theme',
      );
    });

    test('repointing a source rebuilds the rail', () async {
      // The other half: the poster URLs are built from the source's own base
      // URL and key, so a rail that ignored a move would keep pointing its
      // images at the old server.
      final container = _mutableSettingsContainer(
        initial: _secureRadarr,
        radarrService: _MoviesRadarrService([buildMovie(title: 'Dune')]),
      );

      final first = await container.read(servicesRecentlyAddedProvider.future);
      container
          .read(_settingsHolderProvider.notifier)
          .set(_secureRadarr.copyWith(radarrUrl: 'https://moved.local:7878'));
      final second = await container.read(servicesRecentlyAddedProvider.future);

      expect(identical(first, second), isFalse);
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
              ({
                required String baseUrl,
                required String apiKey,
                String? pinnedCertFingerprint,
              }) => statusClient,
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

/// A settings source the test can move, so `select` can be observed doing its
/// job. The production chain is `currentSettingsProvider` → `settingsProvider`,
/// whose notifier needs SharedPreferences; this stands in for that one link.
final _settingsHolderProvider =
    NotifierProvider<_SettingsHolder, SettingsModel>(_SettingsHolder.new);

class _SettingsHolder extends Notifier<SettingsModel> {
  @override
  SettingsModel build() => const SettingsModel();

  void set(SettingsModel next) => state = next;
}

ProviderContainer _mutableSettingsContainer({
  required SettingsModel initial,
  RadarrService? radarrService,
  ApiClient? statusClient,
}) {
  final container = ProviderContainer(
    overrides: [
      currentSettingsProvider.overrideWith(
        (ref) => ref.watch(_settingsHolderProvider),
      ),
      if (statusClient != null)
        serviceStatusClientFactoryProvider.overrideWith(
          (ref) =>
              ({
                required String baseUrl,
                required String apiKey,
                String? pinnedCertFingerprint,
              }) => statusClient,
        ),
      radarrServiceProvider.overrideWith(
        (ref) => radarrService ?? FakeRadarrService(),
      ),
      sonarrServiceProvider.overrideWith((ref) => FakeSonarrService()),
      lidarrServiceProvider.overrideWith((ref) => FakeLidarrService()),
      bazarrServiceProvider.overrideWith((ref) => FakeBazarrService()),
    ],
  );
  addTearDown(container.dispose);
  container.read(_settingsHolderProvider.notifier).set(initial);
  return container;
}

/// One HTTPS-addressed Radarr, so `pinForUrl` has an origin to key a trusted
/// certificate on — [UrlUtils.certOrigin] answers null for plain HTTP, and a
/// test that pinned against an `http://` URL would silently assert nothing.
const _secureRadarr = SettingsModel(
  radarrUrl: 'https://radarr.local:7878',
  radarrApiKey: 'key',
);

class _CountingStatusClient extends ApiClient {
  _CountingStatusClient()
    : super(baseUrl: 'https://status.example.com', apiKey: 'key');

  int calls = 0;

  @override
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) async {
    calls++;
    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: const {'version': '5.4.6'},
    );
  }

  @override
  void close({bool force = false}) {}
}

class _CountingQueueRadarrService extends FakeRadarrService {
  int calls = 0;

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async {
    calls++;
    return const [];
  }
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
    Duration? receiveTimeout,
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
    Duration? receiveTimeout,
  }) async {
    throw Exception('status failed');
  }

  @override
  void close({bool force = false}) {}
}
