import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final moviesProvider = FutureProvider<List<RadarrMovie>>((ref) async {
  final service = ref.watch(radarrServiceProvider);
  return service.getMovies();
});
