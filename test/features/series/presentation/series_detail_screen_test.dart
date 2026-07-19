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

      expect(find.textContaining('Error:'), findsOneWidget);
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

    testWidgets('renders series detail content with seasons when loaded', (
      tester,
    ) async {
      await _pumpSeriesDetail(
        tester,
        detailBuilder: (ref, seriesId) async => _series(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Breaking Bad'), findsAtLeastNWidgets(1));
      expect(find.byType(MediaDetailHeroSummaryCard), findsOneWidget);
      expect(find.byType(GenreChip), findsNWidgets(2));
      expect(
        find.descendant(
          of: find.byType(MediaInfoCard),
          matching: find.byType(GenreChip),
        ),
        findsNothing,
      );
      expect(find.text('A chemistry teacher turns to crime.'), findsOneWidget);

      await _scrollUntilVisible(tester, find.text('Seasons'));

      expect(find.text('Seasons'), findsOneWidget);
      expect(find.byType(SeriesSeasonsList), findsOneWidget);
      expect(find.text('Tags'), findsOneWidget);
      expect(find.byType(MediaInfoCard), findsOneWidget);
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
      expect(find.text('7 / 7 Episodes'), findsOneWidget);
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
      expect(find.text('Add Series'), findsOneWidget);
      expect(find.text('Interactive'), findsNothing);
      expect(find.text('Seasons'), findsNothing);

      await tester.tap(find.text('Add Series'));
      await tester.pumpAndSettle();

      expect(
        find.text('Add Series is not available yet from this view.'),
        findsOneWidget,
      );
    });

    testWidgets('shows monitor action for unmonitored library series', (
      tester,
    ) async {
      final sonarrService = _TrackingSonarrService();

      await _pumpSeriesDetail(
        tester,
        detailBuilder: (ref, seriesId) async => _series(monitored: false),
        sonarrService: sonarrService,
      );
      await tester.pumpAndSettle();

      expect(find.text('Monitor'), findsOneWidget);
      expect(find.text('Interactive'), findsOneWidget);

      await tester.tap(find.text('Monitor'));
      await tester.pumpAndSettle();

      expect(sonarrService.updatedSeriesId, 1);
      expect(sonarrService.updatedMonitored, isTrue);
      expect(find.text('Series monitored'), findsOneWidget);
    });

    testWidgets('shows unmonitor action for monitored library series', (
      tester,
    ) async {
      final sonarrService = _TrackingSonarrService();

      await _pumpSeriesDetail(
        tester,
        detailBuilder: (ref, seriesId) async => _series(),
        sonarrService: sonarrService,
      );
      await tester.pumpAndSettle();

      expect(find.text('Unmonitor'), findsOneWidget);
      expect(find.text('Interactive'), findsOneWidget);

      await tester.tap(find.text('Unmonitor'));
      await tester.pumpAndSettle();

      expect(sonarrService.updatedSeriesId, 1);
      expect(sonarrService.updatedMonitored, isFalse);
      expect(find.text('Series unmonitored'), findsOneWidget);
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
