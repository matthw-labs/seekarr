import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/api/api_client.dart';
import 'package:seekarr/core/api/base_arr_service.dart';

import '../../test_helpers/fake_api_client.dart';

void main() {
  group('ArrActivityMixin helpers', () {
    late FakeApiClient client;
    late TestArrService service;

    setUp(() {
      client = FakeApiClient();
      service = TestArrService(client, ArrServiceConfig.radarr);
    });

    test('fetchAllItems maps list responses', () async {
      client.getResponseData = [
        {'id': 1, 'title': 'One'},
        {'id': 2, 'title': 'Two'},
      ];

      final items = await service.fetchAllItems('movie', TestItem.fromJson);

      expect(client.lastGetPath, '/api/v3/movie');
      expect(items, [
        const TestItem(id: 1, title: 'One'),
        const TestItem(id: 2, title: 'Two'),
      ]);

      items.add(const TestItem(id: 3, title: 'Three'));
      expect(items, hasLength(3));
    });

    test('fetchAllItems returns empty list on error', () async {
      client.getException = Exception('boom');

      final items = await service.fetchAllItems('movie', TestItem.fromJson);

      expect(items, isEmpty);
    });

    test('lookupItems returns empty list for empty term', () async {
      final items = await service.lookupItems(
        'movie/lookup',
        '',
        TestItem.fromJson,
      );

      expect(items, isEmpty);
      expect(client.lastGetPath, isNull);
    });

    test('lookupItems encodes term and maps results', () async {
      client.getResponseData = [
        {'id': 3, 'title': 'Lookup'},
      ];

      final items = await service.lookupItems(
        'movie/lookup',
        'tmdb:123 some title',
        TestItem.fromJson,
      );

      expect(client.lastGetPath, '/api/v3/movie/lookup');
      expect(client.lastGetQueryParameters, {
        'term': 'tmdb%3A123%20some%20title',
      });
      expect(items, [const TestItem(id: 3, title: 'Lookup')]);

      items.add(const TestItem(id: 4, title: 'Growable'));
      expect(items, hasLength(2));
    });

    test('lookupItems forwards the cancel token to ApiClient', () async {
      // The three arr lookups delegate here now, so this is where the
      // superseded-search abort either happens or silently does not.
      client.getResponseData = <dynamic>[];
      final cancelToken = CancelToken();

      await service.lookupItems(
        'movie/lookup',
        'dune',
        TestItem.fromJson,
        cancelToken: cancelToken,
      );

      expect(client.lastGetCancelToken, same(cancelToken));
    });

    test('lookupItems returns empty list on error', () async {
      client.getException = Exception('boom');

      final items = await service.lookupItems(
        'movie/lookup',
        'tmdb:123',
        TestItem.fromJson,
      );

      expect(items, isEmpty);
    });

    test('fetchQualityProfiles returns mapped profiles', () async {
      client.getResponseData = [
        {'id': 1, 'name': 'HD-1080p'},
      ];

      final profiles = await service.fetchQualityProfiles();

      expect(client.lastGetPath, '/api/v3/qualityprofile');
      expect(profiles, [
        {'id': 1, 'name': 'HD-1080p'},
      ]);
    });

    test('updateItemProfile fetches, mutates, and saves item', () async {
      client.getResponseData = {
        'id': 7,
        'title': 'Movie',
        'qualityProfileId': 1,
      };

      await service.updateItemProfile('movie', 7, 4);

      expect(client.lastGetPath, '/api/v3/movie/7');
      expect(client.lastPutPath, '/api/v3/movie/7');
      expect(client.lastPutData, {
        'id': 7,
        'title': 'Movie',
        'qualityProfileId': 4,
      });
    });

    test(
      'fetchReleases raises the receive timeout for the slow search',
      () async {
        // The server fans out to every enabled indexer and answers only once the
        // slowest has, so this is the one arr GET that legitimately runs for
        // minutes. Under the client's 15s default it never returned at all.
        client.getResponseData = [
          {'guid': 'a', 'indexerId': 1},
        ];

        final releases = await service.fetchReleases({'movieId': 7});

        expect(client.lastGetPath, '/api/v3/release');
        expect(client.lastGetQueryParameters, {'movieId': 7});
        expect(client.lastGetReceiveTimeout, kReleaseSearchReceiveTimeout);
        expect(releases, hasLength(1));
      },
    );

    test('the release search timeout clears every common gateway ceiling', () {
      // Not an arbitrary number: it has to sit above nginx's 60s default and
      // Cloudflare's unraisable 100s cap, because that is what makes a failure
      // attributable to the proxy rather than to us.
      expect(
        kReleaseSearchReceiveTimeout,
        greaterThan(const Duration(seconds: 100)),
      );
    });

    test('grabReleaseByGuid posts release payload', () async {
      await service.grabReleaseByGuid(guid: 'guid-123', indexerId: 9);

      expect(client.lastPostPath, '/api/v3/release');
      expect(client.lastPostData, {'guid': 'guid-123', 'indexerId': 9});
    });

    test('getQueue returns records with optional query parameters', () async {
      client.getResponseData = {
        'records': [
          {'id': 1, 'title': 'Queued'},
        ],
      };

      final items = await service.getQueue(
        queryParameters: const {'includeMovie': true},
      );

      expect(client.lastGetPath, '/api/v3/queue');
      expect(client.lastGetQueryParameters, const {'includeMovie': true});
      expect(items, [
        {'id': 1, 'title': 'Queued'},
      ]);
    });

    test('getHistory forwards optional query parameters', () async {
      client.getResponseData = {
        'records': [
          {'id': 2, 'sourceTitle': 'Imported.Release'},
        ],
      };

      final items = await service.getHistory(
        page: 2,
        pageSize: 10,
        queryParameters: const {'includeMovie': true},
      );

      expect(client.lastGetPath, '/api/v3/history');
      expect(client.lastGetQueryParameters, {
        'page': 2,
        'pageSize': 10,
        'includeMovie': true,
      });
      expect(items, [
        {'id': 2, 'sourceTitle': 'Imported.Release'},
      ]);
    });
  });
}

class TestArrService with ArrActivityMixin {
  @override
  final ApiClient client;

  @override
  final ArrServiceConfig config;

  TestArrService(this.client, this.config);
}

class TestItem {
  final int id;
  final String title;

  const TestItem({required this.id, required this.title});

  factory TestItem.fromJson(Map<String, dynamic> json) {
    return TestItem(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? 'Unknown',
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TestItem && other.id == id && other.title == title;
  }

  @override
  int get hashCode => Object.hash(id, title);
}
