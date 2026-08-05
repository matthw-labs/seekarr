import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/utils/arr_model_helpers.dart';

void main() {
  group('parseArrRatings', () {
    test('returns empty list for null input', () {
      expect(parseArrRatings(null), isEmpty);
    });

    test('returns empty list for non-map input', () {
      expect(parseArrRatings('ratings'), isEmpty);
    });

    test('parses multi-source ratings', () {
      final ratings = parseArrRatings({
        'tmdb': {'value': 8.1, 'votes': 200},
        'imdb': {'value': 7.2, 'votes': 1000},
      });

      expect(ratings, hasLength(2));
      expect(ratings[0].name, 'TMDB');
      expect(ratings[0].icon, 'TMDB');
      expect(ratings[0].value, 8.1);
      expect(ratings[0].votes, 200);
      expect(ratings[1].name, 'IMDb');
      expect(ratings[1].icon, 'IMDb');
    });

    test('names the two keys that used to fall through to two letters', () {
      // `rottenTomatoes` and `trakt` are the keys Radarr and Sonarr actually
      // send. Neither had a case, so both took the default branch and became the
      // first two letters of the key: `RO` and `TR`, with names `ROTTENTOMATOES`
      // and `TRAKT`. Fixed here at source rather than only compensated for in
      // `rating_display.dart` at paint time.
      final ratings = parseArrRatings({
        'rottenTomatoes': {'value': 57, 'votes': 0},
        'trakt': {'value': 7.1, 'votes': 900},
      });

      expect(ratings, hasLength(2));
      expect(ratings[0].name, 'Rotten Tomatoes');
      expect(ratings[0].icon, 'RT');
      expect(ratings[1].name, 'Trakt');
      expect(ratings[1].icon, 'Trakt');
    });

    test(
      'leaves an unknown multi-source key spelled as the service sent it',
      () {
        final ratings = parseArrRatings({
          'letterboxd': {'value': 3.8, 'votes': 12},
        });

        expect(ratings, hasLength(1));
        // Was `toUpperCase()`, which put `ROTTENTOMATOES` on screen for the one
        // real key that fell through. An unknown source is shown, not shouted.
        expect(ratings.single.name, 'letterboxd');
        expect(ratings.single.icon, 'LE');
      },
    );

    test('skips multi-source entries with null values', () {
      final ratings = parseArrRatings({
        'tmdb': {'value': null, 'votes': 200},
        'imdb': {'value': 7.2, 'votes': 1000},
      });

      expect(ratings, hasLength(1));
      expect(ratings.single.name, 'IMDb');
    });

    test('skips multi-source entries with non-map values', () {
      final ratings = parseArrRatings({
        'tmdb': 'invalid',
        'imdb': {'value': 7.2, 'votes': 1000},
      });

      expect(ratings, hasLength(1));
      expect(ratings.single.name, 'IMDb');
    });

    test('parses single-source ratings with default icon and name', () {
      final ratings = parseArrRatings({'value': 8.4, 'votes': 145000});

      expect(ratings, hasLength(1));
      expect(ratings.single.icon, 'TVDB');
      // The badge, not the vote count. `name` is what `RatingChip` speaks, and
      // it used to announce "145000 voti rating 7.2" — Italian, in an
      // English-only app, where a source name belongs.
      expect(ratings.single.name, 'TVDB');
      expect(ratings.single.votes, 145000);
      expect(ratings.single.value, 8.4);
    });

    test('parses single-source ratings with custom icon', () {
      final ratings = parseArrRatings({
        'value': 8.4,
        'votes': 145000,
      }, singleSourceIcon: 'MB');

      expect(ratings.single.icon, 'MB');
      expect(ratings.single.name, 'MB');
    });

    test('parses single-source ratings with custom name', () {
      final ratings = parseArrRatings({
        'value': 8.4,
        'votes': 145000,
      }, singleSourceName: 'MusicBrainz');

      expect(ratings.single.name, 'MusicBrainz');
    });

    test('returns empty list when single-source value is null', () {
      final ratings = parseArrRatings({'value': null, 'votes': 145000});

      expect(ratings, isEmpty);
    });

    test('defaults votes to zero when missing', () {
      final ratings = parseArrRatings({'value': 8.4});

      expect(ratings.single.votes, 0);
      // A missing vote count no longer becomes the pill's spoken name.
      expect(ratings.single.name, 'TVDB');
    });

    test('can disable single-source parsing', () {
      final ratings = parseArrRatings({
        'value': 8.4,
        'votes': 145000,
      }, allowSingleSource: false);

      expect(ratings, isEmpty);
    });

    test('can disable multi-source parsing', () {
      final ratings = parseArrRatings({
        'tmdb': {'value': 8.1, 'votes': 200},
      }, allowMultiSource: false);

      expect(ratings, isEmpty);
    });
  });

  group('parseGenreList', () {
    test('returns empty list for null input', () {
      expect(parseGenreList(null), isEmpty);
    });

    test('returns empty list for non-list input', () {
      expect(parseGenreList('genres'), isEmpty);
    });

    test('returns string genres as-is', () {
      expect(parseGenreList(['Action', 'Drama']), ['Action', 'Drama']);
    });

    test('stringifies mixed genre values', () {
      expect(parseGenreList(['Action', 2, null]), ['Action', '2', 'null']);
    });

    test('returns empty list for empty input', () {
      expect(parseGenreList([]), isEmpty);
    });
  });

  group('extractPosterPathFromImages', () {
    test('returns null for empty images', () {
      expect(extractPosterPathFromImages([]), isNull);
    });

    test('prefers remoteUrl when present', () {
      final posterPath = extractPosterPathFromImages([
        {
          'coverType': 'poster',
          'remoteUrl': 'https://example.com/remote.jpg',
          'url': '/local/poster.jpg',
        },
      ]);

      expect(posterPath, 'https://example.com/remote.jpg');
    });

    test('falls back to url when remoteUrl is missing', () {
      final posterPath = extractPosterPathFromImages([
        {'coverType': 'poster', 'url': '/local/poster.jpg'},
      ]);

      expect(posterPath, '/local/poster.jpg');
    });

    test('returns null when no poster cover type is present', () {
      final posterPath = extractPosterPathFromImages([
        {'coverType': 'banner', 'url': '/local/banner.jpg'},
      ]);

      expect(posterPath, isNull);
    });

    test('returns null when image entries are invalid', () {
      final posterPath = extractPosterPathFromImages(['invalid']);

      expect(posterPath, isNull);
    });
  });
}
