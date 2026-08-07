import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_episode.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';

final seriesDetailProvider = FutureProvider.autoDispose
    .family<SonarrSeries?, int>((ref, seriesId) async {
      if (seriesId <= 0) {
        return null;
      }

      final service = ref.watch(sonarrServiceProvider);
      return service.getSeriesById(seriesId);
    });

final seriesEpisodesProvider = FutureProvider.autoDispose
    .family<List<SonarrEpisode>, int>((ref, seriesId) async {
      if (seriesId <= 0) {
        return const [];
      }

      final service = ref.watch(sonarrServiceProvider);
      return service.getEpisodes(seriesId);
    });
