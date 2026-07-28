import 'package:seekarr/core/status/arr_queue_snapshot.dart';
import 'package:seekarr/features/music/domain/models/lidarr_album.dart';
import 'package:seekarr/features/music/domain/models/lidarr_artist.dart';

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
