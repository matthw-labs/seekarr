import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';

void main() {
  group('RadarrMovie', () {
    group('fromJson', () {
      test('parses complete JSON correctly', () {
        final json = {
          'id': 1,
          'title': 'Test Movie',
          'sortTitle': 'test movie',
          'sizeOnDisk': 5000000000,
          'status': 'released',
          'overview': 'A test movie overview.',
          'path': '/movies/Test Movie (2023)',
          'hasFile': true,
          'monitored': true,
          'year': 2023,
          'images': [
            {
              'coverType': 'poster',
              'remoteUrl': 'https://example.com/poster.jpg',
            },
          ],
          'tmdbId': 123456,
          'runtime': 120,
          'studio': 'Test Studio',
          'genres': ['Action', 'Drama'],
          'certification': 'PG-13',
          'originalLanguage': {'id': 1, 'name': 'English'},
          'inCinemas': '2023-06-15T00:00:00Z',
          'digitalRelease': '2023-09-01T00:00:00Z',
          'physicalRelease': '2023-10-01T00:00:00Z',
          'added': '2023-01-01T00:00:00Z',
          'minimumAvailability': 'released',
        };

        final movie = RadarrMovie.fromJson(json);

        expect(movie.id, 1);
        expect(movie.title, 'Test Movie');
        expect(movie.sortTitle, 'test movie');
        expect(movie.sizeOnDisk, 5000000000);
        expect(movie.status, 'released');
        expect(movie.overview, 'A test movie overview.');
        expect(movie.path, '/movies/Test Movie (2023)');
        expect(movie.hasFile, true);
        expect(movie.monitored, true);
        expect(movie.year, 2023);
        expect(movie.images.length, 1);
        expect(movie.tmdbId, 123456);
        expect(movie.runtime, 120);
        expect(movie.studio, 'Test Studio');
        expect(movie.genres, ['Action', 'Drama']);
        expect(movie.certification, 'PG-13');
        expect(movie.originalLanguage?['name'], 'English');
        expect(movie.inCinemas, '2023-06-15T00:00:00Z');
        expect(movie.digitalRelease, '2023-09-01T00:00:00Z');
        expect(movie.physicalRelease, '2023-10-01T00:00:00Z');
        expect(movie.added, '2023-01-01T00:00:00Z');
        expect(movie.minimumAvailability, 'released');
      });

      test('handles missing optional fields', () {
        final json = {
          'id': 1,
          'title': 'Test Movie',
          'sortTitle': 'test movie',
          'sizeOnDisk': 0,
          'status': 'unknown',
          'hasFile': false,
          'monitored': false,
          'year': 2023,
          'images': [],
          'tmdbId': 123,
          'runtime': 0,
          'genres': [],
        };

        final movie = RadarrMovie.fromJson(json);

        expect(movie.overview, isNull);
        expect(movie.path, isNull);
        expect(movie.studio, isNull);
        expect(movie.certification, isNull);
        expect(movie.originalLanguage, isNull);
        expect(movie.inCinemas, isNull);
        expect(movie.digitalRelease, isNull);
        expect(movie.physicalRelease, isNull);
        expect(movie.added, isNull);
        expect(movie.minimumAvailability, isNull);
      });

      test('handles null values with defaults', () {
        final json = <String, dynamic>{};

        final movie = RadarrMovie.fromJson(json);

        expect(movie.id, 0);
        expect(movie.title, 'Unknown');
        expect(movie.sortTitle, '');
        expect(movie.sizeOnDisk, 0);
        expect(movie.status, 'unknown');
        expect(movie.hasFile, false);
        expect(movie.monitored, false);
        expect(movie.year, 0);
        expect(movie.images, isEmpty);
        expect(movie.tmdbId, 0);
        expect(movie.runtime, 0);
        expect(movie.genres, isEmpty);
        expect(movie.certification, isNull);
        expect(movie.originalLanguage, isNull);
        expect(movie.inCinemas, isNull);
        expect(movie.digitalRelease, isNull);
        expect(movie.physicalRelease, isNull);
        expect(movie.added, isNull);
        expect(movie.minimumAvailability, isNull);
      });

      test('parses multi-source ratings', () {
        final movie = RadarrMovie.fromJson({
          'id': 1,
          'title': 'Test Movie',
          'sortTitle': 'test movie',
          'sizeOnDisk': 0,
          'status': 'released',
          'hasFile': false,
          'monitored': false,
          'year': 2023,
          'images': const [],
          'tmdbId': 123,
          'runtime': 120,
          'genres': const [],
          'ratings': {
            'tmdb': {'value': 8.1, 'votes': 200},
            'imdb': {'value': 7.5, 'votes': 1000},
          },
        });

        expect(movie.ratings, hasLength(2));
        expect(movie.ratings.first.name, 'TMDB');
        expect(movie.ratings.first.icon, 'TMDB');
        expect(movie.ratings.first.value, 8.1);
        expect(movie.ratings[1].name, 'IMDb');
      });
    });

    group('toMediaPreview', () {
      test('converts to MediaPreview correctly', () {
        final movie = RadarrMovie(
          id: 1,
          title: 'Test Movie',
          sortTitle: 'test movie',
          sizeOnDisk: 0,
          status: 'released',
          overview: 'Overview',
          hasFile: true,
          monitored: true,
          year: 2023,
          images: [
            {
              'coverType': 'poster',
              'remoteUrl': 'https://example.com/poster.jpg',
            },
          ],
          tmdbId: 123,
          runtime: 120,
          genres: ['Action'],
        );

        final preview = movie.toMediaPreview();

        expect(preview.id, 1);
        expect(preview.title, 'Test Movie');
        expect(preview.posterPath, 'https://example.com/poster.jpg');
        expect(preview.overview, 'Overview');
        expect(preview.releaseDate, '2023');
        expect(preview.mediaType, 'movie');
      });
    });
  });
}
