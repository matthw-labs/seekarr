import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/features/bazarr/data/bazarr_service.dart';
import 'package:seekarr/features/bazarr/domain/models/bazarr_models.dart';
import 'package:seekarr/features/bazarr/presentation/bazarr_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_bazarr_service.dart';

const _settings = SettingsModel(
  bazarrUrl: 'http://bazarr.local',
  bazarrApiKey: 'key',
);

ProviderContainer _container({BazarrService? service}) {
  final container = ProviderContainer(
    overrides: [
      currentSettingsProvider.overrideWith((ref) => _settings),
      bazarrServiceProvider.overrideWith(
        (ref) => service ?? FakeBazarrService(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('bazarrSeriesByIdProvider returns the matching series', () async {
    final fake = FakeBazarrService()
      ..seriesByIdOverride = const BazarrSeries(
        sonarrSeriesId: 7,
        title: 'Foundation',
        year: 2021,
        monitored: true,
        episodeMissingCount: 4,
        profileId: 1,
      );

    final container = _container(service: fake);
    final series = await container.read(bazarrSeriesByIdProvider(7).future);

    expect(series, isNotNull);
    expect(series!.title, 'Foundation');
    expect(series.sonarrSeriesId, 7);
    expect(series.episodeMissingCount, 4);
  });

  test('bazarrSeriesByIdProvider returns null for unknown id', () async {
    final fake = FakeBazarrService()
      ..seriesByIdOverride = const BazarrSeries(
        sonarrSeriesId: 1,
        title: 'Other',
        monitored: true,
      );
    final container = _container(service: fake);

    final series = await container.read(bazarrSeriesByIdProvider(999).future);
    expect(series, isNull);
  });

  test('bazarrMovieByIdProvider returns the matching movie', () async {
    final fake = FakeBazarrService()
      ..movieByIdOverride = const BazarrMovie(
        radarrId: 42,
        title: 'Dune',
        year: 2021,
        monitored: true,
      );
    final container = _container(service: fake);

    final movie = await container.read(bazarrMovieByIdProvider(42).future);

    expect(movie, isNotNull);
    expect(movie!.title, 'Dune');
    expect(movie.radarrId, 42);
  });

  test('bazarrMovieByIdProvider returns null for unknown id', () async {
    final container = _container();
    final movie = await container.read(bazarrMovieByIdProvider(123).future);
    expect(movie, isNull);
  });

  test(
    'bazarrWantedEpisodesForSeriesProvider returns the page contents',
    () async {
      final fake = FakeBazarrService()
        ..wantedEpisodesForSeriesResult = const [
          BazarrWantedItem(
            seriesTitle: 'Foundation',
            episodeNumber: '1x01',
            sonarrSeriesId: 7,
            sonarrEpisodeId: 1,
            missingLanguages: [BazarrSubtitleLanguage(code2: 'en')],
          ),
        ];
      final container = _container(service: fake);

      final items = await container.read(
        bazarrWantedEpisodesForSeriesProvider(7).future,
      );

      expect(items, hasLength(1));
      expect(items.first.seriesTitle, 'Foundation');
      expect(items.first.missingLanguages.first.code2, 'en');
    },
  );

  test(
    'bazarrWantedMovieByIdProvider returns the matching wanted item',
    () async {
      final fake = FakeBazarrService()
        ..wantedMovieByIdOverride = const BazarrWantedItem(
          title: 'Dune',
          radarrId: 42,
          missingLanguages: [BazarrSubtitleLanguage(code2: 'it')],
        );
      final container = _container(service: fake);

      final item = await container.read(
        bazarrWantedMovieByIdProvider(42).future,
      );

      expect(item, isNotNull);
      expect(item!.title, 'Dune');
      expect(item.missingLanguages.first.code2, 'it');
    },
  );

  // The detail-screen widget tests moved to
  // bazarr_movie_detail_screen_test.dart / bazarr_series_detail_screen_test.dart
  // when the screens migrated onto MediaDetailView.
}
