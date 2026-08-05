import 'package:flutter_test/flutter_test.dart';
import 'package:seekarr/features/series/domain/models/sonarr_series.dart';

void main() {
  group('SonarrSeries', () {
    group('fromJson', () {
      test('parses complete JSON correctly', () {
        final json = {
          'id': 1,
          'title': 'Test Series',
          'sortTitle': 'test series',
          'status': 'continuing',
          'overview': 'A test series overview.',
          'path': '/tv/Test Series',
          'monitored': true,
          'year': 2023,
          'images': [
            {
              'coverType': 'poster',
              'remoteUrl': 'https://example.com/poster.jpg',
            },
          ],
          'tvdbId': 123456,
          'runtime': 45,
          'network': 'Netflix',
          'genres': ['Drama', 'Sci-Fi'],
          'seasons': [
            {'seasonNumber': 1, 'monitored': true},
          ],
          'statistics': {'episodeFileCount': 10, 'totalEpisodeCount': 12},
          'seriesType': 'standard',
          'certification': 'TV-MA',
          'firstAired': '2023-01-15T00:00:00Z',
          'lastAired': '2023-12-20T00:00:00Z',
          'added': '2023-01-01T00:00:00Z',
          'originalLanguage': {'id': 1, 'name': 'English'},
        };

        final series = SonarrSeries.fromJson(json);

        expect(series.id, 1);
        expect(series.title, 'Test Series');
        expect(series.sortTitle, 'test series');
        expect(series.status, 'continuing');
        expect(series.overview, 'A test series overview.');
        expect(series.path, '/tv/Test Series');
        expect(series.monitored, true);
        expect(series.year, 2023);
        expect(series.images.length, 1);
        expect(series.tvdbId, 123456);
        expect(series.runtime, 45);
        expect(series.network, 'Netflix');
        expect(series.genres, ['Drama', 'Sci-Fi']);
        expect(series.seasons.length, 1);
        expect(series.statistics?['episodeFileCount'], 10);
        expect(series.seriesType, 'standard');
        expect(series.certification, 'TV-MA');
        expect(series.firstAired, '2023-01-15T00:00:00Z');
        expect(series.lastAired, '2023-12-20T00:00:00Z');
        expect(series.added, '2023-01-01T00:00:00Z');
        expect(series.originalLanguage?['name'], 'English');
      });

      test('handles missing optional fields', () {
        final json = {
          'id': 1,
          'title': 'Test Series',
          'sortTitle': 'test series',
          'status': 'unknown',
          'monitored': false,
          'year': 2023,
          'images': [],
          'tvdbId': 123,
          'runtime': 0,
          'genres': [],
          'seasons': [],
        };

        final series = SonarrSeries.fromJson(json);

        expect(series.overview, isNull);
        expect(series.path, isNull);
        expect(series.network, isNull);
        expect(series.statistics, isNull);
        expect(series.seriesType, isNull);
        expect(series.certification, isNull);
        expect(series.firstAired, isNull);
        expect(series.lastAired, isNull);
        expect(series.added, isNull);
        expect(series.originalLanguage, isNull);
      });

      test('handles null values with defaults', () {
        final json = <String, dynamic>{};

        final series = SonarrSeries.fromJson(json);

        expect(series.id, 0);
        expect(series.title, 'Unknown');
        expect(series.sortTitle, '');
        expect(series.status, 'unknown');
        expect(series.monitored, false);
        expect(series.year, 0);
        expect(series.images, isEmpty);
        expect(series.tvdbId, 0);
        expect(series.runtime, 0);
        expect(series.genres, isEmpty);
        expect(series.seasons, isEmpty);
        expect(series.seriesType, isNull);
        expect(series.certification, isNull);
        expect(series.firstAired, isNull);
        expect(series.lastAired, isNull);
        expect(series.added, isNull);
        expect(series.originalLanguage, isNull);
      });

      test('parses multi-source ratings', () {
        final series = SonarrSeries.fromJson({
          'id': 1,
          'title': 'Test Series',
          'sortTitle': 'test series',
          'status': 'continuing',
          'monitored': true,
          'year': 2023,
          'images': const [],
          'tvdbId': 123456,
          'runtime': 45,
          'genres': const [],
          'seasons': const [],
          'ratings': {
            'tvdb': {'value': 8.0, 'votes': 5000},
            'imdb': {'value': 7.8, 'votes': 12000},
          },
        });

        expect(series.ratings, hasLength(2));
        expect(series.ratings.first.name, 'TVDB');
        expect(series.ratings.first.icon, 'TVDB');
        expect(series.ratings[1].name, 'IMDb');
      });

      test('parses single-source ratings', () {
        final series = SonarrSeries.fromJson({
          'id': 1,
          'title': 'Test Series',
          'sortTitle': 'test series',
          'status': 'continuing',
          'monitored': true,
          'year': 2023,
          'images': const [],
          'tvdbId': 123456,
          'runtime': 45,
          'genres': const [],
          'seasons': const [],
          'ratings': {'value': 8.4, 'votes': 145000},
        });

        expect(series.ratings, hasLength(1));
        // The badge, not the vote count: `name` is the pill's spoken label.
        expect(series.ratings.single.name, 'TVDB');
        expect(series.ratings.single.votes, 145000);
        expect(series.ratings.single.icon, 'TVDB');
        expect(series.ratings.single.value, 8.4);
      });
    });

    group('toMediaPreview', () {
      test('converts to MediaPreview correctly', () {
        final series = SonarrSeries(
          id: 1,
          title: 'Test Series',
          sortTitle: 'test series',
          status: 'continuing',
          overview: 'Overview',
          monitored: true,
          year: 2023,
          images: [
            {
              'coverType': 'poster',
              'remoteUrl': 'https://example.com/poster.jpg',
            },
          ],
          tvdbId: 123,
          runtime: 45,
          genres: ['Drama'],
          seasons: [],
        );

        final preview = series.toMediaPreview();

        expect(preview.id, 1);
        expect(preview.title, 'Test Series');
        expect(preview.posterPath, 'https://example.com/poster.jpg');
        expect(preview.overview, 'Overview');
        expect(preview.releaseDate, '2023');
        expect(preview.mediaType, 'tv');
      });
    });
  });
}
