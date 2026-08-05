import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/music/data/lidarr_service.dart';
import 'package:seekarr/features/music/domain/models/lidarr_album.dart';
import 'package:seekarr/features/music/domain/models/lidarr_track.dart';
import 'package:seekarr/features/music/presentation/widgets/music_albums_list.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/model_builders.dart';

void main() {
  group('MusicAlbumsList', () {
    testWidgets('renders the empty state in the Lidarr accent with no albums', (
      tester,
    ) async {
      await _pumpAlbumsList(tester, albums: const []);

      expect(find.text('No albums yet'), findsOneWidget);
      expect(
        tester.widget<AppEmptyState>(find.byType(AppEmptyState)).accentColor,
        ServiceKey.lidarr.accent,
      );
      // The bare `Text('No albums found.')` this replaced.
      expect(find.text('No albums found.'), findsNothing);
    });

    testWidgets('an album row carries decidable facts and a spoken status', (
      tester,
    ) async {
      await _pumpAlbumsList(tester, albums: [_album()]);

      expect(find.text('OK Computer'), findsOneWidget);
      // Year, the manifest gap and — because the album is complete — no status
      // word, all on one metadata line.
      expect(find.text('1997 • 12 of 12 tracks'), findsOneWidget);
      expect(find.byType(MediaSearchPopupMenu), findsOneWidget);
      expect(find.byType(StatusBadge), findsOneWidget);
      // The `ExpansionTile` this replaced — the third `container -> children`
      // implementation in the codebase.
      expect(find.byType(ExpansionTile), findsNothing);

      expect(
        tester.getSemantics(find.byType(MediaChildTile)),
        containsSemantics(
          label: 'OK Computer, 1997, 12 of 12 tracks',
          value: 'Available',
          isButton: true,
        ),
      );
    });

    testWidgets('an incomplete album says so in words, not only in colour', (
      tester,
    ) async {
      await _pumpAlbumsList(
        tester,
        albums: [
          _album(id: 10, title: 'Complete', fileCount: 12, trackCount: 12),
          _album(id: 11, title: 'Half Album', fileCount: 6, trackCount: 12),
          _album(id: 12, title: 'Empty Album', fileCount: 0, trackCount: 12),
        ],
      );

      expect(find.byType(MediaChildTile), findsNWidgets(3));
      expect(find.text('1997 • 6 of 12 tracks • Partial'), findsOneWidget);
      expect(find.text('1997 • 0 of 12 tracks • Missing'), findsOneWidget);
      expect(find.text('1997 • 12 of 12 tracks'), findsOneWidget);
    });

    testWidgets('tapping an album opens a sheet of sorted tracks', (
      tester,
    ) async {
      final lidarrService = _FakeLidarrService(
        tracksByAlbum: {
          10: [
            buildTrack(
              id: 3,
              mediumNumber: 2,
              trackNumber: '1',
              title: 'Lucky',
            ),
            buildTrack(
              id: 1,
              mediumNumber: 1,
              trackNumber: '10',
              title: 'No Surprises',
            ),
            buildTrack(
              id: 2,
              mediumNumber: 1,
              trackNumber: '2',
              title: 'Paranoid Android',
              hasFile: false,
            ),
          ],
        },
      );

      await _pumpAlbumsList(
        tester,
        albums: [_album()],
        lidarrService: lidarrService,
      );

      await _openAlbum(tester);

      expect(lidarrService.loadedAlbumIds, [10]);
      expect(find.text('Paranoid Android'), findsOneWidget);
      expect(find.text('No Surprises'), findsOneWidget);
      expect(find.text('Lucky'), findsOneWidget);

      expect(
        tester.getTopLeft(find.text('Paranoid Android')).dy,
        lessThan(tester.getTopLeft(find.text('No Surprises')).dy),
      );
      expect(
        tester.getTopLeft(find.text('No Surprises')).dy,
        lessThan(tester.getTopLeft(find.text('Lucky')).dy),
      );

      // A track without a file used to be a 7pt circle in `colorScheme.primary`
      // with no words anywhere near it.
      expect(find.textContaining('Missing'), findsOneWidget);
    });

    testWidgets('a failed track fetch offers a retry inside the sheet', (
      tester,
    ) async {
      final lidarrService = _FakeLidarrService(throwForAlbumIds: {10});

      await _pumpAlbumsList(
        tester,
        albums: [_album()],
        lidarrService: lidarrService,
      );

      await _openAlbum(tester);

      expect(find.text("Couldn't load Lidarr"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('an album with no tracks gets an empty state', (tester) async {
      await _pumpAlbumsList(
        tester,
        albums: [_album()],
        lidarrService: _FakeLidarrService(tracksByAlbum: {10: const []}),
      );

      await _openAlbum(tester);

      expect(find.text('No tracks'), findsOneWidget);
      expect(find.text('No tracks found.'), findsNothing);
    });

    testWidgets('builds only a bounded number of rows for a long discography', (
      tester,
    ) async {
      await _pumpAlbumsList(
        tester,
        albums: [
          for (var index = 0; index < 250; index++)
            _album(id: index, title: 'Album $index'),
        ],
      );

      final built = find.byType(MediaChildTile).evaluate().length;
      expect(built, greaterThan(0));
      expect(built, lessThan(40));
    });

    // `MediaChildTile.stacked` is the one row shape that pairs a *fixed* leading
    // box (38x54 of artwork, correctly ungrown — it holds no text) with text that
    // does grow, plus a progress bar under it. That combination is where a grown
    // box painted at a different scale shows up as an overflow stripe, so it is
    // checked directly rather than inferred from the numbered row's coverage.
    for (final scale in <double>[1.0, 1.3, 2.0, 3.0]) {
      testWidgets('an album row survives a ${scale}x reading size', (
        tester,
      ) async {
        await _pumpAlbumsListAtScale(
          tester,
          scale,
          albums: [
            _album(title: 'A Rather Long Album Title That Will Not Fit'),
            _album(id: 11, title: 'Half Album', fileCount: 6, trackCount: 12),
          ],
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(MediaChildTile), findsNWidgets(2));
      });
    }
  });
}

/// Taps the album row and lets the sheet route settle plus the track fetch
/// resolve. Deliberately not `pumpAndSettle`: the loading state is a shimmer,
/// whose sweep repeats indefinitely.
Future<void> _openAlbum(WidgetTester tester) async {
  await tester.tap(find.text('OK Computer'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _pumpAlbumsList(
  WidgetTester tester, {
  required List<LidarrAlbum> albums,
  LidarrService? lidarrService,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            MusicAlbumsList(
              albums: albums,
              lidarrService: lidarrService ?? _FakeLidarrService(),
              baseUrl: 'http://localhost:8686',
              apiKey: 'key',
              onSearchAlbum: (_) {},
              onInteractiveSearchAlbum: (_) {},
              searchingAlbums: const {},
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpAlbumsListAtScale(
  WidgetTester tester,
  double scale, {
  required List<LidarrAlbum> albums,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: CustomScrollView(
              slivers: [
                MusicAlbumsList(
                  albums: albums,
                  lidarrService: _FakeLidarrService(),
                  baseUrl: 'http://localhost:8686',
                  apiKey: 'key',
                  onSearchAlbum: (_) {},
                  onInteractiveSearchAlbum: (_) {},
                  searchingAlbums: const {},
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

LidarrAlbum _album({
  int id = 10,
  String title = 'OK Computer',
  int trackCount = 12,
  int fileCount = 12,
}) => buildAlbum(
  id: id,
  title: title,
  releaseDate: '1997-06-16',
  statistics: {'totalTrackCount': trackCount, 'trackFileCount': fileCount},
);

class _FakeLidarrService extends FakeLidarrService {
  _FakeLidarrService({
    this.tracksByAlbum = const {},
    this.throwForAlbumIds = const {},
  });

  final Map<int, List<LidarrTrack>> tracksByAlbum;
  final Set<int> throwForAlbumIds;
  final List<int> loadedAlbumIds = [];

  @override
  Future<List<LidarrTrack>> getTracks(int albumId) async {
    loadedAlbumIds.add(albumId);
    if (throwForAlbumIds.contains(albumId)) {
      throw Exception('boom');
    }

    return tracksByAlbum[albumId] ?? const [];
  }
}
