import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/series/domain/models/sonarr_season.dart';

void main() {
  group('SonarrSeason', () {
    test('parses the nested statistics Sonarr sends', () {
      final season = SonarrSeason.fromJson(const {
        'seasonNumber': 3,
        'monitored': true,
        'statistics': {
          'episodeCount': 8,
          'totalEpisodeCount': 10,
          'episodeFileCount': 6,
        },
      });

      expect(season.seasonNumber, 3);
      expect(season.monitored, isTrue);
      expect(season.episodeCount, 8);
      expect(season.totalEpisodeCount, 10);
      expect(season.episodeFileCount, 6);
      expect(season.hasUnairedEpisodes, isTrue);
      expect(season.completionPercent, closeTo(0.75, 0.001));
      expect(season.label, 'Season 3');
      expect(season.shortLabel, 'S3');
    });

    test('falls back safely when statistics are missing', () {
      final season = SonarrSeason.fromJson(const <String, dynamic>{});

      expect(season.seasonNumber, 0);
      expect(season.monitored, isFalse);
      expect(season.episodeCount, 0);
      expect(season.episodeFileCount, 0);
      // Nothing expected yet, so there is no completion to draw.
      expect(season.completionPercent, isNull);
    });

    test('season zero is Specials, not Season 0', () {
      final season = SonarrSeason.fromJson(const {'seasonNumber': 0});

      expect(season.isSpecials, isTrue);
      expect(season.label, 'Specials');
      expect(season.shortLabel, 'Sp');
    });

    test('listFrom drops non-object entries and sorts specials last', () {
      final seasons = SonarrSeason.listFrom(const [
        {'seasonNumber': 2},
        'nonsense',
        {'seasonNumber': 0},
        {'seasonNumber': 1},
        42,
      ]);

      expect(seasons.map((season) => season.seasonNumber).toList(), [1, 2, 0]);
    });

    test('compare puts specials after every numbered season', () {
      final specials = SonarrSeason.fromJson(const {'seasonNumber': 0});
      final last = SonarrSeason.fromJson(const {'seasonNumber': 40});

      expect(SonarrSeason.compare(specials, last), greaterThan(0));
      expect(SonarrSeason.compare(last, specials), lessThan(0));
    });

    test('completion never exceeds one when Sonarr over-reports files', () {
      final season = SonarrSeason.fromJson(const {
        'seasonNumber': 1,
        'statistics': {'episodeCount': 8, 'episodeFileCount': 9},
      });

      expect(season.completionPercent, 1.0);
    });
  });
}
