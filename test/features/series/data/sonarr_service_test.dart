import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';

import '../../../test_helpers/fake_api_client.dart';

void main() {
  group('SonarrService', () {
    test('getQueue requests embedded series and episode data', () async {
      final client = FakeApiClient()
        ..getResponseData = {
          'records': [
            {'id': 1, 'title': 'Queued'},
          ],
        };
      final service = SonarrService(client);

      final items = await service.getQueue();

      expect(items, hasLength(1));
      expect(
        client.lastGetPath,
        '/api/${ArrServiceConfig.sonarr.apiVersion}/queue',
      );
      expect(client.lastGetQueryParameters, const {
        'includeSeries': true,
        'includeEpisode': true,
        'includeUnknownSeriesItems': true,
      });
    });

    test('getHistory requests embedded series and episode data', () async {
      final client = FakeApiClient()
        ..getResponseData = {
          'records': [
            {'id': 1, 'sourceTitle': 'Imported.Release'},
          ],
        };
      final service = SonarrService(client);

      final items = await service.getHistory();

      expect(items, hasLength(1));
      expect(
        client.lastGetPath,
        '/api/${ArrServiceConfig.sonarr.apiVersion}/history',
      );
      expect(client.lastGetQueryParameters, {
        'page': 1,
        'pageSize': 20,
        'includeSeries': true,
        'includeEpisode': true,
      });
    });

    test('getReleases forwards the cancel token to ApiClient', () async {
      final client = FakeApiClient()..getResponseData = const [];
      final service = SonarrService(client);
      final cancelToken = CancelToken();

      await service.getReleases(
        seriesId: 7,
        seasonNumber: 2,
        cancelToken: cancelToken,
      );

      expect(client.lastGetPath, '/api/v3/release');
      expect(client.lastGetQueryParameters, {'seriesId': 7, 'seasonNumber': 2});
      expect(client.lastGetCancelToken, same(cancelToken));
    });

    test('lookupSeries asks nothing for an empty term', () async {
      final client = FakeApiClient();
      final service = SonarrService(client);

      expect(await service.lookupSeries(''), isEmpty);
      expect(client.getCallCount, 0);
    });

    test('lookupSeries encodes the term and maps results', () async {
      final client = FakeApiClient()
        ..getResponseData = [
          {'id': 9, 'title': 'The Boys', 'year': 2019},
        ];
      final service = SonarrService(client);

      final series = await service.lookupSeries('the boys & co');

      expect(client.lastGetPath, '/api/v3/series/lookup');
      expect(client.lastGetQueryParameters, {'term': 'the%20boys%20%26%20co'});
      expect(series.single.title, 'The Boys');
    });

    test('lookupSeries forwards the cancel token to ApiClient', () async {
      final client = FakeApiClient()..getResponseData = const [];
      final service = SonarrService(client);
      final cancelToken = CancelToken();

      await service.lookupSeries('the boys', cancelToken: cancelToken);

      // Global search re-runs this leg on every debounced keystroke; without a
      // token the superseded request runs to completion.
      expect(client.lastGetCancelToken, same(cancelToken));
    });

    group('getSeriesByTvdbId', () {
      test('finds series when TVDB ID matches', () async {
        final service = _TestSonarrService([
          _series(
            id: 1,
            title: 'Series 1',
            tvdbId: 11111,
            year: 2023,
            runtime: 45,
            genres: const ['Drama'],
          ),
          _series(
            id: 2,
            title: 'Series 2',
            tvdbId: 22222,
            year: 2020,
            runtime: 60,
            genres: const ['Comedy'],
          ),
        ]);

        final found = await service.getSeriesByTvdbId(11111);
        expect(found, isNotNull);
        expect(found!.id, 1);
        expect(found.title, 'Series 1');
      });

      test('returns null when TVDB ID not found', () async {
        final service = _TestSonarrService([
          _series(
            id: 1,
            title: 'Series 1',
            tvdbId: 11111,
            year: 2023,
            runtime: 45,
            genres: const ['Drama'],
          ),
        ]);

        final found = await service.getSeriesByTvdbId(99999);
        expect(found, isNull);
      });

      test('handles empty library', () async {
        final service = _TestSonarrService(const []);

        final found = await service.getSeriesByTvdbId(11111);
        expect(found, isNull);
      });
    });
  });
}

class _TestSonarrService extends SonarrService {
  _TestSonarrService(this._series) : super(ApiClient(baseUrl: '', apiKey: ''));

  final List<SonarrSeries> _series;

  @override
  Future<List<SonarrSeries>> getSeries() async => _series;
}

SonarrSeries _series({
  required int id,
  required String title,
  required int tvdbId,
  required int year,
  required int runtime,
  required List<String> genres,
}) {
  return SonarrSeries(
    id: id,
    title: title,
    sortTitle: title.toLowerCase(),
    status: 'continuing',
    overview: 'A test series',
    path: '/tv/${title.toLowerCase()}',
    monitored: true,
    year: year,
    images: const [],
    tvdbId: tvdbId,
    runtime: runtime,
    genres: genres,
    seasons: const [],
  );
}
