import 'package:seekarr/core/status/arr_queue_snapshot.dart';
import 'package:seekarr/features/music/domain/models/lidarr_album.dart';
import 'package:seekarr/features/music/domain/models/lidarr_artist.dart';
import 'package:seekarr/features/music/domain/models/lidarr_track.dart';

/// Resolves the badge status for a Lidarr artist.
MediaStatusInfo lidarrArtistStatus(
  LidarrArtist artist, {
  ArrQueueEntry? queueEntry,
}) {
  return mediaStatusFromQueue(
    availability: lidarrArtistAvailability(artist),
    monitored: artist.monitored,
    queueEntry: queueEntry,
  );
}

MediaAvailability lidarrArtistAvailability(LidarrArtist artist) {
  if (artist.statistics == null) return MediaAvailability.unknown;

  final tracks = artist.trackCount;
  if (tracks <= 0) {
    return artist.trackFileCount > 0
        ? MediaAvailability.available
        : MediaAvailability.unavailable;
  }

  return availabilityFromCounts(
    fileCount: artist.trackFileCount,
    totalCount: tracks,
  );
}

/// Resolves the badge status for a single Lidarr album.
///
/// [queueEntry] comes from the album-keyed snapshot, so an album currently
/// being grabbed shows its download state instead of a bare "missing" dot.
MediaStatusInfo lidarrAlbumStatus(
  LidarrAlbum album, {
  ArrQueueEntry? queueEntry,
}) {
  return mediaStatusFromQueue(
    availability: lidarrAlbumAvailability(album),
    monitored: album.monitored,
    queueEntry: queueEntry,
  );
}

MediaAvailability lidarrAlbumAvailability(LidarrAlbum album) {
  if (album.statistics == null) return MediaAvailability.unknown;

  final tracks = album.trackCount;
  if (tracks <= 0) {
    return album.trackFileCount > 0
        ? MediaAvailability.available
        : MediaAvailability.unavailable;
  }

  return availabilityFromCounts(
    fileCount: album.trackFileCount,
    totalCount: tracks,
  );
}

/// The album's manifest gap in words: `10 of 12 tracks`.
String? lidarrAlbumSummary(LidarrAlbum album) {
  if (album.trackCount <= 0) return null;
  return '${album.trackFileCount} of ${album.trackCount} tracks';
}

/// Resolves the status of one track.
///
/// A track row used to convey `hasFile` with a 7pt circle filled
/// `colorScheme.primary` — the same eight lines the episode row carried, in a
/// file with no `Semantics` at all. Resolving it here is what lets the row draw
/// a tone-aware badge and speak the state.
MediaStatusInfo lidarrTrackStatus(LidarrTrack track) {
  return MediaStatusInfo(
    availability: track.hasFile
        ? MediaAvailability.available
        : MediaAvailability.missing,
  );
}
