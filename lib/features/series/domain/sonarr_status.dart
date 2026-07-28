import 'package:seekarr/core/status/arr_queue_snapshot.dart';
import 'package:seekarr/features/series/domain/models/sonarr_series.dart';

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
