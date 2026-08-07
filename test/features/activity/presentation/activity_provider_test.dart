import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/activity/presentation/activity_screen.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_tab.dart';
import 'package:cupola/features/activity/presentation/widgets/wanted_tab.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/settings_scope.dart';

void main() {
  late SettingsScope scope;

  setUp(() async {
    // The feed distinguishes "not configured" from "did not answer", so it reads
    // settings — which throw unless overridden.
    scope = await settingsScope(configured: activityServiceKeys);
  });

  ProviderContainer createContainer({
    SeerrService? seerrService,
    RadarrService? radarrService,
    SonarrService? sonarrService,
    LidarrService? lidarrService,
    List<SeerrRequest>? requests,
  }) {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => scope.prefs),
        secureSettingsStoreProvider.overrideWith((ref) => scope.secureStore),
        initialSettingsProvider.overrideWith((ref) => scope.settings),
        initialOnboardingCompletedProvider.overrideWith((ref) => true),
        if (seerrService != null)
          seerrServiceProvider.overrideWith((ref) => seerrService),
        if (requests != null)
          requestsProvider.overrideWith((ref) async => requests),
        if (radarrService != null)
          radarrServiceProvider.overrideWith((ref) => radarrService),
        if (sonarrService != null)
          sonarrServiceProvider.overrideWith((ref) => sonarrService),
        if (lidarrService != null)
          lidarrServiceProvider.overrideWith((ref) => lidarrService),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('ServiceType.displayTitle returns the expected label per type', () {
    const expected = {
      ServiceType.movies: 'Movies',
      ServiceType.series: 'Series',
      ServiceType.music: 'Music',
      ServiceType.discover: 'Requests',
    };
    for (final entry in expected.entries) {
      expect(entry.key.displayTitle, entry.value, reason: '${entry.key}');
    }
  });

  test('ServiceType.supportsArrActivity is true only for *arr services', () {
    expect(ServiceType.movies.supportsArrActivity, isTrue);
    expect(ServiceType.series.supportsArrActivity, isTrue);
    expect(ServiceType.music.supportsArrActivity, isTrue);
    expect(ServiceType.discover.supportsArrActivity, isFalse);
  });

  group('resolveArrService', () {
    test('returns the Radarr/Sonarr/Lidarr service for its matching type', () {
      final radarr = FakeRadarrService();
      final sonarr = FakeSonarrService();
      final lidarr = FakeLidarrService();
      final container = createContainer(
        radarrService: radarr,
        sonarrService: sonarr,
        lidarrService: lidarr,
      );

      expect(
        identical(
          container.read(resolvedArrServiceProvider(ServiceType.movies)),
          radarr,
        ),
        isTrue,
      );
      expect(
        identical(
          container.read(resolvedArrServiceProvider(ServiceType.series)),
          sonarr,
        ),
        isTrue,
      );
      expect(
        identical(
          container.read(resolvedArrServiceProvider(ServiceType.music)),
          lidarr,
        ),
        isTrue,
      );
    });

    test('throws for discover', () {
      final container = createContainer();

      expect(
        () => container.read(resolvedArrServiceProvider(ServiceType.discover)),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains(
              'only supports movies, series, and music',
            ),
            'provider error for unsupported discover service type',
          ),
        ),
      );
    });
  });

  test('ActivityTab and WantedTab reject the discover service type', () {
    expect(
      () => ActivityTab(serviceType: ServiceType.discover),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => WantedTab(serviceType: ServiceType.discover),
      throwsA(isA<AssertionError>()),
    );
  });

  group('global activity providers', () {
    test('combines requests, queue, and history sorted newest first', () async {
      final container = createContainer(
        requests: const [
          SeerrRequest(
            id: 1,
            status: RequestStatus.approved,
            media: RequestMedia(title: 'Shogun'),
            createdAt: '2026-04-03T09:05:00Z',
            type: 'tv',
            requestedBy: RequestedBy(id: 1, displayName: 'sarah'),
          ),
        ],
        radarrService: _ActivityRadarrService(
          queue: const [
            {
              'title': 'Furiosa.2024.2160p.WEB-DL-GROUP',
              'status': 'downloading',
              'estimatedCompletionTime': '2026-04-03T14:32:00Z',
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
              'movie': {'title': 'Dune: Part Two'},
            },
          ],
        ),
      );

      final feed = await container.read(globalActivityFeedProvider.future);
      final items = feed.items;

      expect(items.map((item) => item.title), [
        'Furiosa',
        'Shogun',
        'Dune: Part Two',
      ]);
      expect(items.first.subtitle, contains('Furiosa.2024.2160p.WEB-DL-GROUP'));
      expect(items.first.kind, GlobalActivityKind.queue);
      expect(items.first.service, ServiceKey.radarr);
      expect(items.first.progress, 0.75);
      expect(items[1].kind, GlobalActivityKind.request);
      expect(items[1].service, ServiceKey.seerr);
      expect(items[2].kind, GlobalActivityKind.history);
    });

    test('keeps global queue available when one service fails', () async {
      final container = createContainer(
        radarrService: _ThrowingQueueRadarrService(),
        sonarrService: _ActivitySonarrService(
          queue: const [
            {
              'title': 'House.of.the.Dragon.S02E03.1080p.WEB-DL-GROUP',
              'status': 'downloading',
              'series': {'title': 'House of the Dragon'},
              'episode': {'seasonNumber': 2, 'episodeNumber': 3},
            },
          ],
        ),
      );

      final feed = await container.read(globalQueueItemsProvider.future);
      final items = feed.items;

      expect(items, hasLength(1));
      expect(items.single.service, ServiceKey.sonarr);
      expect(items.single.title, 'House of the Dragon');
      expect(
        items.single.subtitle,
        contains('House.of.the.Dragon.S02E03.1080p.WEB-DL-GROUP'),
      );

      // The surviving services still render — but the failure is carried, not
      // swallowed, so the screen can say the list is incomplete instead of
      // implying Radarr had nothing.
      expect(feed.isPartial, isTrue);
      expect(feed.allConfiguredFailed, isFalse);
      expect(
        feed.failures.map((result) => result.service),
        contains(ServiceKey.radarr),
      );
      expect(feed.firstError, isNotNull);
    });

    test(
      'reports every configured service failing as a failure, not empty',
      () async {
        final container = createContainer(
          radarrService: _ThrowingQueueRadarrService(),
          sonarrService: _ThrowingQueueSonarrService(),
          lidarrService: _ThrowingQueueLidarrService(),
        );

        final feed = await container.read(globalQueueItemsProvider.future);

        // Nothing was reached, so "no items" means "we have no idea" — the case
        // that used to render as "Nothing downloading right now".
        expect(feed.items, isEmpty);
        expect(feed.allConfiguredFailed, isTrue);
        expect(feed.hasConfiguredService, isTrue);
        expect(feed.firstError, isNotNull);
      },
    );

    test('an unconfigured service is not reported as a failure', () async {
      scope = await settingsScope(configured: const [ServiceKey.sonarr]);
      final container = createContainer(
        sonarrService: _ActivitySonarrService(
          queue: const [
            {
              'title': 'House.of.the.Dragon.S02E03',
              'status': 'downloading',
              'series': {'title': 'House of the Dragon'},
            },
          ],
        ),
      );

      final feed = await container.read(globalQueueItemsProvider.future);

      expect(feed.items, hasLength(1));
      expect(feed.failures, isEmpty);
      expect(feed.isPartial, isFalse);
      expect(
        feed.unconfigured.map((result) => result.service),
        containsAll(const [ServiceKey.radarr, ServiceKey.lidarr]),
      );
    });

    test('deduplicates release subtitle in global history feed', () async {
      final container = createContainer(
        radarrService: _ActivityRadarrService(
          history: const [
            {
              'sourceTitle': 'Imported.Release',
              'eventType': 'grabbed',
              'date': '2026-04-02T11:18:00Z',
            },
          ],
        ),
      );

      final feed = await container.read(globalHistoryItemsProvider.future);
      final items = feed.items;

      expect(items, hasLength(1));
      expect(items.single.title, 'Imported.Release');
      expect(items.single.subtitle, isEmpty);
    });

    test('wanted provider combines missing and cutoff items', () async {
      final container = createContainer(
        radarrService: _ActivityRadarrService(
          missing: const [
            {'title': 'Kingdom of the Planet of the Apes', 'year': 2024},
          ],
          cutoff: const [
            {'title': 'Inception', 'year': 2010},
          ],
        ),
      );

      final feed = await container.read(globalWantedItemsProvider.future);
      final items = feed.items;

      expect(items.map((item) => item.kind), [
        GlobalActivityKind.missing,
        GlobalActivityKind.cutoff,
      ]);
      expect(items.map((item) => item.title), [
        'Kingdom of the Planet of the Apes',
        'Inception',
      ]);
    });
  });
}

class _ActivityRadarrService extends FakeRadarrService {
  _ActivityRadarrService({
    this.queue = const [],
    this.history = const [],
    this.missing = const [],
    this.cutoff = const [],
  });

  final List<dynamic> queue;
  final List<dynamic> history;
  final List<dynamic> missing;
  final List<dynamic> cutoff;

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
  Future<List<dynamic>> getBlocklist() async => const [];

  @override
  Future<List<dynamic>> getMissing({int page = 1, int pageSize = 20}) async {
    expect(page, 1);
    expect(pageSize, 50);
    return missing;
  }

  @override
  Future<List<dynamic>> getAllMissing() async => missing;

  @override
  Future<List<dynamic>> getCutoff({int page = 1, int pageSize = 20}) async {
    expect(page, 1);
    expect(pageSize, 50);
    return cutoff;
  }

  @override
  Future<List<dynamic>> getAllCutoff() async => cutoff;
}

class _ActivitySonarrService extends FakeSonarrService {
  _ActivitySonarrService({this.queue = const []});

  final List<dynamic> queue;

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => queue;
}

class _ThrowingQueueRadarrService extends FakeRadarrService {
  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => throw Exception('Radarr down');
}

class _ThrowingQueueSonarrService extends FakeSonarrService {
  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => throw Exception('Sonarr down');
}

class _ThrowingQueueLidarrService extends FakeLidarrService {
  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => throw Exception('Lidarr down');
}
