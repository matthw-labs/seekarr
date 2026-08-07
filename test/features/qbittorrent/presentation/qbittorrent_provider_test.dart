import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_service.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent_properties.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

class _StubAdapter implements HttpClientAdapter {
  // Holds JSON responses keyed by request path. The values can be either
  // a `Map<String, dynamic>` (for object-shaped payloads like /properties)
  // or a `List<dynamic>` (for list-shaped payloads like /torrents/info),
  // matching the real qBittorrent API surface.
  final Map<String, dynamic> responses = {};
  final Map<String, Exception> exceptions = {};

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (exceptions.containsKey(options.path)) {
      throw exceptions[options.path]!;
    }
    final body = responses[options.path] ?? <dynamic>[];
    return ResponseBody.fromBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(body))),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

Map<String, dynamic> _torrentJson({
  String hash = 'aaa',
  String state = 'downloading',
  String category = '',
  String tracker = '',
  List<String> tags = const [],
}) => {
  'hash': hash,
  'name': 'A',
  'size': 100,
  'progress': 0.5,
  'state': state,
  'dlspeed': 0,
  'upspeed': 0,
  'eta': 60,
  'category': category,
  'tracker': tracker,
  'tags': tags,
  'ratio': 1.0,
  'added_on': 0,
  'completed': 0,
  'num_leechs': 0,
  'num_seeds': 0,
};

ProviderContainer _container({
  SettingsModel? settings,
  Map<String, dynamic>? responses,
}) {
  final container = ProviderContainer(
    overrides: [
      currentSettingsProvider.overrideWith(
        (ref) => settings ?? const SettingsModel(),
      ),
      qbittorrentServiceProvider.overrideWith((ref) {
        final s = ref.watch(currentSettingsProvider);
        if (s.qbittorrentUrl.isEmpty) {
          throw Exception('qBittorrent not configured');
        }
        final dio = Dio(BaseOptions(baseUrl: s.qbittorrentUrl));
        final adapter = _StubAdapter();
        if (responses != null) adapter.responses.addAll(responses);
        dio.httpClientAdapter = adapter;
        final client = QbittorrentClient(
          url: s.qbittorrentUrl,
          username: s.qbittorrentUsername.isEmpty
              ? null
              : s.qbittorrentUsername,
          password: s.qbittorrentPassword.isEmpty
              ? null
              : s.qbittorrentPassword,
          dio: dio,
        );
        return QbittorrentService(client);
      }),
    ],
  );
  return container;
}

void main() {
  group('qbittorrentServiceProvider', () {
    test('throws when URL is empty', () {
      final container = _container();
      expect(() => container.read(qbittorrentServiceProvider), throwsException);
    });

    test('creates service when URL configured', () {
      final container = _container(
        settings: const SettingsModel(qbittorrentUrl: 'http://localhost:8080'),
      );
      final service = container.read(qbittorrentServiceProvider);
      expect(service, isA<QbittorrentService>());
    });
  });

  group('available* providers', () {
    test('availableCategories derives from allTorrentsProvider', () async {
      final container = _container(
        settings: const SettingsModel(qbittorrentUrl: 'http://localhost'),
        responses: {
          '/api/v2/torrents/info': [
            _torrentJson(category: 'linux'),
            _torrentJson(category: 'movies'),
            _torrentJson(category: 'linux'), // duplicate
            _torrentJson(category: ''), // ignored
          ],
        },
      );

      // Touch allTorrentsProvider so it builds.
      await container.read(allTorrentsProvider.future);
      final cats = container.read(availableCategoriesProvider);

      expect(cats, ['linux', 'movies']);
    });

    test('availableTags aggregates all torrent tags', () async {
      final container = _container(
        settings: const SettingsModel(qbittorrentUrl: 'http://localhost'),
        responses: {
          '/api/v2/torrents/info': [
            _torrentJson(tags: ['a', 'b']),
            _torrentJson(tags: ['b', 'c']),
          ],
        },
      );

      await container.read(allTorrentsProvider.future);
      final tags = container.read(availableTagsProvider);

      expect(tags, ['a', 'b', 'c']);
    });

    test('availableTrackers extracts domains', () async {
      final container = _container(
        settings: const SettingsModel(qbittorrentUrl: 'http://localhost'),
        responses: {
          '/api/v2/torrents/info': [
            _torrentJson(tracker: 'https://tracker.example/announce'),
            _torrentJson(tracker: 'https://other.example/announce'),
            _torrentJson(tracker: 'https://www.tracker.example/announce'),
            _torrentJson(tracker: ''),
          ],
        },
      );

      await container.read(allTorrentsProvider.future);
      final trackers = container.read(availableTrackersProvider);

      expect(trackers, ['other.example', 'tracker.example']);
    });

    test('available* return empty when allTorrentsProvider has no data', () {
      final container = _container(
        settings: const SettingsModel(qbittorrentUrl: 'http://localhost'),
      );
      expect(container.read(availableCategoriesProvider), isEmpty);
      expect(container.read(availableTagsProvider), isEmpty);
      expect(container.read(availableTrackersProvider), isEmpty);
    });
  });

  group('torrentsProvider filters', () {
    test(
      'queued filter applies client-side even though api filter is all',
      () async {
        final container = _container(
          settings: const SettingsModel(qbittorrentUrl: 'http://localhost'),
          responses: {
            '/api/v2/torrents/info': [
              _torrentJson(hash: 'a', state: 'downloading'),
              _torrentJson(hash: 'b', state: 'queuedDL'),
              _torrentJson(hash: 'c', state: 'queuedUP'),
            ],
          },
        );

        container.read(torrentFilterProvider.notifier).state =
            TorrentFilter.queued;
        final torrents = await container.read(torrentsProvider.future);

        expect(torrents.map((t) => t.hash), containsAll(['b', 'c']));
        expect(torrents.map((t) => t.hash), isNot(contains('a')));
      },
    );

    test('category filter is applied on top of API filter', () async {
      final container = _container(
        settings: const SettingsModel(qbittorrentUrl: 'http://localhost'),
        responses: {
          '/api/v2/torrents/info': [
            _torrentJson(hash: 'a', category: 'linux'),
            _torrentJson(hash: 'b', category: 'movies'),
          ],
        },
      );

      container
        ..read(torrentFilterProvider.notifier).state = TorrentFilter.all
        ..read(torrentCategoryFilterProvider.notifier).state = 'linux';
      final torrents = await container.read(torrentsProvider.future);

      expect(torrents.map((t) => t.hash), ['a']);
    });

    test('tag filter narrows by tag membership', () async {
      final container = _container(
        settings: const SettingsModel(qbittorrentUrl: 'http://localhost'),
        responses: {
          '/api/v2/torrents/info': [
            _torrentJson(hash: 'a', tags: ['4k', 'remux']),
            _torrentJson(hash: 'b', tags: ['1080p']),
          ],
        },
      );

      container
        ..read(torrentFilterProvider.notifier).state = TorrentFilter.all
        ..read(torrentTagFilterProvider.notifier).state = '4k';
      final torrents = await container.read(torrentsProvider.future);

      expect(torrents.map((t) => t.hash), ['a']);
    });

    test('tracker filter narrows by domain', () async {
      final container = _container(
        settings: const SettingsModel(qbittorrentUrl: 'http://localhost'),
        responses: {
          '/api/v2/torrents/info': [
            _torrentJson(hash: 'a', tracker: 'https://alpha.example/announce'),
            _torrentJson(hash: 'b', tracker: 'https://beta.example/announce'),
          ],
        },
      );

      container
        ..read(torrentFilterProvider.notifier).state = TorrentFilter.all
        ..read(torrentTrackerFilterProvider.notifier).state = 'alpha.example';
      final torrents = await container.read(torrentsProvider.future);

      expect(torrents.map((t) => t.hash), ['a']);
    });
  });

  group('qbittorrentTorrentsProvider', () {
    test('forwards hashes query to service', () async {
      final container = _container(
        settings: const SettingsModel(qbittorrentUrl: 'http://localhost'),
        responses: {
          '/api/v2/torrents/info': [_torrentJson(hash: 'a')],
        },
      );

      final torrents = await container.read(
        qbittorrentTorrentsProvider('a').future,
      );
      expect(torrents, hasLength(1));
      expect(torrents.first.hash, 'a');
    });
  });

  group('torrentPropertiesProvider', () {
    test('forwards hash and parses the /properties response', () async {
      final container = _container(
        settings: const SettingsModel(qbittorrentUrl: 'http://localhost'),
        responses: {
          '/api/v2/torrents/properties': {
            'save_path': '/downloads/Ubuntu',
            'creation_date': 1700000000,
            'piece_size': 32768,
            'comment': 'ubuntu-24.04',
            'total_wasted': 0,
            'total_uploaded': 1048576,
            'total_uploaded_session': 0,
            'total_downloaded': 2097152,
            'total_downloaded_session': 0,
            'up_limit': -1,
            'dl_limit': 1024,
            'time_elapsed': 7200,
            'seeding_time': 600,
            'nb_connections': 5,
            'nb_connections_limit': 100,
            'share_ratio': 1.5,
            'addition_date': 1700000000,
            'completion_date': 1700001000,
            'created_by': 'qBittorrent v4.6.0',
            'dl_speed_avg': 1024,
            'dl_speed': 2048,
            'eta': 3600,
            'last_seen': 1700005000,
            'peers': 5,
            'peers_total': 10,
            'pieces_have': 32,
            'pieces_num': 64,
            'reannounce': 30,
            'seeds': 7,
            'seeds_total': 15,
            'total_size': 2147483648,
            'up_speed_avg': 512,
            'up_speed': 256,
            'is_private': 0,
          },
        },
      );

      final props = await container.read(
        torrentPropertiesProvider('abc').future,
      );
      expect(props, isA<TorrentProperties>());
      expect(props.savePath, '/downloads/Ubuntu');
      expect(props.timeElapsed, 7200);
      expect(props.seedingTime, 600);
      expect(props.totalSize, 2147483648);
      expect(props.shareRatio, 1.5);
      expect(props.dlLimit, 1024);
      expect(props.upLimit, -1);
      expect(props.isPrivate, isFalse);
    });

    test('surfaces service errors as AsyncValue.error', () async {
      // The provider must NOT swallow errors — the UI's _PropRow renders
      // "—" per cell when the family is in `error` state, so we need that
      // state to actually fire (older qB versions return 404 on /properties,
      // network drops, etc.). Trigger the error by serving a non-object
      // payload for /properties: the service's
      // `response.data as Map<String, dynamic>` cast will throw.
      final container2 = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => const SettingsModel(qbittorrentUrl: 'http://localhost'),
          ),
          qbittorrentServiceProvider.overrideWith((ref) {
            final s = ref.watch(currentSettingsProvider);
            final dio = Dio(BaseOptions(baseUrl: s.qbittorrentUrl));
            final adapter = _StubAdapter()
              ..responses['/api/v2/torrents/properties'] = <String>[];
            dio.httpClientAdapter = adapter;
            final client = QbittorrentClient(
              url: s.qbittorrentUrl,
              username: s.qbittorrentUsername.isEmpty
                  ? null
                  : s.qbittorrentUsername,
              password: s.qbittorrentPassword.isEmpty
                  ? null
                  : s.qbittorrentPassword,
              dio: dio,
            );
            return QbittorrentService(client);
          }),
        ],
      );
      addTearDown(container2.dispose);

      // The provider's family `.future` rethrows the service's error so the
      // family is left in `AsyncError` — that's the state `_PropRow` keys on
      // to render "—" per cell. Use a plain try/catch to avoid `expectLater`
      // + `throwsA` hangs on Riverpod minor-version behavior changes.
      Object? caught;
      try {
        await container2.read(torrentPropertiesProvider('abc').future);
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<TypeError>());
    });
  });
}
