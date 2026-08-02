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
      expect(unavailable?.pipeline, MediaPipeline.clientUnavailable);
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
      // Not `importPending`: the two used to share it, which hid every record
      // asking for a manual import inside the queue's most common transient
      // state. `importBlocked` waits for a person; `importPending` clears itself.
      'importBlocked': MediaPipeline.importBlocked,
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

    test('downloadClientUnavailable is a state of its own, not a label', () {
      final entry = ArrQueueEntry.fromQueueItem({
        'status': 'downloadClientUnavailable',
      });

      // It used to be `paused` carrying a `label`, which had two consequences:
      // it inherited the lowest salience in the enum, and a label is precisely
      // what the merge is entitled to drop. See the merge test below.
      expect(entry?.pipeline, MediaPipeline.clientUnavailable);
      expect(entry?.label, isNull);
      expect(entry?.toneOverride, isNull);
    });

    test('an unreachable client outranks a healthy sibling in the merge', () {
      // The regression this exists for: one episode blocked by a dead download
      // client and one merely queued reported "Queued", because
      // `clientUnavailable` was `paused` at salience 0 and the queued record
      // outranked it — taking the reason for the outage down with it.
      final snapshot = ArrQueueSnapshot.fromQueueItems([
        {'seriesId': 1, 'status': 'queued'},
        {'seriesId': 1, 'status': 'downloadClientUnavailable'},
      ], idsFor: (item) => [item['seriesId'] as int]);

      final entry = snapshot.entryFor(1);
      expect(entry?.pipeline, MediaPipeline.clientUnavailable);
      expect(
        mediaStatusFromQueue(
          availability: MediaAvailability.missing,
          monitored: true,
          queueEntry: entry,
        ).label,
        'Client Unavailable',
      );
    });

    test('a stalled transfer does not report itself as downloading', () {
      // The \*arr services have no `stalled` status; they say it in prose. Before
      // this, the row read "Downloading" — the opposite of the truth — for the
      // most common reason anyone opens Activity.
      final entry = ArrQueueEntry.fromQueueItem({
        'status': 'downloading',
        'trackedDownloadState': 'downloading',
        'errorMessage': 'The download is stalled with no connections',
        'size': 100,
        'sizeleft': 57,
      });

      expect(entry?.pipeline, MediaPipeline.stalled);
      expect(entry?.progress, closeTo(0.43, 1e-9));
    });

    test('a stalled transfer keeps showing how far it got', () {
      // "Stalled at 43%" is how the user chooses between waiting and
      // blocklisting, so `progressPercent` has to survive a state that is not
      // `isActive`.
      final status = mediaStatusFromQueue(
        availability: MediaAvailability.missing,
        monitored: true,
        queueEntry: ArrQueueEntry.fromQueueItem({
          'status': 'downloading',
          'trackedDownloadState': 'downloading',
          'statusMessages': ['The download is stalled with no connections'],
          'size': 100,
          'sizeleft': 57,
        }),
      );

      expect(status.label, 'Stalled');
      expect(status.isActive, isFalse);
      expect(status.showsProgress, isTrue);
      expect(status.progressPercent, 43);
    });

    test('unrecognised wording degrades to downloading, never to stalled', () {
      // The stall signal is text-matched, so it has to fail safe: if the
      // upstream phrasing changes, the record must fall back to the previous
      // behaviour rather than mislabel a healthy transfer.
      final entry = ArrQueueEntry.fromQueueItem({
        'status': 'downloading',
        'trackedDownloadState': 'downloading',
        'errorMessage': 'Something nobody has seen before',
      });

      expect(entry?.pipeline, MediaPipeline.downloading);
    });

    test('status "warning" is a state, not an unknown string', () {
      // It used to fall through to the unrecognised-status branch, which turned
      // a flagged record into the word "Warning" sitting inside a "Queued" row.
      final entry = ArrQueueEntry.fromQueueItem({
        'status': 'warning',
        'trackedDownloadState': 'downloading',
      });

      expect(entry?.pipeline, MediaPipeline.downloading);
      expect(entry?.label, isNull);
      expect(entry?.severity, ArrQueueSeverity.warning);
    });

    test('a service-reported error outranks a warning', () {
      final entry = ArrQueueEntry.fromQueueItem({
        'status': 'downloading',
        'trackedDownloadState': 'downloading',
        'trackedDownloadStatus': 'error',
      });

      expect(entry?.severity, ArrQueueSeverity.error);
      expect(entry?.toneOverride, StatusTone.error);
      expect(
        mediaStatusFromQueue(
          availability: MediaAvailability.missing,
          monitored: true,
          queueEntry: entry,
        ).tone,
        // Not downgraded to `warning` by `hasWarning`, which is what used to
        // happen to every record the service had explicitly failed.
        StatusTone.error,
      );
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

    test('the detail line describes the state that won the headline', () {
      // `_detail` was assigned from whichever record arrived first regardless of
      // which one won, while `_label` was reset when the headline changed. So a
      // row could headline one episode's state and print another episode's
      // message underneath it.
      final snapshot = ArrQueueSnapshot.fromQueueItems([
        {
          'seriesId': 1,
          'status': 'downloading',
          'trackedDownloadState': 'downloading',
          'statusMessages': ['A note about the healthy episode'],
        },
        {
          'seriesId': 1,
          'status': 'completed',
          'trackedDownloadState': 'importBlocked',
          'statusMessages': ['Not an upgrade for the existing file'],
        },
      ], idsFor: (item) => [item['seriesId'] as int]);

      final entry = snapshot.entryFor(1);
      expect(entry?.pipeline, MediaPipeline.importBlocked);
      expect(entry?.detail, 'Not an upgrade for the existing file');
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
