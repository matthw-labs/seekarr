import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/presentation/music_detail_view_model.dart';

void main() {
  group('MusicDetailViewModel', () {
    LidarrArtist makeArtist({
      String? artistType,
      String? disambiguation,
      List<String> genres = const [],
      Map<String, dynamic>? statistics,
      String? path,
    }) {
      return LidarrArtist(
        id: 1,
        artistName: 'Test Artist',
        status: 'active',
        overview: 'A great artist.',
        monitored: true,
        images: const [],
        genres: genres,
        statistics: statistics,
        artistType: artistType,
        disambiguation: disambiguation,
        path: path,
      );
    }

    group('fromArtist', () {
      test('maps basic fields', () {
        final vm = MusicDetailViewModel.fromArtist(
          makeArtist(
            statistics: {
              'albumCount': 5,
              'trackCount': 50,
              'trackFileCount': 40,
            },
          ),
          baseUrl: 'http://localhost:8686',
          apiKey: 'test-key',
        );

        expect(vm.title, 'Test Artist');
        expect(vm.albumCount, 5);
        expect(vm.trackCount, 50);
      });

      test('maps enrichment fields', () {
        final vm = MusicDetailViewModel.fromArtist(
          makeArtist(
            artistType: 'Group',
            disambiguation: 'UK band',
            path: '/music/Test Artist',
          ),
          baseUrl: 'http://localhost:8686',
          apiKey: 'test-key',
        );

        expect(vm.artistType, 'Group');
        expect(vm.disambiguation, 'UK band');
        expect(vm.path, '/music/Test Artist');
      });
    });

    group('metadataItems', () {
      test('includes album and track counts', () {
        final vm = MusicDetailViewModel.fromArtist(
          makeArtist(
            statistics: {
              'albumCount': 3,
              'trackCount': 30,
              'trackFileCount': 0,
            },
          ),
          baseUrl: 'http://localhost:8686',
          apiKey: 'test-key',
        );

        expect(vm.metadataItems, ['3 Albums', '30 Tracks']);
      });

      test('empty when no albums or tracks', () {
        final vm = MusicDetailViewModel.fromArtist(
          makeArtist(),
          baseUrl: 'http://localhost:8686',
          apiKey: 'test-key',
        );

        expect(vm.metadataItems, isEmpty);
      });
    });

    group('buildInfoGroups', () {
      test('returns empty when no enrichment data or genres', () {
        final vm = MusicDetailViewModel.fromArtist(
          makeArtist(),
          baseUrl: 'http://localhost:8686',
          apiKey: 'test-key',
        );

        expect(vm.buildInfoGroups(), isEmpty);
      });

      test('includes artist type capitalized', () {
        final vm = MusicDetailViewModel.fromArtist(
          makeArtist(artistType: 'group'),
          baseUrl: 'http://localhost:8686',
          apiKey: 'test-key',
        );

        final typeGroup = vm.buildInfoGroups().firstWhere(
          (group) => group.title == 'Artist Type',
        );

        expect((typeGroup.child as Text).data, 'Group');
      });

      test('includes disambiguation and library path', () {
        final vm = MusicDetailViewModel.fromArtist(
          makeArtist(
            disambiguation: 'UK rock band',
            path: '/music/Test Artist',
          ),
          baseUrl: 'http://localhost:8686',
          apiKey: 'test-key',
        );

        final titles = vm
            .buildInfoGroups()
            .map((group) => group.title)
            .toList();

        expect(titles, contains('Disambiguation'));
        expect(titles, contains('Library Path'));
      });

      test('preserves group order', () {
        final vm = MusicDetailViewModel.fromArtist(
          makeArtist(
            artistType: 'Solo',
            disambiguation: 'singer',
            genres: const ['Pop'],
            path: '/music/Test Artist',
          ),
          baseUrl: 'http://localhost:8686',
          apiKey: 'test-key',
        );

        expect(vm.buildInfoGroups().map((group) => group.title).toList(), [
          'Artist Type',
          'Disambiguation',
          'Genre',
          'Library Path',
        ]);
      });
    });
  });
}
