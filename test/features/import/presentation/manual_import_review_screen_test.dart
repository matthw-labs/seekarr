import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/theme.dart';
import 'package:seekarr/features/import/data/manual_import_service.dart';
import 'package:seekarr/features/import/presentation/manual_import_review_screen.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_api_client.dart';

class _FakeManualImportService extends ManualImportService {
  _FakeManualImportService(FakeApiClient client, ServiceKey service)
    : super(client: client, service: service);
}

Map<String, dynamic> _episode({
  required String name,
  required String series,
  required int season,
  required int episode,
  required String episodeTitle,
  List<Map<String, dynamic>> rejections = const [],
  // Sonarr reports the library file an already-imported release belongs to;
  // anything above 0 means "I have this one".
  int episodeFileId = 0,
}) {
  return {
    'path': '/downloads/$name',
    // The \*arrs put the basename *without* the extension in `name`, so the
    // fixture does too — anything reading `name` as "the file" shows up.
    'name': name.replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), ''),
    // Deliberately disagrees with the matched episode below on some rows, so a
    // row that displays parsed data instead of matched data fails.
    'seasonNumber': 1,
    'size': 2147483648,
    'series': {'id': series.hashCode, 'title': series},
    'episodes': [
      {
        'id': episode + season * 100,
        'seasonNumber': season,
        'episodeNumber': episode,
        'title': episodeTitle,
      },
    ],
    'quality': {
      'quality': {'id': 3, 'name': 'WEBDL-2160p'},
    },
    if (episodeFileId > 0) 'episodeFileId': episodeFileId,
    if (rejections.isNotEmpty) 'rejections': rejections,
  };
}

/// A Sonarr scan of a realistic mixed downloads folder: two series with several
/// episodes each, an unmatched episode, an unmatched playlist, and a song.
FakeApiClient _scanClient() {
  final client = FakeApiClient();
  client.getResponseQueue.addAll([
    [
      {'id': 1, 'path': '/downloads', 'accessible': true},
    ],
    {'parent': null, 'directories': <dynamic>[], 'files': <dynamic>[]},
    [
      _episode(
        name: 'Boruto.S01E11.1080p.WEB-DL.mkv',
        series: 'Boruto',
        season: 1,
        episode: 11,
        episodeTitle: 'The Pain',
      ),
      _episode(
        name: 'Boruto.S01E12.1080p.WEB-DL.mkv',
        series: 'Boruto',
        season: 1,
        episode: 12,
        episodeTitle: 'The Vow',
      ),
      _episode(
        name: 'The.Pitt.S02E01.2160p.HMAX.WEB-DL.mkv',
        series: 'The Pitt',
        season: 2,
        episode: 1,
        episodeTitle: '7:00 A.M.',
      ),
      _episode(
        name: 'The.Pitt.S01E01.2160p.DVHDR.mkv',
        series: 'The Pitt',
        season: 1,
        episode: 1,
        episodeTitle: '6:00 A.M.',
        rejections: [
          {
            'reason': 'Not an upgrade for existing episode file',
            'type': 'permanent',
          },
        ],
      ),
      // A series with exactly one file: it gets no group header, so the row
      // itself has to carry both matched names.
      _episode(
        name: 'Daredevil.Rinascita.S01E06.2160p.WEB-DL.mkv',
        series: 'Daredevil: Born Again',
        season: 1,
        episode: 6,
        episodeTitle: 'Excessive Force',
      ),
      {
        'path': '/downloads/Supergirl.2026.WEB-DL.mkv',
        'name': 'Supergirl.2026.WEB-DL',
        'size': 20100000000,
        'rejections': [
          {'reason': 'Unable to determine series', 'type': 'permanent'},
        ],
      },
      {
        'path': '/downloads/200-linkin_park-from_zero.m3u',
        'name': '200-linkin_park-from_zero.m3u',
        'size': 329,
      },
      {
        'path': '/downloads/Green Day - 39-Smooth.mp3',
        'name': 'Green Day - 39-Smooth.mp3',
        'size': 8000000,
      },
    ],
  ]);
  return client;
}

/// The same folder, plus one episode Sonarr has already taken into the library.
///
/// It sits between two of Boruto's ready episodes on purpose: an imported file's
/// job on this screen is to explain the gap where it is, so the tests assert it
/// renders *inside* that group rather than in a section of its own.
FakeApiClient _scanClientWithImported() {
  final client = FakeApiClient();
  client.getResponseQueue.addAll([
    [
      {'id': 1, 'path': '/downloads', 'accessible': true},
    ],
    {'parent': null, 'directories': <dynamic>[], 'files': <dynamic>[]},
    [
      _episode(
        name: 'Boruto.S01E10.1080p.WEB-DL.mkv',
        series: 'Boruto',
        season: 1,
        episode: 10,
        episodeTitle: 'The Ghost Incident',
        episodeFileId: 5001,
      ),
      _episode(
        name: 'Boruto.S01E11.1080p.WEB-DL.mkv',
        series: 'Boruto',
        season: 1,
        episode: 11,
        episodeTitle: 'The Pain',
      ),
      _episode(
        name: 'Boruto.S01E12.1080p.WEB-DL.mkv',
        series: 'Boruto',
        season: 1,
        episode: 12,
        episodeTitle: 'The Vow',
      ),
    ],
  ]);
  return client;
}

Future<void> _pumpReview(
  WidgetTester tester, {
  FakeApiClient? client,
  ThemeData? theme,
}) async {
  // A tall viewport so the whole grouped list is laid out: the list is lazily
  // built, so anything below the fold genuinely does not exist to a finder.
  tester.view.physicalSize = const Size(500, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        manualImportServiceProvider(ServiceKey.sonarr).overrideWith(
          (ref) => _FakeManualImportService(
            client ?? _scanClient(),
            ServiceKey.sonarr,
          ),
        ),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.darkTheme(),
        home: const ManualImportReviewScreen(service: ServiceKey.sonarr),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('sorts files into the four buckets the user must act on', (
    tester,
  ) async {
    await _pumpReview(tester);

    expect(find.bySemanticsLabel('Step 2 of 3: Review'), findsOneWidget);

    // Five ready episodes, one genuinely unmatched file. The playlist and the
    // song are not counted as needing a match — they are not Sonarr's business.
    expect(find.text('5 ready'), findsOneWidget);
    expect(find.text('1 needs a match'), findsOneWidget);
    expect(find.text('2 other'), findsOneWidget);
  });

  testWidgets('groups ready files by series with a per-group select-all', (
    tester,
  ) async {
    await _pumpReview(tester);

    // Group headers name the series; the episodes sit under them.
    expect(find.text('Boruto'), findsOneWidget);
    expect(find.text('The Pitt'), findsOneWidget);

    // Every row states its episode code and name, so the match is checkable.
    expect(find.text('S01E11'), findsOneWidget);
    expect(find.text('The Pain'), findsOneWidget);
    expect(find.text('S02E01'), findsOneWidget);
    expect(find.text('7:00 A.M.'), findsOneWidget);

    // The group's own checkbox takes every file of that series at once.
    expect(
      find.bySemanticsLabel('Select all 2 files of Boruto'),
      findsOneWidget,
    );
  });

  testWidgets('filtering narrows the list to one series', (tester) async {
    await _pumpReview(tester);

    await tester.enterText(find.byType(TextField), 'boruto');
    await tester.pump();

    expect(find.text('Boruto'), findsOneWidget);
    expect(find.text('The Pitt'), findsNothing);
    expect(find.text('The Pain'), findsOneWidget);
    expect(find.text('7:00 A.M.'), findsNothing);
    // The unmatched Supergirl file is filtered out too.
    expect(find.text('Unable to determine series'), findsNothing);
  });

  testWidgets('a filtered view can take only what it shows', (tester) async {
    await _pumpReview(tester);

    await tester.enterText(find.byType(TextField), 'boruto');
    await tester.pump();

    // The counts above still describe the whole scan, so the slice says so.
    expect(find.text('Showing 2 of 8 files'), findsOneWidget);

    // Every ready file starts selected; narrowing to Boruto and taking only
    // those is the whole point of the filter.
    expect(find.text('Import 5 files'), findsOneWidget);
    await tester.tap(find.text('Import only these 2'));
    await tester.pump();
    expect(find.text('Import 2 files'), findsOneWidget);
  });

  testWidgets('a filter with no hits says so instead of showing nothing', (
    tester,
  ) async {
    await _pumpReview(tester);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump();

    expect(find.text('No files match "zzzz"'), findsOneWidget);
  });

  group('every ready row states matched identity then the raw file', () {
    testWidgets('the chip and the name beside it are the matched values', (
      tester,
    ) async {
      await _pumpReview(tester);

      // The Pitt S02E01 is matched to season 2 while the payload's parsed
      // `seasonNumber` says 1, so an S01 chip here would mean the row is
      // rendering the guess rather than the match.
      expect(find.text('S02E01'), findsOneWidget);
      expect(find.text('7:00 A.M.'), findsOneWidget);
    });

    testWidgets('the second line is the raw filename, extension included', (
      tester,
    ) async {
      await _pumpReview(tester);

      // Asserted through the accessible value rather than the painted string,
      // which is middle-elided to fit: the row must carry the real file, not
      // the service's extension-stripped `name`.
      final row = tester.getSemantics(
        find.bySemanticsLabel(RegExp('^The Pitt, S02E01')).first,
      );
      expect(row.value, contains('The.Pitt.S02E01.2160p.HMAX.WEB-DL.mkv'));
    });

    testWidgets('a row standing alone still names its series and episode', (
      tester,
    ) async {
      await _pumpReview(tester);

      // Daredevil has a single file, so it gets no group header — the row has
      // to carry both matched names itself, and the filename stays line two.
      expect(
        find.text('Daredevil: Born Again · Excessive Force'),
        findsOneWidget,
      );
    });
  });

  testWidgets(
    'the row sheet is titled by the match and subtitled by the file',
    (tester) async {
      await _pumpReview(tester);

      await tester.tap(find.text('7:00 A.M.'));
      await tester.pumpAndSettle();

      // Title: the matched series plus the matched episode code, nothing else.
      expect(find.text('The Pitt · S02E01'), findsOneWidget);
      // Subtitle: the raw file, nothing else.
      expect(
        find.text('The.Pitt.S02E01.2160p.HMAX.WEB-DL.mkv'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a warning on a ready file spells out the service reason', (
    tester,
  ) async {
    await _pumpReview(tester);

    // Previously this was an unexplained amber triangle on a "Ready" badge.
    expect(
      find.text('Not an upgrade for existing episode file'),
      findsOneWidget,
    );
  });

  testWidgets('shared assignment is offered only for files the user picked', (
    tester,
  ) async {
    await _pumpReview(tester);

    // With nothing ticked there is no bulk action at all — the old "Fix all"
    // applied one series to every unmatched file, playlists included.
    expect(find.textContaining('Assign'), findsNothing);

    await tester.tap(
      find.bySemanticsLabel(
        'Assign Supergirl.2026.WEB-DL.mkv together with other files',
      ),
    );
    await tester.pump();

    // One file is not a batch: the hint explains what a second tick unlocks.
    expect(
      find.text('Tick another file of the same title to assign them together.'),
      findsOneWidget,
    );
  });

  testWidgets('the group select-all selects exactly that series', (
    tester,
  ) async {
    await _pumpReview(tester);

    // Nothing is preselected here: every ready file already has a match, so
    // they all start selected. Clear first, then take one group.
    await tester.tap(find.byTooltip('Clear selection'));
    await tester.pump();
    expect(find.text('Nothing selected to import'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.bySemanticsLabel('Select all 2 files of Boruto'),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.pump();

    expect(find.text('Import 2 files'), findsOneWidget);
  });

  group('the count row is the filter', () {
    testWidgets('a count hides its own files and stays legible', (
      tester,
    ) async {
      await _pumpReview(tester);

      expect(find.text('Unable to determine series'), findsOneWidget);

      await tester.tap(find.text('1 needs a match'));
      await tester.pump();

      // The rows are gone — which is what makes a folder with hundreds of
      // unmatched files navigable — while the count itself stays on screen, so
      // what is hidden is still stated rather than merely absent.
      expect(find.text('1 needs a match'), findsOneWidget);
      expect(find.text('Needs attention'), findsNothing);
      expect(find.text('Unable to determine series'), findsNothing);
      // The matched list is still reachable behind it.
      expect(find.text('Matched files'), findsOneWidget);
    });

    testWidgets('the unimportable files start hidden behind their count', (
      tester,
    ) async {
      await _pumpReview(tester);

      // Two files Sonarr cannot import: counted, not listed.
      expect(find.text('2 other'), findsOneWidget);
      expect(find.text('Other files'), findsNothing);
      expect(find.text('Showing 6 of 8 files'), findsOneWidget);

      await tester.tap(find.text('2 other'));
      await tester.pump();

      expect(find.text('Other files'), findsOneWidget);
      expect(find.text('Showing 6 of 8 files'), findsNothing);
    });

    testWidgets('switching every count off offers the way back', (
      tester,
    ) async {
      await _pumpReview(tester);

      await tester.tap(find.text('5 ready'));
      await tester.pump();
      await tester.tap(find.text('1 needs a match'));
      await tester.pump();

      expect(find.text('Every file is filtered out'), findsOneWidget);

      await tester.tap(find.text('Show all 8 files'));
      await tester.pump();

      expect(find.text('Matched files'), findsOneWidget);
      expect(find.text('Other files'), findsOneWidget);
    });

    testWidgets('the counts flow along the row instead of stacking', (
      tester,
    ) async {
      await _pumpReview(tester);

      // An `Align` — or a `Container` with an `alignment` — expands to the
      // widest constraint it is handed, and inside a `Wrap` that is the whole
      // row: every chip took a line of its own and the row read as a stack of
      // buttons. Geometry, because no finder can see that.
      final ready = tester.getRect(find.text('5 ready'));
      final attention = tester.getRect(find.text('1 needs a match'));
      expect(attention.center.dy, closeTo(ready.center.dy, 1));
      expect(attention.left, greaterThan(ready.right));
    });

    testWidgets('each count carries a full touch target', (tester) async {
      await _pumpReview(tester);

      // The pill keeps its badge proportions; the hit box does not.
      expect(
        tester.getSize(find.bySemanticsLabel('5 files ready to import')).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('each count is spoken as a sentence, not as a pill', (
      tester,
    ) async {
      await _pumpReview(tester);

      // "1 needs a match files" is what reading the painted label out loud
      // would produce.
      expect(find.bySemanticsLabel('1 file needs a match'), findsOneWidget);
      expect(find.bySemanticsLabel('5 files ready to import'), findsOneWidget);
    });
  });

  group('files already in the library', () {
    testWidgets('are listed by default, inside the group they belong to', (
      tester,
    ) async {
      await _pumpReview(tester, client: _scanClientWithImported());

      // No section of its own, and no toggle needed to see it.
      expect(find.text('Already imported'), findsNothing);
      expect(find.text('1 imported'), findsOneWidget);
      expect(find.text('Imported'), findsOneWidget);
      expect(
        find.text('2 of 2 selected · 1 already in the library'),
        findsOneWidget,
      );

      // In broadcast order among its siblings, which is the whole point: the
      // row explains the gap where the gap actually is.
      final imported = tester.getTopLeft(find.text('S01E10')).dy;
      final nextReady = tester.getTopLeft(find.text('S01E11')).dy;
      final groupHeader = tester.getTopLeft(find.text('Boruto')).dy;
      expect(groupHeader, lessThan(imported));
      expect(imported, lessThan(nextReady));
    });

    testWidgets('can be sent again, and say what that will do', (tester) async {
      await _pumpReview(tester, client: _scanClientWithImported());

      // Never preselected: replacing a file in the library is a decision.
      expect(find.text('Import 2 files'), findsOneWidget);

      await tester.tap(
        find.bySemanticsLabel(RegExp('^Import Boruto S01E10 again')),
      );
      await tester.pump();

      expect(find.text('Import 3 files'), findsOneWidget);
      expect(find.text('Re-import'), findsOneWidget);
      expect(
        find.text('Re-importing replaces the copy Sonarr already holds.'),
        findsOneWidget,
      );
      expect(
        find.text('2 of 2 selected · 1 of 1 being re-imported'),
        findsOneWidget,
      );
    });

    testWidgets('are never swept in by the group select-all', (tester) async {
      await _pumpReview(tester, client: _scanClientWithImported());

      await tester.tap(find.byTooltip('Clear selection'));
      await tester.pump();

      // The group holds three files; only the two not in the library are the
      // select-all's business.
      expect(
        find.bySemanticsLabel('Select all 2 files of Boruto'),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: find.bySemanticsLabel('Select all 2 files of Boruto'),
          matching: find.byType(Checkbox),
        ),
      );
      await tester.pump();

      expect(find.text('Import 2 files'), findsOneWidget);
    });

    testWidgets('can be filtered out by their own count', (tester) async {
      await _pumpReview(tester, client: _scanClientWithImported());

      await tester.tap(find.text('1 imported'));
      await tester.pump();

      expect(find.text('Imported'), findsNothing);
      expect(find.text('S01E10'), findsNothing);
      // The count survives the hiding, so the file is still accounted for.
      expect(find.text('1 imported'), findsOneWidget);
    });
  });

  testWidgets('a card title never wraps onto a second line', (tester) async {
    // A wrapping title pushed the filename and the technical line down and left
    // the status badge floating: the card's geometry came apart on any episode
    // name longer than the row.
    await _pumpReview(tester);

    final titles = tester
        .widgetList<Text>(find.text('Daredevil: Born Again · Excessive Force'))
        .followedBy(tester.widgetList<Text>(find.text('The Pain')))
        .followedBy(tester.widgetList<Text>(find.text('7:00 A.M.')));

    expect(titles, isNotEmpty);
    for (final title in titles) {
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
    }
  });

  testWidgets('renders in the light theme without exception', (tester) async {
    await _pumpReview(tester, theme: AppTheme.lightTheme());
    expect(find.text('Matched files'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives an accessibility text size', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pumpReview(tester);
    expect(find.text('Matched files'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
