import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/music/data/lidarr_service.dart';
import 'package:seekarr/features/music/domain/models/lidarr_album.dart';
import 'package:seekarr/features/music/domain/models/lidarr_artist.dart';
import 'package:seekarr/features/music/presentation/music_detail_provider.dart';
import 'package:seekarr/features/music/presentation/music_detail_screen.dart';
import 'package:seekarr/features/music/presentation/widgets/music_albums_list.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/model_builders.dart';

LidarrArtist _artist({
  int id = 1,
  bool monitored = true,
  String? path,
  Map<String, dynamic>? statistics,
}) => buildArtist(
  id: id,
  artistName: 'Radiohead',
  overview: 'An English rock band.',
  monitored: monitored,
  statistics:
      statistics ??
      const {'albumCount': 9, 'trackCount': 120, 'trackFileCount': 100},
  genres: const ['Rock', 'Alternative'],
  artistType: 'Group',
  disambiguation: 'UK band',
  path: path ?? '/music/Radiohead',
);

List<LidarrAlbum> _albums() => [
  buildAlbum(
    id: 10,
    title: 'OK Computer',
    releaseDate: '1997-06-16',
    statistics: const {'totalTrackCount': 12, 'trackFileCount': 12},
  ),
];

void main() {
  group('MusicDetailScreen', () {
    testWidgets('shows loading state when provider is loading', (tester) async {
      await _pumpMusicDetail(
        tester,
        detailBuilder: (ref, artistId) => Completer<LidarrArtist?>().future,
        albumsBuilder: (ref, artistId) => Completer<List<LidarrAlbum>>().future,
      );
      await tester.pump();

      expect(find.byType(MediaDetailLoadingView), findsOneWidget);
    });

    testWidgets('shows error text for generic errors', (tester) async {
      await _pumpMusicDetail(
        tester,
        detailBuilder: (ref, artistId) =>
            Future<LidarrArtist?>.error(Exception('Network error')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Error:'), findsOneWidget);
      expect(find.textContaining('Network error'), findsOneWidget);
    });

    testWidgets('shows not configured placeholder for configuration errors', (
      tester,
    ) async {
      await _pumpMusicDetail(
        tester,
        detailBuilder: (ref, artistId) =>
            Future<LidarrArtist?>.error(Exception('Lidarr not configured')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
    });

    testWidgets('renders artist detail content with albums when loaded', (
      tester,
    ) async {
      await _pumpMusicDetail(
        tester,
        detailBuilder: (ref, artistId) async => _artist(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Radiohead'), findsAtLeastNWidgets(1));
      expect(find.byType(MediaDetailHeroSummaryCard), findsOneWidget);
      expect(find.text('An English rock band.'), findsOneWidget);

      await _scrollUntilVisible(tester, find.text('Tags'));

      expect(find.text('Tags'), findsOneWidget);

      await _scrollUntilVisible(
        tester,
        find.widgetWithText(MediaDetailSectionHeader, 'Albums'),
      );

      expect(find.byType(MusicAlbumsList), findsOneWidget);
      expect(find.text('OK Computer'), findsOneWidget);
      expect(find.byType(MusicAlbumsList), findsOneWidget);
      expect(find.byType(MediaInfoCard), findsOneWidget);
    });

    testWidgets('uses initialArtist while provider is still loading', (
      tester,
    ) async {
      await _pumpMusicDetail(
        tester,
        detailBuilder: (ref, artistId) => Completer<LidarrArtist?>().future,
        initialArtist: _artist(),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Radiohead'), findsAtLeastNWidgets(1));
      expect(find.byType(MediaDetailLoadingView), findsNothing);
    });

    testWidgets('shows album and track count tags', (tester) async {
      await _pumpMusicDetail(
        tester,
        detailBuilder: (ref, artistId) async => _artist(),
      );
      await tester.pumpAndSettle();

      expect(find.text('9 Albums'), findsOneWidget);
      expect(find.text('120 Tracks'), findsOneWidget);
      expect(find.byType(TagChip), findsAtLeastNWidgets(2));
    });

    testWidgets('shows albums loading indicator while albums are loading', (
      tester,
    ) async {
      await _pumpMusicDetail(
        tester,
        detailBuilder: (ref, artistId) async => _artist(),
        albumsBuilder: (ref, artistId) => Completer<List<LidarrAlbum>>().future,
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Radiohead'), findsAtLeastNWidgets(1));

      await _scrollUntilVisible(
        tester,
        find.widgetWithText(MediaDetailSectionHeader, 'Albums'),
        settle: false,
      );

      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('shows add artist action and hides albums for lookup miss', (
      tester,
    ) async {
      var requestedArtist = false;
      var requestedAlbums = false;

      await _pumpMusicDetail(
        tester,
        artistId: 0,
        detailBuilder: (ref, artistId) async {
          requestedArtist = true;
          return null;
        },
        albumsBuilder: (ref, artistId) async {
          requestedAlbums = true;
          return const [];
        },
        initialArtist: _artist(
          id: 0,
          monitored: false,
          path: null,
          statistics: const {
            'albumCount': 0,
            'trackCount': 0,
            'trackFileCount': 0,
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(requestedArtist, isFalse);
      expect(requestedAlbums, isFalse);
      expect(find.text('Add Artist'), findsOneWidget);
      expect(find.text('Interactive'), findsNothing);
      expect(
        find.widgetWithText(MediaDetailSectionHeader, 'Albums'),
        findsNothing,
      );

      await tester.tap(find.text('Add Artist'));
      await tester.pumpAndSettle();

      expect(
        find.text('Add Artist is not available yet from this view.'),
        findsOneWidget,
      );
    });

    testWidgets('shows monitor action for unmonitored library artists', (
      tester,
    ) async {
      final lidarrService = _TrackingLidarrService();

      await _pumpMusicDetail(
        tester,
        detailBuilder: (ref, artistId) async => _artist(monitored: false),
        lidarrService: lidarrService,
      );
      await tester.pumpAndSettle();

      expect(find.text('Monitor'), findsOneWidget);
      expect(find.text('Interactive'), findsOneWidget);

      await tester.tap(find.text('Monitor'));
      await tester.pumpAndSettle();

      expect(lidarrService.updatedArtistId, 1);
      expect(lidarrService.updatedMonitored, isTrue);
      expect(find.text('Artist monitored'), findsOneWidget);
    });

    testWidgets('shows unmonitor action for monitored library artists', (
      tester,
    ) async {
      final lidarrService = _TrackingLidarrService();

      await _pumpMusicDetail(
        tester,
        detailBuilder: (ref, artistId) async => _artist(),
        lidarrService: lidarrService,
      );
      await tester.pumpAndSettle();

      expect(find.text('Unmonitor'), findsOneWidget);
      expect(find.text('Interactive'), findsOneWidget);

      await tester.tap(find.text('Unmonitor'));
      await tester.pumpAndSettle();

      expect(lidarrService.updatedArtistId, 1);
      expect(lidarrService.updatedMonitored, isFalse);
      expect(find.text('Artist unmonitored'), findsOneWidget);
    });
  });
}

Future<void> _scrollUntilVisible(
  WidgetTester tester,
  Finder finder, {
  bool settle = true,
}) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _pumpMusicDetail(
  WidgetTester tester, {
  required FutureOr<LidarrArtist?> Function(Ref ref, int artistId)
  detailBuilder,
  FutureOr<List<LidarrAlbum>> Function(Ref ref, int artistId)? albumsBuilder,
  LidarrArtist? initialArtist,
  int artistId = 1,
  LidarrService? lidarrService,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => const SettingsModel(
            lidarrUrl: 'http://localhost:8686',
            lidarrApiKey: 'key',
          ),
        ),
        musicDetailProvider.overrideWith(detailBuilder),
        musicAlbumsProvider.overrideWith(
          albumsBuilder ?? (ref, artistId) async => _albums(),
        ),
        lidarrServiceProvider.overrideWith(
          (ref) => lidarrService ?? FakeLidarrService(),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: MusicDetailScreen(
            artistId: artistId,
            heroTag: 'music-1',
            initialArtist: initialArtist,
          ),
        ),
      ),
    ),
  );
}

class _TrackingLidarrService extends FakeLidarrService {
  int? updatedArtistId;
  bool? updatedMonitored;

  @override
  Future<void> updateArtistMonitored(int artistId, bool monitored) async {
    updatedArtistId = artistId;
    updatedMonitored = monitored;
  }
}
