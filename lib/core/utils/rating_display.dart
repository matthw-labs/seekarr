import 'package:cupola/core/models/rating_source.dart';

/// Display vocabulary for rating pills.
///
/// The -arr APIs hand back a JSON key per source (`imdb`, `rottenTomatoes`,
/// `trakt`) and the parser turns it into a two-letter badge. On a page that
/// stacks five of them that produced `MC 53.0`, `RO 57.0`, `TR 7.1` — three of
/// five labels being abbreviations that appear nowhere else in the app and are
/// not the sources' own names. `RO` is not what Rotten Tomatoes is called by
/// anyone, and it is only two characters because the parser's default branch
/// takes the first two letters of a key it does not recognise.
///
/// Every rating pill on every detail page routes its label through here, so a
/// source is named the way its own brand names it, once.

/// Legible name for a rating source, resolved from whatever identifiers survived
/// the -arr payload.
///
/// Takes both fields because neither alone is reliable: [icon] is the truncated
/// badge (`RO`, `TR`, `MB`) and [name] is a display string that, for a
/// single-source payload, is not a source name at all — Sonarr's and Lidarr's
/// parse path puts a vote count there. Whichever of the two is recognisable
/// wins; when neither is, [icon] is kept unchanged rather than guessed at,
/// because inventing a brand name for an unknown source would be worse than
/// showing what the server said.
String ratingSourceLabel({required String icon, required String name}) {
  return _knownSourceLabel(icon) ?? _knownSourceLabel(name) ?? icon;
}

/// Re-labels every rating in [ratings] so the pill, its tooltip and its spoken
/// name all say the same legible thing.
///
/// Both fields are replaced on purpose. `RatingChip` renders `icon` and speaks
/// `name`, so today a Sonarr rating reads `TVDB 7.2` on screen and announces
/// itself to a screen reader as "145000 voti rating 7.2" — a vote count where a
/// source name belongs, in the wrong language.
List<RatingSource> legibleRatings(List<RatingSource> ratings) {
  return ratings
      .map((rating) {
        final label = ratingSourceLabel(icon: rating.icon, name: rating.name);
        return RatingSource(
          name: label,
          value: rating.value,
          votes: rating.votes,
          icon: label,
        );
      })
      .toList(growable: false);
}

/// A score formatted for a pill, plus the scale it is measured on.
///
/// [denominator] is the visual suffix (`/10`, `/100`, `%`) and is empty only
/// for a source whose scale is unknown.
typedef RatingDisplay = ({String value, String denominator});

/// Formats [value] on its source's own scale.
///
/// Five pills in a row used to read `IMDb 8.4  TMDB 8.1  MC 53.0  RO 57.0
/// TR 7.1` — five numbers presented identically, three of which are on entirely
/// different scales. A 53 next to an 8.4 reads as a much worse score than it is,
/// and the `.0` is actively misleading: a decimal place on a /100 scale is what
/// makes the five look comparable in the first place.
///
/// The scales are fixed properties of the sources, not of the payload: IMDb,
/// TMDB, TVDB, Trakt and MusicBrainz are 0–10; Metacritic is 0–100; Rotten
/// Tomatoes is a percentage. A source this app does not know keeps one decimal
/// and no denominator — showing what the server said beats asserting a scale.
///
/// Takes the identifiers rather than a model for the same reason
/// [ratingSourceLabel] does: the -arr pages hold `RatingSource` while the Seerr
/// page holds its own record type, and one scale table has to serve both.
RatingDisplay ratingDisplayFor({
  required String icon,
  required String name,
  required double value,
}) {
  switch (_knownSourceLabel(icon) ?? _knownSourceLabel(name)) {
    case 'Metacritic':
      return (value: value.round().toString(), denominator: '/100');
    case 'Rotten Tomatoes':
      return (value: value.round().toString(), denominator: '%');
    case 'IMDb':
    case 'TMDB':
    case 'TVDB':
    case 'Trakt':
    case 'MusicBrainz':
      return (value: value.toStringAsFixed(1), denominator: '/10');
    default:
      return (value: value.toStringAsFixed(1), denominator: '');
  }
}

/// Matches an -arr source key, a display name or a truncated badge against the
/// sources this app actually renders.
///
/// Punctuation and case are stripped first so `rottenTomatoes`,
/// `Rotten Tomatoes`, `ROTTENTOMATOES` and `RO` all land on one answer — the
/// parser produces all four spellings for the same source depending on which
/// branch built it.
String? _knownSourceLabel(String value) {
  final key = value.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
  if (key.isEmpty) return null;

  switch (key) {
    case 'imdb':
      return 'IMDb';
    case 'tmdb':
    case 'themoviedb':
      return 'TMDB';
    case 'tvdb':
    case 'thetvdb':
      return 'TVDB';
    case 'metacritic':
    case 'mc':
      return 'Metacritic';
    case 'rotten':
    case 'rottentomatoes':
    case 'ro':
    case 'rt':
      return 'Rotten Tomatoes';
    case 'trakt':
    case 'tr':
      return 'Trakt';
    case 'musicbrainz':
    case 'mb':
      return 'MusicBrainz';
    default:
      return null;
  }
}
