import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/movies/domain/models/radarr_movie.dart';
import 'package:seekarr/features/movies/presentation/movie_detail_view_model.dart';

void main() {
  group('MovieDetailViewModel', () {
    RadarrMovie makeMovie({
      String? certification,
      Map<String, dynamic>? originalLanguage,
      String? inCinemas,
      String? digitalRelease,
      String? physicalRelease,
      String? studio,
      List<String> genres = const [],
      int year = 2023,
      int runtime = 120,
    }) {
      return RadarrMovie(
        id: 1,
        title: 'Test Movie',
        sortTitle: 'test movie',
        sizeOnDisk: 0,
        status: 'released',
        overview: 'A great movie.',
        hasFile: true,
        monitored: true,
        year: year,
        images: const [],
        tmdbId: 100,
        runtime: runtime,
        studio: studio,
        genres: genres,
        certification: certification,
        originalLanguage: originalLanguage,
        inCinemas: inCinemas,
        digitalRelease: digitalRelease,
        physicalRelease: physicalRelease,
      );
    }

    group('fromMovie', () {
      test('maps basic fields', () {
        final vm = MovieDetailViewModel.fromMovie(
          makeMovie(studio: 'Paramount'),
          baseUrl: 'http://localhost:7878',
          apiKey: 'test-key',
        );

        expect(vm.title, 'Test Movie');
        expect(vm.year, '2023');
        // One runtime voice across every detail page: hours and minutes, never
        // Radarr's raw `120 min`.
        expect(vm.runtimeStr, '2h');
        expect(vm.studio, 'Paramount');
      });

      test('maps enrichment fields', () {
        final vm = MovieDetailViewModel.fromMovie(
          makeMovie(
            certification: 'PG-13',
            originalLanguage: {'id': 1, 'name': 'English'},
            inCinemas: '2023-06-15T00:00:00Z',
            digitalRelease: '2023-09-01T00:00:00Z',
            physicalRelease: '2023-10-01T00:00:00Z',
          ),
          baseUrl: 'http://localhost:7878',
          apiKey: 'test-key',
        );

        expect(vm.certification, 'PG-13');
        expect(vm.originalLanguage, 'English');
        expect(vm.inCinemas, '2023-06-15T00:00:00Z');
        expect(vm.digitalRelease, '2023-09-01T00:00:00Z');
        expect(vm.physicalRelease, '2023-10-01T00:00:00Z');
      });
    });

    group('metadataItems', () {
      test('includes year and runtime', () {
        final vm = MovieDetailViewModel.fromMovie(
          makeMovie(),
          baseUrl: 'http://localhost:7878',
          apiKey: 'test-key',
        );

        expect(vm.metadataItems, ['2023', '2h']);
      });

      test('excludes zero year', () {
        final vm = MovieDetailViewModel.fromMovie(
          makeMovie(year: 0),
          baseUrl: 'http://localhost:7878',
          apiKey: 'test-key',
        );

        expect(vm.metadataItems, ['2h']);
      });
    });

    group('buildInfoGroups', () {
      test('returns empty when no data', () {
        final vm = MovieDetailViewModel.fromMovie(
          makeMovie(),
          baseUrl: 'http://localhost:7878',
          apiKey: 'test-key',
        );

        expect(vm.buildInfoGroups(), isEmpty);
      });

      test('includes certification when present', () {
        final vm = MovieDetailViewModel.fromMovie(
          makeMovie(certification: 'R'),
          baseUrl: 'http://localhost:7878',
          apiKey: 'test-key',
        );

        expect(
          vm.buildInfoGroups().any((group) => group.title == 'Certification'),
          isTrue,
        );
      });

      test('includes release dates as MediaFactsList', () {
        final vm = MovieDetailViewModel.fromMovie(
          makeMovie(
            inCinemas: '2023-06-15T00:00:00Z',
            digitalRelease: '2023-09-01T00:00:00Z',
          ),
          baseUrl: 'http://localhost:7878',
          apiKey: 'test-key',
        );

        final releaseGroup = vm.buildInfoGroups().firstWhere(
          (group) => group.title == 'Release Dates',
        );

        expect(releaseGroup.child, isA<MediaFactsList>());
      });

      test('includes genre and studio groups', () {
        final vm = MovieDetailViewModel.fromMovie(
          makeMovie(genres: const ['Action', 'Drama'], studio: 'Warner'),
          baseUrl: 'http://localhost:7878',
          apiKey: 'test-key',
        );

        final titles = vm
            .buildInfoGroups()
            .map((group) => group.title)
            .toList();

        expect(titles, contains('Genre'));
        expect(titles, contains('Studio'));
      });

      test('preserves group order', () {
        final vm = MovieDetailViewModel.fromMovie(
          makeMovie(
            certification: 'PG-13',
            originalLanguage: {'id': 1, 'name': 'English'},
            inCinemas: '2023-06-15T00:00:00Z',
            genres: const ['Action'],
            studio: 'WB',
          ),
          baseUrl: 'http://localhost:7878',
          apiKey: 'test-key',
        );

        expect(vm.buildInfoGroups().map((group) => group.title).toList(), [
          'Certification',
          'Original Language',
          'Release Dates',
          'Genre',
          'Studio',
        ]);
      });
    });
  });
}
