import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/features/series/domain/models/sonarr_episode.dart';

void main() {
  group('SonarrEpisode', () {
    group('fromJson', () {
      test('parses complete JSON correctly', () {
        final episode = SonarrEpisode.fromJson({
          'id': 11,
          'seasonNumber': 2,
          'episodeNumber': 4,
          'title': 'Episode Title',
          'hasFile': true,
          'monitored': true,
        });

        expect(episode.id, 11);
        expect(episode.seasonNumber, 2);
        expect(episode.episodeNumber, 4);
        expect(episode.title, 'Episode Title');
        expect(episode.hasFile, isTrue);
        expect(episode.monitored, isTrue);
      });

      test('falls back safely for missing values', () {
        final episode = SonarrEpisode.fromJson(<String, dynamic>{});

        expect(episode.id, 0);
        expect(episode.seasonNumber, 0);
        expect(episode.episodeNumber, 0);
        expect(episode.title, 'Episode ?');
        expect(episode.hasFile, isFalse);
        expect(episode.monitored, isFalse);
      });

      test('uses episode number in fallback title when title is blank', () {
        final episode = SonarrEpisode.fromJson({
          'episodeNumber': 8,
          'title': '   ',
        });

        expect(episode.title, 'Episode 8');
      });

      test('reads the broadcast fields the row needs to be decidable', () {
        final episode = SonarrEpisode.fromJson(const {
          'airDate': '2011-04-17',
          'airDateUtc': '2011-04-18T01:00:00Z',
          'runtime': 62,
        });

        expect(episode.airDate, '2011-04-17');
        expect(episode.airDateUtc, '2011-04-18T01:00:00Z');
        expect(episode.runtime, 62);
        expect(episode.airsAt, DateTime.utc(2011, 4, 18, 1));
      });
    });

    group('airsAt / isUnairedAt', () {
      test('prefers the UTC instant over the local date', () {
        const episode = SonarrEpisode(
          id: 1,
          seasonNumber: 1,
          episodeNumber: 1,
          title: 'Episode',
          hasFile: false,
          monitored: true,
          airDate: '2011-04-17',
          airDateUtc: '2011-04-18T01:00:00Z',
        );

        expect(episode.airsAt, DateTime.utc(2011, 4, 18, 1));
      });

      test('a future broadcast is unaired', () {
        const episode = SonarrEpisode(
          id: 1,
          seasonNumber: 1,
          episodeNumber: 1,
          title: 'Episode',
          hasFile: false,
          monitored: true,
          airDateUtc: '2999-01-01T00:00:00Z',
        );

        expect(episode.isUnairedAt(DateTime.utc(2026, 1, 1)), isTrue);
      });

      test('no air date at all counts as aired', () {
        // Sonarr leaves the field empty for older catalogues; reporting
        // "Not Released" for something from 1994 would be worse than silence.
        const episode = SonarrEpisode(
          id: 1,
          seasonNumber: 1,
          episodeNumber: 1,
          title: 'Episode',
          hasFile: false,
          monitored: true,
        );

        expect(episode.airsAt, isNull);
        expect(episode.isUnairedAt(DateTime.utc(2026, 1, 1)), isFalse);
      });

      test('an unparseable air date does not throw', () {
        const episode = SonarrEpisode(
          id: 1,
          seasonNumber: 1,
          episodeNumber: 1,
          title: 'Episode',
          hasFile: false,
          monitored: true,
          airDate: 'soon',
          airDateUtc: '   ',
        );

        expect(episode.airsAt, isNull);
        expect(episode.isUnairedAt(DateTime.utc(2026, 1, 1)), isFalse);
      });
    });
  });
}
