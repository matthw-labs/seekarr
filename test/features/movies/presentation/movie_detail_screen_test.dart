import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/status/arr_queue_snapshot.dart';
import 'package:seekarr/core/utils/arr_model_helpers.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/movies/data/radarr_service.dart';
import 'package:seekarr/features/movies/domain/models/radarr_movie.dart';
import 'package:seekarr/features/movies/presentation/movie_detail_provider.dart';
import 'package:seekarr/features/movies/presentation/movie_detail_screen.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/model_builders.dart';

RadarrMovie _movie({
  int id = 1,
  bool hasFile = true,
  bool monitored = true,
  String? path,
}) => buildMovie(
  id: id,
  title: 'Inception',
  overview: 'A mind-bending thriller.',
  path: path ?? '/movies/Inception (2010)/Inception.mkv',
  hasFile: hasFile,
  monitored: monitored,
  year: 2010,
  tmdbId: 100,
  runtime: 148,
  sizeOnDisk: 1000000,
  studio: 'Warner Bros',
  genres: const ['Sci-Fi', 'Action'],
  certification: 'PG-13',
);

void main() {
  group('MovieDetailScreen', () {
    testWidgets('shows loading state when provider is loading', (tester) async {
      await _pumpMovieDetail(
        tester,
        detailBuilder: (ref, movieId) => Completer<RadarrMovie?>().future,
      );
      await tester.pump();

      expect(find.byType(MediaDetailLoadingView), findsOneWidget);
    });

    testWidgets('shows error text for generic errors', (tester) async {
      await _pumpMovieDetail(
        tester,
        detailBuilder: (ref, movieId) =>
            Future<RadarrMovie?>.error(Exception('Network failure')),
      );
      await tester.pumpAndSettle();

      // The headline names what failed; the exception stays on screen as the
      // demoted detail line, not as the message.
      expect(find.text("Couldn't load Radarr"), findsOneWidget);
      expect(find.textContaining('Network failure'), findsOneWidget);
    });

    testWidgets('a failed load can be retried in place', (tester) async {
      var loads = 0;

      await _pumpMovieDetail(
        tester,
        detailBuilder: (ref, movieId) {
          loads++;
          return Future<RadarrMovie?>.error(Exception('Connection refused'));
        },
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppErrorState), findsOneWidget);
      expect(loads, 1);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      // The page recovers where it stands instead of costing a trip back to the
      // library and in again.
      expect(loads, 2);
    });

    testWidgets('a pull re-runs the same load the retry button re-runs', (
      tester,
    ) async {
      var loads = 0;

      await _pumpMovieDetail(
        tester,
        detailBuilder: (ref, movieId) async {
          loads++;
          return _movie();
        },
      );
      await tester.pumpAndSettle();

      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(loads, 1);

      // A pull used to be visibly accepted — it stretched the hero backdrop —
      // and then do nothing at all on six of the seven detail screens.
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 320),
        1000,
      );
      await tester.pumpAndSettle();

      expect(loads, 2);
    });

    testWidgets('shows not configured placeholder for configuration errors', (
      tester,
    ) async {
      await _pumpMovieDetail(
        tester,
        detailBuilder: (ref, movieId) =>
            Future<RadarrMovie?>.error(Exception('Radarr not configured')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
    });

    testWidgets('renders movie detail content in canonical region order', (
      tester,
    ) async {
      await _pumpMovieDetail(
        tester,
        detailBuilder: (ref, movieId) async => _movie(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Inception'), findsAtLeastNWidgets(1));
      expect(find.byType(MediaDetailHeroSummary), findsOneWidget);
      expect(find.byType(MediaMetadataLine), findsOneWidget);

      // A movie has no child records, so region 3 is the file — and the path a
      // self-hoster hunts for is near the top of the page rather than buried in
      // an encyclopaedic grid.
      expect(find.text('FILE'), findsOneWidget);
      expect(find.byType(FileInfoSection), findsOneWidget);

      await _scrollUntilVisible(tester, find.text('A mind-bending thriller.'));
      expect(find.text('A mind-bending thriller.'), findsOneWidget);

      await _scrollUntilVisible(tester, find.text('DETAILS'));
      expect(find.byType(MediaInfoCard), findsOneWidget);

      // Genres appear once, labelled honestly. 'Tags' names a real Radarr
      // release-profile concept that these are not.
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

    testWidgets('the extras region spends a heading only on what it has', (
      tester,
    ) async {
      await _pumpMovieDetail(
        tester,
        detailBuilder: (ref, movieId) async => _movie(),
      );
      await tester.pumpAndSettle();

      final body = tester
          .widget<MediaDetailView>(find.byType(MediaDetailView))
          .body;

      // Seerr is unconfigured in this harness, so the extras resolve to the
      // Connect prompt — one slot, deliberately unlabelled, because an accent
      // eyebrow reading CAST over a card that says "Connect Seerr" would name
      // content that is not there. Cast and Collection used to be one
      // undifferentiated section that drew its own headings.
      expect(body.related, hasLength(1));
      expect(body.related.single.label, isNull);

      // Scrolled to, not just resolved: the assertion that no heading exists is
      // worthless if the region was never built.
      await _scrollUntilVisible(tester, find.text('Cast & collections'));
      expect(find.text('Cast & collections'), findsOneWidget);
      expect(find.text('CAST'), findsNothing);
      expect(find.text('COLLECTION'), findsNothing);
    });

    testWidgets('the hero chip slot states how much of the manifest exists', (
      tester,
    ) async {
      await _pumpMovieDetail(
        tester,
        detailBuilder: (ref, movieId) async => _movie(),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 file'), findsOneWidget);
      // Genres are no longer duplicated into the hero.
      expect(
        find.descendant(
          of: find.byType(MediaDetailPosterRow),
          matching: find.byType(GenreChip),
        ),
        findsNothing,
      );
    });

    testWidgets('uses initialMovie while provider is still loading', (
      tester,
    ) async {
      await _pumpMovieDetail(
        tester,
        detailBuilder: (ref, movieId) => Completer<RadarrMovie?>().future,
        initialMovie: _movie(),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Inception'), findsAtLeastNWidgets(1));
      expect(find.byType(MediaDetailLoadingView), findsNothing);
    });

    testWidgets('a tracked movie with nothing on disk says so in region 3', (
      tester,
    ) async {
      await _pumpMovieDetail(
        tester,
        detailBuilder: (ref, movieId) async =>
            _movie(hasFile: false, path: null),
      );
      await tester.pumpAndSettle();

      // The manifest region still exists, and it now reports the gap on the
      // *same row shape* a real file gets — so the region does not jump when one
      // arrives — instead of a centred well with a circled glyph.
      expect(find.byType(FileInfoSection), findsOneWidget);
      expect(find.text('FILE'), findsOneWidget);
      expect(find.text('No file'), findsOneWidget);
      // A suggestion, naming the route the promoted "Auto search" does not.
      expect(find.text('Import a file you already have'), findsOneWidget);
      expect(
        find.text('Manual import is in the actions menu.'),
        findsOneWidget,
      );
    });

    testWidgets('a movie Radarr does not track gets a sentence, not a CTA', (
      tester,
    ) async {
      var requestedMovie = false;

      await _pumpMovieDetail(
        tester,
        movieId: 0,
        detailBuilder: (ref, movieId) async {
          requestedMovie = true;
          return null;
        },
        initialMovie: _movie(
          id: 0,
          hasFile: false,
          monitored: false,
          path: null,
        ),
      );
      await tester.pumpAndSettle();

      expect(requestedMovie, isFalse);
      // The full-width service-accent CTA whose only behaviour was an info
      // snackbar is gone: with no add path the capability is withheld, and the
      // page explains itself instead.
      expect(find.text('Add Movie'), findsNothing);
      expect(find.byType(MediaDetailUnavailableSection), findsOneWidget);
      expect(
        find.textContaining('Radarr is not tracking this movie'),
        findsOneWidget,
      );
      expect(find.text('FILE'), findsNothing);
    });

    testWidgets('an unmonitored movie with no file promotes Monitor', (
      tester,
    ) async {
      final radarrService = _TrackingRadarrService();

      await _pumpMovieDetail(
        tester,
        detailBuilder: (ref, movieId) async =>
            _movie(monitored: false, hasFile: false),
        radarrService: radarrService,
      );
      await tester.pumpAndSettle();

      // Not monitoring is the reason nothing is being hunted, so here — and only
      // here — monitoring is the promoted verb.
      await tester.tap(find.text('Monitor'));
      await tester.pumpAndSettle();

      expect(radarrService.updatedMovieId, 1);
      expect(radarrService.updatedMonitored, isTrue);
      expect(find.text('Radarr is monitoring this movie'), findsOneWidget);
    });

    testWidgets('a movie in flight promotes Open queue, not a sentence', (
      tester,
    ) async {
      await _pumpMovieDetail(
        tester,
        detailBuilder: (ref, movieId) async => _movie(hasFile: false),
        queueSnapshot: ArrQueueSnapshot.fromQueueItems(const [
          {
            'movieId': 1,
            'status': 'downloading',
            'size': 100.0,
            'sizeleft': 40.0,
          },
        ], idsFor: (item) => [item['movieId'] as int]),
      );
      await tester.pumpAndSettle();

      // `onOpenQueue` was declared by the ladder and wired by nobody, so the
      // single most common transient state on a real page — something actually
      // downloading — withheld its verb and degraded to prose. The route exists
      // now, so the rung fires.
      expect(find.text('Open queue'), findsOneWidget);
    });

    testWidgets('an available movie promotes nothing and hides Unmonitor', (
      tester,
    ) async {
      final radarrService = _TrackingRadarrService();

      await _pumpMovieDetail(
        tester,
        detailBuilder: (ref, movieId) async => _movie(),
        radarrService: radarrService,
      );
      await tester.pumpAndSettle();

      // The loudest element on an available monitored title used to read
      // "Unmonitor". It is replaced with nothing at all.
      expect(find.text('Unmonitor'), findsNothing);
      expect(find.text('Stop monitoring'), findsNothing);

      await tester.tap(
        find.widgetWithIcon(OutlinedButton, Icons.more_horiz_rounded),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Stop monitoring'));
      await tester.pumpAndSettle();

      expect(radarrService.updatedMovieId, 1);
      expect(radarrService.updatedMonitored, isFalse);
      expect(
        find.text('Radarr has stopped monitoring this movie'),
        findsOneWidget,
      );
    });

    testWidgets('a quality-profile change is confirmed before Radarr sees it', (
      tester,
    ) async {
      final radarrService = _ProfileRadarrService();

      await _pumpMovieDetail(
        tester,
        detailBuilder: (ref, movieId) async => _movieWithProfile(),
        radarrService: radarrService,
      );
      await tester.pumpAndSettle();

      // On an available title the primary is withheld, which frees both visible
      // slots — so the profile is a labelled button in the band rather than a
      // sheet row. Still two deliberate steps to a server write, and still not
      // one stray tap in a crowded row of six equal-weight buttons.
      await tester.tap(find.text('Quality profile'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ultra-HD'));
      await tester.pumpAndSettle();

      // The confirmation names the transition and what it may set off, rather
      // than firing a library-wide upgrade sweep straight off a 42pt tap.
      expect(
        find.textContaining('moves from HD-1080p to Ultra-HD'),
        findsOneWidget,
      );
      // Scoped to the dialog: the available rung's own consequence sentence now
      // ends "isn't searching", so a bare textContaining('searching') matches
      // twice and asserts nothing.
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('searching'),
        ),
        findsOneWidget,
      );
      expect(radarrService.profileWrites, isEmpty);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(radarrService.profileWrites, isEmpty);
    });

    testWidgets('a confirmed quality-profile change lands and says so', (
      tester,
    ) async {
      final radarrService = _ProfileRadarrService();

      await _pumpMovieDetail(
        tester,
        detailBuilder: (ref, movieId) async => _movieWithProfile(),
        radarrService: radarrService,
      );
      await tester.pumpAndSettle();

      // On an available title the primary is withheld, which frees both visible
      // slots — so the profile is a labelled button in the band rather than a
      // sheet row. Still two deliberate steps to a server write, and still not
      // one stray tap in a crowded row of six equal-weight buttons.
      await tester.tap(find.text('Quality profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ultra-HD'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change profile'));
      await tester.pumpAndSettle();

      expect(radarrService.profileWrites, [(1, 2)]);
      expect(find.text('Quality profile changed to Ultra-HD'), findsOneWidget);
    });

    testWidgets('rating pills name their sources instead of badging them', (
      tester,
    ) async {
      await _pumpMovieDetail(
        tester,
        detailBuilder: (ref, movieId) async => _movieWithRatings(),
      );
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, find.text('SCORES'));

      // `MC 53.0`, `RO 57.0` and `TR 7.1` were three abbreviations that appear
      // nowhere else in the app; `RO` in particular is only two letters because
      // the parser truncates a key it does not recognise.
      expect(find.text('Metacritic'), findsOneWidget);
      expect(find.text('Rotten Tomatoes'), findsOneWidget);
      expect(find.text('Trakt'), findsOneWidget);
      expect(find.text('IMDb'), findsOneWidget);
      expect(find.text('MC'), findsNothing);
      expect(find.text('RO'), findsNothing);
      expect(find.text('TR'), findsNothing);
    });

    testWidgets('a 200-character title cannot push a dialog past its buttons', (
      tester,
    ) async {
      // A real phone viewport: at the 800x600 test default a bottom sheet is
      // only 450pt tall, which turns any two-line header into an overflow that
      // has nothing to do with the copy.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpMovieDetail(
        tester,
        detailBuilder: (ref, movieId) async => _longTitledMovie(),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithIcon(OutlinedButton, Icons.more_horiz_rounded),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // An AlertDialog's title sits above its scrollable content, so an
      // uncapped "Delete <title>?" grew the header until the checkboxes and both
      // buttons left the viewport. A user cannot shorten their own library.
      final heading = _visibleTextStartingWith(tester, 'Delete The');
      expect(heading, endsWith('…?'));
      expect(heading.length, lessThan(80));

      // The controls the dialog exists for are still on screen.
      expect(find.text('Delete files'), findsOneWidget);
      expect(find.text('Add list exclusion'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('the releases sheet names the title once and caps it', (
      tester,
    ) async {
      // See the dialog test: the 800x600 default makes a sheet 450pt tall.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpMovieDetail(
        tester,
        detailBuilder: (ref, movieId) async => _longTitledMovie(),
        radarrService: _ReleasesRadarrService(),
      );
      await tester.pumpAndSettle();

      // Interactive search holds the first visible slot on an available title.
      await tester.tap(find.text('Interactive search'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // The sheet heads itself "Releases" and the caller's string lands in the
      // subtitle below it, so "Releases for X" printed the word twice.
      final header = tester.widget<AppSheetHeader>(find.byType(AppSheetHeader));
      expect(header.title, 'Releases');
      expect(header.subtitle, isNot(startsWith('Releases')));
      // The subtitle Text has no maxLines, so an uncapped 200-character title
      // grew the header until it crowded out the list it was introducing.
      expect(header.subtitle, endsWith('…'));
      expect(header.subtitle!.length, lessThan(80));
    });
  });
}

/// A library movie carrying the five-source ratings payload a real Radarr
/// returns, keys and all.
RadarrMovie _movieWithRatings() => buildMovie(
  id: 1,
  title: 'Inception',
  path: '/movies/Inception (2010)',
  overview: 'A mind-bending thriller.',
  year: 2010,
  tmdbId: 100,
  ratings: parseArrRatings(const {
    'imdb': {'value': 6.9, 'votes': 317100},
    'metacritic': {'value': 53.0, 'votes': 0},
    'rottenTomatoes': {'value': 57.0, 'votes': 0},
    'trakt': {'value': 7.1, 'votes': 15000},
  }, allowSingleSource: false),
);

/// A title of the length an anime release or a restored documentary genuinely
/// has — 200+ characters, which is not an edge case the user can avoid.
RadarrMovie _longTitledMovie() => buildMovie(
  id: 1,
  title: 'The ${'Extremely ' * 20}Long Cut',
  path: '/movies/Long',
  overview: 'A very long name.',
  year: 2010,
  tmdbId: 100,
);

/// The single visible [Text] whose content starts with [prefix].
String _visibleTextStartingWith(WidgetTester tester, String prefix) {
  final matches = tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data)
      .whereType<String>()
      .where((data) => data.startsWith(prefix))
      .toList();

  expect(matches, hasLength(1));
  return matches.single;
}

/// A library movie that already carries a quality profile, so the action row
/// offers the profile path at all.
RadarrMovie _movieWithProfile() => buildMovie(
  title: 'Inception',
  sizeOnDisk: 1000000,
  overview: 'A mind-bending thriller.',
  path: '/movies/Inception (2010)',
  year: 2010,
  tmdbId: 100,
  runtime: 148,
  genres: const ['Sci-Fi'],
  qualityProfileId: 1,
);

Future<void> _scrollUntilVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpMovieDetail(
  WidgetTester tester, {
  required FutureOr<RadarrMovie?> Function(Ref ref, int movieId) detailBuilder,
  RadarrMovie? initialMovie,
  int movieId = 1,
  RadarrService? radarrService,
  ArrQueueSnapshot? queueSnapshot,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      // Riverpod 3 re-runs a failed provider on its own backoff schedule, which
      // would make load counts non-deterministic. Switched off so the tests
      // measure only what the retry button does.
      retry: (retryCount, error) => null,
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => const SettingsModel(
            radarrUrl: 'http://localhost:7878',
            radarrApiKey: 'key',
          ),
        ),
        movieDetailProvider.overrideWith(detailBuilder),
        radarrServiceProvider.overrideWith(
          (ref) => radarrService ?? FakeRadarrService(),
        ),
        if (queueSnapshot != null)
          radarrQueueSnapshotProvider.overrideWith((ref) => queueSnapshot),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: MovieDetailScreen(
            movieId: movieId,
            heroTag: 'movie-1',
            initialMovie: initialMovie,
          ),
        ),
      ),
    ),
  );
}

class _ProfileRadarrService extends FakeRadarrService {
  final List<(int movieId, int profileId)> profileWrites = [];

  @override
  Future<List<Map<String, dynamic>>> getQualityProfiles() async => const [
    {'id': 1, 'name': 'HD-1080p'},
    {'id': 2, 'name': 'Ultra-HD'},
  ];

  @override
  Future<void> updateMovieProfile(int movieId, int profileId) async {
    profileWrites.add((movieId, profileId));
  }
}

/// Answers the interactive-search fetch offline, so the sheet opens on an empty
/// result rather than reaching for the network.
class _ReleasesRadarrService extends FakeRadarrService {
  @override
  Future<List<dynamic>> getReleases(
    int movieId, {
    CancelToken? cancelToken,
  }) async => const [];
}

class _TrackingRadarrService extends FakeRadarrService {
  int? updatedMovieId;
  bool? updatedMonitored;

  @override
  Future<void> updateMovieMonitored(int movieId, bool monitored) async {
    updatedMovieId = movieId;
    updatedMonitored = monitored;
  }
}
