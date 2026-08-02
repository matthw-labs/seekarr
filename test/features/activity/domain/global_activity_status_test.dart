import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/status/media_status.dart';
import 'package:seekarr/features/activity/domain/global_activity_status.dart';
import 'package:seekarr/features/discover/domain/models/seerr_request.dart';

void main() {
  group('resolveHistoryStatus', () {
    test('a failed download is an error, not a success', () {
      // The regression this whole layer exists for: the tile switched on the
      // row's *kind*, so `history` was unconditionally the success green and a
      // `downloadFailed` event rendered the word "Failed" inside a green pill.
      final status = resolveHistoryStatus(const {
        'eventType': 'downloadFailed',
      });

      expect(status.label, 'Failed');
      expect(status.tone, StatusTone.error);
    });

    test('an import is a success and a grab is in-flight', () {
      expect(
        resolveHistoryStatus(const {'eventType': 'downloadImported'}).tone,
        StatusTone.success,
      );
      expect(
        resolveHistoryStatus(const {
          'eventType': 'downloadFolderImported',
        }).tone,
        StatusTone.success,
      );
      expect(
        resolveHistoryStatus(const {'eventType': 'grabbed'}).tone,
        StatusTone.info,
      );
    });

    test('a deleted file warns and a rename is neutral', () {
      expect(
        resolveHistoryStatus(const {'eventType': 'movieFileDeleted'}).tone,
        StatusTone.warning,
      );
      expect(
        resolveHistoryStatus(const {'eventType': 'episodeFileRenamed'}).tone,
        StatusTone.neutral,
      );
    });

    test('an unknown event type is humanised and stays neutral', () {
      final status = resolveHistoryStatus(const {
        'eventType': 'someFutureEvent',
      });

      expect(status.label, 'Some Future Event');
      expect(status.tone, StatusTone.neutral);
    });

    test('a missing event type does not throw', () {
      expect(resolveHistoryStatus(const {}).tone, StatusTone.neutral);
    });
  });

  group('resolveQueueDisplayStatus', () {
    test('a failed queue record resolves to the error tone', () {
      // The other half of the same bug: the queue row was painted in the service
      // accent, so a stalled download was chromatically identical to a healthy
      // one and nothing on the row was red.
      final status = resolveQueueDisplayStatus(const {
        'status': 'failed',
        'title': 'Some.Release',
      });

      expect(status.tone, StatusTone.error);
    });

    test('a downloading record carries progress and the info tone', () {
      final status = resolveQueueDisplayStatus(const {
        'status': 'downloading',
        'size': 100,
        'sizeleft': 25,
      });

      expect(status.pipeline, MediaPipeline.downloading);
      expect(status.progress, 0.75);
      expect(status.progressPercent, 75);
      expect(status.tone, StatusTone.info);
    });

    test('an already-imported record still gets a row', () {
      final status = resolveQueueDisplayStatus(const {
        'trackedDownloadState': 'imported',
      });

      expect(status.label, 'Imported');
    });

    test('an ignored record is labelled as such', () {
      final status = resolveQueueDisplayStatus(const {
        'trackedDownloadState': 'ignored',
      });

      expect(status.label, 'Ignored');
    });

    test('a warning escalates an otherwise calm tone', () {
      final status = resolveQueueDisplayStatus(const {
        'trackedDownloadState': 'imported',
        'trackedDownloadStatus': 'warning',
      });

      expect(status.hasWarning, isTrue);
      expect(status.tone, StatusTone.warning);
    });
  });

  group('resolveWantedStatus', () {
    test('missing warns rather than erroring', () {
      // Every row in the Wanted bucket is missing by definition, so red on all
      // of them leaves nothing for a real problem to stand out against.
      final status = resolveWantedStatus(const {}, isCutoff: false);

      expect(status.label, 'Missing');
      expect(status.tone, StatusTone.warning);
    });

    test('an unmet cutoff is an opportunity, not a problem', () {
      final status = resolveWantedStatus(const {}, isCutoff: true);

      // Matches the "Cutoff Unmet" sub-segment label; the old string was
      // 'Cutoff', which is not the term the *arr services use.
      expect(status.label, 'Cutoff Unmet');
      expect(status.tone, StatusTone.info);
    });

    test('an unmonitored item is neutral in both buckets', () {
      for (final isCutoff in [true, false]) {
        final status = resolveWantedStatus(const {
          'monitored': false,
        }, isCutoff: isCutoff);

        expect(status.label, 'Unmonitored');
        expect(status.tone, StatusTone.neutral, reason: 'isCutoff: $isCutoff');
      }
    });
  });

  group('resolveBlocklistStatus', () {
    test('is always an error and carries the reason', () {
      final status = resolveBlocklistStatus(const {
        'message': 'Release rejected by the indexer',
      });

      expect(status.label, 'Blocked');
      expect(status.tone, StatusTone.error);
      expect(status.detail, 'Release rejected by the indexer');
    });

    test('falls back to the first status message when there is no message', () {
      final status = resolveBlocklistStatus(const {
        'statusMessages': [
          {'title': 'Not an upgrade'},
        ],
      });

      expect(status.detail, isNotNull);
    });
  });

  group('resolveRequestStatus', () {
    SeerrRequest requestWith(RequestStatus status) => SeerrRequest(
      id: 1,
      status: status,
      createdAt: '2026-04-03T09:05:00Z',
      type: 'movie',
    );

    test('a declined request reads as a problem, not as the Seerr accent', () {
      final status = resolveRequestStatus(requestWith(RequestStatus.declined));

      expect(status.tone, StatusTone.error);
      expect(status.label, 'Declined');
    });

    test('a pending request warns and an approved one is in-flight', () {
      expect(
        resolveRequestStatus(requestWith(RequestStatus.pendingApproval)).tone,
        StatusTone.warning,
      );
      expect(
        resolveRequestStatus(requestWith(RequestStatus.approved)).tone,
        StatusTone.info,
      );
    });

    test("preserves Seerr's own wording as the label", () {
      final status = resolveRequestStatus(
        requestWith(RequestStatus.pendingApproval),
      );

      expect(status.label, 'Pending');
    });
  });

  group('resolveActivityStatus', () {
    test('dispatches each kind to its resolver', () {
      expect(
        resolveActivityStatus(GlobalActivityKind.history, const {
          'eventType': 'downloadFailed',
        }).tone,
        StatusTone.error,
      );
      expect(
        resolveActivityStatus(GlobalActivityKind.blocklist, const {}).tone,
        StatusTone.error,
      );
      expect(
        resolveActivityStatus(GlobalActivityKind.missing, const {}).label,
        'Missing',
      );
      expect(
        resolveActivityStatus(GlobalActivityKind.cutoff, const {}).label,
        'Cutoff Unmet',
      );
    });
  });

  group('MediaStatusInfo.toneOverride', () {
    test('overrides the derived tone', () {
      const status = MediaStatusInfo(
        availability: MediaAvailability.available,
        toneOverride: StatusTone.error,
      );

      // Availability alone would resolve to success.
      expect(status.tone, StatusTone.error);
    });

    test('a warning escalates over an override, but never over an error', () {
      const warned = MediaStatusInfo(
        toneOverride: StatusTone.neutral,
        hasWarning: true,
      );
      expect(warned.tone, StatusTone.warning);

      const errored = MediaStatusInfo(
        toneOverride: StatusTone.error,
        hasWarning: true,
      );
      expect(errored.tone, StatusTone.error);
    });

    test('participates in equality and copyWith', () {
      const base = MediaStatusInfo(toneOverride: StatusTone.info);

      expect(base, const MediaStatusInfo(toneOverride: StatusTone.info));
      expect(base == const MediaStatusInfo(), isFalse);
      expect(
        base.copyWith(toneOverride: StatusTone.error).tone,
        StatusTone.error,
      );
    });
  });
}
