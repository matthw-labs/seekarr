import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/series/presentation/series_detail_view_model.dart';

void main() {
  group('SeriesDetailViewModel', () {
    SonarrSeries makeSeries({
      String? seriesType,
      String? certification,
      String? firstAired,
      String? lastAired,
      String? originalLanguage,
      String? network,
      List<String> genres = const [],
      int year = 2023,
      int runtime = 45,
      Map<String, dynamic>? statistics,
    }) {
      return SonarrSeries(
        id: 1,
        title: 'Test Series',
        sortTitle: 'test series',
        status: 'continuing',
        overview: 'A great series.',
        monitored: true,
        year: year,
        images: const [],
        tvdbId: 200,
        runtime: runtime,
        network: network,
        genres: genres,
        seasons: const [],
        statistics: statistics,
        seriesType: seriesType,
        certification: certification,
        firstAired: firstAired,
        lastAired: lastAired,
        originalLanguage: originalLanguage == null
            ? null
            : {'id': 1, 'name': originalLanguage},
      );
    }

    group('fromSeries', () {
      test('maps basic fields', () {
        final vm = SeriesDetailViewModel.fromSeries(
          makeSeries(network: 'HBO'),
          baseUrl: 'http://localhost:8989',
          apiKey: 'test-key',
        );

        expect(vm.title, 'Test Series');
        expect(vm.network, 'HBO');
      });

      test('maps enrichment fields', () {
        final vm = SeriesDetailViewModel.fromSeries(
          makeSeries(
            seriesType: 'standard',
            certification: 'TV-MA',
            firstAired: '2023-01-15T00:00:00Z',
            lastAired: '2023-12-20T00:00:00Z',
            originalLanguage: 'English',
          ),
          baseUrl: 'http://localhost:8989',
          apiKey: 'test-key',
        );

        expect(vm.seriesType, 'standard');
        expect(vm.certification, 'TV-MA');
        expect(vm.firstAired, '2023-01-15T00:00:00Z');
        expect(vm.lastAired, '2023-12-20T00:00:00Z');
        expect(vm.originalLanguage, 'English');
      });
    });

    group('episodeSummary', () {
      test('returns season and episode counts', () {
        final vm = SeriesDetailViewModel.fromSeries(
          makeSeries(
            statistics: {
              'seasonCount': 3,
              'episodeCount': 30,
              'episodeFileCount': 28,
            },
          ),
          baseUrl: 'http://localhost:8989',
          apiKey: 'test-key',
        );

        expect(vm.episodeSummary, contains('3 Seasons'));
        expect(vm.episodeSummary, contains('30 Episodes'));
      });

      test('returns null when no stats', () {
        final vm = SeriesDetailViewModel.fromSeries(
          makeSeries(),
          baseUrl: 'http://localhost:8989',
          apiKey: 'test-key',
        );

        expect(vm.episodeSummary, isNull);
      });
    });

    group('buildInfoGroups', () {
      test('returns empty when no data', () {
        final vm = SeriesDetailViewModel.fromSeries(
          makeSeries(),
          baseUrl: 'http://localhost:8989',
          apiKey: 'test-key',
        );

        expect(vm.buildInfoGroups(), isEmpty);
      });

      test('includes series type capitalized', () {
        final vm = SeriesDetailViewModel.fromSeries(
          makeSeries(seriesType: 'anime'),
          baseUrl: 'http://localhost:8989',
          apiKey: 'test-key',
        );

        final typeGroup = vm.buildInfoGroups().firstWhere(
          (group) => group.title == 'Series Type',
        );

        expect(typeGroup.child, isA<Text>());
        expect((typeGroup.child as Text).data, 'Anime');
      });

      test('includes air dates as MediaFactsList', () {
        final vm = SeriesDetailViewModel.fromSeries(
          makeSeries(
            firstAired: '2023-01-15T00:00:00Z',
            lastAired: '2023-12-20T00:00:00Z',
          ),
          baseUrl: 'http://localhost:8989',
          apiKey: 'test-key',
        );

        final airDatesGroup = vm.buildInfoGroups().firstWhere(
          (group) => group.title == 'Air Dates',
        );

        expect(airDatesGroup.child, isA<MediaFactsList>());
      });

      test('preserves group order', () {
        final vm = SeriesDetailViewModel.fromSeries(
          makeSeries(
            seriesType: 'standard',
            certification: 'TV-14',
            originalLanguage: 'English',
            firstAired: '2023-01-15T00:00:00Z',
            genres: const ['Drama'],
            network: 'Netflix',
          ),
          baseUrl: 'http://localhost:8989',
          apiKey: 'test-key',
        );

        expect(vm.buildInfoGroups().map((group) => group.title).toList(), [
          'Series Type',
          'Certification',
          'Original Language',
          'Air Dates',
          'Genre',
          'Network',
        ]);
      });
    });
  });
}
