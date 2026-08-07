import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';

final movieDetailProvider = FutureProvider.autoDispose
    .family<RadarrMovie?, int>((ref, movieId) async {
      if (movieId <= 0) {
        return null;
      }

      final service = ref.watch(radarrServiceProvider);
      return service.getMovie(movieId);
    });
