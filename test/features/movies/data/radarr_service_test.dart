import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/api/base_arr_service.dart';
import 'package:seekarr/core/api/api_client.dart';
import 'package:seekarr/features/movies/data/radarr_service.dart';
import 'package:seekarr/features/movies/domain/models/radarr_movie.dart';

import '../../../test_helpers/fake_api_client.dart';

void main() {
  group('RadarrService', () {
    test('getQueue requests embedded movie data', () async {
      final client = FakeApiClient()
        ..getResponseData = {
          'records': [
            {'id': 1, 'title': 'Queued'},
          ],
        };
      final service = RadarrService(client);

      final items = await service.getQueue();

      expect(items, hasLength(1));
      expect(
        client.lastGetPath,
        '/api/${ArrServiceConfig.radarr.apiVersion}/queue',
      );
      expect(client.lastGetQueryParameters, const {'includeMovie': true});
    });

    test('getHistory requests embedded movie data', () async {
      final client = FakeApiClient()
        ..getResponseData = {
          'records': [
            {'id': 1, 'sourceTitle': 'Imported.Release'},
          ],
        };
      final service = RadarrService(client);

      final items = await service.getHistory();

      expect(items, hasLength(1));
      expect(
        client.lastGetPath,
        '/api/${ArrServiceConfig.radarr.apiVersion}/history',
      );
      expect(client.lastGetQueryParameters, {
        'page': 1,
        'pageSize': 20,
        'includeMovie': true,
      });
    });

    test('getReleases forwards the cancel token to ApiClient', () async {
      final client = FakeApiClient()..getResponseData = const [];
      final service = RadarrService(client);
      final cancelToken = CancelToken();

      await service.getReleases(42, cancelToken: cancelToken);

      expect(client.lastGetPath, '/api/v3/release');
      expect(client.lastGetQueryParameters, {'movieId': 42});
      expect(client.lastGetCancelToken, same(cancelToken));
    });

    test('lookupMovies asks nothing for an empty term', () async {
      final client = FakeApiClient();
      final service = RadarrService(client);

      expect(await service.lookupMovies(''), isEmpty);
      expect(client.getCallCount, 0);
    });

    test('lookupMovies encodes the term and maps results', () async {
      final client = FakeApiClient()
        ..getResponseData = [
          {'id': 7, 'title': 'Dune', 'year': 2021},
        ];
      final service = RadarrService(client);

      final movies = await service.lookupMovies('dune & friends');

      expect(client.lastGetPath, '/api/v3/movie/lookup');
      expect(client.lastGetQueryParameters, {'term': 'dune%20%26%20friends'});
      expect(movies.single.title, 'Dune');
    });

    test('lookupMovies forwards the cancel token to ApiClient', () async {
      final client = FakeApiClient()..getResponseData = const [];
      final service = RadarrService(client);
      final cancelToken = CancelToken();

      await service.lookupMovies('dune', cancelToken: cancelToken);

      // Global search re-runs this leg on every debounced keystroke; without a
      // token the superseded request runs to completion.
      expect(client.lastGetCancelToken, same(cancelToken));
    });

    group('getMovieByTmdbId', () {
      test('finds movie when TMDB ID matches', () async {
        final service = _TestRadarrService([
          _movie(
            id: 1,
            title: 'Movie 1',
            tmdbId: 12345,
            year: 2023,
            runtime: 120,
          ),
          _movie(
            id: 2,
            title: 'Movie 2',
            tmdbId: 67890,
            year: 2024,
            runtime: 90,
          ),
        ]);

        final found = await service.getMovieByTmdbId(12345);

        expect(found, isNotNull);
        expect(found?.id, 1);
        expect(found?.title, 'Movie 1');
      });

      test('returns null when TMDB ID not found', () async {
        final service = _TestRadarrService([
          _movie(
            id: 1,
            title: 'Movie 1',
            tmdbId: 12345,
            year: 2023,
            runtime: 120,
          ),
        ]);

        final found = await service.getMovieByTmdbId(99999);
        expect(found, isNull);
      });

      test('handles empty library', () async {
        final service = _TestRadarrService(const []);

        final found = await service.getMovieByTmdbId(12345);
        expect(found, isNull);
      });
    });
  });
}

class _TestRadarrService extends RadarrService {
  _TestRadarrService(this._movies) : super(ApiClient(baseUrl: '', apiKey: ''));

  final List<RadarrMovie> _movies;

  @override
  Future<List<RadarrMovie>> getMovies() async => _movies;
}

RadarrMovie _movie({
  required int id,
  required String title,
  required int tmdbId,
  required int year,
  required int runtime,
}) {
  return RadarrMovie(
    id: id,
    title: title,
    sortTitle: title.toLowerCase(),
    sizeOnDisk: 0,
    status: 'released',
    hasFile: true,
    monitored: true,
    year: year,
    images: const [],
    tmdbId: tmdbId,
    runtime: runtime,
    genres: const [],
  );
}
