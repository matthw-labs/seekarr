import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/presentation/discover_detail_extras_provider.dart';
import 'package:cupola/features/discover/presentation/discover_detail_screen.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_seasons_list.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

/// Screen-level coverage for the Seerr detail page.
///
/// This was the only one of the eight detail screens with none, so its
/// distinguishing decisions — `Keywords` rather than `Tags`, the certification as
/// plain text in the metadata line rather than a chip, a lazy Seasons sliver in
/// region 3, and pull-to-refresh — were verified by the analyzer alone.
const _movieId = 603;
const _tvId = 1396;

Map<String, dynamic> _movie({
  String certification = 'R',
  List<Map<String, dynamic>> keywords = const [
    {'name': 'dystopia'},
  ],
  List<Map<String, dynamic>> genres = const [
    {'name': 'Action'},
  ],
}) => <String, dynamic>{
  'title': 'The Matrix',
  'overview': 'A hacker learns the truth.',
  'releaseDate': '1999-03-31',
  'runtime': 136,
  'genres': genres,
  'keywords': keywords,
  'releases': {
    'results': [
      {
        'iso_3166_1': 'US',
        'release_dates': [
          {'certification': certification, 'release_date': '1999-03-31'},
        ],
      },
    ],
  },
};

Map<String, dynamic> _tv({int seasonCount = 3}) => <String, dynamic>{
  'name': 'Breaking Bad',
  'overview': 'A teacher turns to crime.',
  'firstAirDate': '2008-01-20',
  'genres': [
    {'name': 'Crime'},
  ],
  'keywords': [
    {'name': 'new mexico'},
  ],
  'seasons': [
    for (var i = 1; i <= seasonCount; i++)
      {
        'seasonNumber': i,
        'name': 'Season $i',
        'episodeCount': 7,
        'episodes': [
          for (var e = 1; e <= 7; e++)
            {
              'episodeNumber': e,
              'name': 'Episode $e',
              'airDate': '2008-01-2$e',
            },
        ],
      },
  ],
};

Future<int> _pump(
  WidgetTester tester, {
  required FutureOr<Map<String, dynamic>> Function() details,
  String mediaType = 'movie',
  int mediaId = _movieId,
  void Function(int)? onLoad,
}) async {
  var loads = 0;
  await tester.pumpWidget(
    ProviderScope(
      // Riverpod 3 re-runs a failed provider on its own backoff schedule, which
      // would make any load count non-deterministic.
      retry: (retryCount, error) => null,
      overrides: [
        discoverDetailProvider.overrideWith((ref, arg) {
          loads++;
          onLoad?.call(loads);
          return details();
        }),
        // The extras provider reaches for Radarr/Sonarr and the settings store;
        // stubbed so the page renders offline with the library check resolved.
        discoverDetailExtrasProvider.overrideWith(
          (ref, arg) async =>
              (isInLibrary: false, libraryCheckDone: true, lookupRatings: null),
        ),
        regionProvider.overrideWithValue('US'),
      ],
      child: MaterialApp(
        home: DiscoverDetailScreen(
          mediaId: mediaId,
          mediaType: mediaType,
          heroTag: 'discover_${mediaType}_$mediaId',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return loads;
}

void main() {
  group('DiscoverDetailScreen', () {
    testWidgets('TMDB keywords are labelled Keywords, never Tags', (
      tester,
    ) async {
      await _pump(tester, details: () => _movie());

      // 'Tags' names a real Radarr/Sonarr concept this app also surfaces, so
      // heading TMDB keywords with it asserted something false about the
      // user's server.
      final labels = tester
          .widgetList<MediaDetailSectionLabel>(
            find.byType(MediaDetailSectionLabel),
          )
          .map((label) => label.label)
          .toList();

      expect(labels, contains('Keywords'));
      expect(labels, contains('Genres'));
      expect(labels, isNot(contains('Tags')));
      // Rendered uppercase for the eye, sentence case in the argument.
      expect(find.text('KEYWORDS'), findsOneWidget);
    });

    testWidgets('the certification is metadata text, not a chip', (
      tester,
    ) async {
      await _pump(tester, details: () => _movie(certification: 'R'));

      // As a bordered chip beside the genres it was indistinguishable from one,
      // so an "R" read as a genre called R.
      expect(find.text('R'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              (widget is TagChip && widget.text == 'R') ||
              (widget is GenreChip && widget.genre == 'R'),
        ),
        findsNothing,
      );

      final line = tester.widget<MediaDetailPosterRow>(
        find.byType(MediaDetailPosterRow),
      );
      expect(line.metadataItems, contains('R'));
      // One voice for runtime, shared with the Radarr page: not `136min`.
      expect(line.metadataItems, contains('2h 16m'));
    });

    testWidgets('a show gets a lazy Seasons sliver in region 3', (
      tester,
    ) async {
      await _pump(
        tester,
        details: () => _tv(),
        mediaType: 'tv',
        mediaId: _tvId,
      );

      expect(find.byType(DiscoverSeasonsList), findsOneWidget);

      final body = tester
          .widget<MediaDetailView>(find.byType(MediaDetailView))
          .body;
      final seasons = body.operate.single;

      // `.lazy`, so a 40-season show builds the rows on screen rather than every
      // episode of every season — and region 3 puts it above the synopsis.
      expect(seasons.label, 'Seasons');
      expect(seasons.sliver, isNotNull);
      expect(seasons.box, isNull);
      expect(body.synopsis.single.label, 'Overview');
    });

    testWidgets('a movie has no Seasons region at all', (tester) async {
      await _pump(tester, details: () => _movie());

      final body = tester
          .widget<MediaDetailView>(find.byType(MediaDetailView))
          .body;
      // Omitted, not an empty labelled slot spending 24pt of air on nothing.
      expect(body.operate, isEmpty);
    });

    testWidgets('regions are emitted in canonical order', (tester) async {
      await _pump(
        tester,
        details: () => _tv(),
        mediaType: 'tv',
        mediaId: _tvId,
      );

      final body = tester
          .widget<MediaDetailView>(find.byType(MediaDetailView))
          .body;

      // Region 3 (the manifest) above region 4 (the prose), then the reference
      // block in its own fixed internal order, then everything about other
      // titles. A variant omits a region; it never reorders one.
      expect(body.slots.map((slot) => slot.label).toList(), [
        'Seasons',
        'Overview',
        'Details',
        'Genres',
        'Keywords',
        'Where to watch',
      ]);
    });

    testWidgets('pull-to-refresh re-runs the detail load exactly once', (
      tester,
    ) async {
      var loads = 0;
      await _pump(
        tester,
        details: () => _movie(),
        onLoad: (count) => loads = count,
      );
      expect(loads, 1);

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 320),
        1000,
      );
      await tester.pumpAndSettle();

      expect(loads, 2);
      // One claimant on the gesture: the spine owns the indicator, so a screen
      // cannot add a second by wrapping its own.
      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    testWidgets('a failed lookup names Seerr and offers a way out', (
      tester,
    ) async {
      final loads = await _pump(
        tester,
        details: () =>
            Future<Map<String, dynamic>>.error(Exception('Connection refused')),
      );

      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.textContaining('Connection refused'), findsOneWidget);
      expect(loads, 1);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.byType(AppErrorState), findsOneWidget);
    });

    testWidgets('the page is lit by Seerr and nothing else', (tester) async {
      await _pump(tester, details: () => _movie());

      final accent = tester
          .widget<MediaDetailView>(find.byType(MediaDetailView))
          .accent;

      // One screen, one accent: every region label and the ambient room read
      // this single value.
      for (final label in tester.widgetList<MediaDetailSectionLabel>(
        find.byType(MediaDetailSectionLabel),
      )) {
        expect(label.accent, accent);
      }
    });
  });
}
