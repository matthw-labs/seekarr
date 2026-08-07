import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/models/rating_source.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/discover/presentation/discover_detail_view_model.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

typedef DiscoverDetailExtras = ({
  bool? isInLibrary,
  bool libraryCheckDone,
  List<DiscoverDetailRating>? lookupRatings,
});

final discoverDetailExtrasProvider = FutureProvider.autoDispose
    .family<
      DiscoverDetailExtras,
      ({int mediaId, String mediaType, int? tvdbId, double? voteAverage})
    >((ref, arg) async {
      final settings = ref.watch(currentSettingsProvider);
      final mediaType = arg.mediaType == 'movie' ? 'movie' : 'tv';
      final isRadarrConfigured =
          settings.radarrUrl.isNotEmpty && settings.radarrApiKey.isNotEmpty;
      final isSonarrConfigured =
          settings.sonarrUrl.isNotEmpty && settings.sonarrApiKey.isNotEmpty;

      bool? isInLibrary;
      List<DiscoverDetailRating>? lookupRatings;
      final libraryCheckDone = mediaType == 'movie'
          ? isRadarrConfigured
          : isSonarrConfigured && arg.tvdbId != null;

      if (mediaType == 'movie') {
        if (isRadarrConfigured) {
          final radarrService = ref.read(radarrServiceProvider);

          try {
            final movie = await radarrService.getMovieByTmdbId(arg.mediaId);
            isInLibrary = movie != null;
          } catch (_) {
            isInLibrary = null;
          }

          if (arg.voteAverage == null) {
            try {
              final results = await radarrService.lookupMovies(
                'tmdb:${arg.mediaId}',
              );
              if (results.isNotEmpty) {
                lookupRatings = _mapRatings(results.first.ratings);
              }
            } catch (_) {
              lookupRatings = null;
            }
          }
        }
      } else {
        if (isSonarrConfigured && arg.tvdbId != null) {
          final sonarrService = ref.read(sonarrServiceProvider);

          try {
            final series = await sonarrService.getSeriesByTvdbId(arg.tvdbId!);
            isInLibrary = series != null;
          } catch (_) {
            isInLibrary = null;
          }

          if (arg.voteAverage == null) {
            try {
              final results = await sonarrService.lookupSeries(
                'tvdb:${arg.tvdbId}',
              );
              if (results.isNotEmpty) {
                lookupRatings = _mapRatings(results.first.ratings);
              }
            } catch (_) {
              lookupRatings = null;
            }
          }
        }
      }

      return (
        isInLibrary: isInLibrary,
        libraryCheckDone: libraryCheckDone,
        lookupRatings: lookupRatings,
      );
    });

List<DiscoverDetailRating> _mapRatings(List<RatingSource> ratings) {
  return ratings
      .map(
        (rating) => (
          name: rating.name,
          value: rating.value,
          votes: rating.votes,
          icon: rating.icon,
        ),
      )
      .toList(growable: false);
}
