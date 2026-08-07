import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/music/domain/models/lidarr_track.dart';

void main() {
  group('LidarrTrack', () {
    group('fromJson', () {
      test('parses complete JSON correctly', () {
        final track = LidarrTrack.fromJson({
          'id': 21,
          'mediumNumber': 2,
          'trackNumber': '4',
          'title': 'Track Title',
          'hasFile': true,
          'duration': 185000,
        });

        expect(track.id, 21);
        expect(track.mediumNumber, 2);
        expect(track.trackNumber, '4');
        expect(track.title, 'Track Title');
        expect(track.hasFile, isTrue);
        expect(track.duration, 185000);
        expect(track.formattedDuration, '3:05');
        expect(track.sortableTrackNumber, 4);
        expect(track.displayTrackNumber, '4');
      });

      test('handles missing values with safe defaults', () {
        final track = LidarrTrack.fromJson(<String, dynamic>{});

        expect(track.id, 0);
        expect(track.mediumNumber, isNull);
        expect(track.trackNumber, isNull);
        expect(track.title, 'Track ?');
        expect(track.hasFile, isFalse);
        expect(track.duration, 0);
        expect(track.formattedDuration, '0:00');
        expect(track.sortableTrackNumber, 0);
        expect(track.displayTrackNumber, '?');
      });

      test('parses sortable track number from composite string values', () {
        final track = LidarrTrack.fromJson({'trackNumber': '7/12'});

        expect(track.sortableTrackNumber, 7);
      });
    });
  });
}
