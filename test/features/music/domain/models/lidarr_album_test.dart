import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/music/domain/models/lidarr_album.dart';

void main() {
  group('LidarrAlbum', () {
    group('fromJson', () {
      test('parses complete JSON correctly', () {
        final album = LidarrAlbum.fromJson({
          'id': 3,
          'title': 'Test Album',
          'releaseDate': '2024-02-29',
          'monitored': true,
          'images': const [
            {
              'coverType': 'cover',
              'remoteUrl': 'https://example.com/cover.jpg',
            },
          ],
          'statistics': {'totalTrackCount': 12, 'trackFileCount': 9},
        });

        expect(album.id, 3);
        expect(album.title, 'Test Album');
        expect(album.releaseDate, '2024-02-29');
        expect(album.monitored, isTrue);
        expect(album.images, hasLength(1));
        expect(album.year, '2024');
        expect(album.trackCount, 12);
        expect(album.trackFileCount, 9);
        expect(album.completionPercent, closeTo(0.75, 0.0001));
      });

      test('handles missing values with safe defaults', () {
        final album = LidarrAlbum.fromJson(<String, dynamic>{});

        expect(album.id, 0);
        expect(album.title, 'Unknown Album');
        expect(album.releaseDate, isNull);
        expect(album.monitored, isFalse);
        expect(album.images, isEmpty);
        expect(album.statistics, isNull);
        expect(album.year, isEmpty);
        expect(album.trackCount, 0);
        expect(album.trackFileCount, 0);
        expect(album.completionPercent, 0);
      });
    });
  });
}
