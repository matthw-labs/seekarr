import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/features/prowlarr/data/prowlarr_service.dart';

import '../../../test_helpers/fake_api_client.dart';

void main() {
  group('ProwlarrService.getStatus', () {
    test('parses the flat status object and surfaces the version', () async {
      final client = FakeApiClient()
        ..getResponseData = {
          'appName': 'Prowlarr',
          'instanceName': 'Prowlarr',
          'version': '2.5.0.5422',
          'osName': 'alpine',
          'startTime': '2026-07-12T13:29:15Z',
        };
      final service = ProwlarrService(client);

      final status = await service.getStatus();

      expect(status.version, '2.5.0.5422');
      expect(status.appName, 'Prowlarr');
      expect(status.instanceName, 'Prowlarr');
      expect(status.osName, 'alpine');
      expect(client.lastGetPath, '/api/v1/system/status');
    });
  });

  group('ProwlarrService.getHealth', () {
    test('parses the flat health array', () async {
      final client = FakeApiClient()
        ..getResponseData = [
          {
            'source': 'IndexerLongTermStatusCheck',
            'type': 'warning',
            'message': 'Indexers unavailable due to failures',
            'wikiUrl': 'https://wiki.servarr.com/prowlarr',
          },
          {'source': 'UpdateCheck', 'type': 'error', 'message': 'boom'},
        ];
      final service = ProwlarrService(client);

      final issues = await service.getHealth();

      expect(issues, hasLength(2));
      expect(issues.first.source, 'IndexerLongTermStatusCheck');
      expect(issues.first.isError, isFalse);
      expect(issues[1].isError, isTrue);
      expect(client.lastGetPath, '/api/v1/health');
    });
  });

  group('ProwlarrService.getIndexers', () {
    test('parses the indexer array', () async {
      final client = FakeApiClient()
        ..getResponseData = [
          {
            'id': 1,
            'name': 'ItaTorrents',
            'definitionName': 'itatorrents',
            'enable': true,
            'protocol': 'torrent',
            'privacy': 'semiPrivate',
            'priority': 25,
            'supportsRss': true,
            'supportsSearch': true,
            'language': 'it-IT',
            'tags': [1, 2],
          },
          {'id': 2, 'name': 'Disabled', 'enable': false},
        ];
      final service = ProwlarrService(client);

      final indexers = await service.getIndexers();

      expect(indexers, hasLength(2));
      expect(indexers.first.id, 1);
      expect(indexers.first.name, 'ItaTorrents');
      expect(indexers.first.enable, isTrue);
      expect(indexers.first.protocol, 'torrent');
      expect(indexers.first.privacy, 'semiPrivate');
      expect(indexers.first.tags, [1, 2]);
      expect(indexers[1].enable, isFalse);
      expect(client.lastGetPath, '/api/v1/indexer');
    });
  });

  group('ProwlarrService.getIndexerStats', () {
    test('unwraps the nested indexers list and aggregates totals', () async {
      final client = FakeApiClient()
        ..getResponseData = {
          'indexers': [
            {
              'indexerId': 1,
              'indexerName': 'ItaTorrents',
              'averageResponseTime': 303,
              'numberOfQueries': 23,
              'numberOfGrabs': 8,
              'numberOfFailedQueries': 1,
              'numberOfFailedGrabs': 2,
            },
            {
              'indexerId': 3,
              'indexerName': 'ilcorsaroblu',
              'numberOfQueries': 7,
              'numberOfGrabs': 4,
              'numberOfFailedQueries': 0,
              'numberOfFailedGrabs': 0,
            },
          ],
          'userAgents': [],
          'hosts': [],
        };
      final service = ProwlarrService(client);

      final stats = await service.getIndexerStats(startDate: '2026-07-01');

      expect(stats.indexers, hasLength(2));
      expect(stats.totalQueries, 30);
      expect(stats.totalGrabs, 12);
      expect(stats.totalFailures, 3);
      expect(stats.indexers.first.numberOfFailures, 3);
      expect(client.lastGetPath, '/api/v1/indexerstats');
      expect(client.lastGetQueryParameters, {'startDate': '2026-07-01'});
    });

    test('returns empty stats when the payload is not a map', () async {
      final client = FakeApiClient()..getResponseData = 'nope';
      final service = ProwlarrService(client);

      final stats = await service.getIndexerStats();

      expect(stats.indexers, isEmpty);
      expect(stats.totalQueries, 0);
    });
  });

  group('ProwlarrService.getIndexerStatus', () {
    test('parses the disabled-indexer array', () async {
      final client = FakeApiClient()
        ..getResponseData = [
          {
            'indexerId': 2,
            'disabledTill': '2026-07-19T20:17:46Z',
            'mostRecentFailure': '2026-07-18T20:17:46Z',
            'initialFailure': '2026-01-26T10:35:38Z',
          },
        ];
      final service = ProwlarrService(client);

      final statuses = await service.getIndexerStatus();

      expect(statuses, hasLength(1));
      expect(statuses.first.indexerId, 2);
      expect(statuses.first.disabledTill, '2026-07-19T20:17:46Z');
      expect(client.lastGetPath, '/api/v1/indexerstatus');
    });
  });

  group('ProwlarrService.getHistory', () {
    test(
      'parses the paged records envelope and passes paging params',
      () async {
        final client = FakeApiClient()
          ..getResponseData = {
            'page': 1,
            'pageSize': 20,
            'sortKey': 'date',
            'sortDirection': 'descending',
            'totalRecords': 401,
            'records': [
              {
                'id': 400552,
                'indexerId': 3,
                'date': '2026-07-19T13:57:59Z',
                'successful': true,
                'eventType': 'indexerRss',
                'data': {
                  'query': '',
                  'queryResults': '15',
                  'source': 'Lidarr',
                  'elapsedTime': '1402',
                },
              },
            ],
          };
        final service = ProwlarrService(client);

        final history = await service.getHistory(page: 1, pageSize: 20);

        expect(history.totalRecords, 401);
        expect(history.records, hasLength(1));
        expect(history.hasMore, isTrue);
        final item = history.records.first;
        expect(item.id, 400552);
        expect(item.indexerId, 3);
        expect(item.eventType, 'indexerRss');
        expect(item.successful, isTrue);
        // `data` values stay raw strings, even numeric-looking ones.
        expect(item.data['queryResults'], '15');
        expect(item.data['source'], 'Lidarr');
        expect(client.lastGetPath, '/api/v1/history');
        expect(client.lastGetQueryParameters?['page'], 1);
        expect(client.lastGetQueryParameters?['pageSize'], 20);
        expect(client.lastGetQueryParameters?['sortKey'], 'date');
      },
    );

    test('forwards the optional eventType filter', () async {
      final client = FakeApiClient()..getResponseData = {'records': []};
      final service = ProwlarrService(client);

      await service.getHistory(eventType: 'releaseGrabbed');

      expect(client.lastGetQueryParameters?['eventType'], 'releaseGrabbed');
    });
  });

  group('ProwlarrService.getApplications', () {
    test('parses the applications array', () async {
      final client = FakeApiClient()
        ..getResponseData = [
          {
            'id': 1,
            'name': 'Lidarr',
            'syncLevel': 'fullSync',
            'enable': true,
            'implementation': 'Lidarr',
          },
        ];
      final service = ProwlarrService(client);

      final apps = await service.getApplications();

      expect(apps, hasLength(1));
      expect(apps.first.name, 'Lidarr');
      expect(apps.first.syncLevel, 'fullSync');
      expect(apps.first.enable, isTrue);
      expect(client.lastGetPath, '/api/v1/applications');
    });
  });
}
