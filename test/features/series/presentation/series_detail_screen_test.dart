import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/series/data/sonarr_service.dart';
import 'package:seekarr/features/series/domain/models/sonarr_episode.dart';
import 'package:seekarr/features/series/domain/models/sonarr_series.dart';
import 'package:seekarr/features/series/presentation/series_detail_provider.dart';
import 'package:seekarr/features/series/presentation/series_detail_screen.dart';
import 'package:seekarr/features/series/presentation/widgets/series_seasons_list.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/model_builders.dart';

SonarrSeries _series({
  int id = 1,
  bool monitored = true,
  String? path,
  List<Map<String, dynamic>>? seasons,
  Map<String, dynamic>? statistics,
}) => buildSeries(
  id: id,
  title: 'Breaking Bad',
  overview: 'A chemistry teacher turns to crime.',
  path: path ?? '/tv/Breaking Bad',
  year: 2008,
  tvdbId: 81189,
  runtime: 45,
  status: 'ended',
  monitored: monitored,
  network: 'AMC',
  genres: const ['Drama', 'Crime'],
  seasons:
      seasons ??
      const [
        {
          'seasonNumber': 1,
          'monitored': true,
          'statistics': {
            'episodeFileCount': 7,
            'totalEpisodeCount': 7,
            'episodeCount': 7,
          },
        },
        {
          'seasonNumber': 2,
          'monitored': true,
          'statistics': {
            'episodeFileCount': 0,
            'totalEpisodeCount': 1,
            'episodeCount': 1,
          },
        },
      ],
  statistics:
      statistics ??
      const {'seasonCount': 1, 'episodeCount': 7, 'episodeFileCount': 7},
  seriesType: 'standard',
  certification: 'TV-MA',
);

List<SonarrEpisode> _episodes() => [
  buildEpisode(id: 101, title: 'Pilot'),
  buildEpisode(id: 201, seasonNumber: 2, title: 'Seven Thirty-Seven'),
];

void main() {
  group('SeriesDetailScreen', () {
    testWidgets('shows loading state when provider is loading', (tester) async {
      await _pumpSeriesDetail(
        tester,
        detailBuilder: (ref, seriesId) => Completer<SonarrSeries?>().future,
        episodesBuilder: (ref, seriesId) =>
            Completer<List<SonarrEpisode>>().future,
      );
      await tester.pump();

      expect(find.byType(MediaDetailLoadingView), findsOneWidget);
    });

    testWidgets('shows error text for generic errors', (tester) async {
      await _pumpSeriesDetail(
        tester,
        detailBuilder: (ref, seriesId) =>
            Future<SonarrSeries?>.error(Exception('Network error')),
      );
      await tester.pumpAndSettle();

      // The headline names what failed; the exception stays on screen as the
      // demoted detail line, not as the message.
      expect(find.text("Couldn't load Sonarr"), findsOneWidget);
      expect(find.textContaining('Network error'), findsOneWidget);
    });

    testWidgets('shows not configured placeholder for configuration errors', (
      tester,
    ) async {
      await _pumpSeriesDetail(
        tester,
        detailBuilder: (ref, seriesId) =>
            Future<SonarrSeries?>.error(Exception('Sonarr not configured')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
    });

    testWidgets('renders series detail content in canonical region order', (
      tester,
    ) async {
      await _pumpSeriesDetail(
        tester,
        detailBuilder: (ref, seriesId) async => _series(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Breaking Bad'), findsAtLeastNWidgets(1));
      expect(find.byType(MediaDetailHeroSummary), findsOneWidget);

      // The seasons are region 3, so they arrive before the prose and the
      // catalogue rather than sixth.
      expect(find.text('SEASONS'), findsOneWidget);
      expect(find.byType(SeriesSeasonsList), findsOneWidget);

      await _scrollUntilVisible(
        tester,
        find.text('A chemistry teacher turns to crime.'),
      );
      expect(find.text('A chemistry teacher turns to crime.'), findsOneWidget);

      await _scrollUntilVisible(tester, find.text('DETAILS'));
      expect(find.byType(MediaInfoCard), findsOneWidget);

      // Genres appear exactly once, under a heading that is true. The hero chip
      // slot carries the manifest counter instead.
      await _scrollUntilVisible(tester, find.text('GENRES'));
      expect(find.byType(GenreChip), findsNWidgets(2));
      expect(
        find.descendant(
          of: find.byType(MediaInfoCard),
          matching: find.byType(GenreChip),
        ),
        findsNothing,
      );
      expect(find.text('TAGS'), findsNothing);
    });

    testWidgets('the canonical region order puts seasons above the catalogue', (
      tester,
    ) async {
      await _pumpSeriesDetail(
        tester,
        detailBuilder: (ref, seriesId) async => _series(),
      );
      await tester.pumpAndSettle();

      final labels = tester
          .widgetList<MediaDetailSectionLabel>(
            find.byType(MediaDetailSectionLabel, skipOffstage: false),
          )
          .map((label) => label.label)
          .toList();

      expect(labels.first, 'Seasons');
      expect(
        labels.indexOf('Overview'),
        greaterThan(labels.indexOf('Seasons')),
      );
      expect(labels.indexOf('Genres'), greaterThan(labels.indexOf('Details')));
    });

    testWidgets('a pull re-runs both loads the retry button re-runs', (
      tester,
    ) async {
      var detailLoads = 0;
      var episodeLoads = 0;

      await _pumpSeriesDetail(
        tester,
        detailBuilder: (ref, seriesId) async {
          detailLoads++;
          return _series();
        },
        episodesBuilder: (ref, seriesId) async {
          episodeLoads++;
          return _episodes();
        },
      );
      await tester.pumpAndSettle();

      expect(find.byType(RefreshIndicator), findsOneWidget);

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 320),
        1000,
      );
      await tester.pumpAndSettle();

      expect(detailLoads, 2);
      expect(episodeLoads, 2);
    });

    testWidgets('the hero chip slot carries the manifest counter', (
      tester,
    ) async {
      await _pumpSeriesDetail(
        tester,
        detailBuilder: (ref, seriesId) async => _series(),
      );
      await tester.pumpAndSettle();

      // One meaning for the chip slot on every variant: how much of what the
      // service tracks actually arrived.
      expect(find.text('7/7 episodes'), findsOneWidget);
      expect(find.text('1 season'), findsOneWidget);
    });

    testWidgets('uses initialSeries while provider is still loading', (
      tester,
    ) async {
      await _pumpSeriesDetail(
        tester,
        detailBuilder: (ref, seriesId) => Completer<SonarrSeries?>().future,
        initialSeries: _series(),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Breaking Bad'), findsAtLeastNWidgets(1));
      expect(find.byType(MediaDetailLoadingView), findsNothing);
    });

    testWidgets('shows season tile with episode progress', (tester) async {
      await _pumpSeriesDetail(
        tester,
        detailBuilder: (ref, seriesId) async => _series(),
      );
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, find.text('Season 1'));

      expect(find.text('Season 1'), findsOneWidget);
      expect(find.textContaining('7 of 7 episodes'), findsOneWidget);
    });

    testWidgets('shows episodes for the selected season pill', (tester) async {
      await _pumpSeriesDetail(
        tester,
        detailBuilder: (ref, seriesId) async => _series(),
      );
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, find.text('S2'));

      expect(find.text('Pilot'), findsOneWidget);
      expect(find.text('Seven Thirty-Seven'), findsNothing);

      await tester.tap(find.text('S2'));
      await tester.pumpAndSettle();

      expect(find.text('Seven Thirty-Seven'), findsOneWidget);
      expect(find.text('Pilot'), findsNothing);
    });

    testWidgets('shows add series action and hides seasons for lookup miss', (
      tester,
    ) async {
      var requestedSeries = false;
      var requestedEpisodes = false;

      await _pumpSeriesDetail(
        tester,
        seriesId: 0,
        detailBuilder: (ref, seriesId) async {
          requestedSeries = true;
          return null;
        },
        episodesBuilder: (ref, seriesId) async {
          requestedEpisodes = true;
          return const [];
        },
        initialSeries: _series(
          id: 0,
          monitored: false,
          path: null,
          seasons: const [],
          statistics: const {
            'seasonCount': 0,
            'episodeCount': 0,
            'episodeFileCount': 0,
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(requestedSeries, isFalse);
      expect(requestedEpisodes, isFalse);
      // The dead full-width CTA is gone: with no add path the capability falls
      // through to a sentence instead of a button that apologises when pressed.
      expect(find.text('Add Series'), findsNothing);
      expect(find.byType(MediaDetailUnavailableSection), findsOneWidget);
      expect(
        find.textContaining('Sonarr is not tracking this series'),
        findsOneWidget,
      );
      expect(find.text('SEASONS'), findsNothing);
    });

    testWidgets('monitoring an unmonitored-but-complete series is in the sheet', (
      tester,
    ) async {
      final sonarrService = _TrackingSonarrService();

      await _pumpSeriesDetail(
        tester,
        detailBuilder: (ref, seriesId) async => _series(monitored: false),
        sonarrService: sonarrService,
      );
      await tester.pumpAndSettle();

      // Everything expected is already on disk, so nothing is promoted at all —
      // not another search that could churn the library, and not a monitor
      // toggle nobody opened the page for.
      expect(find.text('Monitor'), findsNothing);

      await tester.tap(
        find.widgetWithIcon(OutlinedButton, Icons.more_horiz_rounded),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Monitor'));
      await tester.pumpAndSettle();

      expect(sonarrService.updatedSeriesId, 1);
      expect(sonarrService.updatedMonitored, isTrue);
      expect(find.text('Sonarr is monitoring this series'), findsOneWidget);
    });

    testWidgets('unmonitoring a monitored series lives in the overflow sheet', (
      tester,
    ) async {
      final sonarrService = _TrackingSonarrService();

      await _pumpSeriesDetail(
        tester,
        detailBuilder: (ref, seriesId) async => _series(),
        sonarrService: sonarrService,
      );
      await tester.pumpAndSettle();

      // "Unmonitor" used to be the loudest element on an available monitored
      // series. It is no longer promoted at all.
      expect(find.text('Unmonitor'), findsNothing);
      expect(find.text('Stop monitoring'), findsNothing);

      await tester.tap(
        find.widgetWithIcon(OutlinedButton, Icons.more_horiz_rounded),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Stop monitoring'));
      await tester.pumpAndSettle();

      expect(sonarrService.updatedSeriesId, 1);
      expect(sonarrService.updatedMonitored, isFalse);
      expect(
        find.text('Sonarr has stopped monitoring this series'),
        findsOneWidget,
      );
    });

    testWidgets('a whole-series search says what it just set off', (
      tester,
    ) async {
      final sonarrService = _SearchingSonarrService();

      await _pumpSeriesDetail(
        tester,
        detailBuilder: (ref, seriesId) async => _series(),
        sonarrService: sonarrService,
      );
      await tester.pumpAndSettle();

      // Auto search is one of the two visible secondaries on an available
      // series, so it is reached directly rather than through the sheet.
      await tester.tap(find.text('Auto search'));
      await tester.pumpAndSettle();

      expect(sonarrService.searchedSeriesId, 1);
      // "Search started for entire series" left the cost unstated. This one
      // search runs against every monitored episode the show has, which is the
      // fact a self-hoster on a metered connection needs.
      expect(
        find.text('Sonarr is searching for every monitored episode'),
        findsOneWidget,
      );
    });
  });
}

Future<void> _scrollUntilVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpSeriesDetail(
  WidgetTester tester, {
  required FutureOr<SonarrSeries?> Function(Ref ref, int seriesId)
  detailBuilder,
  FutureOr<List<SonarrEpisode>> Function(Ref ref, int seriesId)?
  episodesBuilder,
  SonarrSeries? initialSeries,
  int seriesId = 1,
  SonarrService? sonarrService,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => const SettingsModel(
            sonarrUrl: 'http://localhost:8989',
            sonarrApiKey: 'key',
          ),
        ),
        seriesDetailProvider.overrideWith(detailBuilder),
        seriesEpisodesProvider.overrideWith(
          episodesBuilder ?? (ref, seriesId) async => _episodes(),
        ),
        sonarrServiceProvider.overrideWith(
          (ref) => sonarrService ?? FakeSonarrService(),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SeriesDetailScreen(
            seriesId: seriesId,
            heroTag: 'series-1',
            initialSeries: initialSeries,
          ),
        ),
      ),
    ),
  );
}

class _TrackingSonarrService extends FakeSonarrService {
  int? updatedSeriesId;
  bool? updatedMonitored;

  @override
  Future<void> updateSeriesMonitored(int seriesId, bool monitored) async {
    updatedSeriesId = seriesId;
    updatedMonitored = monitored;
  }
}

/// Accepts the search command offline so the confirmation copy can be asserted.
class _SearchingSonarrService extends FakeSonarrService {
  int? searchedSeriesId;

  @override
  Future<void> searchSeries(int seriesId) async {
    searchedSeriesId = seriesId;
  }
}
