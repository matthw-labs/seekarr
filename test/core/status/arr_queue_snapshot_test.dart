import 'package:flutter_test/flutter_test.dart';
import 'package:seekarr/core/status/arr_queue_snapshot.dart';

void main() {
  group('ArrQueueEntry.fromQueueItem', () {
    test('trackedDownloadState wins for the post-download phases', () {
      // `status: completed` covers every post-download phase, so only
      // trackedDownloadState can tell them apart.
      final entry = ArrQueueEntry.fromQueueItem({
        'status': 'completed',
        'trackedDownloadState': 'importPending',
      });

      expect(entry?.pipeline, MediaPipeline.importPending);
    });

    test('the client status wins while the item is still with the client', () {
      // A queued item also carries `trackedDownloadState: downloading` — that
      // field means "still with the download client", not "bytes are moving".
      // Reading it as Downloading was wrong and the recorded payloads caught it.
      final queued = ArrQueueEntry.fromQueueItem({
        'status': 'queued',
        'trackedDownloadState': 'downloading',
      });
      final paused = ArrQueueEntry.fromQueueItem({
        'status': 'paused',
        'trackedDownloadState': 'downloading',
      });
      final unavailable = ArrQueueEntry.fromQueueItem({
        'status': 'downloadClientUnavailable',
        'trackedDownloadState': 'downloading',
      });

      expect(queued?.pipeline, MediaPipeline.queued);
      expect(paused?.pipeline, MediaPipeline.paused);
      expect(unavailable?.pipeline, MediaPipeline.paused);
    });

    test('trackedDownloadState alone still implies an active download', () {
      expect(
        ArrQueueEntry.fromQueueItem({
          'trackedDownloadState': 'downloading',
        })?.pipeline,
        MediaPipeline.downloading,
      );
    });

    final trackedStates = <String, MediaPipeline>{
      'importPending': MediaPipeline.importPending,
      'importBlocked': MediaPipeline.importPending,
      'importing': MediaPipeline.importing,
      'failedPending': MediaPipeline.failed,
      'failed': MediaPipeline.failed,
    };

    trackedStates.forEach((state, pipeline) {
      test('trackedDownloadState "$state" maps to ${pipeline.name}', () {
        expect(
          ArrQueueEntry.fromQueueItem({
            'trackedDownloadState': state,
          })?.pipeline,
          pipeline,
        );
      });
    });

    for (final finished in ['imported', 'ignored']) {
      test('"$finished" yields no entry so it cannot mask availability', () {
        expect(
          ArrQueueEntry.fromQueueItem({'trackedDownloadState': finished}),
          isNull,
        );
      });
    }

    final statuses = <String, MediaPipeline>{
      'queued': MediaPipeline.queued,
      'delay': MediaPipeline.queued,
      'downloading': MediaPipeline.downloading,
      'paused': MediaPipeline.paused,
      'failed': MediaPipeline.failed,
      // The client finished; the *arr has not imported yet.
      'completed': MediaPipeline.importPending,
    };

    statuses.forEach((status, pipeline) {
      test('status "$status" maps to ${pipeline.name}', () {
        expect(
          ArrQueueEntry.fromQueueItem({'status': status})?.pipeline,
          pipeline,
        );
      });
    });

    test('an unrecognised status still counts as in-flight', () {
      // The guarantee that keeps a queued item from rendering as Missing when a
      // service adds a status value we have never seen.
      final entry = ArrQueueEntry.fromQueueItem({'status': 'someNewState'});

      expect(entry, isNotNull);
      expect(entry!.pipeline, MediaPipeline.queued);
      expect(entry.label, 'Some New State');
    });

    test('an empty record still counts as in-flight', () {
      expect(
        ArrQueueEntry.fromQueueItem(<String, dynamic>{})?.pipeline,
        MediaPipeline.queued,
      );
    });

    test('downloadClientUnavailable is a paused state with a warning', () {
      final entry = ArrQueueEntry.fromQueueItem({
        'status': 'downloadClientUnavailable',
      });

      expect(entry?.pipeline, MediaPipeline.paused);
      expect(entry?.label, 'Client Unavailable');
      expect(entry?.hasWarning, isTrue);
    });

    test('progress is derived from size and sizeleft', () {
      final entry = ArrQueueEntry.fromQueueItem({
        'status': 'downloading',
        'size': 100,
        'sizeleft': 25,
      });

      expect(entry?.progress, 0.75);
    });

    test('progress also accepts Seerr\'s sizeLeft spelling', () {
      final entry = ArrQueueEntry.fromQueueItem({
        'status': 'downloading',
        'size': 200,
        'sizeLeft': 50,
      });

      expect(entry?.progress, 0.75);
    });

    test(
      'trackedDownloadStatus warning and status messages raise the flag',
      () {
        expect(
          ArrQueueEntry.fromQueueItem({
            'status': 'downloading',
            'trackedDownloadStatus': 'warning',
          })?.hasWarning,
          isTrue,
        );
        expect(
          ArrQueueEntry.fromQueueItem({
            'status': 'downloading',
            'statusMessages': ['Unable to Import Automatically'],
          })?.hasWarning,
          isTrue,
        );
      },
    );

    test('errorMessage is preferred as the detail line', () {
      final entry = ArrQueueEntry.fromQueueItem({
        'status': 'failed',
        'errorMessage': 'Download client reported a failure',
        'statusMessages': ['Something else'],
      });

      expect(entry?.detail, 'Download client reported a failure');
    });
  });

  group('ArrQueueSnapshot.fromQueueItems', () {
    test('indexes records by media id', () {
      final snapshot = ArrQueueSnapshot.fromQueueItems([
        {'movieId': 10, 'status': 'downloading'},
        {'movieId': 11, 'status': 'queued'},
      ], idsFor: (item) => [item['movieId'] as int]);

      expect(snapshot.entryFor(10)?.pipeline, MediaPipeline.downloading);
      expect(snapshot.entryFor(11)?.pipeline, MediaPipeline.queued);
      expect(snapshot.entryFor(12), isNull);
      expect(snapshot.entryFor(null), isNull);
    });

    test('drops non-positive and unresolvable ids', () {
      final snapshot = ArrQueueSnapshot.fromQueueItems(
        [
          {'movieId': 0, 'status': 'downloading'},
          {'movieId': -1, 'status': 'downloading'},
          'not a map',
        ],
        idsFor: (item) => [if (item['movieId'] is int) item['movieId'] as int],
      );

      expect(snapshot.isEmpty, isTrue);
    });

    test('the most salient state becomes the headline', () {
      // A series with one episode queued and one failing must surface the
      // failure, not the queue.
      final snapshot = ArrQueueSnapshot.fromQueueItems([
        {'seriesId': 1, 'status': 'queued'},
        {'seriesId': 1, 'trackedDownloadState': 'failed'},
      ], idsFor: (item) => [item['seriesId'] as int]);

      expect(snapshot.entryFor(1)?.pipeline, MediaPipeline.failed);
    });

    test('progress is averaged across the records sharing the headline', () {
      final snapshot = ArrQueueSnapshot.fromQueueItems([
        {'seriesId': 1, 'status': 'downloading', 'size': 100, 'sizeleft': 80},
        {'seriesId': 1, 'status': 'downloading', 'size': 100, 'sizeleft': 20},
        // A queued sibling must not drag the average down.
        {'seriesId': 1, 'status': 'queued', 'size': 100, 'sizeleft': 100},
      ], idsFor: (item) => [item['seriesId'] as int]);

      expect(snapshot.entryFor(1)?.progress, closeTo(0.5, 1e-9));
    });

    test('a warning on any record propagates to the merged entry', () {
      final snapshot = ArrQueueSnapshot.fromQueueItems([
        {'seriesId': 1, 'status': 'downloading'},
        {
          'seriesId': 1,
          'status': 'downloading',
          'trackedDownloadStatus': 'warning',
        },
      ], idsFor: (item) => [item['seriesId'] as int]);

      expect(snapshot.entryFor(1)?.hasWarning, isTrue);
    });

    test('one record can map onto several media ids', () {
      final snapshot = ArrQueueSnapshot.fromQueueItems([
        {'status': 'downloading'},
      ], idsFor: (_) => [7, 8]);

      expect(snapshot.entryFor(7)?.pipeline, MediaPipeline.downloading);
      expect(snapshot.entryFor(8)?.pipeline, MediaPipeline.downloading);
    });
  });

  group('mediaStatusFromQueue', () {
    test('a queue entry can never resolve to missing', () {
      final status = mediaStatusFromQueue(
        availability: MediaAvailability.missing,
        monitored: true,
        queueEntry: const ArrQueueEntry(
          pipeline: MediaPipeline.downloading,
          progress: 0.5,
        ),
      );

      expect(status.label, 'Downloading');
      expect(status.progress, 0.5);
      expect(status.isInPipeline, isTrue);
    });

    test('without a queue entry the availability shows through', () {
      final status = mediaStatusFromQueue(
        availability: MediaAvailability.missing,
        monitored: false,
      );

      expect(status.pipeline, isNull);
      expect(status.unmonitored, isTrue);
      expect(status.label, 'Unmonitored');
    });
  });

  group('mergeArrQueueEntries', () {
    test('returns null for no entries', () {
      expect(mergeArrQueueEntries(const []), isNull);
    });

    test('collapses onto the most salient pipeline', () {
      final merged = mergeArrQueueEntries(const [
        ArrQueueEntry(pipeline: MediaPipeline.queued),
        ArrQueueEntry(pipeline: MediaPipeline.downloading, progress: 0.25),
      ]);

      expect(merged?.pipeline, MediaPipeline.downloading);
      expect(merged?.progress, 0.25);
    });
  });
}
