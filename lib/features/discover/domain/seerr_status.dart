import 'package:seekarr/core/status/arr_queue_snapshot.dart';
import 'package:seekarr/core/utils/dynamic_map_utils.dart';

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
