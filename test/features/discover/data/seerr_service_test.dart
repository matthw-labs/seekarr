import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/data/seerr_service.dart';

import '../../../test_helpers/fake_api_client.dart';

void main() {
  late FakeApiClient client;
  late SeerrService service;

  setUp(() {
    client = FakeApiClient();
    service = SeerrService(client);
  });

  group('createRequest', () {
    test('movie body contains required fields without seasons', () async {
      await service.createRequest(
        mediaType: 'movie',
        mediaId: 12345,
        profileId: 1,
        rootFolder: '/movies',
      );

      expect(client.lastPostPath, '/api/v1/request');
      final body = client.lastPostData as Map<String, dynamic>;
      expect(body, {
        'mediaType': 'movie',
        'mediaId': 12345,
        'is4k': false,
        'profileId': 1,
        'rootFolder': '/movies',
      });
      expect(body.containsKey('seasons'), isFalse);
    });

    test('tv body defaults seasons to "all" when not specified', () async {
      await service.createRequest(mediaType: 'tv', mediaId: 67890);
      expect((client.lastPostData as Map)['seasons'], 'all');
    });

    test('tv body uses specific seasons when provided', () async {
      await service.createRequest(
        mediaType: 'tv',
        mediaId: 67890,
        seasons: const [1, 2, 3],
      );
      expect((client.lastPostData as Map)['seasons'], [1, 2, 3]);
    });

    test('is4k flag is forwarded', () async {
      await service.createRequest(
        mediaType: 'movie',
        mediaId: 12345,
        is4k: true,
      );
      expect((client.lastPostData as Map)['is4k'], isTrue);
    });

    test('serverId is forwarded when provided', () async {
      await service.createRequest(mediaType: 'movie', mediaId: 1, serverId: 42);
      expect((client.lastPostData as Map)['serverId'], 42);
    });
  });

  group('search', () {
    test('returns empty list when query is empty (no network call)', () async {
      final results = await service.search('');
      expect(results, isEmpty);
      expect(client.getCallCount, 0);
    });

    test('filters out person results and keeps movies & tv', () async {
      client.getResponseData = {
        'results': [
          {'id': 1, 'mediaType': 'movie', 'title': 'Movie'},
          {'id': 2, 'mediaType': 'person', 'name': 'Actor'},
          {'id': 3, 'mediaType': 'tv', 'name': 'Show'},
          {'id': 4, 'media_type': 'person', 'name': 'Another Actor'},
          {'id': 5, 'media_type': 'movie', 'title': 'Snake Case Movie'},
        ],
      };

      final results = await service.search('test');

      expect(results.length, 3);
      expect(results.any((r) => r.mediaType == 'person'), isFalse);
      expect(client.lastGetPath, '/api/v1/search');
    });

    test('url-encodes the query', () async {
      client.getResponseData = {'results': const []};
      await service.search('star wars & friends');
      final q = client.lastGetQueryParameters!['query'] as String;
      expect(q, Uri.encodeComponent('star wars & friends'));
    });

    test('forwards the cancel token to ApiClient', () async {
      // The other three global-search legs pin this at service level; Seerr's
      // only cover was a fake that overrode `search` outright, so dropping the
      // forwarding here left the whole suite green.
      client.getResponseData = {'results': const []};
      final cancelToken = CancelToken();

      await service.search('dune', cancelToken: cancelToken);

      expect(client.lastGetCancelToken, same(cancelToken));
    });

    test('returns empty list on network error', () async {
      client.getException = Exception('network down');
      expect(await service.search('anything'), isEmpty);
    });
  });

  group('discover endpoints', () {
    test('getDiscoverMovies hits the correct path', () async {
      client.getResponseData = {'results': const []};
      await service.getDiscoverMovies(page: 2);
      expect(client.lastGetPath, '/api/v1/discover/movies');
      expect(client.lastGetQueryParameters, {'page': 2});
    });

    test('getDiscoverTV hits the correct path', () async {
      client.getResponseData = {'results': const []};
      await service.getDiscoverTV();
      expect(client.lastGetPath, '/api/v1/discover/tv');
    });

    test('getDiscoverTrending hits the correct path', () async {
      client.getResponseData = {'results': const []};
      await service.getDiscoverTrending();
      expect(client.lastGetPath, '/api/v1/discover/trending');
    });

    test('discover endpoints return empty on error', () async {
      client.getException = Exception('boom');
      expect(await service.getDiscoverMovies(), isEmpty);
      expect(await service.getDiscoverTV(), isEmpty);
      expect(await service.getDiscoverTrending(), isEmpty);
    });
  });

  group('getRequests', () {
    test('parses results and skips malformed entries', () async {
      client.getResponseQueue.addAll([
        {
          'results': [
            {
              'id': 7,
              'status': 2,
              'createdAt': '2024-01-02T00:00:00.000Z',
              'type': 'movie',
              'is4k': false,
              'requestedBy': {'id': 1, 'displayName': 'Matt'},
              'media': {
                'id': 101,
                'tmdbId': 111,
                'status': 5,
                'mediaType': 'movie',
                'title': 'Hydrated Movie',
                'posterPath': '/poster.jpg',
              },
            },
            'bad',
          ],
        },
      ]);

      final requests = await service.getRequests();

      expect(requests, hasLength(1));
      expect(requests.single.id, 7);
      expect(client.lastGetPath, '/api/v1/request');
      expect(client.lastGetQueryParameters, {
        'take': 20,
        'skip': 0,
        'sort': 'added',
        'filter': 'all',
      });
    });

    test('hydrates media when title is Unknown via movie detail', () async {
      client.getResponseQueue.addAll([
        {
          'results': [
            {
              'id': 7,
              'status': 2,
              'createdAt': '2024-01-02T00:00:00.000Z',
              'type': 'movie',
              'is4k': false,
              'requestedBy': {'id': 1, 'displayName': 'Matt'},
              'media': {
                'id': 101,
                'tmdbId': 111,
                'status': 5,
                'mediaType': 'movie',
                'title': 'Unknown Media',
              },
            },
          ],
        },
        {
          'title': 'Hydrated Movie',
          'releaseDate': '2022-05-01',
          'posterPath': '/hydrated.jpg',
        },
      ]);

      final requests = await service.getRequests();

      expect(requests.single.media?.title, 'Hydrated Movie');
      expect(requests.single.media?.year, '2022');
      expect(requests.single.media?.posterPath, '/hydrated.jpg');
    });

    test('returns [] on network error', () async {
      client.getException = Exception('offline');
      expect(await service.getRequests(), isEmpty);
    });
  });

  group('media endpoints', () {
    test('getMovie hits /api/v1/movie/:id', () async {
      client.getResponseData = {'title': 'Movie'};
      final data = await service.getMovie(123);
      expect(client.lastGetPath, '/api/v1/movie/123');
      expect(data['title'], 'Movie');
    });

    test('getTv hits /api/v1/tv/:id', () async {
      client.getResponseData = {'name': 'Show'};
      final data = await service.getTv(123);
      expect(client.lastGetPath, '/api/v1/tv/123');
      expect(data['name'], 'Show');
    });

    test('getCollection returns {} on error', () async {
      client.getException = Exception('offline');
      expect(await service.getCollection(5), isEmpty);
    });

    test('deleteMedia hits /api/v1/media/:id', () async {
      await service.deleteMedia(123);
      expect(client.lastDeletePath, '/api/v1/media/123');
    });

    test('deleteMediaFile hits /api/v1/media/:id/file', () async {
      await service.deleteMediaFile(456);
      expect(client.lastDeletePath, '/api/v1/media/456/file');
    });

    test('deleteRequest hits /api/v1/request/:id', () async {
      await service.deleteRequest(77);
      expect(client.lastDeletePath, '/api/v1/request/77');
    });
  });

  group('service integration endpoints', () {
    test('getRadarrServers returns list on success', () async {
      client.getResponseData = [
        {'id': 1, 'name': 'Main'},
      ];
      final servers = await service.getRadarrServers();
      expect(servers, hasLength(1));
      expect(client.lastGetPath, '/api/v1/service/radarr');
    });

    test('getRadarrServers returns [] on error', () async {
      client.getException = Exception('boom');
      expect(await service.getRadarrServers(), isEmpty);
    });

    test('getSonarrServers hits /api/v1/service/sonarr', () async {
      client.getResponseData = const <Map<String, dynamic>>[];
      await service.getSonarrServers();
      expect(client.lastGetPath, '/api/v1/service/sonarr');
    });

    test('getRadarrProfiles hits /api/v1/service/radarr/:id', () async {
      client.getResponseData = {'profiles': const [], 'rootFolders': const []};
      await service.getRadarrProfiles(42);
      expect(client.lastGetPath, '/api/v1/service/radarr/42');
    });

    test('getSonarrProfiles hits /api/v1/service/sonarr/:id', () async {
      client.getResponseData = {'profiles': const [], 'rootFolders': const []};
      await service.getSonarrProfiles(9);
      expect(client.lastGetPath, '/api/v1/service/sonarr/9');
    });
  });
}
