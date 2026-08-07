import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/domain/models/discover_detail_model.dart';
import 'package:cupola/features/discover/domain/seerr_status.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_seasons_list.dart';

void main() {
  group('DiscoverSeasonsList', () {
    testWidgets('shows episodes for the selected season pill', (tester) async {
      await _pump(
        tester,
        seasons: const [
          TvSeason(
            id: 1,
            seasonNumber: 1,
            name: 'Season 1',
            episodeCount: 1,
            episodes: [
              TvEpisodeSummary(
                name: 'Pilot',
                episodeNumber: 1,
                airDate: '2019-05-22',
              ),
            ],
          ),
          TvSeason(
            id: 2,
            seasonNumber: 2,
            name: 'Season 2',
            episodeCount: 1,
            episodes: [
              TvEpisodeSummary(name: 'Second Start', episodeNumber: 1),
            ],
          ),
        ],
      );

      expect(find.text('Pilot'), findsOneWidget);
      expect(find.text('Second Start'), findsNothing);

      // The pill rail is short labels now; the full name sits on the summary
      // line under it.
      await tester.tap(find.text('S2'));
      await tester.pumpAndSettle();

      expect(find.text('Second Start'), findsOneWidget);
      expect(find.text('Pilot'), findsNothing);
      expect(find.text('Season 2'), findsOneWidget);
    });

    testWidgets('an episode row carries its air date in the app voice', (
      tester,
    ) async {
      await _pump(
        tester,
        seasons: const [
          TvSeason(
            id: 1,
            seasonNumber: 1,
            name: 'Season 1',
            episodeCount: 1,
            episodes: [
              TvEpisodeSummary(
                name: 'Pilot',
                episodeNumber: 1,
                airDate: '2019-05-22',
              ),
            ],
          ),
        ],
      );

      expect(find.textContaining('May 22, 2019'), findsOneWidget);
      expect(find.textContaining('2019-05-22'), findsNothing);
    });

    testWidgets('per-season availability is resolved from mediaInfo and read '
        'as words', (tester) async {
      const seasons = [
        TvSeason(
          id: 1,
          seasonNumber: 1,
          name: 'Season 1',
          episodeCount: 1,
          episodes: [TvEpisodeSummary(name: 'Pilot', episodeNumber: 1)],
        ),
        TvSeason(
          id: 2,
          seasonNumber: 2,
          name: 'Season 2',
          episodeCount: 1,
          episodes: [TvEpisodeSummary(name: 'Second Start', episodeNumber: 1)],
        ),
      ];

      await _pump(
        tester,
        seasons: seasons,
        mediaInfo: const {
          'seasons': [
            {'seasonNumber': 1, 'status': 5},
            {'seasonNumber': 2, 'status': 4},
          ],
        },
      );

      // The selected season's state is a badge with a label, not a coloured
      // glyph tucked inside a pill.
      expect(find.text('Available'), findsOneWidget);

      await tester.tap(find.text('S2'));
      await tester.pumpAndSettle();

      expect(find.text('Partially Available'), findsOneWidget);
    });

    testWidgets('episode rows carry no invented per-episode status', (
      tester,
    ) async {
      await _pump(
        tester,
        seasons: const [
          TvSeason(
            id: 1,
            seasonNumber: 1,
            name: 'Season 1',
            episodeCount: 1,
            episodes: [TvEpisodeSummary(name: 'Pilot', episodeNumber: 1)],
          ),
        ],
        mediaInfo: const {
          'seasons': [
            {'seasonNumber': 1, 'status': 4},
          ],
        },
      );

      // Seerr models availability per season, so the only badge on screen is
      // the season's own.
      expect(find.byType(MediaChildTile), findsOneWidget);
      expect(find.byType(StatusBadge), findsOneWidget);
    });

    testWidgets('no seasons renders the empty state in the Seerr accent', (
      tester,
    ) async {
      await _pump(tester, seasons: const []);

      expect(find.text('No seasons listed'), findsOneWidget);
      expect(
        tester.widget<AppEmptyState>(find.byType(AppEmptyState)).accentColor,
        ServiceKey.seerr.accent,
      );
    });

    testWidgets('a season with no episode details gets an empty state', (
      tester,
    ) async {
      await _pump(
        tester,
        seasons: const [
          TvSeason(id: 1, seasonNumber: 1, name: 'Season 1', episodeCount: 8),
        ],
      );

      expect(find.text('8 episodes listed'), findsOneWidget);
      expect(find.byType(AppEmptyState), findsOneWidget);
    });

    testWidgets('builds only a bounded number of rows for a long season', (
      tester,
    ) async {
      await _pump(
        tester,
        seasons: [
          TvSeason(
            id: 1,
            seasonNumber: 1,
            name: 'Season 1',
            episodeCount: 250,
            episodes: [
              for (var number = 1; number <= 250; number++)
                TvEpisodeSummary(name: 'Ep $number', episodeNumber: number),
            ],
          ),
        ],
      );

      final built = find.byType(MediaChildTile).evaluate().length;
      expect(built, greaterThan(0));
      expect(built, lessThan(40));
    });
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required List<TvSeason> seasons,
  Map<String, dynamic>? mediaInfo,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            DiscoverSeasonsList(
              seasons: seasons,
              seasonStatuses: seerrSeasonStatuses(mediaInfo, seasons),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}
