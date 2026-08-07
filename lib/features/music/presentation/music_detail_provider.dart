import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';

final musicDetailProvider = FutureProvider.autoDispose
    .family<LidarrArtist?, int>((ref, artistId) async {
      if (artistId <= 0) {
        return null;
      }

      final service = ref.watch(lidarrServiceProvider);
      return service.getArtistById(artistId);
    });

final musicAlbumsProvider = FutureProvider.autoDispose
    .family<List<LidarrAlbum>, int>((ref, artistId) async {
      if (artistId <= 0) {
        return const [];
      }

      final service = ref.watch(lidarrServiceProvider);
      return service.getAlbums(artistId);
    });
