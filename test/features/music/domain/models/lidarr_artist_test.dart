import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';

void main() {
  group('LidarrArtist', () {
    group('fromJson', () {
      test('parses complete JSON correctly', () {
        final json = {
          'id': 1,
          'artistName': 'Test Artist',
          'status': 'active',
          'overview': 'A test artist overview.',
          'monitored': true,
          'images': [
            {
              'coverType': 'poster',
              'remoteUrl': 'https://example.com/poster.jpg',
            },
          ],
          'statistics': {'albumCount': 5, 'trackCount': 50},
          'genres': ['Rock', 'Alternative'],
          'artistType': 'Group',
          'disambiguation': 'UK band',
          'links': [
            {'url': 'https://example.com', 'name': 'Official'},
          ],
          'added': '2023-01-01T00:00:00Z',
          'path': '/music/Test Artist',
        };

        final artist = LidarrArtist.fromJson(json);

        expect(artist.id, 1);
        expect(artist.artistName, 'Test Artist');
        expect(artist.status, 'active');
        expect(artist.overview, 'A test artist overview.');
        expect(artist.monitored, true);
        expect(artist.images.length, 1);
        expect(artist.statistics?['albumCount'], 5);
        expect(artist.genres, ['Rock', 'Alternative']);
        expect(artist.artistType, 'Group');
        expect(artist.disambiguation, 'UK band');
        expect(artist.links, hasLength(1));
        expect(artist.added, '2023-01-01T00:00:00Z');
        expect(artist.path, '/music/Test Artist');
      });

      test('handles missing optional fields', () {
        final json = {
          'id': 1,
          'artistName': 'Test Artist',
          'status': 'unknown',
          'monitored': false,
          'images': [],
          'genres': [],
        };

        final artist = LidarrArtist.fromJson(json);

        expect(artist.overview, isNull);
        expect(artist.statistics, isNull);
        expect(artist.artistType, isNull);
        expect(artist.disambiguation, isNull);
        expect(artist.links, isNull);
        expect(artist.added, isNull);
        expect(artist.path, isNull);
      });

      test('handles null values with defaults', () {
        final json = <String, dynamic>{};

        final artist = LidarrArtist.fromJson(json);

        expect(artist.id, 0);
        expect(artist.artistName, 'Unknown');
        expect(artist.status, 'unknown');
        expect(artist.monitored, false);
        expect(artist.images, isEmpty);
        expect(artist.genres, isEmpty);
        expect(artist.artistType, isNull);
        expect(artist.disambiguation, isNull);
        expect(artist.links, isNull);
        expect(artist.added, isNull);
        expect(artist.path, isNull);
      });

      test('exposes typed statistics getters', () {
        final artist = LidarrArtist.fromJson({
          'id': 1,
          'artistName': 'Test Artist',
          'status': 'active',
          'monitored': true,
          'images': const [],
          'genres': const [],
          'statistics': {
            'albumCount': 5,
            'trackCount': 50,
            'trackFileCount': 40,
          },
        });

        expect(artist.albumCount, 5);
        expect(artist.trackCount, 50);
        expect(artist.trackFileCount, 40);
        expect(artist.hasFiles, isTrue);
      });

      test('parses single-source ratings', () {
        final artist = LidarrArtist.fromJson({
          'id': 1,
          'artistName': 'Test Artist',
          'status': 'active',
          'monitored': true,
          'images': const [],
          'genres': const [],
          'ratings': {'value': 8.1, 'votes': 42500},
        });

        expect(artist.ratings, hasLength(1));
        expect(artist.ratings.single.name, 'MB');
        expect(artist.ratings.single.votes, 42500);
        expect(artist.ratings.single.icon, 'MB');
        expect(artist.ratings.single.value, 8.1);
      });
    });

    group('toMediaPreview', () {
      test('converts to MediaPreview correctly', () {
        final artist = LidarrArtist(
          id: 1,
          artistName: 'Test Artist',
          status: 'active',
          overview: 'Overview',
          monitored: true,
          images: [
            {
              'coverType': 'poster',
              'remoteUrl': 'https://example.com/poster.jpg',
            },
          ],
          genres: ['Rock'],
        );

        final preview = artist.toMediaPreview();

        expect(preview.id, 1);
        expect(preview.title, 'Test Artist');
        expect(preview.posterPath, 'https://example.com/poster.jpg');
        expect(preview.overview, 'Overview');
        expect(preview.mediaType, 'music');
      });
    });
  });
}
