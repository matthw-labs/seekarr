import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/models/media_preview.dart';
import 'package:seekarr/core/widgets/content_card.dart';
import 'package:seekarr/core/widgets/shimmer_placeholder.dart';
import 'package:seekarr/features/discover/domain/models/seerr_genre.dart';
import 'package:seekarr/features/discover/domain/models/seerr_request.dart';
import 'package:seekarr/features/discover/presentation/discover_provider.dart';
import 'package:seekarr/features/discover/presentation/discover_screen.dart';
import 'package:seekarr/features/discover/presentation/discover_search_provider.dart';

const _movies = [
  MediaPreview(id: 1, title: 'Movie One', mediaType: 'movie'),
  MediaPreview(id: 2, title: 'Movie Two', mediaType: 'movie'),
];

const _tvShows = [MediaPreview(id: 10, title: 'Show One', mediaType: 'tv')];

const _trending = [
  MediaPreview(id: 20, title: 'Trending One', mediaType: 'movie'),
];

void main() {
  group('DiscoverScreen catalog', () {
    testWidgets('renders curated section headers when data loads', (
      tester,
    ) async {
      await _pumpDiscover(tester);
      await tester.pumpAndSettle();

      expect(find.text('Trending'), findsOneWidget);
      expect(find.text('Popular Movies'), findsOneWidget);
      expect(find.text('Popular Series'), findsOneWidget);
      expect(find.byType(ContentCard), findsWidgets);
    });

    testWidgets('shows skeleton when a section is loading', (tester) async {
      await _pumpDiscover(
        tester,
        trendingBuilder: (ref) => Completer<List<MediaPreview>>().future,
      );
      await tester.pump();

      expect(find.byType(ShimmerPlaceholder), findsWidgets);
    });

    testWidgets('hides a section that returns an empty list', (tester) async {
      await _pumpDiscover(
        tester,
        moviesBuilder: (ref) async => const <MediaPreview>[],
      );
      await tester.pumpAndSettle();

      // Empty rows collapse rather than showing a placeholder message.
      expect(find.text('Popular Movies'), findsNothing);
      expect(find.text('Trending'), findsOneWidget);
    });

    testWidgets('renders app bar with title and activity button', (
      tester,
    ) async {
      await _pumpDiscover(tester);
      await tester.pumpAndSettle();

      expect(find.text('Discover'), findsOneWidget);
      expect(find.byIcon(Icons.history_rounded), findsOneWidget);
    });
  });

  group('DiscoverScreen search', () {
    testWidgets('shows search results grid when query is non-empty', (
      tester,
    ) async {
      await _pumpDiscover(
        tester,
        searchQueryBuilder: (ref) => 'batman',
        searchResultsBuilder: (ref) async => _movies,
      );
      await tester.pumpAndSettle();

      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(ContentCard), findsNWidgets(2));
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    });

    testWidgets('shows no results message when search returns empty', (
      tester,
    ) async {
      await _pumpDiscover(
        tester,
        searchQueryBuilder: (ref) => 'xyz',
        searchResultsBuilder: (ref) async => const <MediaPreview>[],
      );
      await tester.pumpAndSettle();

      expect(find.text('No results found'), findsOneWidget);
      expect(find.byIcon(Icons.search_off_rounded), findsOneWidget);
    });

    testWidgets('shows error state when search fails', (tester) async {
      await _pumpDiscover(
        tester,
        searchQueryBuilder: (ref) => 'fail',
        searchResultsBuilder: (ref) =>
            Future<List<MediaPreview>?>.error(Exception('Network error')),
      );
      await tester.pumpAndSettle();

      // The headline names what failed; the exception is demoted to a detail
      // line under it rather than being the message itself.
      expect(find.text("Couldn't load search results"), findsOneWidget);
      expect(find.textContaining('Network error'), findsOneWidget);
    });

    testWidgets('uses unique hero tags for mixed media search results', (
      tester,
    ) async {
      await _pumpDiscover(
        tester,
        searchQueryBuilder: (ref) => 'same-id',
        searchResultsBuilder: (ref) async => const [
          MediaPreview(id: 42, title: 'Movie 42', mediaType: 'movie'),
          MediaPreview(id: 42, title: 'Show 42', mediaType: 'tv'),
        ],
      );
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Hero && widget.tag == 'discover_search_movie_42_0',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Hero && widget.tag == 'discover_search_tv_42_1',
        ),
        findsOneWidget,
      );
    });
  });
}

Future<void> _pumpDiscover(
  WidgetTester tester, {
  Future<List<MediaPreview>> Function(Ref ref)? trendingBuilder,
  Future<List<MediaPreview>> Function(Ref ref)? moviesBuilder,
  Future<List<MediaPreview>> Function(Ref ref)? tvBuilder,
  String Function(Ref ref)? searchQueryBuilder,
  Future<List<MediaPreview>?> Function(Ref ref)? searchResultsBuilder,
}) async {
  // Tall viewport so all catalog rows build (the vertical ListView is lazy).
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        discoverTrendingProvider.overrideWith(
          trendingBuilder ?? (ref) async => _trending,
        ),
        discoverMoviesProvider.overrideWith(
          moviesBuilder ?? (ref) async => _movies,
        ),
        discoverTVProvider.overrideWith(tvBuilder ?? (ref) async => _tvShows),
        // Keep the rest of the catalog deterministic (empty → hidden rows).
        discoverUpcomingMoviesProvider.overrideWith(
          (ref) async => const <MediaPreview>[],
        ),
        discoverUpcomingTvProvider.overrideWith(
          (ref) async => const <MediaPreview>[],
        ),
        discoverTopRatedMoviesProvider.overrideWith(
          (ref) async => const <MediaPreview>[],
        ),
        movieGenresProvider.overrideWith((ref) async => const <SeerrGenre>[]),
        requestsProvider.overrideWith((ref) async => const <SeerrRequest>[]),
        discoverSearchQueryProvider.overrideWith(
          searchQueryBuilder ?? (ref) => '',
        ),
        discoverSearchResultsProvider.overrideWith(
          searchResultsBuilder ?? (ref) async => null,
        ),
      ],
      child: const MaterialApp(home: DiscoverScreen()),
    ),
  );
}
