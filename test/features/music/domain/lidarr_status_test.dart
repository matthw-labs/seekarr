import 'package:flutter_test/flutter_test.dart';
import 'package:seekarr/core/status/arr_queue_snapshot.dart';
import 'package:seekarr/features/music/domain/lidarr_status.dart';

import '../../../test_helpers/model_builders.dart';

void main() {
  group('lidarrTrackStatus', () {
    test('a track with a file is available', () {
      final status = lidarrTrackStatus(buildTrack(hasFile: true));

      expect(status.availability, MediaAvailability.available);
      expect(status.label, 'Available');
      expect(status.tone, StatusTone.success);
    });

    test('a track with no file is missing, and says so', () {
      // This used to be a 7pt circle filled `colorScheme.primary` with no words
      // anywhere on the page.
      final status = lidarrTrackStatus(buildTrack(hasFile: false));

      expect(status.availability, MediaAvailability.missing);
      expect(status.label, 'Missing');
      expect(status.semanticLabel, 'Missing');
    });
  });

  group('lidarrAlbumSummary', () {
    test('states the manifest gap', () {
      expect(
        lidarrAlbumSummary(
          buildAlbum(
            statistics: const {'totalTrackCount': 12, 'trackFileCount': 7},
          ),
        ),
        '7 of 12 tracks',
      );
    });

    test('an album with no known tracks has no summary', () {
      expect(lidarrAlbumSummary(buildAlbum()), isNull);
    });
  });
}
