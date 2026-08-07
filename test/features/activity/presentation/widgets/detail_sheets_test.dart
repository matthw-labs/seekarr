import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/presentation/activity_screen.dart';
import 'package:cupola/features/activity/presentation/widgets/detail_sheets.dart';

void main() {
  group('DetailSheets', () {
    testWidgets('showQueueDetail renders sections and messages', (
      tester,
    ) async {
      await _pumpDetailSheet(
        tester,
        showSheet: (context) => DetailSheets.showQueueDetail(context, {
          'title': 'Movie.2024.2160p.WEB-DL-GROUP',
          'status': 'downloading',
          'trackedDownloadStatus': 'warning',
          'trackedDownloadState': 'downloading',
          'movie': {'title': 'Movie', 'year': 2024},
          'quality': {
            'quality': {'name': 'HD-1080p'},
          },
          'protocol': 'torrent',
          'downloadClient': 'qBittorrent',
          'indexer': 'Indexer',
          'size': 1000000000,
          'sizeleft': 250000000,
          'timeleft': '00:12:34',
          'estimatedCompletionTime': '2026-04-03T12:34:56Z',
          'outputPath': '/downloads/movie',
          'statusMessages': [
            {
              'title': 'Import Warning',
              'messages': ['Needs manual import'],
            },
          ],
        }),
      );

      expect(find.text('Movie (2024)'), findsOneWidget);
      expect(find.text('Summary'), findsOneWidget);
      expect(find.text('Downloading (Warning)'), findsOneWidget);
      await _scrollSheetUntilVisible(tester, find.text('Transfer'));
      expect(find.text('Transfer'), findsOneWidget);
      await _scrollSheetUntilVisible(tester, find.text('Status Messages'));
      expect(find.text('Status Messages'), findsOneWidget);
      expect(find.text('qBittorrent'), findsOneWidget);
      expect(find.text('/downloads/movie'), findsOneWidget);
      expect(find.text('Movie.2024.2160p.WEB-DL-GROUP'), findsOneWidget);
      expect(find.text('Import Warning: Needs manual import'), findsOneWidget);
      expect(find.text('Manual Import'), findsNothing);
    });

    testWidgets(
      'showHistoryDetail renders additional data and excludes noise',
      (tester) async {
        await _pumpDetailSheet(
          tester,
          showSheet: (context) => DetailSheets.showHistoryDetail(context, {
            'sourceTitle': 'Release.Name',
            'eventType': 'downloadImported',
            'date': '2026-04-03T12:34:56Z',
            'quality': {
              'quality': {'name': 'HD-1080p'},
            },
            'data': {
              'size': 2147483648,
              'protocol': 'torrent',
              'downloadId': 'abc123',
              'movieMatchType': 'title',
            },
          }),
        );

        expect(find.text('Release.Name'), findsOneWidget);
        expect(find.text('Event'), findsOneWidget);
        await _scrollSheetUntilVisible(tester, find.text('Additional Data'));
        expect(find.text('Additional Data'), findsOneWidget);
        expect(find.text('Imported'), findsOneWidget);
        expect(find.text('Download Id'), findsOneWidget);
        expect(find.text('abc123'), findsOneWidget);
        expect(find.text('Date'), findsOneWidget);
        expect(find.textContaining('2026-04-03'), findsWidgets);
        expect(find.text('Protocol'), findsNothing);
        expect(find.text('Movie Match Type'), findsNothing);
      },
    );

    testWidgets('showHistoryDetail prefers embedded movie title', (
      tester,
    ) async {
      await _pumpDetailSheet(
        tester,
        showSheet: (context) => DetailSheets.showHistoryDetail(context, {
          'sourceTitle': 'Furiosa.2024.2160p.WEB-DL-GROUP',
          'eventType': 'downloadImported',
          'date': '2026-04-03T12:34:56Z',
          'movie': {'title': 'Furiosa', 'year': 2024},
        }),
      );

      expect(find.text('Furiosa (2024)'), findsOneWidget);
      expect(find.text('Furiosa.2024.2160p.WEB-DL-GROUP'), findsOneWidget);
    });

    testWidgets('showBlocklistDetail prefers embedded series title', (
      tester,
    ) async {
      await _pumpDetailSheet(
        tester,
        showSheet: (context) => DetailSheets.showBlocklistDetail(context, {
          'sourceTitle': 'Frieren.S01E03.1080p.WEB-DL-GROUP',
          'date': '2026-04-03T12:34:56Z',
          'protocol': 'torrent',
          'message': 'Rejected',
          'series': {'title': 'Frieren: Beyond Journey\'s End'},
        }),
      );

      expect(find.text("Frieren: Beyond Journey's End"), findsOneWidget);
      expect(find.text('Frieren.S01E03.1080p.WEB-DL-GROUP'), findsOneWidget);
    });

    testWidgets('showBlocklistDetail renders blocked release and messages', (
      tester,
    ) async {
      await _pumpDetailSheet(
        tester,
        showSheet: (context) => DetailSheets.showBlocklistDetail(context, {
          'sourceTitle': 'Bad.Release',
          'date': '2026-04-03T12:34:56Z',
          'protocol': 'torrent',
          'indexer': 'Indexer',
          'message': 'Rejected',
          'statusMessages': ['Still blocked'],
        }),
      );

      expect(find.text('Bad.Release'), findsOneWidget);
      expect(find.text('Blocked Release'), findsOneWidget);
      expect(find.text('Reason'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
      await _scrollSheetUntilVisible(tester, find.text('Status Messages'));
      expect(find.text('Status Messages'), findsOneWidget);
      expect(find.text('Still blocked'), findsOneWidget);
    });

    testWidgets('showWantedDetail renders series-specific fields', (
      tester,
    ) async {
      await _pumpDetailSheet(
        tester,
        showSheet: (context) => DetailSheets.showWantedDetail(context, {
          'title': 'Pilot',
          'series': {'title': 'Breaking Bad'},
          'seasonNumber': 1,
          'episodeNumber': 2,
          'airDateUtc': '2026-04-03T12:34:56Z',
          'monitored': true,
          'episodeFile': {
            'quality': {
              'quality': {'name': 'WEBDL-1080p'},
            },
          },
        }, ServiceType.series),
      );

      expect(find.text('Pilot'), findsWidgets);
      expect(find.text('Series'), findsOneWidget);
      expect(find.text('Breaking Bad'), findsOneWidget);
      expect(find.text('Episode Code'), findsOneWidget);
      expect(find.text('S01E02'), findsOneWidget);
      expect(find.text('Episode missing from disk'), findsOneWidget);
      expect(find.text('WEBDL-1080p'), findsOneWidget);
    });

    testWidgets('showWantedDetail renders movie-specific fields', (
      tester,
    ) async {
      await _pumpDetailSheet(
        tester,
        showSheet: (context) => DetailSheets.showWantedDetail(context, {
          'title': 'Cool Movie',
          'status': 'released',
          'year': 2024,
          'digitalRelease': '2026-04-05T12:34:56Z',
          'monitored': false,
          'movieFile': {
            'quality': {
              'quality': {'name': 'BluRay-1080p'},
            },
          },
        }, ServiceType.movies),
      );

      expect(find.text('Cool Movie'), findsWidgets);
      expect(find.text('Year'), findsOneWidget);
      expect(find.text('2024'), findsOneWidget);
      expect(find.text('Movie missing from disk'), findsOneWidget);
      expect(find.textContaining('2026-04-05'), findsOneWidget);
      expect(find.text('BluRay-1080p'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);
    });

    testWidgets('showWantedDetail renders music-specific fields', (
      tester,
    ) async {
      await _pumpDetailSheet(
        tester,
        showSheet: (context) => DetailSheets.showWantedDetail(context, {
          'title': 'Release Name',
          'artist': {'artistName': 'Artist Name'},
          'album': {'title': 'Album Name'},
          'releaseDate': '2026-04-07T12:34:56Z',
          'statistics': {'trackFileCount': 0},
        }, ServiceType.music),
      );

      expect(find.text('Release Name'), findsWidgets);
      expect(find.text('Artist'), findsOneWidget);
      expect(find.text('Artist Name'), findsOneWidget);
      expect(find.text('Album'), findsOneWidget);
      expect(find.text('Album Name'), findsOneWidget);
      expect(find.text('Album missing from disk'), findsOneWidget);
      expect(find.textContaining('2026-04-07'), findsOneWidget);
    });
  });
}

Future<void> _pumpDetailSheet(
  WidgetTester tester, {
  required Future<void> Function(BuildContext context) showSheet,
}) async {
  await tester.pumpWidget(
    MaterialApp(home: _DetailSheetLauncher(showSheet: showSheet)),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollSheetUntilVisible(
  WidgetTester tester,
  Finder finder,
) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.descendant(
      of: find.byType(DraggableScrollableSheet),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
}

class _DetailSheetLauncher extends StatefulWidget {
  const _DetailSheetLauncher({required this.showSheet});

  final Future<void> Function(BuildContext context) showSheet;

  @override
  State<_DetailSheetLauncher> createState() => _DetailSheetLauncherState();
}

class _DetailSheetLauncherState extends State<_DetailSheetLauncher> {
  bool _shown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_shown) {
      return;
    }

    _shown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      widget.showSheet(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('LauncherPage')));
  }
}
