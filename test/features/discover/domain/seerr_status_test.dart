import 'package:flutter_test/flutter_test.dart';
import 'package:seekarr/core/status/media_status.dart';
import 'package:seekarr/features/discover/domain/models/discover_detail_model.dart';
import 'package:seekarr/features/discover/domain/seerr_status.dart';

void main() {
  group('seerrMediaStatus', () {
    test('no media record at all is an invitation to request', () {
      final status = seerrMediaStatus(null);

      expect(status.label, 'Available to Request');
      expect(status.availability, MediaAvailability.notTracked);
      expect(status.tone, StatusTone.primary);
    });

    final codeLabels = <int, String>{
      1: 'Unknown',
      2: 'Pending',
      3: 'Processing',
      4: 'Partially Available',
      5: 'Available',
      6: 'Deleted',
    };

    codeLabels.forEach((code, label) {
      test('status $code reads "$label"', () {
        expect(seerrMediaStatus({'status': code}).label, label);
      });
    });

    test('an unknown status code degrades to Unknown', () {
      expect(seerrMediaStatus({'status': 999}).label, 'Unknown');
    });

    test('downloadStatus turns a static Processing into a live download', () {
      // The field Seerr has always exposed and the app never read.
      final status = seerrMediaStatus({
        'status': 3,
        'downloadStatus': [
          {
            'status': 'downloading',
            'trackedDownloadState': 'downloading',
            'size': 1000,
            'sizeLeft': 250,
          },
        ],
      });

      expect(status.label, 'Downloading');
      expect(status.progress, 0.75);
      expect(status.tone, StatusTone.info);
    });

    test('several downloads are averaged into one headline', () {
      final status = seerrMediaStatus({
        'status': 3,
        'downloadStatus': [
          {'status': 'downloading', 'size': 100, 'sizeLeft': 80},
          {'status': 'downloading', 'size': 100, 'sizeLeft': 20},
        ],
      });

      expect(status.label, 'Downloading');
      expect(status.progress, closeTo(0.5, 1e-9));
    });

    test('a warning from the connected *arr propagates', () {
      final status = seerrMediaStatus({
        'status': 3,
        'downloadStatus': [
          {'status': 'downloading', 'trackedDownloadStatus': 'warning'},
        ],
      });

      expect(status.hasWarning, isTrue);
      expect(status.tone, StatusTone.warning);
    });

    test('an empty downloadStatus array falls back to the status code', () {
      expect(
        seerrMediaStatus({'status': 3, 'downloadStatus': const []}).label,
        'Processing',
      );
    });

    test('a malformed downloadStatus payload is ignored', () {
      expect(
        seerrMediaStatus({'status': 3, 'downloadStatus': 'nonsense'}).label,
        'Processing',
      );
    });

    test('the 4k axis reads its own fields', () {
      final payload = {
        'status': 5,
        'status4k': 3,
        'downloadStatus': const [],
        'downloadStatus4k': [
          {'status': 'downloading', 'size': 100, 'sizeLeft': 10},
        ],
      };

      expect(seerrMediaStatus(payload).label, 'Available');
      expect(seerrMediaStatus(payload, is4k: true).label, 'Downloading');
      expect(
        seerrMediaStatus(payload, is4k: true).progress,
        closeTo(0.9, 1e-9),
      );
    });

    test('an available title stays available even mid-upgrade', () {
      final status = seerrMediaStatus({'status': 5});

      expect(status.availability, MediaAvailability.available);
      expect(status.tone, StatusTone.success);
    });
  });

  group('seerrDownloadEntry', () {
    test('returns null for anything that is not a populated list', () {
      expect(seerrDownloadEntry(null), isNull);
      expect(seerrDownloadEntry(const []), isNull);
      expect(seerrDownloadEntry('nonsense'), isNull);
      expect(seerrDownloadEntry(const ['not a map']), isNull);
    });
  });

  group('seerrSeasonStatuses', () {
    const seasons = [
      TvSeason(id: 1, seasonNumber: 1, name: 'Season 1', episodeCount: 10),
      TvSeason(id: 2, seasonNumber: 2, name: 'Season 2', episodeCount: 10),
      TvSeason(id: 0, seasonNumber: 0, name: 'Specials', episodeCount: 2),
    ];

    test('maps Seerr codes onto the shared status vocabulary', () {
      final statuses = seerrSeasonStatuses(const {
        'seasons': [
          {'seasonNumber': 1, 'status': 5},
          {'seasonNumber': 2, 'status': 4},
        ],
      }, seasons);

      expect(statuses[1]!.availability, MediaAvailability.available);
      expect(statuses[1]!.label, 'Available');
      expect(statuses[2]!.availability, MediaAvailability.partial);
      // Seerr's own wording survives, the same way the page-level status keeps
      // it.
      expect(statuses[2]!.label, 'Partially Available');
    });

    test('a season Seerr has no record of is notTracked, not unknown', () {
      final statuses = seerrSeasonStatuses(const {
        'seasons': [
          {'seasonNumber': 1, 'status': 5},
        ],
      }, seasons);

      expect(statuses[0]!.availability, MediaAvailability.notTracked);
      expect(statuses[0]!.label, 'Not Requested');
      expect(statuses[2]!.availability, MediaAvailability.notTracked);
    });

    test('resolves a status for every season even with no mediaInfo', () {
      final statuses = seerrSeasonStatuses(null, seasons);

      expect(statuses.keys.toSet(), {0, 1, 2});
      for (final status in statuses.values) {
        expect(status.availability, MediaAvailability.notTracked);
      }
    });

    test('survives a malformed seasons payload', () {
      final statuses = seerrSeasonStatuses(const {
        'seasons': [
          'nonsense',
          42,
          {'status': 5},
        ],
      }, seasons);

      expect(statuses.length, 3);
      expect(statuses[1]!.availability, MediaAvailability.notTracked);
    });

    test('ignores a seasons key that is not a list', () {
      expect(seerrSeasonStatuses(const {'seasons': 'nope'}, seasons).length, 3);
    });
  });
}
