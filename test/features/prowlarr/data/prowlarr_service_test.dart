import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/prowlarr/data/prowlarr_service.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';

import '../../../test_helpers/fake_api_client.dart';

/// A rejected save/test as Prowlarr answers it: HTTP 400 with the validation
/// failures in the body.
DioException _validationError(List<Map<String, dynamic>> failures) {
  final request = RequestOptions(path: '/api/v1/indexer');
  return DioException(
    requestOptions: request,
    response: Response<dynamic>(
      requestOptions: request,
      statusCode: 400,
      data: failures,
    ),
  );
}

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

  group('ProwlarrService.getIndexerHistory', () {
    test('asks the server to filter by indexer', () async {
      final client = FakeApiClient()
        ..getResponseData = [
          {
            'id': 1,
            'indexerId': 7,
            'eventType': 'indexerQuery',
            'successful': true,
            'data': {'query': 'dune'},
          },
        ];
      final service = ProwlarrService(client);

      final items = await service.getIndexerHistory(7, limit: 10);

      expect(items, hasLength(1));
      expect(items.first.indexerId, 7);
      expect(client.lastGetPath, '/api/v1/history/indexer');
      expect(client.lastGetQueryParameters, {'indexerId': 7, 'limit': 10});
    });
  });

  group('ProwlarrService.getIndexerSchema', () {
    test('parses definitions and drops the server-computed bulk', () async {
      final client = FakeApiClient()
        ..getResponseData = [
          {
            'name': '1337x',
            'implementation': 'Cardigann',
            'configContract': 'CardigannSettings',
            'definitionName': '1337x',
            'protocol': 'torrent',
            'privacy': 'public',
            'supportsRss': true,
            'fields': [
              {'order': 1, 'name': 'baseUrl', 'type': 'select', 'value': 0},
              {
                'order': 0,
                'name': 'definitionFile',
                'hidden': 'hidden',
                'value': '1337x',
              },
            ],
            'capabilities': {
              'categories': [
                {'id': 2000, 'name': 'Movies'},
              ],
            },
            'presets': [
              {'name': 'preset'},
            ],
          },
        ];
      final service = ProwlarrService(client);

      final definitions = await service.getIndexerSchema();

      expect(definitions, hasLength(1));
      final definition = definitions.first;
      expect(definition.name, '1337x');
      expect(definition.implementation, 'Cardigann');
      // Fields come back sorted by `order`, hidden ones included.
      expect(definition.fields.map((f) => f.name), [
        'definitionFile',
        'baseUrl',
      ]);
      expect(definition.fields.first.isHidden, isTrue);
      expect(definition.raw.containsKey('capabilities'), isFalse);
      expect(definition.raw.containsKey('presets'), isFalse);
      expect(client.lastGetPath, '/api/v1/indexer/schema');
    });
  });

  group('ProwlarrService.saveIndexer', () {
    test('posts when the payload has no id', () async {
      final client = FakeApiClient()..postResponseData = {'id': 9};
      final service = ProwlarrService(client);

      final saved = await service.saveIndexer({'name': 'New', 'fields': []});

      expect(saved.id, 9);
      expect(client.lastPostPath, '/api/v1/indexer');
      expect(client.putCallCount, 0);
    });

    test('puts to the id route when the payload carries one', () async {
      final client = FakeApiClient()..putResponseData = {'id': 4, 'name': 'X'};
      final service = ProwlarrService(client);

      await service.saveIndexer({'id': 4, 'name': 'X'});

      expect(client.lastPutPath, '/api/v1/indexer/4');
      expect(client.postCallCount, 0);
    });

    test('surfaces the validation failures instead of the HTTP code', () async {
      final client = FakeApiClient()
        ..postException = _validationError([
          {
            'propertyName': 'ApiKey',
            'errorMessage': 'Unable to connect: invalid API key',
          },
        ]);
      final service = ProwlarrService(client);

      await expectLater(
        service.saveIndexer({'name': 'New'}),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('invalid API key'),
          ),
        ),
      );
    });

    test('falls back to the status code when the body says nothing', () async {
      final request = RequestOptions(path: '/api/v1/indexer');
      final client = FakeApiClient()
        ..postException = DioException(
          requestOptions: request,
          response: Response<dynamic>(requestOptions: request, statusCode: 500),
        );
      final service = ProwlarrService(client);

      await expectLater(
        service.saveIndexer({'name': 'New'}),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('Could not add the indexer'), contains('HTTP 500')),
          ),
        ),
      );
    });
  });

  group('ProwlarrService.deleteIndexer', () {
    test('deletes the id route', () async {
      final client = FakeApiClient();
      final service = ProwlarrService(client);

      await service.deleteIndexer(3);

      expect(client.lastDeletePath, '/api/v1/indexer/3');
    });
  });

  group('ProwlarrService.testIndexer', () {
    test('posts the payload to the test route', () async {
      final client = FakeApiClient();
      final service = ProwlarrService(client);

      await service.testIndexer({'id': 2, 'name': 'X'});

      expect(client.lastPostPath, '/api/v1/indexer/test');
      expect(client.lastPostData, {'id': 2, 'name': 'X'});
      // A test reaches out to the tracker, so it outlives the client default.
      expect(client.lastPostReceiveTimeout, const Duration(seconds: 60));
    });

    test('reports the failure reason the tracker gave', () async {
      final client = FakeApiClient()
        ..postException = _validationError([
          {'errorMessage': 'Query successful, but no results were returned'},
        ]);
      final service = ProwlarrService(client);

      await expectLater(
        service.testIndexer({'id': 2}),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('no results were returned'),
          ),
        ),
      );
    });
  });

  group('ProwlarrService.testAllIndexers', () {
    test('parses each result with its validation failures', () async {
      final client = FakeApiClient()
        ..postResponseData = [
          {'id': 1, 'isValid': true, 'validationFailures': []},
          {
            'id': 2,
            'isValid': false,
            'validationFailures': [
              {'propertyName': '', 'errorMessage': 'Auth failed'},
            ],
          },
        ];
      final service = ProwlarrService(client);

      final results = await service.testAllIndexers();

      expect(results, hasLength(2));
      expect(results.first.isValid, isTrue);
      expect(results[1].isValid, isFalse);
      expect(results[1].failures.single.errorMessage, 'Auth failed');
      expect(client.lastPostPath, '/api/v1/indexer/testall');
    });

    test('reads the report back out of the 400 Prowlarr answers with', () async {
      // Servarr's ProviderControllerBase returns BadRequest(result) — body
      // included — as soon as ANY provider is invalid, which is the *normal*
      // partial-failure case. ApiClient rejects >= 400, so without claiming the
      // body back the "N of M failed" report was unreachable code.
      final client = FakeApiClient()
        ..postException = _validationError([
          {'id': 1, 'isValid': true, 'validationFailures': []},
          {
            'id': 2,
            'isValid': false,
            'validationFailures': [
              {'propertyName': 'ApiKey', 'errorMessage': 'Auth failed'},
            ],
          },
        ]);
      final service = ProwlarrService(client);

      final results = await service.testAllIndexers();

      expect(results, hasLength(2));
      expect(results.first.isValid, isTrue);
      expect(results[1].isValid, isFalse);
      expect(results[1].failures.single.errorMessage, 'Auth failed');
    });

    test('a real failure still fails, with the reason it gave', () async {
      final request = RequestOptions(path: '/api/v1/indexer/testall');
      final client = FakeApiClient()
        ..postException = DioException(
          requestOptions: request,
          response: Response<dynamic>(
            requestOptions: request,
            statusCode: 401,
            data: {'message': 'Unauthorized'},
          ),
        );

      await expectLater(
        ProwlarrService(client).testAllIndexers(),
        throwsA(isA<Exception>()),
      );
    });

    test('a testall report on the provider route is read back too', () async {
      final client = FakeApiClient()
        ..postException = _validationError([
          {
            'id': 3,
            'isValid': false,
            'validationFailures': [
              {'errorMessage': 'Unable to connect to Sonarr'},
            ],
          },
        ]);

      final results = await ProwlarrService(
        client,
      ).testAllProviders(ProwlarrProviderKind.application);

      expect(results.single.isValid, isFalse);
      expect(
        results.single.failures.single.errorMessage,
        'Unable to connect to Sonarr',
      );
    });
  });

  group('ProwlarrService.bulkUpdateIndexers', () {
    test('sends only the properties that change', () async {
      final client = FakeApiClient();
      final service = ProwlarrService(client);

      await service.bulkUpdateIndexers(ids: [1, 2], enable: false);

      expect(client.lastPutPath, '/api/v1/indexer/bulk');
      expect(client.lastPutData, {
        'ids': [1, 2],
        'enable': false,
      });
    });

    test('pairs tags with their apply mode', () async {
      final client = FakeApiClient();
      final service = ProwlarrService(client);

      await service.bulkUpdateIndexers(
        ids: [5],
        tags: [3],
        applyTags: 'replace',
        priority: 10,
        seedRatio: 1.5,
      );

      expect(client.lastPutData, {
        'ids': [5],
        'priority': 10,
        'tags': [3],
        'applyTags': 'replace',
        'seedRatio': 1.5,
      });
    });
  });

  group('ProwlarrService.bulkDeleteIndexers', () {
    test('sends the ids in the delete body', () async {
      final client = FakeApiClient();
      final service = ProwlarrService(client);

      await service.bulkDeleteIndexers([4, 6]);

      expect(client.lastDeletePath, '/api/v1/indexer/bulk');
      expect(client.lastDeleteData, {
        'ids': [4, 6],
      });
    });
  });

  group('ProwlarrService tags and profiles', () {
    test('parses tags', () async {
      final client = FakeApiClient()
        ..getResponseData = [
          {'id': 1, 'label': 'italian'},
        ];
      final service = ProwlarrService(client);

      final tags = await service.getTags();

      expect(tags.single.label, 'italian');
      expect(client.lastGetPath, '/api/v1/tag');
    });

    test('creates a tag and returns its id', () async {
      final client = FakeApiClient()
        ..postResponseData = {'id': 7, 'label': 'anime'};
      final service = ProwlarrService(client);

      final tag = await service.createTag('anime');

      expect(tag.id, 7);
      expect(client.lastPostPath, '/api/v1/tag');
      expect(client.lastPostData, {'label': 'anime'});
    });

    test('parses sync profiles', () async {
      final client = FakeApiClient()
        ..getResponseData = [
          {
            'id': 1,
            'name': 'Standard',
            'enableRss': true,
            'enableAutomaticSearch': true,
            'enableInteractiveSearch': false,
            'minimumSeeders': 2,
          },
        ];
      final service = ProwlarrService(client);

      final profiles = await service.getAppProfiles();

      expect(profiles.single.name, 'Standard');
      expect(profiles.single.enableInteractiveSearch, isFalse);
      expect(profiles.single.minimumSeeders, 2);
      expect(client.lastGetPath, '/api/v1/appprofile');
    });
  });

  group('ProwlarrService commands', () {
    test('queues the app sync command by name', () async {
      final client = FakeApiClient()
        ..postResponseData = {
          'id': 42,
          'name': 'ApplicationIndexerSync',
          'status': 'queued',
        };
      final service = ProwlarrService(client);

      final command = await service.syncAppIndexers();

      expect(command.id, 42);
      expect(command.isFinished, isFalse);
      expect(client.lastPostPath, '/api/v1/command');
      expect(client.lastPostData, {'name': 'ApplicationIndexerSync'});
    });

    test('reads a finished command back', () async {
      final client = FakeApiClient()
        ..getResponseData = {
          'id': 42,
          'name': 'ApplicationIndexerSync',
          'status': 'failed',
          'message': 'Sonarr is unreachable',
        };
      final service = ProwlarrService(client);

      final command = await service.getCommand(42);

      expect(command.isFailed, isTrue);
      expect(command.isFinished, isTrue);
      expect(command.message, 'Sonarr is unreachable');
      expect(client.lastGetPath, '/api/v1/command/42');
    });
  });

  group('ProwlarrService provider resources', () {
    test('reads each kind from its own path', () async {
      for (final kind in ProwlarrProviderKind.values) {
        final client = FakeApiClient()..getResponseData = const [];
        await ProwlarrService(client).getProviders(kind);
        expect(client.lastGetPath, '/api/v1/${kind.path}');

        await ProwlarrService(client).getProviderSchema(kind);
        expect(client.lastGetPath, '/api/v1/${kind.path}/schema');
      }
    });

    test('an application is active unless its sync level is disabled', () async {
      final client = FakeApiClient()
        ..getResponseData = [
          {'id': 1, 'name': 'Sonarr', 'syncLevel': 'fullSync'},
          {'id': 2, 'name': 'Radarr', 'syncLevel': 'disabled'},
        ];
      final apps = await ProwlarrService(client).getApplications();

      // Applications carry no `enable` flag; the sync level is the on/off state.
      expect(apps.first.isActive, isTrue);
      expect(apps[1].isActive, isFalse);
    });

    test('a download client falls back to its own enable flag', () async {
      final client = FakeApiClient()
        ..getResponseData = [
          {
            'id': 3,
            'name': 'qBittorrent',
            'enable': false,
            'protocol': 'torrent',
            'priority': 2,
          },
        ];
      final clients = await ProwlarrService(
        client,
      ).getProviders(ProwlarrProviderKind.downloadClient);

      expect(clients.single.isActive, isFalse);
      expect(clients.single.protocol, 'torrent');
      expect(clients.single.priority, 2);
    });

    test('posts a new provider and puts an existing one', () async {
      final client = FakeApiClient()..postResponseData = {'id': 5};
      final service = ProwlarrService(client);

      await service.saveProvider(ProwlarrProviderKind.notification, {
        'name': 'Telegram',
      });
      expect(client.lastPostPath, '/api/v1/notification');

      client.putResponseData = {'id': 5};
      await service.saveProvider(ProwlarrProviderKind.notification, {
        'id': 5,
        'name': 'Telegram',
      });
      expect(client.lastPutPath, '/api/v1/notification/5');
    });

    test('deletes and tests through the kind path', () async {
      final client = FakeApiClient();
      final service = ProwlarrService(client);

      await service.deleteProvider(ProwlarrProviderKind.indexerProxy, 2);
      expect(client.lastDeletePath, '/api/v1/indexerproxy/2');

      await service.testProvider(ProwlarrProviderKind.indexerProxy, {'id': 2});
      expect(client.lastPostPath, '/api/v1/indexerproxy/test');

      client.postResponseData = [
        {'id': 2, 'isValid': true},
      ];
      final results = await service.testAllProviders(
        ProwlarrProviderKind.indexerProxy,
      );
      expect(client.lastPostPath, '/api/v1/indexerproxy/testall');
      expect(results.single.isValid, isTrue);
    });

    test('surfaces the validation failure of a refused save', () async {
      final client = FakeApiClient()
        ..postException = _validationError([
          {'errorMessage': 'Unable to connect to Sonarr'},
        ]);

      await expectLater(
        ProwlarrService(
          client,
        ).saveProvider(ProwlarrProviderKind.application, {'name': 'Sonarr'}),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Unable to connect to Sonarr'),
          ),
        ),
      );
    });
  });

  group('ProwlarrService sync profiles', () {
    test('posts a new profile and puts an existing one', () async {
      final client = FakeApiClient()..postResponseData = {'id': 2};
      final service = ProwlarrService(client);

      await service.saveAppProfile({'name': 'Standard'});
      expect(client.lastPostPath, '/api/v1/appprofile');

      client.putResponseData = {'id': 2};
      await service.saveAppProfile({'id': 2, 'name': 'Standard'});
      expect(client.lastPutPath, '/api/v1/appprofile/2');

      await service.deleteAppProfile(2);
      expect(client.lastDeletePath, '/api/v1/appprofile/2');
    });
  });

  group('ProwlarrService tag management', () {
    test('reads tag usage from tag/detail', () async {
      final client = FakeApiClient()
        ..getResponseData = [
          {
            'id': 1,
            'label': 'italian',
            'indexerIds': [3, 4],
            'applicationIds': [1],
            'notificationIds': [],
            'indexerProxyIds': [],
          },
          {'id': 2, 'label': 'unused'},
        ];
      final tags = await ProwlarrService(client).getTagDetails();

      expect(client.lastGetPath, '/api/v1/tag/detail');
      expect(tags.first.usageCount, 3);
      expect(tags.first.isUnused, isFalse);
      expect(tags[1].isUnused, isTrue);
    });

    test('renames and deletes a tag', () async {
      final client = FakeApiClient()
        ..putResponseData = {'id': 1, 'label': 'ita'};
      final service = ProwlarrService(client);

      final renamed = await service.renameTag(1, 'ita');
      expect(renamed.label, 'ita');
      expect(client.lastPutPath, '/api/v1/tag/1');
      expect(client.lastPutData, {'id': 1, 'label': 'ita'});

      await service.deleteTag(1);
      expect(client.lastDeletePath, '/api/v1/tag/1');
    });
  });

  group('ProwlarrService.getIndexerCategories', () {
    test('parses the category tree', () async {
      final client = FakeApiClient()
        ..getResponseData = [
          {
            'id': 2000,
            'name': 'Movies',
            'subCategories': [
              {'id': 2040, 'name': 'Movies/HD'},
            ],
          },
        ];
      final categories = await ProwlarrService(client).getIndexerCategories();

      expect(client.lastGetPath, '/api/v1/indexer/categories');
      expect(categories.single.name, 'Movies');
      expect(categories.single.subCategories.single.id, 2040);
    });
  });

  group('ProwlarrIndexer categories', () {
    test('flattens capabilities into ids the filter can match', () {
      final indexer = ProwlarrIndexer.fromJson({
        'id': 1,
        'name': 'Tracker',
        'capabilities': {
          'categories': [
            {
              'id': 2000,
              'name': 'Movies',
              'subCategories': [
                {'id': 2040, 'name': 'Movies/HD'},
              ],
            },
            {'id': 5000, 'name': 'TV'},
          ],
        },
      });

      expect(indexer.categoryIds, [2000, 2040, 5000]);
    });

    test('survives a schema parse that strips the capabilities', () async {
      final client = FakeApiClient()
        ..getResponseData = [
          {
            'name': 'Tracker',
            'capabilities': {
              'categories': [
                {'id': 2000, 'name': 'Movies'},
              ],
            },
          },
        ];
      final definitions = await ProwlarrService(client).getIndexerSchema();

      expect(definitions.single.categoryIds, [2000]);
      expect(definitions.single.raw.containsKey('capabilities'), isFalse);
    });
  });
}
