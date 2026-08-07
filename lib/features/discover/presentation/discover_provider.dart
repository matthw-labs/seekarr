import 'package:cupola/features/discover/domain/models/seerr_genre.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sort key for the "Top Rated" rows.
const kTopRatedSort = 'vote_average.desc';

/// Identifies a per-genre discover row.
typedef GenreRowKey = ({String mediaType, int genreId});

final requestsProvider = FutureProvider<List<SeerrRequest>>((ref) async {
  final service = ref.watch(seerrServiceProvider);
  return service.getRequests();
});

// Basic providers for the main Discover screen (Carousels) - fetching page 1
final discoverMoviesProvider = FutureProvider<List<MediaPreview>>((ref) async {
  final service = ref.watch(seerrServiceProvider);
  return service.getDiscoverMovies(page: 1);
});

final discoverTVProvider = FutureProvider<List<MediaPreview>>((ref) async {
  final service = ref.watch(seerrServiceProvider);
  return service.getDiscoverTV(page: 1);
});

final discoverTrendingProvider = FutureProvider<List<MediaPreview>>((
  ref,
) async {
  final service = ref.watch(seerrServiceProvider);
  return service.getDiscoverTrending(page: 1);
});

// Upcoming + top-rated carousels (page 1)
final discoverUpcomingMoviesProvider = FutureProvider<List<MediaPreview>>((
  ref,
) async {
  final service = ref.watch(seerrServiceProvider);
  return service.getDiscoverUpcomingMovies(page: 1);
});

final discoverUpcomingTvProvider = FutureProvider<List<MediaPreview>>((
  ref,
) async {
  final service = ref.watch(seerrServiceProvider);
  return service.getDiscoverUpcomingTv(page: 1);
});

final discoverTopRatedMoviesProvider = FutureProvider<List<MediaPreview>>((
  ref,
) async {
  final service = ref.watch(seerrServiceProvider);
  return service.getDiscoverMovies(page: 1, sortBy: kTopRatedSort);
});

// Genre list + per-genre carousels
final movieGenresProvider = FutureProvider<List<SeerrGenre>>((ref) async {
  final service = ref.watch(seerrServiceProvider);
  return service.getMovieGenres();
});

final discoverByGenreProvider =
    FutureProvider.family<List<MediaPreview>, GenreRowKey>((ref, key) async {
      final service = ref.watch(seerrServiceProvider);
      if (key.mediaType == 'tv') {
        return service.getDiscoverTV(page: 1, genre: key.genreId);
      }
      return service.getDiscoverMovies(page: 1, genre: key.genreId);
    });

// Paginated per-genre + top-rated providers for "See All" screens
final discoverByGenrePageProvider =
    FutureProvider.family<List<MediaPreview>, ({GenreRowKey key, int page})>((
      ref,
      args,
    ) async {
      final service = ref.watch(seerrServiceProvider);
      if (args.key.mediaType == 'tv') {
        return service.getDiscoverTV(page: args.page, genre: args.key.genreId);
      }
      return service.getDiscoverMovies(
        page: args.page,
        genre: args.key.genreId,
      );
    });

// Family providers for pagination in "See All" screens
final discoverMoviesPageProvider =
    FutureProvider.family<List<MediaPreview>, int>((ref, page) async {
      final service = ref.watch(seerrServiceProvider);
      return service.getDiscoverMovies(page: page);
    });

final discoverTVPageProvider = FutureProvider.family<List<MediaPreview>, int>((
  ref,
  page,
) async {
  final service = ref.watch(seerrServiceProvider);
  return service.getDiscoverTV(page: page);
});

final discoverTrendingPageProvider =
    FutureProvider.family<List<MediaPreview>, int>((ref, page) async {
      final service = ref.watch(seerrServiceProvider);
      return service.getDiscoverTrending(page: page);
    });
