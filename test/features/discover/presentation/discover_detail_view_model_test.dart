import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/features/discover/presentation/discover_detail_view_model.dart';

void main() {
  group('DiscoverDetailViewModel', () {
    test('parses movie response with rich metadata', () {
      final cast = List.generate(
        25,
        (index) => {
          'name': 'Actor $index',
          'character': 'Character $index',
          'profilePath': '/actor-$index.jpg',
        },
      );
      final keywords = List.generate(10, (index) => {'name': 'Keyword $index'});
      final details = <String, dynamic>{
        'title': 'Test Movie',
        'overview': 'A movie overview.',
        'posterPath': '/poster.jpg',
        'mediaInfo': {'status': 4, 'path': '/movies/Test Movie'},
        'genres': [
          {'name': 'Action'},
          {'name': 'Drama'},
        ],
        'production_companies': [
          {'name': 'Studio A'},
          {'name': 'Studio B'},
          {'name': 'Studio C'},
        ],
        'releaseDate': '2024-03-25',
        'runtime': 123,
        'voteAverage': 7.4,
        'voteCount': 240,
        'credits': {
          'cast': cast,
          'crew': [
            {'job': 'Director', 'name': 'Director A'},
            {'job': 'Director', 'name': 'Director B'},
            {'job': 'Director', 'name': 'Director C'},
            {'job': 'Writer', 'name': 'Writer A'},
            {'job': 'Screenplay', 'name': 'Writer B'},
            {'job': 'Writer', 'name': 'Writer C'},
          ],
        },
        'keywords': keywords,
        'externalIds': {'tvdbId': 999},
      };

      final viewModel = DiscoverDetailViewModel.fromResponse(details);

      expect(viewModel.title, 'Test Movie');
      expect(viewModel.overview, 'A movie overview.');
      expect(viewModel.posterUrl, 'https://image.tmdb.org/t/p/w500/poster.jpg');
      expect(viewModel.seerrStatus, 'Partially Available');
      expect(viewModel.isAvailable, isFalse);
      expect(viewModel.isPartiallyAvailable, isTrue);
      expect(viewModel.genres, 'Action, Drama');
      expect(viewModel.genresList, ['Action', 'Drama']);
      expect(viewModel.year, '2024');
      // Seerr's `123min` now speaks the same voice as Radarr's page.
      expect(viewModel.runtimeStr, '2h 3m');
      expect(viewModel.studios, ['Studio A', 'Studio B', 'Studio C']);
      expect(viewModel.voteAverage, 7.4);
      expect(viewModel.voteCount, 240);
      expect(viewModel.cast, hasLength(20));
      expect(viewModel.cast.first.name, 'Actor 0');
      expect(viewModel.cast.first.character, 'Character 0');
      expect(viewModel.directors, ['Director A', 'Director B']);
      expect(viewModel.writers, ['Writer A', 'Writer B']);
      expect(viewModel.keywords, hasLength(8));
      expect(viewModel.keywords.first, 'Keyword 0');
      expect(viewModel.tvdbId, 999);
      expect(viewModel.metadataLine, 'Action, Drama');
      expect(viewModel.hasManageableMedia, isFalse);
      expect(viewModel.servicePath, '/movies/Test Movie');
      expect(viewModel.directorNames, 'Director A, Director B');
      expect(viewModel.writerNames, 'Writer A, Writer B');
    });

    test('parses tv response and prefers initial poster override', () {
      final details = <String, dynamic>{
        'name': 'Test Show',
        'overview': 'A tv overview.',
        'posterPath': '/ignored.jpg',
        'mediaInfo': {'status': 2},
        'genres': [
          {'name': 'Sci-Fi'},
        ],
        'firstAirDate': '2021-01-10',
        'numberOfSeasons': 3,
        'networks': [
          {'name': 'HBO'},
          {'name': 'Max'},
          {'name': 'Ignored'},
        ],
        'vote_average': 8.1,
        'vote_count': 1000,
        'tvdbId': 321,
      };

      final viewModel = DiscoverDetailViewModel.fromResponse(
        details,
        initialPosterUrl: 'https://cdn.example.com/poster.jpg',
      );

      expect(viewModel.title, 'Test Show');
      expect(viewModel.posterUrl, 'https://cdn.example.com/poster.jpg');
      expect(viewModel.seerrStatus, 'Pending');
      expect(viewModel.year, '2021');
      expect(viewModel.numberOfSeasons, 3);
      expect(viewModel.networks, 'HBO, Max');
      expect(viewModel.voteAverage, 8.1);
      expect(viewModel.voteCount, 1000);
      expect(viewModel.tvdbId, 321);
      expect(viewModel.metadataLine, 'Sci-Fi • HBO, Max');
    });

    test('handles missing optional data with safe defaults', () {
      final viewModel = DiscoverDetailViewModel.fromResponse(
        const <String, dynamic>{},
      );

      expect(viewModel.title, 'Unknown');
      expect(viewModel.overview, isEmpty);
      expect(viewModel.posterUrl, isEmpty);
      expect(viewModel.seerrStatus, 'Available to Request');
      expect(viewModel.isAvailable, isFalse);
      expect(viewModel.genres, isEmpty);
      expect(viewModel.genresList, isEmpty);
      expect(viewModel.year, isEmpty);
      expect(viewModel.runtimeStr, isNull);
      expect(viewModel.numberOfSeasons, isNull);
      expect(viewModel.networks, isEmpty);
      expect(viewModel.studios, isEmpty);
      expect(viewModel.voteAverage, isNull);
      expect(viewModel.voteCount, isNull);
      expect(viewModel.cast, isEmpty);
      expect(viewModel.directors, isEmpty);
      expect(viewModel.writers, isEmpty);
      expect(viewModel.keywords, isEmpty);
      expect(viewModel.tvdbId, isNull);
      expect(viewModel.metadataLine, isEmpty);
      expect(viewModel.hasManageableMedia, isFalse);
      expect(viewModel.servicePath, isNull);
    });

    test('maps seerr status codes consistently', () {
      expect(
        DiscoverDetailViewModel.mapSeerrStatus(null),
        'Available to Request',
      );
      expect(DiscoverDetailViewModel.mapSeerrStatus(1), 'Unknown');
      expect(DiscoverDetailViewModel.mapSeerrStatus(2), 'Pending');
      expect(DiscoverDetailViewModel.mapSeerrStatus(3), 'Processing');
      expect(DiscoverDetailViewModel.mapSeerrStatus(4), 'Partially Available');
      expect(DiscoverDetailViewModel.mapSeerrStatus(5), 'Available');
      expect(DiscoverDetailViewModel.mapSeerrStatus(6), 'Deleted');
      expect(DiscoverDetailViewModel.mapSeerrStatus(99), 'Unknown');
    });

    test('parses runtime from string episode runtimes without crashing', () {
      final viewModel = DiscoverDetailViewModel.fromResponse({
        'name': 'Runtime Test Show',
        'episodeRunTime': ['45', 50],
      });

      expect(viewModel.runtimeStr, '45m');
    });

    test('bills one cast tile per person, not per role', () {
      // TMDB returns one credits entry per role, so an actor playing a dual
      // role comes back twice under the same person id. The cast rail tags each
      // tile `person_<id>`, and two Heroes with one tag assert on the next push.
      final viewModel = DiscoverDetailViewModel.fromResponse({
        'title': 'Dual Role',
        'credits': {
          'cast': [
            {
              'id': 7,
              'name': 'Tatiana Maslany',
              'character': 'Sarah',
              'profilePath': '/tatiana.jpg',
            },
            {'id': 7, 'name': 'Tatiana Maslany', 'character': 'Helena'},
            {'id': 9, 'name': 'Jordan Gavaris', 'character': 'Felix'},
          ],
        },
      });

      expect(viewModel.cast.map((member) => member.id), [7, 9]);
      // The extra role is folded into the tile rather than dropped.
      expect(viewModel.cast.first.character, 'Sarah / Helena');
      // The duplicate carried no image; the entry that did keeps it.
      expect(viewModel.cast.first.profilePath, '/tatiana.jpg');
    });

    test('a duplicated credit does not cost the 20th actor their place', () {
      final cast = [
        for (var index = 0; index < 21; index++)
          {'id': index + 1, 'name': 'Actor $index', 'character': 'C$index'},
      ];
      // The lead is billed twice, as a dual role would be.
      cast.insert(1, {'id': 1, 'name': 'Actor 0', 'character': 'Alter ego'});

      final viewModel = DiscoverDetailViewModel.fromResponse({
        'title': 'Long Cast',
        'credits': {'cast': cast},
      });

      expect(viewModel.cast, hasLength(20));
      expect(viewModel.cast.map((member) => member.id).toSet(), hasLength(20));
    });

    test('keeps unidentified cast entries, which cannot collide', () {
      final viewModel = DiscoverDetailViewModel.fromResponse({
        'title': 'No Ids',
        'credits': {
          'cast': [
            {'name': 'Extra A', 'character': 'Passer-by'},
            {'name': 'Extra B', 'character': 'Passer-by'},
          ],
        },
      });

      // Id 0 makes the rail untappable, so it builds no Hero and no tag —
      // deduping these would only lose faces.
      expect(viewModel.cast, hasLength(2));
    });

    test('parses season episodes when present', () {
      final viewModel = DiscoverDetailViewModel.fromResponse({
        'name': 'Episode Test Show',
        'seasons': [
          {
            'id': 1,
            'seasonNumber': 1,
            'episodeCount': 1,
            'episodes': [
              {
                'name': 'Pilot',
                'seasonNumber': 1,
                'episodeNumber': 1,
                'airDate': '2024-01-01',
              },
            ],
          },
        ],
      });

      expect(viewModel.seasons, hasLength(1));
      expect(viewModel.seasons.single.episodes, hasLength(1));
      expect(viewModel.seasons.single.episodes.single.name, 'Pilot');
    });
  });
}
