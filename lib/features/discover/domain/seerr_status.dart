import 'package:seekarr/core/status/arr_queue_snapshot.dart';
import 'package:seekarr/core/utils/dynamic_map_utils.dart';
import 'package:seekarr/features/discover/domain/models/discover_detail_model.dart';

/// Resolves the badge status for a Seerr media entry.
///
/// Seerr's `status` code alone cannot say whether a "Processing" item is
/// actually moving: that lives in `mediaInfo.downloadStatus`, an array of live
/// records forwarded from the connected \*arr instances. Reading it turns a
/// static "Processing" into a real "Downloading 42%".
MediaStatusInfo seerrMediaStatus(
  Map<String, dynamic>? mediaInfo, {
  bool is4k = false,
}) {
  final code = intOrNull(mediaInfo?[is4k ? 'status4k' : 'status']);
  final entry = seerrDownloadEntry(
    mediaInfo?[is4k ? 'downloadStatus4k' : 'downloadStatus'],
  );

  // Seerr has no record of this title at all.
  if (code == null) {
    return const MediaStatusInfo(
      availability: MediaAvailability.notTracked,
      labelOverride: 'Available to Request',
    );
  }

  final availability = switch (code) {
    4 => MediaAvailability.partial,
    5 => MediaAvailability.available,
    6 => MediaAvailability.deleted,
    2 || 3 => MediaAvailability.missing,
    _ => MediaAvailability.unknown,
  };

  // Seerr's own coarse pipeline states, superseded by the live download record
  // whenever one is present.
  final fallbackPipeline = switch (code) {
    2 => MediaPipeline.queued,
    3 => MediaPipeline.downloading,
    _ => null,
  };

  return MediaStatusInfo(
    availability: availability,
    pipeline: entry?.pipeline ?? fallbackPipeline,
    progress: entry?.progress,
    hasWarning: entry?.hasWarning ?? false,
    detail: entry?.detail,
    // Preserve Seerr's wording only while there is no better live state to
    // report.
    labelOverride: entry != null
        ? entry.label
        : switch (code) {
            2 => 'Pending',
            3 => 'Processing',
            4 => 'Partially Available',
            6 => 'Deleted',
            _ => null,
          },
  );
}

/// Resolves a status for every season of a title, keyed by season number.
///
/// Seerr reports per-season availability inside `mediaInfo.seasons`, a list of
/// `{seasonNumber, status}` records. That mapping used to happen inside
/// `DiscoverSeasonsList.build`, which both put a raw `Map<String, dynamic>` in
/// the presentation layer's hands and produced a bare
/// [SeerrMediaAvailability] the shared status vocabulary could not render.
/// Routing it through [seerrMediaStatus] means a season badge speaks exactly the
/// same language as the page's own — including Seerr's wording for
/// "Partially Available".
///
/// Seasons absent from the payload are [seerrUntrackedSeasonStatus].
///
/// The returned map covers **every** season in [seasons], so a caller never has
/// to invent a fallback for a missing key — which is what the seasons list was
/// doing, restating this exact `notTracked` decision inside a widget.
Map<int, MediaStatusInfo> seerrSeasonStatuses(
  Map<String, dynamic>? mediaInfo,
  List<TvSeason> seasons,
) {
  final byNumber = <int, MediaStatusInfo>{};

  final rawSeasons = mediaInfo?['seasons'];
  if (rawSeasons is List) {
    for (final raw in rawSeasons) {
      final entry = mapOrNull(raw);
      if (entry == null) continue;

      final seasonNumber = intOrNull(entry['seasonNumber']);
      if (seasonNumber == null) continue;

      byNumber[seasonNumber] = seerrMediaStatus(<String, dynamic>{
        'status': entry['status'],
      });
    }
  }

  for (final season in seasons) {
    byNumber.putIfAbsent(season.seasonNumber, () => seerrUntrackedSeasonStatus);
  }

  return byNumber;
}

/// The status of a season Seerr has no record of.
///
/// Named and exported so the one decision lives in one place: Seerr has never
/// heard of this season, which is a different fact from "unknown" and the one the
/// Request button acts on. [seerrSeasonStatuses] fills absent seasons with it, and
/// `DiscoverSeasonsList` reads it for the total-function lookup Dart's
/// `Map<int, …>[]` forces — rather than writing a second `notTracked` literal
/// that could silently disagree with this one.
const MediaStatusInfo seerrUntrackedSeasonStatus = MediaStatusInfo(
  availability: MediaAvailability.notTracked,
);

/// Parses Seerr's `downloadStatus` array into a single queue entry.
///
/// The records use the same field names as an \*arr `/queue` record, except
/// that the remaining bytes arrive as `sizeLeft` rather than `sizeleft` —
/// `queueProgress` already accepts both spellings.
ArrQueueEntry? seerrDownloadEntry(dynamic rawDownloadStatus) {
  if (rawDownloadStatus is! List || rawDownloadStatus.isEmpty) return null;

  final entries = <ArrQueueEntry>[];
  for (final raw in rawDownloadStatus) {
    final item = mapOrNull(raw);
    if (item == null) continue;
    final entry = ArrQueueEntry.fromQueueItem(item);
    if (entry != null) entries.add(entry);
  }

  return mergeArrQueueEntries(entries);
}
