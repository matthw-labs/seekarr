import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/theme.dart';
import 'package:seekarr/features/qbittorrent/domain/models/torrent.dart';
import 'package:seekarr/features/qbittorrent/presentation/widgets/torrent_tile.dart';

Torrent _torrent({
  String name = 'Ubuntu 24.04 LTS',
  String state = 'downloading',
  int dlSpeed = 1024,
  int upSpeed = 256,
  double progress = 0.42,
}) {
  return Torrent.fromJson({
    'hash': 'abc123',
    'name': name,
    'size': 1024 * 1024 * 1024,
    'progress': progress,
    'state': state,
    'dlspeed': dlSpeed,
    'upspeed': upSpeed,
    'eta': 3600,
    'category': 'linux',
    'tracker': 'https://tracker.example.com/announce',
    'tags': ['iso'],
    'ratio': 1.5,
    'added_on': 1700000000,
    'completed': 512,
    'num_leechs': 3,
    'num_seeds': 7,
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  ThemeData? theme,
  Size? size,
}) async {
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.lightTheme(),
      home: Scaffold(body: ListView(children: [child])),
    ),
  );
}

void main() {
  group('TorrentTile', () {
    // Regression guard for the P0 found in QA: the tile passed both
    // `borderRadius` and `shape` to Material, which trips
    // `!(shape != null && borderRadius != null)` and blanked the entire
    // qBittorrent list. Only mounting the widget catches a build assertion —
    // the provider tests never did.
    testWidgets('builds without tripping a Material assertion', (tester) async {
      await _pump(tester, TorrentTile(torrent: _torrent()));

      expect(tester.takeException(), isNull);
      expect(find.byType(TorrentTile), findsOneWidget);
      expect(find.text('Ubuntu 24.04 LTS'), findsOneWidget);
    });

    testWidgets('builds selected, in both themes', (tester) async {
      for (final theme in [AppTheme.lightTheme(), AppTheme.darkTheme()]) {
        await _pump(
          tester,
          TorrentTile(torrent: _torrent(), selected: true),
          theme: theme,
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('builds across every torrent state', (tester) async {
      const states = [
        'downloading',
        'stalledDL',
        'uploading',
        'stalledUP',
        'pausedDL',
        'stoppedDL',
        'queuedDL',
        'checkingDL',
        'error',
        'missingFiles',
        'moving',
      ];
      for (final state in states) {
        await _pump(
          tester,
          TorrentTile(torrent: _torrent(state: state, dlSpeed: 0, upSpeed: 0)),
        );
        expect(tester.takeException(), isNull, reason: state);
      }
    });

    testWidgets('forwards tap and long-press', (tester) async {
      var taps = 0;
      var longPresses = 0;
      await _pump(
        tester,
        TorrentTile(
          torrent: _torrent(),
          onTap: () => taps++,
          onLongPress: () => longPresses++,
        ),
      );

      await tester.tap(find.byType(TorrentTile));
      await tester.pumpAndSettle();
      expect(taps, 1);

      await tester.longPress(find.byType(TorrentTile));
      await tester.pumpAndSettle();
      expect(longPresses, 1);
    });

    testWidgets('survives a long name on a narrow screen', (tester) async {
      await _pump(
        tester,
        TorrentTile(torrent: _torrent(name: 'A' * 240)),
        size: const Size(320, 640),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a large text scale', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: Scaffold(
              body: ListView(children: [TorrentTile(torrent: _torrent())]),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
