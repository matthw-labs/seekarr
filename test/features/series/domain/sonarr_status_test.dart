import 'package:flutter_test/flutter_test.dart';
import 'package:seekarr/core/status/arr_queue_snapshot.dart';
import 'package:seekarr/features/series/domain/sonarr_status.dart';

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
}
