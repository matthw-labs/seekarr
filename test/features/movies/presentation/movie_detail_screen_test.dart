import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/movies/data/radarr_service.dart';
import 'package:seekarr/features/movies/domain/models/radarr_movie.dart';
import 'package:seekarr/features/movies/presentation/movie_detail_provider.dart';
import 'package:seekarr/features/movies/presentation/movie_detail_screen.dart';
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

      expect(find.textContaining('Error:'), findsOneWidget);
      expect(find.textContaining('Network failure'), findsOneWidget);
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

    testWidgets('renders movie detail content when data is loaded', (
      tester,
    ) async {
      await _pumpMovieDetail(
        tester,
        detailBuilder: (ref, movieId) async => _movie(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Inception'), findsAtLeastNWidgets(1));
      expect(find.byType(MediaDetailHeroSummaryCard), findsOneWidget);
      expect(find.byType(GenreChip), findsNWidgets(2));
      expect(
        find.descendant(
          of: find.byType(MediaInfoCard),
          matching: find.byType(GenreChip),
        ),
        findsNothing,
      );
      expect(find.text('A mind-bending thriller.'), findsOneWidget);
      expect(find.byType(MediaMetadataLine), findsOneWidget);
      expect(find.byType(MediaInfoCard), findsOneWidget);
      expect(find.byType(FileInfoSection), findsOneWidget);

      await _scrollUntilVisible(tester, find.text('Tags'));

      expect(find.text('Tags'), findsOneWidget);
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

    testWidgets('hides file info section when the movie has no file', (
      tester,
    ) async {
      await _pumpMovieDetail(
        tester,
        detailBuilder: (ref, movieId) async =>
            _movie(hasFile: false, path: null),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FileInfoSection), findsNothing);
    });

    testWidgets('shows add movie action for lookup results not in library', (
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
      expect(find.text('Add Movie'), findsOneWidget);
      expect(find.text('Interactive'), findsNothing);
      expect(find.text('Auto Search'), findsNothing);
      expect(find.text('Delete'), findsNothing);

      await tester.tap(find.text('Add Movie'));
      await tester.pumpAndSettle();

      expect(
        find.text('Add Movie is not available yet from this view.'),
        findsOneWidget,
      );
    });

    testWidgets('shows monitor action for unmonitored library movies', (
      tester,
    ) async {
      final radarrService = _TrackingRadarrService();

      await _pumpMovieDetail(
        tester,
        detailBuilder: (ref, movieId) async => _movie(monitored: false),
        radarrService: radarrService,
      );
      await tester.pumpAndSettle();

      expect(find.text('Monitor'), findsOneWidget);
      expect(find.text('Interactive'), findsOneWidget);

      await tester.tap(find.text('Monitor'));
      await tester.pumpAndSettle();

      expect(radarrService.updatedMovieId, 1);
      expect(radarrService.updatedMonitored, isTrue);
      expect(find.text('Movie monitored'), findsOneWidget);
    });

    testWidgets('shows unmonitor action for monitored library movies', (
      tester,
    ) async {
      final radarrService = _TrackingRadarrService();

      await _pumpMovieDetail(
        tester,
        detailBuilder: (ref, movieId) async => _movie(),
        radarrService: radarrService,
      );
      await tester.pumpAndSettle();

      expect(find.text('Unmonitor'), findsOneWidget);
      expect(find.text('Interactive'), findsOneWidget);

      await tester.tap(find.text('Unmonitor'));
      await tester.pumpAndSettle();

      expect(radarrService.updatedMovieId, 1);
      expect(radarrService.updatedMonitored, isFalse);
      expect(find.text('Movie unmonitored'), findsOneWidget);
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

Future<void> _pumpMovieDetail(
  WidgetTester tester, {
  required FutureOr<RadarrMovie?> Function(Ref ref, int movieId) detailBuilder,
  RadarrMovie? initialMovie,
  int movieId = 1,
  RadarrService? radarrService,
}) async {
  await tester.pumpWidget(
    ProviderScope(
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

class _TrackingRadarrService extends FakeRadarrService {
  int? updatedMovieId;
  bool? updatedMonitored;

  @override
  Future<void> updateMovieMonitored(int movieId, bool monitored) async {
    updatedMovieId = movieId;
    updatedMonitored = monitored;
  }
}
