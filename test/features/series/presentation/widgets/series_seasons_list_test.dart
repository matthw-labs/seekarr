import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/series/domain/models/sonarr_episode.dart';
import 'package:seekarr/features/series/domain/models/sonarr_season.dart';
import 'package:seekarr/features/series/presentation/widgets/series_seasons_list.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

void main() {
  group('SeriesSeasonsList', () {
    testWidgets('renders the empty state, in the service accent, with no '
        'seasons', (tester) async {
      await _pump(tester, seasons: const [], episodes: const []);

      expect(find.text('No seasons yet'), findsOneWidget);
      final emptyState = tester.widget<AppEmptyState>(
        find.byType(AppEmptyState),
      );
      expect(emptyState.accentColor, ServiceKey.sonarr.accent);
      // The bare `Text('No seasons found.')` this replaced.
      expect(find.text('No seasons found.'), findsNothing);
    });

    testWidgets('builds only a bounded number of rows for a 250-episode '
        'season', (tester) async {
      await _pump(
        tester,
        seasons: [_season(1, episodeCount: 250, fileCount: 250)],
        episodes: [
          for (var number = 1; number <= 250; number++)
            _episode(id: number, episodeNumber: number, title: 'Ep $number'),
        ],
      );

      final built = find.byType(MediaChildTile).evaluate().length;
      expect(built, greaterThan(0));
      // The old list was a `Column` inside one `SliverToBoxAdapter`: all 250
      // rows were instantiated to show the eight on screen.
      expect(built, lessThan(40));
      expect(find.text('Ep 1'), findsOneWidget);
      expect(find.text('Ep 250'), findsNothing);
    });

    testWidgets('every row carries decidable metadata and a spoken status', (
      tester,
    ) async {
      await _pump(
        tester,
        seasons: [_season(1, episodeCount: 2, fileCount: 1)],
        episodes: [
          _episode(
            id: 1,
            episodeNumber: 1,
            title: 'Winter Is Coming',
            airDate: '2011-04-17',
          ),
          _episode(
            id: 2,
            episodeNumber: 2,
            title: 'The Kingsroad',
            hasFile: false,
            airDate: '2011-04-24',
          ),
        ],
      );

      // The air date is the fact the row used to be missing entirely, in the
      // detail pages' voice rather than the arr web UI's ISO one.
      expect(find.textContaining('Apr 17, 2011'), findsOneWidget);
      expect(find.textContaining('2011-04-17'), findsNothing);

      // State by colour alone is the defect: the tone dot is decoration, and
      // the word rides in the metadata line beside it.
      expect(find.textContaining('Missing'), findsOneWidget);
      expect(find.byType(StatusBadge), findsNWidgets(3));

      expect(
        tester.getSemantics(find.byType(MediaChildTile).last),
        containsSemantics(value: 'Missing'),
      );
      expect(
        tester.getSemantics(find.byType(MediaChildTile).first),
        containsSemantics(label: 'Episode 1, Winter Is Coming, Apr 17, 2011'),
      );
    });

    testWidgets('an unaired episode reads Not Released, never Missing', (
      tester,
    ) async {
      final airsAt = DateTime.now().add(const Duration(days: 30));

      await _pump(
        tester,
        seasons: [_season(1, episodeCount: 1, fileCount: 1, total: 2)],
        episodes: [
          _episode(
            id: 2,
            episodeNumber: 2,
            title: 'Next Week',
            hasFile: false,
            airDate: airsAt.toIso8601String(),
          ),
        ],
      );

      expect(find.textContaining('Not Released'), findsOneWidget);
      expect(find.textContaining('Missing'), findsNothing);
    });

    testWidgets('the search affordance only appears on rows a search would '
        'change', (tester) async {
      await _pump(
        tester,
        seasons: [_season(1, episodeCount: 2, fileCount: 1)],
        episodes: [
          _episode(id: 1, episodeNumber: 1, airDate: '2011-04-17'),
          _episode(
            id: 2,
            episodeNumber: 2,
            hasFile: false,
            airDate: '2011-04-24',
          ),
        ],
      );

      // One for the missing episode, one for the season header — not the same
      // magnifier repeated down every row of a finished season.
      expect(find.byType(MediaSearchPopupMenu), findsNWidgets(2));
      expect(find.byTooltip('Search episode 2'), findsOneWidget);
      expect(find.byTooltip('Search episode 1'), findsNothing);
      expect(find.byTooltip('Search Season 1'), findsOneWidget);
    });

    testWidgets('the season selector is a 20dp pill, not a full-radius chip', (
      tester,
    ) async {
      await _pump(
        tester,
        seasons: [_season(1), _season(2)],
        episodes: [_episode(id: 1, episodeNumber: 1)],
      );

      // `ChoiceChip`'s default shape is full radius, which this system reserves
      // for non-interactive metadata.
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(SelectionPills<int>), findsOneWidget);

      final radii = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(SelectionPills<int>),
              matching: find.byType(Container),
            ),
          )
          .map((container) => (container.decoration as BoxDecoration?))
          .whereType<BoxDecoration>()
          .map((decoration) => decoration.borderRadius)
          .toList();

      expect(radii, isNotEmpty);
      for (final radius in radii) {
        expect(radius, AppRadius.borderRadiusPill);
        expect(radius, isNot(AppRadius.borderRadiusFull));
      }
    });

    testWidgets('selecting another season swaps the episodes', (tester) async {
      await _pump(
        tester,
        seasons: [_season(1), _season(2)],
        episodes: [
          _episode(id: 1, seasonNumber: 1, episodeNumber: 1, title: 'Pilot'),
          _episode(
            id: 2,
            seasonNumber: 2,
            episodeNumber: 1,
            title: 'Second Start',
          ),
        ],
      );

      expect(find.text('Pilot'), findsOneWidget);
      expect(find.text('Second Start'), findsNothing);

      await tester.tap(find.text('S2'));
      await tester.pumpAndSettle();

      expect(find.text('Second Start'), findsOneWidget);
      expect(find.text('Pilot'), findsNothing);
      expect(find.text('Season 2'), findsOneWidget);
    });

    testWidgets('a long run of seasons gets a count and a jump-to picker', (
      tester,
    ) async {
      await _pump(
        tester,
        seasons: [for (var number = 1; number <= 40; number++) _season(number)],
        episodes: [
          _episode(
            id: 40,
            seasonNumber: 40,
            episodeNumber: 1,
            title: 'The Fortieth',
          ),
        ],
      );

      // The count the unbounded horizontal rail never had. It rides in the
      // accessible name and the tooltip rather than in a visible caption, so the
      // control can sit at the end of the rail without eating the width the
      // pills need.
      // `byTooltip` is the assertion that matters: Flutter's `Tooltip` is what
      // supplies the icon button's accessible name, so finding it proves both
      // the hover affordance and the screen-reader name in one go.
      final picker = find.byTooltip('All 40 seasons');
      expect(picker, findsOneWidget);

      await tester.tap(picker);
      await tester.pumpAndSettle();

      // Every season is reachable, each with its status in words rather than as
      // an unlabelled glyph inside a pill.
      expect(find.text('Season 40'), findsOneWidget);
      await tester.ensureVisible(find.text('Season 40'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Season 40'));
      await tester.pumpAndSettle();

      expect(find.text('The Fortieth'), findsOneWidget);
    });

    testWidgets('specials sort last', (tester) async {
      await _pump(
        tester,
        seasons: [_season(0), _season(1), _season(2)],
        episodes: [_episode(id: 1, seasonNumber: 1, episodeNumber: 1)],
      );

      expect(
        tester.getTopLeft(find.text('S1')).dx,
        lessThan(tester.getTopLeft(find.text('Sp')).dx),
      );
      // The first season is selected, not the specials.
      expect(find.text('Season 1'), findsOneWidget);
    });

    testWidgets('a failed episode fetch offers a retry', (tester) async {
      var retries = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SeriesSeasonsList(
                  seasons: [_season(1)],
                  episodesAsync: AsyncValue<List<SonarrEpisode>>.error(
                    Exception('boom'),
                    StackTrace.empty,
                  ),
                  onSearchSeason: (_) {},
                  onInteractiveSearchSeason: (_) {},
                  onSearchEpisode: (_) {},
                  onInteractiveSearchEpisode: (_, _) {},
                  searchingSeasons: const {},
                  searchingEpisodes: const {},
                  onRetryEpisodes: () => retries++,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text("Couldn't load Sonarr"), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(retries, 1);
    });

    testWidgets('a pending episode fetch shows a labelled skeleton', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SeriesSeasonsList(
                  seasons: [_season(1)],
                  episodesAsync:
                      const AsyncValue<List<SonarrEpisode>>.loading(),
                  onSearchSeason: (_) {},
                  onInteractiveSearchSeason: (_) {},
                  onSearchEpisode: (_) {},
                  onInteractiveSearchEpisode: (_, _) {},
                  searchingSeasons: const {},
                  searchingEpisodes: const {},
                ),
              ],
            ),
          ),
        ),
      );
      // Never `pumpAndSettle` here: the shimmer sweep repeats indefinitely.
      await tester.pump();

      expect(find.byType(ShimmerList), findsOneWidget);
      // An unlabelled skeleton reads as an empty screen.
      expect(find.semantics.byLabel('Loading episodes'), findsOneWidget);
    });

    testWidgets('a season with no episodes gets an empty state, not a bare '
        'sentence', (tester) async {
      await _pump(
        tester,
        seasons: [_season(1, episodeCount: 0, fileCount: 0, total: 0)],
        episodes: const [],
      );

      expect(find.byType(AppEmptyState), findsOneWidget);
      expect(find.text('No episodes'), findsOneWidget);
    });

    // Nothing in this region has a fixed height, so growth is the whole
    // mechanism: the row reflows, the summary line stacks past 1.4x, and the
    // ordinal column widens with the scale instead of clipping in place.
    for (final scale in <double>[1.0, 1.3, 2.0, 3.0]) {
      testWidgets('survives a ${scale}x reading size without overflowing', (
        tester,
      ) async {
        await _pumpAtScale(
          tester,
          scale,
          seasons: [_season(1, episodeCount: 2, fileCount: 1), _season(2)],
          episodes: [
            _episode(
              id: 1,
              episodeNumber: 1,
              title: 'A Rather Long Episode Title That Will Not Fit',
              airDate: '2011-04-17',
            ),
            _episode(
              id: 2,
              episodeNumber: 2,
              title: 'The Kingsroad',
              hasFile: false,
              airDate: '2011-04-24',
            ),
          ],
        );

        expect(tester.takeException(), isNull);
        // Nothing vanished: the season is still named and both rows are built.
        expect(find.text('Season 1'), findsOneWidget);
        expect(find.byType(MediaChildTile), findsNWidgets(2));
      });
    }
  });
  group('the collapse control', () {
    List<SonarrEpisode> _run(int count, {int seasonNumber = 1}) => [
      for (var number = 1; number <= count; number++)
        _episode(
          id: seasonNumber * 1000 + number,
          seasonNumber: seasonNumber,
          episodeNumber: number,
          title: 'S${seasonNumber}E$number',
        ),
    ];

    /// A viewport tall enough to hold an expanded 25-episode season.
    ///
    /// The footer control lives after a lazy sliver, so on a short viewport it
    /// is simply not built — and a test that scrolls to find it has to guess
    /// which direction to scroll after every tap. Height is the honest fixture.
    void _tallView(WidgetTester tester) {
      tester.view.physicalSize = const Size(600, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    testWidgets('a short season is never collapsed', (tester) async {
      await _pump(
        tester,
        seasons: [_season(1, episodeCount: 5, fileCount: 5)],
        episodes: _run(5),
      );

      expect(find.text('S1E5'), findsOneWidget);
      expect(find.textContaining('Show all'), findsNothing);
      expect(find.text('Show fewer'), findsNothing);
    });

    testWidgets('a long season builds only the collapsed count', (
      tester,
    ) async {
      _tallView(tester);
      await _pump(
        tester,
        seasons: [_season(1, episodeCount: 25, fileCount: 25)],
        episodes: _run(25),
      );

      // Capped, not hidden: the rows past the cap were never built.
      expect(find.text('S1E8'), findsOneWidget);
      expect(find.text('S1E9'), findsNothing);
      expect(find.text('Show all 25 episodes'), findsOneWidget);
    });

    testWidgets('expanding reveals the rest and offers the way back', (
      tester,
    ) async {
      _tallView(tester);
      await _pump(
        tester,
        seasons: [_season(1, episodeCount: 25, fileCount: 25)],
        episodes: _run(25),
      );

      await tester.tap(find.text('Show all 25 episodes'));
      await tester.pump();

      expect(find.text('Show all 25 episodes'), findsNothing);
      expect(find.text('Show fewer'), findsOneWidget);
      // The control names what shrinks for a reader, not just for the eye.
      expect(find.bySemanticsLabel('Show fewer episodes'), findsOneWidget);

      await tester.tap(find.text('Show fewer'));
      await tester.pump();
      expect(find.text('Show all 25 episodes'), findsOneWidget);
    });

    testWidgets('switching container returns to collapsed', (tester) async {
      _tallView(tester);
      await _pump(
        tester,
        seasons: [
          _season(1, episodeCount: 25, fileCount: 25),
          _season(2, episodeCount: 25, fileCount: 25),
        ],
        episodes: [..._run(25), ..._run(25, seasonNumber: 2)],
      );

      await tester.tap(find.text('Show all 25 episodes'));
      await tester.pump();
      expect(find.text('Show fewer'), findsOneWidget);

      await tester.tap(find.text('S2'));
      await tester.pump();

      // Expanding season 1 must not drop the user into 25 rows of season 2.
      expect(find.text('Show all 25 episodes'), findsOneWidget);
      expect(find.text('Show fewer'), findsNothing);
    });

    testWidgets('the toggle clears the 48dp touch minimum', (tester) async {
      _tallView(tester);
      await _pump(
        tester,
        seasons: [_season(1, episodeCount: 25, fileCount: 25)],
        episodes: _run(25),
      );

      // Matched as a `ButtonStyleButton`: `TextButton.icon` does not put a
      // `TextButton` of its own in the tree, so naming the concrete type here
      // would pass or fail on a framework detail rather than on the target size.
      final toggle = find.ancestor(
        of: find.text('Show all 25 episodes'),
        matching: find.byWidgetPredicate(
          (widget) => widget is ButtonStyleButton,
        ),
      );
      expect(toggle, findsOneWidget);
      expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48));
    });
  });

  testWidgets('a rail that fits gets no jump-to picker', (tester) async {
    await _pump(
      tester,
      seasons: [for (var number = 1; number <= 5; number++) _season(number)],
      episodes: [_episode(id: 1)],
    );

    // Five pills fit, so a picker beside them would duplicate them in a band of
    // dead space — which is exactly what it used to do.
    expect(find.byIcon(Icons.unfold_more_rounded), findsNothing);
  });
}

Future<void> _pumpAtScale(
  WidgetTester tester,
  double scale, {
  required List<SonarrSeason> seasons,
  required List<SonarrEpisode> episodes,
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
                SeriesSeasonsList(
                  seasons: seasons,
                  episodesAsync: AsyncValue<List<SonarrEpisode>>.data(episodes),
                  onSearchSeason: (_) {},
                  onInteractiveSearchSeason: (_) {},
                  onSearchEpisode: (_) {},
                  onInteractiveSearchEpisode: (_, _) {},
                  searchingSeasons: const {},
                  searchingEpisodes: const {},
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

Future<void> _pump(
  WidgetTester tester, {
  required List<SonarrSeason> seasons,
  required List<SonarrEpisode> episodes,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SeriesSeasonsList(
              seasons: seasons,
              episodesAsync: AsyncValue<List<SonarrEpisode>>.data(episodes),
              onSearchSeason: (_) {},
              onInteractiveSearchSeason: (_) {},
              onSearchEpisode: (_) {},
              onInteractiveSearchEpisode: (_, _) {},
              searchingSeasons: const {},
              searchingEpisodes: const {},
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}

SonarrSeason _season(
  int seasonNumber, {
  int episodeCount = 1,
  int fileCount = 1,
  int? total,
}) {
  return SonarrSeason(
    seasonNumber: seasonNumber,
    monitored: true,
    episodeCount: episodeCount,
    totalEpisodeCount: total ?? episodeCount,
    episodeFileCount: fileCount,
  );
}

SonarrEpisode _episode({
  required int id,
  int seasonNumber = 1,
  int episodeNumber = 1,
  String title = 'Episode',
  bool hasFile = true,
  String? airDate,
}) {
  return SonarrEpisode(
    id: id,
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
    title: title,
    hasFile: hasFile,
    monitored: true,
    airDate: airDate,
    airDateUtc: airDate,
  );
}
