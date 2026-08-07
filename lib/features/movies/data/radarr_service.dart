import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

final radarrServiceProvider = Provider<RadarrService>((ref) {
  final settings = ref.watch(currentSettingsProvider);
  if (settings.radarrUrl.isEmpty || settings.radarrApiKey.isEmpty) {
    throw Exception('Radarr not configured');
  }
  return RadarrService(
    ApiClient(
      baseUrl: settings.radarrUrl,
      apiKey: settings.radarrApiKey,
      pinnedCertFingerprint: settings.pinForUrl(settings.radarrUrl),
    ),
  );
});

/// Service for interacting with Radarr API.
///
/// Provides movie-specific operations plus shared activity operations
/// via [ArrActivityMixin].
class RadarrService with ArrActivityMixin {
  @override
  final ApiClient client;

  @override
  final ArrServiceConfig config = ArrServiceConfig.radarr;

  RadarrService(this.client);

  @override
  Future<List<dynamic>> getQueue({Map<String, dynamic>? queryParameters}) {
    return super.getQueue(
      queryParameters: {'includeMovie': true, ...?queryParameters},
    );
  }

  /// Fetches all movies from Radarr.
  Future<List<RadarrMovie>> getMovies() async {
    return fetchAllItems('movie', RadarrMovie.fromJson);
  }

  /// Fetches a single movie by its Radarr ID.
  Future<RadarrMovie?> getMovie(int movieId) async {
    try {
      final response = await client.get('/api/v3/movie/$movieId');
      return RadarrMovie.fromJson(response.data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<dynamic>> getHistory({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) {
    return super.getHistory(
      page: page,
      pageSize: pageSize,
      queryParameters: {'includeMovie': true, ...?queryParameters},
    );
  }

  @override
  Future<List<dynamic>> getAllHistory({Map<String, dynamic>? queryParameters}) {
    return super.getAllHistory(
      queryParameters: {'includeMovie': true, ...?queryParameters},
    );
  }

  /// Triggers an automatic search for the given movie ID.
  Future<void> searchMovie(int movieId) async {
    await client.post(
      '/api/v3/command',
      data: {
        'name': 'MoviesSearch',
        'movieIds': [movieId],
      },
    );
  }

  /// Fetches releases for interactive search.
  Future<List<dynamic>> getReleases(
    int movieId, {
    CancelToken? cancelToken,
  }) async {
    return fetchReleases({'movieId': movieId}, cancelToken: cancelToken);
  }

  /// Grabs a specific release for download.
  Future<void> grabRelease({
    required String guid,
    required int indexerId,
  }) async {
    await grabReleaseByGuid(guid: guid, indexerId: indexerId);
  }

  /// Searches for movies by term using the lookup API.
  ///
  /// [cancelToken] aborts the request once the search that asked for it has
  /// been superseded — see [ArrActivityMixin.lookupItems], which owns the
  /// empty-term guard, the isolate mapping and the degrade-to-`[]` rule the
  /// three arr lookups share.
  Future<List<RadarrMovie>> lookupMovies(
    String term, {
    CancelToken? cancelToken,
  }) {
    return lookupItems(
      'movie/lookup',
      term,
      RadarrMovie.fromJson,
      cancelToken: cancelToken,
    );
  }

  /// Finds a movie in the library by its TMDB ID.
  /// Returns null if not found in the library.
  Future<RadarrMovie?> getMovieByTmdbId(int tmdbId) async {
    try {
      final movies = await getMovies();
      return movies.where((m) => m.tmdbId == tmdbId).firstOrNull;
    } catch (_) {
      return null;
    }
  }

  /// Fetches all quality profiles.
  Future<List<Map<String, dynamic>>> getQualityProfiles() async {
    return fetchQualityProfiles();
  }

  /// Updates a movie's quality profile.
  Future<void> updateMovieProfile(int movieId, int qualityProfileId) async {
    await updateItemProfile('movie', movieId, qualityProfileId);
  }

  /// Updates a movie's monitored state.
  Future<void> updateMovieMonitored(int movieId, bool monitored) async {
    await updateItemMonitored('movie', movieId, monitored);
  }

  /// Deletes a movie from Radarr.
  Future<void> deleteMovie(
    int movieId, {
    bool deleteFiles = false,
    bool addImportExclusion = false,
  }) async {
    await client.delete(
      '/api/v3/movie/$movieId',
      queryParameters: {
        'deleteFiles': deleteFiles,
        'addImportExclusion': addImportExclusion,
      },
    );
  }
}
