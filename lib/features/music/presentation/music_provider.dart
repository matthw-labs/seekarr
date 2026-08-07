import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final musicProvider = FutureProvider<List<LidarrArtist>>((ref) async {
  final service = ref.watch(lidarrServiceProvider);
  return service.getArtists();
});
