import 'package:seekarr/core/status/arr_queue_snapshot.dart';

/// Lidarr's queue indexed two ways.
///
/// A queue record names an album, while the library screen and artist detail
/// page badge artists — so the same fetch is indexed by both, and the expensive
/// album → artist resolution happens once.
class LidarrQueueSnapshots {
  final ArrQueueSnapshot byArtist;
  final ArrQueueSnapshot byAlbum;

  const LidarrQueueSnapshots({required this.byArtist, required this.byAlbum});

  static const LidarrQueueSnapshots empty = LidarrQueueSnapshots(
    byArtist: ArrQueueSnapshot.empty,
    byAlbum: ArrQueueSnapshot.empty,
  );
}
