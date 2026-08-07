import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/features/series/domain/models/sonarr_episode.dart';
import 'package:cupola/features/series/domain/models/sonarr_season.dart';
import 'package:cupola/features/series/domain/sonarr_status.dart';

import '../../../test_helpers/model_builders.dart';

void main() {
  group('sonarrSeriesAvailability', () {
    test('all aired episodes on disk is available', () {
      expect(
        sonarrSeriesAvailability(
          buildSeries(
            statistics: const {'episodeCount': 10, 'episodeFileCount': 10},
          ),
        ),
        MediaAvailability.available,
      );
    });

    test('a continuing series holding every aired episode is available', () {
      // `episodeCount` counts aired, monitored episodes — a running show must
      // not be stuck at `partial` forever just because more will air later.
      expect(
        sonarrSeriesAvailability(
          buildSeries(
            status: 'continuing',
            statistics: const {
              'episodeCount': 8,
              'totalEpisodeCount': 20,
              'episodeFileCount': 8,
            },
          ),
        ),
        MediaAvailability.available,
      );
    });

    test('some aired episodes on disk is partial', () {
      expect(
        sonarrSeriesAvailability(
          buildSeries(
            statistics: const {'episodeCount': 10, 'episodeFileCount': 4},
          ),
        ),
        MediaAvailability.partial,
      );
    });

    test('no episodes on disk is missing', () {
      expect(
        sonarrSeriesAvailability(
          buildSeries(
            statistics: const {'episodeCount': 10, 'episodeFileCount': 0},
          ),
        ),
        MediaAvailability.missing,
      );
    });

    test('nothing aired yet is unavailable, not missing', () {
      expect(
        sonarrSeriesAvailability(
          buildSeries(
            status: 'upcoming',
            statistics: const {
              'episodeCount': 0,
              'totalEpisodeCount': 10,
              'episodeFileCount': 0,
            },
          ),
        ),
        MediaAvailability.unavailable,
      );
    });

    test('absent statistics is unknown rather than missing', () {
      expect(
        sonarrSeriesAvailability(buildSeries()),
        MediaAvailability.unknown,
      );
    });

    test('deleted outranks the counts', () {
      expect(
        sonarrSeriesAvailability(
          buildSeries(
            status: 'deleted',
            statistics: const {'episodeCount': 10, 'episodeFileCount': 10},
          ),
        ),
        MediaAvailability.deleted,
      );
    });
  });

  group('sonarrSeriesStatus', () {
    test('a series in the queue never reads Missing', () {
      final status = sonarrSeriesStatus(
        buildSeries(
          statistics: const {'episodeCount': 10, 'episodeFileCount': 0},
        ),
        queueEntry: const ArrQueueEntry(
          pipeline: MediaPipeline.downloading,
          progress: 0.3,
        ),
      );

      expect(status.label, 'Downloading');
      expect(status.availability, MediaAvailability.missing);
    });

    test('a partially available series in the queue reports the download', () {
      final status = sonarrSeriesStatus(
        buildSeries(
          statistics: const {'episodeCount': 10, 'episodeFileCount': 4},
        ),
        queueEntry: const ArrQueueEntry(pipeline: MediaPipeline.importPending),
      );

      expect(status.label, 'Import Pending');
      expect(status.availability, MediaAvailability.partial);
    });
  });

  group('SonarrSeries statistics getters', () {
    test('reads the counts Sonarr exposes', () {
      final series = buildSeries(
        statistics: const {
          'episodeCount': 8,
          'totalEpisodeCount': 20,
          'episodeFileCount': 5,
        },
      );

      expect(series.episodeCount, 8);
      expect(series.totalEpisodeCount, 20);
      expect(series.episodeFileCount, 5);
      expect(series.hasFiles, isTrue);
    });

    test('absent statistics yields nulls, not zeros', () {
      final series = buildSeries();

      expect(series.episodeCount, isNull);
      expect(series.episodeFileCount, isNull);
      expect(series.hasFiles, isFalse);
    });
  });

  group('sonarrSeasonStatus', () {
    test('every aired episode on disk is available', () {
      final status = sonarrSeasonStatus(
        _season(episodeCount: 8, fileCount: 8, total: 10),
      );

      expect(status.availability, MediaAvailability.available);
      expect(status.label, 'Available');
      expect(status.tone, StatusTone.success);
    });

    test('some on disk is partial', () {
      expect(
        sonarrSeasonAvailability(_season(episodeCount: 8, fileCount: 3)),
        MediaAvailability.partial,
      );
    });

    test('a season that has not started airing is not missing', () {
      // An announced season is not a failure to download anything.
      expect(
        sonarrSeasonAvailability(
          _season(episodeCount: 0, fileCount: 0, total: 10),
        ),
        MediaAvailability.unavailable,
      );
    });

    test('an unmonitored empty season reads Unmonitored', () {
      final status = sonarrSeasonStatus(
        _season(episodeCount: 8, fileCount: 0, monitored: false),
      );

      expect(status.label, 'Unmonitored');
      expect(status.unmonitored, isTrue);
    });

    test('a queue entry beats availability', () {
      final status = sonarrSeasonStatus(
        _season(episodeCount: 8, fileCount: 0),
        queueEntry: ArrQueueEntry.fromQueueItem(const {
          'status': 'downloading',
          'size': 100,
          'sizeleft': 40,
        }),
      );

      expect(status.pipeline, MediaPipeline.downloading);
      expect(status.label, isNot('Missing'));
    });
  });

  group('sonarrSeasonSummary', () {
    test('states the manifest gap', () {
      expect(
        sonarrSeasonSummary(_season(episodeCount: 10, fileCount: 8, total: 10)),
        '8 of 10 episodes',
      );
    });

    test('names the total when episodes are still to air', () {
      // `8 of 8 episodes` on a season that will end up with twelve is true and
      // misleading at once.
      expect(
        sonarrSeasonSummary(_season(episodeCount: 8, fileCount: 8, total: 12)),
        '8 of 8 aired · 12 total',
      );
    });

    test('an announced season reports what is coming', () {
      expect(
        sonarrSeasonSummary(_season(episodeCount: 0, fileCount: 0, total: 6)),
        '6 episodes announced',
      );
    });

    test('a season Sonarr knows nothing about has no summary', () {
      expect(
        sonarrSeasonSummary(_season(episodeCount: 0, fileCount: 0, total: 0)),
        isNull,
      );
    });
  });

  group('sonarrEpisodeStatus', () {
    test('a file on disk is available', () {
      final status = sonarrEpisodeStatus(buildEpisode(hasFile: true));

      expect(status.availability, MediaAvailability.available);
      expect(status.tone, StatusTone.success);
    });

    test('an aired episode with no file is missing', () {
      final status = sonarrEpisodeStatus(
        _episode(hasFile: false, airDateUtc: '2011-04-17T00:00:00Z'),
        now: DateTime.utc(2026, 1, 1),
      );

      expect(status.availability, MediaAvailability.missing);
      expect(status.label, 'Missing');
    });

    test('an unaired episode is Not Released, never Missing', () {
      final status = sonarrEpisodeStatus(
        _episode(hasFile: false, airDateUtc: '2999-01-01T00:00:00Z'),
        now: DateTime.utc(2026, 1, 1),
      );

      expect(status.availability, MediaAvailability.unavailable);
      expect(status.label, 'Not Released');
      expect(status.tone, StatusTone.neutral);
    });

    test('a queue entry wins over the availability axis', () {
      final status = sonarrEpisodeStatus(
        _episode(hasFile: false),
        now: DateTime.utc(2026, 1, 1),
        queueEntry: ArrQueueEntry.fromQueueItem(const {
          'status': 'downloading',
          'size': 100,
          'sizeleft': 25,
        }),
      );

      expect(status.pipeline, MediaPipeline.downloading);
      expect(status.progressPercent, 75);
    });
  });
}

SonarrSeason _season({
  int seasonNumber = 1,
  int episodeCount = 10,
  int fileCount = 10,
  int? total,
  bool monitored = true,
}) {
  return SonarrSeason(
    seasonNumber: seasonNumber,
    monitored: monitored,
    episodeCount: episodeCount,
    totalEpisodeCount: total ?? episodeCount,
    episodeFileCount: fileCount,
  );
}

SonarrEpisode _episode({bool hasFile = false, String? airDateUtc}) {
  return SonarrEpisode(
    id: 1,
    seasonNumber: 1,
    episodeNumber: 1,
    title: 'Episode',
    hasFile: hasFile,
    monitored: true,
    airDateUtc: airDateUtc,
  );
}
