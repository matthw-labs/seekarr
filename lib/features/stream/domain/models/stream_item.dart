/// One item anywhere in a media server's tree — film, show, season, episode,
/// album or track.
///
/// **One type for every depth, on purpose.** A Jellyfin `BaseItemDto` and a Plex
/// `Metadata` element describe all of those with the same fields, which is a real
/// difference from the arr side: Radarr, Sonarr and Lidarr each needed their own
/// model and their own detail screen, and the Stream service needs one of each.
/// That is why `ServiceRoutes.jellyfinItem` is a single recursive route.
library;

import 'package:flutter/foundation.dart';

enum StreamItemKind {
  movie,
  series,
  season,
  episode,
  album,
  track,
  other;

  /// Whether this kind contains other items, and so navigates deeper rather than
  /// terminating in a detail page.
  bool get hasChildren =>
      this == StreamItemKind.series ||
      this == StreamItemKind.season ||
      this == StreamItemKind.album;
}

/// How a library is being read.
///
/// The order is the order the browse offers them, and [all] being last is the
/// design's load-bearing choice rather than a default that drifted.
///
/// **The idle-month test:** if a Stream library screen would look identical after
/// nobody watched anything for a month, it is Radarr rendered twice and must not
/// ship. Every lens above [all] fails to render at all without watch history, so
/// the landing state cannot degrade into a title list. [all] is available as an
/// explicit sort and is never the lens a library opens on.
enum StreamLibraryLens {
  continueWatching(label: 'Continue'),
  nextUp(label: 'Next up'),
  recentlyAdded(label: 'Recent'),
  unplayed(label: 'Unplayed'),
  all(label: 'A–Z');

  const StreamLibraryLens({required this.label});

  final String label;

  /// Whether this lens needs a viewer to mean anything.
  ///
  /// Jellyfin can answer these for any household member because an admin API key
  /// may pass any `userId`. Plex cannot: its token *is* the user and `/library/*`
  /// takes no impersonation parameter, so a Plex library has exactly one
  /// perspective and its viewer chip is hidden rather than showing a list of one.
  bool get isPerViewer => this != StreamLibraryLens.recentlyAdded;
}

@immutable
class StreamItem {
  /// Opaque server id — a Jellyfin GUID or a Plex `ratingKey`.
  final String id;

  final String title;

  /// Series name for an episode, artist for a track, year for a film.
  final String? subtitle;

  final StreamItemKind kind;

  /// Relative artwork path; resolved by the client layer, which owns the
  /// credential. See [StreamSession.posterPath] for why this is not a URL.
  final String? posterPath;

  final int? year;

  /// Total runtime in milliseconds.
  ///
  /// Milliseconds rather than either server's native unit, because the two
  /// disagree and both are traps: Jellyfin counts .NET *ticks* (100ns, so
  /// `/ 10000`) and Plex counts milliseconds for `duration`/`viewOffset` but
  /// *epoch seconds* for `addedAt`/`lastViewedAt`. Normalising at the client
  /// boundary is what keeps a two-hour film from rendering as two minutes.
  final int? runtimeMs;

  /// Whether this item is fully watched **by the viewer this was fetched for**.
  final bool isPlayed;

  /// Resume position in milliseconds, when part-watched.
  final int? resumeOffsetMs;

  /// Unwatched children, for a series or season badge.
  final int? unplayedChildCount;

  const StreamItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.kind,
    required this.posterPath,
    required this.year,
    required this.runtimeMs,
    required this.isPlayed,
    required this.resumeOffsetMs,
    required this.unplayedChildCount,
  });

  /// Fraction watched, 0..1, or null when there is no resume point.
  double? get resumeProgress {
    final offset = resumeOffsetMs;
    final total = runtimeMs;
    if (offset == null || total == null || total <= 0) return null;
    return (offset / total).clamp(0.0, 1.0);
  }

  bool get isInProgress => resumeProgress != null && !isPlayed;
}
