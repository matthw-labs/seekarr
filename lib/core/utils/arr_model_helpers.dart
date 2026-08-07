import 'package:cupola/core/models/rating_source.dart';

/// Parses *arr API ratings data into a list of [RatingSource].
List<RatingSource> parseArrRatings(
  dynamic ratingsData, {
  bool allowMultiSource = true,
  bool allowSingleSource = true,
  String singleSourceIcon = 'TVDB',
  String? singleSourceName,
}) {
  if (ratingsData is! Map<String, dynamic>) {
    return [];
  }

  final ratings = <RatingSource>[];
  final isMultiSource = ratingsData.values.any(
    (value) => value is Map && value['value'] != null,
  );

  if (allowMultiSource && isMultiSource) {
    ratingsData.forEach((source, data) {
      if (data is Map && data['value'] != null) {
        final value = (data['value'] as num?)?.toDouble();
        final votes = (data['votes'] as num?)?.toInt() ?? 0;

        if (value != null) {
          ratings.add(
            RatingSource(
              name: _displayNameForSource(source),
              value: value,
              votes: votes,
              icon: _iconForSource(source),
            ),
          );
        }
      }
    });

    return ratings;
  }

  if (!allowSingleSource || isMultiSource) {
    return ratings;
  }

  final value = (ratingsData['value'] as num?)?.toDouble();
  final votes = (ratingsData['votes'] as num?)?.toInt() ?? 0;

  if (value == null) {
    return ratings;
  }

  ratings.add(
    RatingSource(
      // The badge, never a vote count. `RatingSource.name` is the field
      // `RatingChip` speaks to a screen reader and shows in its tooltip, so the
      // old `'$votes voti'` announced a Sonarr rating as "145000 voti rating
      // 7.2" — a number where a source name belongs, in Italian, in an
      // English-only app. The count is already carried by `votes`.
      name: singleSourceName ?? singleSourceIcon,
      value: value,
      votes: votes,
      icon: singleSourceIcon,
    ),
  );

  return ratings;
}

/// Parses a JSON genres field into a typed `List<String>`.
List<String> parseGenreList(dynamic genres) {
  if (genres is! List) {
    return [];
  }

  return genres.map((genre) => genre.toString()).toList();
}

/// Extracts a poster URL string from an *arr images list for MediaPreview use.
String? extractPosterPathFromImages(List<dynamic> images) {
  try {
    final poster = images.firstWhere(
      (image) => image['coverType'] == 'poster',
      orElse: () => null,
    );

    return poster?['remoteUrl'] ?? poster?['url'];
  } catch (_) {
    return null;
  }
}

String _iconForSource(String source) {
  switch (source.toLowerCase()) {
    case 'tmdb':
      return 'TMDB';
    case 'imdb':
      return 'IMDb';
    case 'tvdb':
      return 'TVDB';
    case 'metacritic':
      return 'MC';
    // Radarr and Sonarr send `rottenTomatoes`, not `rotten`, and they send
    // `trakt` — neither of which used to match, so both fell to the default
    // branch and became the first two letters of the key: `RO` and `TR`.
    case 'rotten':
    case 'rottentomatoes':
      return 'RT';
    case 'trakt':
      return 'Trakt';
    default:
      final upper = source.toUpperCase();
      return upper.length >= 2 ? upper.substring(0, 2) : upper;
  }
}

String _displayNameForSource(String source) {
  switch (source.toLowerCase()) {
    case 'tmdb':
      return 'TMDB';
    case 'imdb':
      return 'IMDb';
    case 'tvdb':
      return 'TVDB';
    case 'metacritic':
      return 'Metacritic';
    case 'rotten':
    case 'rottentomatoes':
      return 'Rotten Tomatoes';
    case 'trakt':
      return 'Trakt';
    default:
      // Not `toUpperCase()`: an unrecognised key used to arrive on screen as
      // `ROTTENTOMATOES`. Left as the service spelled it, so an unknown source
      // is shown rather than shouted.
      return source;
  }
}
