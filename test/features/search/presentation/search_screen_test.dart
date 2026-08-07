import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:seekarr/core/widgets/content_card.dart';
import 'package:seekarr/core/widgets/media_poster_card.dart';

import 'package:seekarr/features/discover/data/seerr_service.dart';
import 'package:seekarr/features/movies/data/radarr_service.dart';
import 'package:seekarr/features/movies/domain/models/radarr_movie.dart';
import 'package:seekarr/features/search/presentation/global_search_provider.dart';
import 'package:seekarr/features/search/presentation/search_screen.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/model_builders.dart';
import '../../../test_helpers/reel_finders.dart';

void main() {
  testWidgets('renders grouped global search result cards', (tester) async {
    await _pumpSearch(tester);

    expect(find.text('Radarr'), findsWidgets);
    expect(findLine('1 result'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Movie'), findsOneWidget);
    expect(find.text('Available'), findsWidgets);
    expect(_posterSizedContentCard(tester), findsOneWidget);
    expect(_solidActionIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('filters search results by selected service', (tester) async {
    await _pumpSearch(tester);

    await tester.tap(find.text('Seerr').first);
    await tester.pumpAndSettle();

    expect(find.text('Dune'), findsNothing);
    expect(find.text('No Seerr results'), findsOneWidget);

    await tester.tap(find.text('Radarr').first);
    await tester.pumpAndSettle();

    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('No Seerr results'), findsNothing);
  });

  testWidgets('tapping a result navigates with the result as route extra', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/search',
      routes: [
        GoRoute(
          path: '/search',
          builder: (context, state) => const SearchScreen(),
        ),
        GoRoute(
          path: '/services/radarr/movie/:id',
          builder: (context, state) {
            final movie = state.extra as RadarrMovie?;
            return Scaffold(
              body: Text(
                'Movie detail ${state.pathParameters['id']} ${movie?.title}',
              ),
            );
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dune'));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/services/radarr/movie/10');
    // The poster's shared-element tag travels with the route so the detail
    // page's Hero has a matching destination.
    expect(
      router.state.uri.queryParameters['heroTag'],
      'search_radarr_movie_10',
    );
    expect(find.text('Movie detail 10 Dune'), findsOneWidget);
  });

  testWidgets('a result with artwork flies its poster into the detail page', (
    tester,
  ) async {
    await _pumpSearch(tester, withPoster: true);

    final hero = tester.widget<Hero>(
      find.ancestor(of: find.byType(ContentCard), matching: find.byType(Hero)),
    );
    expect(hero.tag, 'search_radarr_movie_10');
    // Same toggle every other poster Hero uses, so the interactive swipe-back
    // carries this one home too.
    expect(hero.transitionOnUserGestures, MediaPosterCard.flightOnUserGestures);
  });

  testWidgets('a result without artwork does not fly an empty box', (
    tester,
  ) async {
    // No images on the lookup result, so `extractPosterUrl` yields nothing —
    // the same situation every Bazarr row is in.
    await _pumpSearch(tester);

    expect(find.byType(ContentCard), findsOneWidget);
    expect(
      find.ancestor(of: find.byType(ContentCard), matching: find.byType(Hero)),
      findsNothing,
    );
  });

  testWidgets('the flight into a real detail page completes cleanly', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/search',
      routes: [
        GoRoute(
          path: '/search',
          builder: (context, state) => const SearchScreen(),
        ),
        GoRoute(
          path: '/services/radarr/movie/:id',
          builder: (context, state) => Scaffold(
            body: SizedBox(
              width: 82,
              height: 123,
              child: MediaPosterCard(
                heroTag: state.uri.queryParameters['heroTag']!,
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(withPoster: true),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await _pumpFrames(tester);

    await tester.tap(find.text('Dune'));
    await tester.pump();
    // Mid-flight: two live Heroes sharing one tag would throw here rather than
    // at settle.
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.takeException(), isNull);

    // Discrete pumps, not pumpAndSettle: the destination poster's shimmer
    // placeholder repeats forever in tests.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MediaPosterCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Finder _solidActionIcon(IconData icon) {
  return find.descendant(
    of: find.byWidgetPredicate((widget) => widget is DecoratedBox),
    matching: find.byIcon(icon),
  );
}

Finder _posterSizedContentCard(WidgetTester tester) {
  for (final element in find.byType(ContentCard).evaluate()) {
    final box = element.renderObject as RenderBox?;
    if (box?.size == const Size(50, 75)) {
      return find.byWidget(element.widget);
    }
  }
  return find.byKey(const ValueKey('missing-poster-sized-content-card'));
}

Future<void> _pumpSearch(WidgetTester tester, {bool withPoster = false}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(withPoster: withPoster),
      child: const MaterialApp(home: SearchScreen()),
    ),
  );
  if (withPoster) {
    // A poster URL puts ContentCard's shimmer placeholder on screen, and its
    // controller repeats forever — `pumpAndSettle` would never return.
    await _pumpFrames(tester);
  } else {
    await tester.pumpAndSettle();
  }
}

/// Advances enough frames for the providers to resolve, without waiting for a
/// repeating shimmer to stop.
Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

_overrides({bool withPoster = false}) {
  return [
    currentSettingsProvider.overrideWith(
      (ref) => const SettingsModel(
        radarrUrl: 'http://radarr.local:7878',
        radarrApiKey: 'key',
      ),
    ),
    globalSearchQueryProvider.overrideWith((ref) => 'dune'),
    seerrServiceProvider.overrideWith((ref) => FakeSeerrService()),
    radarrServiceProvider.overrideWith(
      (ref) => _SearchRadarrService(
        results: [
          buildMovie(
            id: 10,
            title: 'Dune',
            year: 2024,
            images: withPoster
                ? const [
                    {'coverType': 'poster', 'url': '/MediaCover/10/poster.jpg'},
                  ]
                : const [],
          ),
        ],
      ),
    ),
  ];
}

class _SearchRadarrService extends FakeRadarrService {
  final List<RadarrMovie> results;

  _SearchRadarrService({required this.results});

  @override
  Future<List<RadarrMovie>> lookupMovies(
    String term, {
    CancelToken? cancelToken,
  }) async => results;
}
