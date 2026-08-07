import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/features/bazarr/data/bazarr_service.dart';

import '../../../test_helpers/fake_api_client.dart';

void main() {
  group('BazarrService.getStatus', () {
    test(
      'parses the nested data envelope and surfaces the Bazarr version',
      () async {
        final client = FakeApiClient()
          ..getResponseData = {
            'data': {
              'bazarr_version': '1.4.5',
              'sonarr_version': '4.0.0',
              'radarr_version': '5.0.0',
              'operating_system': 'linux',
              'database_engine': 'sqlite',
            },
          };
        final service = BazarrService(client);

        final status = await service.getStatus();

        expect(status.bazarrVersion, '1.4.5');
        expect(status.sonarrVersion, '4.0.0');
        expect(status.radarrVersion, '5.0.0');
        expect(status.operatingSystem, 'linux');
        expect(status.databaseEngine, 'sqlite');
        expect(client.lastGetPath, '/api/system/status');
      },
    );
  });

  group('BazarrService.getBadges', () {
    test('parses the unwrapped badges payload and totals wanted', () async {
      final client = FakeApiClient()
        ..getResponseData = {
          'episodes': 12,
          'movies': 4,
          'providers': 3,
          'status': true,
          'sonarr_signalr': true,
          'radarr_signalr': false,
          'announcements': 1,
        };
      final service = BazarrService(client);

      final badges = await service.getBadges();

      expect(badges.episodes, 12);
      expect(badges.movies, 4);
      expect(badges.totalWanted, 16);
      expect(badges.providers, 3);
      expect(badges.status, isTrue);
      expect(badges.sonarrSignalR, isTrue);
      expect(badges.radarrSignalR, isFalse);
      expect(badges.announcements, 1);
      expect(client.lastGetPath, '/api/badges');
    });

    test(
      'returns an empty badges object when the payload is not a map',
      () async {
        final client = FakeApiClient()..getResponseData = 'unexpected';
        final service = BazarrService(client);

        final badges = await service.getBadges();

        expect(badges.totalWanted, 0);
        expect(badges.status, isFalse);
      },
    );
  });

  group('BazarrService paged endpoints', () {
    test('getSeries forwards start/length and unwraps data + total', () async {
      final client = FakeApiClient()
        ..getResponseData = {
          'data': [
            {
              'sonarrSeriesId': 1,
              'title': 'The Series',
              'monitored': true,
              'episodeMissingCount': 2,
              'profileId': 4,
              'tags': ['tvdb:123'],
            },
          ],
          'total': 42,
        };
      final service = BazarrService(client);

      final result = await service.getSeries(start: 0, length: 10);

      expect(client.lastGetPath, '/api/series');
      expect(client.lastGetQueryParameters, {'start': 0, 'length': 10});
      expect(result.data, hasLength(1));
      expect(result.total, 42);
      expect(result.hasMore, isTrue);
      final series = result.data.single;
      expect(series.sonarrSeriesId, 1);
      expect(series.title, 'The Series');
      expect(series.monitored, isTrue);
      expect(series.episodeMissingCount, 2);
      expect(series.profileId, 4);
      expect(series.tags, ['tvdb:123']);
    });

    test('getSeries hasMore respects start offset on later pages', () async {
      final client = FakeApiClient()
        ..getResponseData = {
          'data': List.generate(
            50,
            (i) => {'sonarrSeriesId': 1000 + i, 'title': 'Series $i'},
          ),
          'total': 100,
        };
      final service = BazarrService(client);

      final result = await service.getSeries(start: 50, length: 50);

      expect(result.hasMore, isFalse);
    });

    test(
      'getMovies parses missing_subtitles language list and radarrId',
      () async {
        final client = FakeApiClient()
          ..getResponseData = {
            'data': [
              {
                'radarrId': 99,
                'title': 'Dune: Part Two',
                'year': '2024',
                'monitored': true,
                'missing_subtitles': [
                  {'name': 'English', 'code2': 'en', 'code3': 'eng'},
                  {
                    'name': 'Italian',
                    'code2': 'it',
                    'code3': 'ita',
                    'forced': true,
                  },
                ],
              },
            ],
            'total': 1,
          };
        final service = BazarrService(client);

        final result = await service.getMovies(start: 0, length: 25);

        expect(client.lastGetPath, '/api/movies');
        expect(client.lastGetQueryParameters, {'start': 0, 'length': 25});
        final movie = result.data.single;
        expect(movie.radarrId, 99);
        expect(movie.title, 'Dune: Part Two');
        expect(movie.missingSubtitlesCount, 2);
        expect(movie.missingLanguages.first.code2, 'en');
        expect(movie.missingLanguages.last.forced, isTrue);
        expect(result.hasMore, isFalse);
      },
    );

    test(
      'getWantedEpisodes returns wanted items with missing languages',
      () async {
        final client = FakeApiClient()
          ..getResponseData = {
            'data': [
              {
                'seriesTitle': 'Foundation',
                'episode_number': '1x02',
                'episodeTitle': 'The Emperor',
                'sonarrSeriesId': 11,
                'sonarrEpisodeId': 22,
                'missing_subtitles': [
                  {'name': 'English', 'code2': 'en', 'code3': 'eng'},
                  {'name': 'Spanish', 'code2': 'es', 'code3': 'spa'},
                ],
                'tags': ['tvdb:1'],
              },
            ],
            'total': 1,
          };
        final service = BazarrService(client);

        final result = await service.getWantedEpisodes();

        expect(client.lastGetPath, '/api/episodes/wanted');
        final item = result.data.single;
        expect(item.seriesTitle, 'Foundation');
        expect(item.episodeNumber, '1x02');
        expect(item.season, 1);
        expect(item.missingSubtitlesCount, 2);
        expect(item.missingLanguages.map((l) => l.code2).toList(), [
          'en',
          'es',
        ]);
        expect(item.sonarrSeriesId, 11);
        expect(item.sonarrEpisodeId, 22);
      },
    );

    test('getWantedMovies returns movie wanted items', () async {
      final client = FakeApiClient()
        ..getResponseData = {
          'data': [
            {
              'title': 'Dune',
              'radarrId': 7,
              'missing_subtitles': [
                {'name': 'Italian', 'code2': 'it', 'code3': 'ita', 'hi': true},
              ],
              'sceneName': 'Dune.2021',
            },
          ],
          'total': 1,
        };
      final service = BazarrService(client);

      final result = await service.getWantedMovies();

      expect(client.lastGetPath, '/api/movies/wanted');
      final item = result.data.single;
      expect(item.title, 'Dune');
      expect(item.radarrId, 7);
      expect(item.sceneName, 'Dune.2021');
      expect(item.missingSubtitlesCount, 1);
      expect(item.missingLanguages.single.code2, 'it');
      expect(item.missingLanguages.single.hi, isTrue);
    });
  });

  group('BazarrService queues and tasks', () {
    test('getSystemTasks unwraps the data list into model items', () async {
      final client = FakeApiClient()
        ..getResponseData = {
          'data': [
            {
              'interval': '1d',
              'job_id': 'wanted_search_subtitles',
              'job_running': false,
              'name': 'Wanted search',
              'next_run_in': '12h',
            },
          ],
        };
      final service = BazarrService(client);

      final tasks = await service.getSystemTasks();

      expect(client.lastGetPath, '/api/system/tasks');
      expect(tasks, hasLength(1));
      expect(tasks.single.name, 'Wanted search');
      expect(tasks.single.jobRunning, isFalse);
      expect(tasks.single.nextRunIn, '12h');
    });

    test('getJobs filters by status when provided', () async {
      final client = FakeApiClient()
        ..getResponseData = {
          'data': [
            {
              'job_id': 'j1',
              'job_name': 'Search subtitles',
              'status': 'failed',
              'is_progress': false,
              'is_signalr': true,
            },
          ],
        };
      final service = BazarrService(client);

      final jobs = await service.getJobs(status: 'failed');

      expect(client.lastGetPath, '/api/system/jobs');
      expect(client.lastGetQueryParameters, {'status': 'failed'});
      expect(jobs.single.status, 'failed');
      expect(jobs.single.jobId, 'j1');
    });
  });

  group('BazarrService mutating actions', () {
    test(
      'patchSeriesAction forwards seriesid and action as query params',
      () async {
        final client = FakeApiClient();
        final service = BazarrService(client);

        await service.patchSeriesAction(42, 'search-wanted');

        expect(client.lastPatchPath, '/api/series');
        expect(client.lastPatchQueryParameters, {
          'seriesid': '42',
          'action': 'search-wanted',
        });
      },
    );

    test(
      'patchMovieAction forwards radarrid and action as query params',
      () async {
        final client = FakeApiClient();
        final service = BazarrService(client);

        await service.patchMovieAction(7, 'search-missing');

        expect(client.lastPatchPath, '/api/movies');
        expect(client.lastPatchQueryParameters, {
          'radarrid': '7',
          'action': 'search-missing',
        });
      },
    );

    test('runSystemTask posts the task id', () async {
      final client = FakeApiClient();
      final service = BazarrService(client);

      await service.runSystemTask('wanted_search_subtitles');

      expect(client.lastPostPath, '/api/system/tasks');
      expect(client.lastPostQueryParameters, {
        'taskid': 'wanted_search_subtitles',
      });
    });

    test('runJobAction posts the job id and action', () async {
      final client = FakeApiClient();
      final service = BazarrService(client);

      await service.runJobAction('j1', 'force_start');

      expect(client.lastPostPath, '/api/system/jobs');
      expect(client.lastPostQueryParameters, {
        'id': 'j1',
        'action': 'force_start',
      });
    });

    test('emptyJobQueue patches with the queueName', () async {
      final client = FakeApiClient();
      final service = BazarrService(client);

      await service.emptyJobQueue('failed');

      expect(client.lastPatchPath, '/api/system/jobs');
      expect(client.lastPatchQueryParameters, {'queueName': 'failed'});
    });

    test('deleteJob sends id via delete', () async {
      final client = FakeApiClient();
      final service = BazarrService(client);

      await service.deleteJob('j1');

      expect(client.lastDeletePath, '/api/system/jobs');
      expect(client.lastDeleteQueryParameters, {'id': 'j1'});
    });
  });

  group('BazarrService.searchLibrary', () {
    /// The two GETs a library snapshot makes: `/api/series` then `/api/movies`.
    void seedLibrary(FakeApiClient client) {
      client.getResponseQueue.addAll([
        {
          'data': [
            {'sonarrSeriesId': 5, 'title': 'Foundation'},
            {'sonarrSeriesId': 6, 'title': 'The Boys'},
            {'sonarrSeriesId': 7},
          ],
          'total': 3,
        },
        {
          'data': [
            {'radarrId': 11, 'title': 'Dune'},
            {'radarrId': 12, 'title': 'Foundation: The Movie'},
          ],
          'total': 2,
        },
      ]);
    }

    test('matches series and movies by title, case-insensitively', () async {
      final client = FakeApiClient();
      seedLibrary(client);
      final service = BazarrService(client);

      final hits = await service.searchLibrary('FOUND');

      expect(hits.map((hit) => hit.id), [5, 12]);
      expect(hits.map((hit) => hit.isMovie), [false, true]);
      expect(hits.map((hit) => hit.title), [
        'Foundation',
        'Foundation: The Movie',
      ]);
    });

    test('returns nothing, and asks nothing, for a blank query', () async {
      final client = FakeApiClient();
      final service = BazarrService(client);

      expect(await service.searchLibrary('   '), isEmpty);
      expect(client.getCallCount, 0);
    });

    test('reuses the snapshot instead of re-downloading the library', () async {
      final client = FakeApiClient();
      seedLibrary(client);
      final service = BazarrService(client);

      await service.searchLibrary('dune');
      await service.searchLibrary('dun');
      await service.searchLibrary('du');

      // Bazarr has no search endpoint, so each query used to pull both lists in
      // full — up to 1000 records per debounced keystroke pause.
      expect(client.getCallCount, 2);
    });

    test('shares a fetch already in flight', () async {
      final client = FakeApiClient();
      seedLibrary(client);
      final service = BazarrService(client);

      final results = await Future.wait([
        service.searchLibrary('dune'),
        service.searchLibrary('boys'),
      ]);

      expect(client.getCallCount, 2);
      expect(results.first.single.title, 'Dune');
      expect(results[1].single.title, 'The Boys');
    });

    test('a superseded query skips the match but keeps the snapshot', () async {
      final client = FakeApiClient();
      seedLibrary(client);
      final service = BazarrService(client);
      final cancelToken = CancelToken()..cancel();

      final hits = await service.searchLibrary(
        'found',
        cancelToken: cancelToken,
      );

      // Cancelling cannot abort the download — it is shared with whatever query
      // comes next (see `_libraryIndex`) — so the snapshot still lands and the
      // successor reads it without a second round trip.
      expect(hits, isEmpty);
      expect(client.getCallCount, 2);
      expect((await service.searchLibrary('found')).map((hit) => hit.id), [
        5,
        12,
      ]);
      expect(client.getCallCount, 2);
    });

    test('a failed round does not poison the next query', () async {
      final client = FakeApiClient()..getException = Exception('bazarr down');
      final service = BazarrService(client);

      await expectLater(service.searchLibrary('dune'), throwsA(isA<Object>()));

      // The in-flight future is released on failure too, or every later query
      // would await a future that already lost.
      client.getException = null;
      seedLibrary(client);
      final hits = await service.searchLibrary('dune');

      expect(hits.single.title, 'Dune');
    });
  });
}
