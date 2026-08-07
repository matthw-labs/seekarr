import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/features/series/domain/models/sonarr_episode.dart';
import 'package:cupola/features/series/domain/models/sonarr_season.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';

/// Resolves the badge status for a Sonarr series.
MediaStatusInfo sonarrSeriesStatus(
  SonarrSeries series, {
  ArrQueueEntry? queueEntry,
}) {
  return mediaStatusFromQueue(
    availability: sonarrSeriesAvailability(series),
    monitored: series.monitored,
    queueEntry: queueEntry,
  );
}

MediaAvailability sonarrSeriesAvailability(SonarrSeries series) {
  if (series.status.toLowerCase() == 'deleted') {
    return MediaAvailability.deleted;
  }

  final files = series.episodeFileCount;
  if (series.statistics == null || files == null) {
    return MediaAvailability.unknown;
  }

  // `episodeCount` counts aired, monitored episodes, so a continuing series
  // that holds everything broadcast so far is `available` rather than being
  // stuck at `partial` forever.
  final aired = series.episodeCount ?? 0;
  if (aired <= 0) {
    return files > 0
        ? MediaAvailability.available
        : MediaAvailability.unavailable;
  }

  return availabilityFromCounts(fileCount: files, totalCount: aired);
}

/// Resolves the status of one season.
///
/// The season header used to signal monitoring with a green bookmark while the
/// rows beneath it signalled `hasFile` with an indigo dot — two vocabularies for
/// related facts, neither of them written down anywhere on the page. Both now
/// come from here, so the header badge and the row badge cannot disagree.
MediaStatusInfo sonarrSeasonStatus(
  SonarrSeason season, {
  ArrQueueEntry? queueEntry,
}) {
  return mediaStatusFromQueue(
    availability: sonarrSeasonAvailability(season),
    monitored: season.monitored,
    queueEntry: queueEntry,
  );
}

MediaAvailability sonarrSeasonAvailability(SonarrSeason season) {
  // Nothing has aired yet: an announced season is not a missing one.
  if (season.episodeCount <= 0) {
    return season.episodeFileCount > 0
        ? MediaAvailability.available
        : MediaAvailability.unavailable;
  }

  return availabilityFromCounts(
    fileCount: season.episodeFileCount,
    totalCount: season.episodeCount,
  );
}

/// The season's manifest gap in words: `8 of 10 episodes`.
///
/// The gap is the only reason this region exists — Sonarr models expected
/// episodes (`episodeCount`) separately from present ones
/// (`episodeFileCount`) — so it is stated rather than left to a bar. When more
/// episodes are still to air the total is named too, because `8 of 8 episodes`
/// on a season that will end up with twelve is true and misleading at once.
String? sonarrSeasonSummary(SonarrSeason season) {
  if (season.episodeCount <= 0) {
    return season.totalEpisodeCount > 0
        ? '${season.totalEpisodeCount} episodes announced'
        : null;
  }

  final aired = '${season.episodeFileCount} of ${season.episodeCount}';
  if (season.hasUnairedEpisodes) {
    return '$aired aired · ${season.totalEpisodeCount} total';
  }

  return '$aired episodes';
}

/// Resolves the status of one episode.
///
/// [now] is injectable so the unaired case is testable without freezing the
/// clock; it defaults to the wall clock.
MediaStatusInfo sonarrEpisodeStatus(
  SonarrEpisode episode, {
  DateTime? now,
  ArrQueueEntry? queueEntry,
}) {
  return mediaStatusFromQueue(
    availability: sonarrEpisodeAvailability(episode, now: now),
    monitored: episode.monitored,
    queueEntry: queueEntry,
  );
}

MediaAvailability sonarrEpisodeAvailability(
  SonarrEpisode episode, {
  DateTime? now,
}) {
  if (episode.hasFile) return MediaAvailability.available;
  // Not yet broadcast: nothing is wrong and nothing is expected, so this is
  // "Not Released" rather than the red "Missing" every future episode of a
  // continuing series used to draw.
  if (episode.isUnairedAt(now ?? DateTime.now())) {
    return MediaAvailability.unavailable;
  }

  return MediaAvailability.missing;
}
