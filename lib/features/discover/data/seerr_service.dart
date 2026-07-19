import 'dart:isolate';
import 'package:seekarr/core/api/api_client.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/discover/domain/models/seerr_genre.dart';
import 'package:seekarr/features/discover/domain/models/seerr_request.dart';
import 'package:seekarr/core/models/media_preview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final seerrServiceProvider = Provider<SeerrService>((ref) {
  final settings = ref.watch(currentSettingsProvider);
  if (settings.seerrUrl.isEmpty || settings.seerrApiKey.isEmpty) {
    throw Exception('Seerr not configured');
  }
  return SeerrService(
    ApiClient(baseUrl: settings.seerrUrl, apiKey: settings.seerrApiKey),
  );
});

class SeerrService {
  final ApiClient _client;

  SeerrService(this._client);

  Future<List<SeerrRequest>> getRequests() async {
    try {
      final response = await _client.get(
        '/api/v1/request',
        queryParameters: {
          'take': 20,
          'skip': 0,
          'sort': 'added',
          'filter': 'all',
        },
      );
      final results = response.data['results'] as List<dynamic>;
      final requests = results
          .map((e) {
            try {
              return SeerrRequest.fromJson(e);
            } catch (e) {
              return null;
            }
          })
          .whereType<SeerrRequest>()
          .toList();

      // Hydrate missing titles
      return await Future.wait(
        requests.map((request) async {
          if (request.media?.title != null &&
              request.media?.posterPath != null &&
              request.media!.title != 'Unknown Media' &&
              !request.media!.title!.startsWith('Unknown Media (')) {
            return request;
          }

          try {
            if (request.media?.mediaType == 'movie' &&
                request.media?.tmdbId != null) {
              final details = await getMovie(request.media!.tmdbId!);
              return request.copyWith(
                media: request.media?.copyWith(
                  title: details['title'],
                  year: details['releaseDate']?.toString().substring(0, 4),
                  posterPath:
                      details['posterPath']?.toString() ??
                      details['poster_path']?.toString(),
                ),
              );
            } else if (request.media?.mediaType == 'tv' &&
                request.media?.tmdbId != null) {
              final details = await getTv(request.media!.tmdbId!);
              return request.copyWith(
                media: request.media?.copyWith(
                  title: details['name'],
                  year: details['firstAirDate']?.toString().substring(0, 4),
                  posterPath:
                      details['posterPath']?.toString() ??
                      details['poster_path']?.toString(),
                ),
              );
            }
          } catch (e) {
            // Ignore hydration errors
          }
          return request;
        }),
      );
    } catch (e) {
      return [];
    }
  }

  Future<void> deleteRequest(int requestId) async {
    await _client.delete('/api/v1/request/$requestId');
  }

  Future<List<MediaPreview>> getDiscoverMovies({
    int page = 1,
    int? genre,
    String? sortBy,
  }) async {
    try {
      final response = await _client.get(
        '/api/v1/discover/movies',
        queryParameters: {
          'page': page,
          if (genre != null) 'genre': genre,
          if (sortBy != null) 'sortBy': sortBy,
        },
      );
      final results = response.data['results'] as List<dynamic>;
      return await Isolate.run(
        () => results
            .map((e) => MediaPreview.fromJson(e, forcedMediaType: 'movie'))
            .toList(),
      );
    } catch (e) {
      return [];
    }
  }

  Future<List<MediaPreview>> getDiscoverTV({
    int page = 1,
    int? genre,
    String? sortBy,
  }) async {
    try {
      final response = await _client.get(
        '/api/v1/discover/tv',
        queryParameters: {
          'page': page,
          if (genre != null) 'genre': genre,
          if (sortBy != null) 'sortBy': sortBy,
        },
      );
      final results = response.data['results'] as List<dynamic>;
      return await Isolate.run(
        () => results
            .map((e) => MediaPreview.fromJson(e, forcedMediaType: 'tv'))
            .toList(),
      );
    } catch (e) {
      return [];
    }
  }

  /// Upcoming movies (Overseerr/Jellyseerr `/discover/movies/upcoming`).
  Future<List<MediaPreview>> getDiscoverUpcomingMovies({int page = 1}) async {
    try {
      final response = await _client.get(
        '/api/v1/discover/movies/upcoming',
        queryParameters: {'page': page},
      );
      final results = response.data['results'] as List<dynamic>;
      return await Isolate.run(
        () => results
            .map((e) => MediaPreview.fromJson(e, forcedMediaType: 'movie'))
            .toList(),
      );
    } catch (e) {
      return [];
    }
  }

  /// Upcoming TV (Overseerr/Jellyseerr `/discover/tv/upcoming`).
  Future<List<MediaPreview>> getDiscoverUpcomingTv({int page = 1}) async {
    try {
      final response = await _client.get(
        '/api/v1/discover/tv/upcoming',
        queryParameters: {'page': page},
      );
      final results = response.data['results'] as List<dynamic>;
      return await Isolate.run(
        () => results
            .map((e) => MediaPreview.fromJson(e, forcedMediaType: 'tv'))
            .toList(),
      );
    } catch (e) {
      return [];
    }
  }

  /// Available movie genres (used to build per-genre discover rows).
  Future<List<SeerrGenre>> getMovieGenres() => _getGenres('movie');

  /// Available TV genres.
  Future<List<SeerrGenre>> getTvGenres() => _getGenres('tv');

  Future<List<SeerrGenre>> _getGenres(String mediaType) async {
    try {
      final response = await _client.get(
        '/api/v1/discover/genreslider/$mediaType',
      );
      final results = (response.data as List<dynamic>);
      return results
          .whereType<Map<String, dynamic>>()
          .map(SeerrGenre.fromJson)
          .where((g) => g.id > 0 && g.name.isNotEmpty)
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<MediaPreview>> getDiscoverTrending({int page = 1}) async {
    try {
      final response = await _client.get(
        '/api/v1/discover/trending',
        queryParameters: {'page': page},
      );
      final results = response.data['results'] as List<dynamic>;
      return await Isolate.run(
        () => results.map((e) => MediaPreview.fromJson(e)).toList(),
      );
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>> getMovie(int movieId) async {
    final response = await _client.get('/api/v1/movie/$movieId');
    return response.data;
  }

  Future<Map<String, dynamic>> getTv(int tvId) async {
    final response = await _client.get('/api/v1/tv/$tvId');
    return response.data;
  }

  Future<Map<String, dynamic>> getCollection(int collectionId) async {
    try {
      final response = await _client.get('/api/v1/collection/$collectionId');
      return response.data;
    } catch (_) {
      return {};
    }
  }

  /// TMDB person details (bio, department, birthday) proxied by Overseerr /
  /// Jellyseerr. Returns `{}` on any error so the UI can degrade gracefully.
  Future<Map<String, dynamic>> getPerson(int personId) async {
    try {
      final response = await _client.get('/api/v1/person/$personId');
      return response.data as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// A person's combined movie + TV cast filmography, de-duped by id and sorted
  /// by rating so the strongest credits lead. Returns `[]` on error.
  Future<List<MediaPreview>> getPersonCombinedCredits(int personId) async {
    try {
      final response = await _client.get(
        '/api/v1/person/$personId/combinedCredits',
      );
      final cast = (response.data['cast'] as List<dynamic>? ?? const []);
      final seen = <int>{};
      final items = <MediaPreview>[];
      for (final entry in cast) {
        if (entry is! Map<String, dynamic>) continue;
        final mediaType = entry['mediaType'] ?? entry['media_type'];
        if (mediaType != 'movie' && mediaType != 'tv') continue;
        final id = (entry['id'] as num?)?.toInt();
        if (id == null || !seen.add(id)) continue;
        items.add(MediaPreview.fromJson(entry));
      }
      items.sort((a, b) => (b.voteAverage ?? 0).compareTo(a.voteAverage ?? 0));
      return items;
    } catch (_) {
      return const [];
    }
  }

  /// Searches for movies and TV shows by query string.
  /// Filters out 'person' results to only return movies and TV shows.
  Future<List<MediaPreview>> search(String query, {int page = 1}) async {
    if (query.isEmpty) return [];
    try {
      // URL-encode the query to handle spaces and special characters
      final encodedQuery = Uri.encodeComponent(query);
      final response = await _client.get(
        '/api/v1/search',
        queryParameters: {'query': encodedQuery, 'page': page},
      );
      final results = response.data['results'] as List<dynamic>;
      // Filter out 'person' results - only keep movies and TV shows
      return results
          .where((e) {
            final mediaType = e['mediaType'] ?? e['media_type'];
            return mediaType == 'movie' || mediaType == 'tv';
          })
          .map((e) => MediaPreview.fromJson(e))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Gets available Radarr servers from Seerr.
  Future<List<Map<String, dynamic>>> getRadarrServers() async {
    try {
      final response = await _client.get('/api/v1/service/radarr');
      final data = response.data as List<dynamic>;
      return data.cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  /// Gets available Sonarr servers from Seerr.
  Future<List<Map<String, dynamic>>> getSonarrServers() async {
    try {
      final response = await _client.get('/api/v1/service/sonarr');
      final data = response.data as List<dynamic>;
      return data.cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  /// Gets quality profiles for a specific Radarr server.
  Future<Map<String, dynamic>> getRadarrProfiles(int serverId) async {
    final response = await _client.get('/api/v1/service/radarr/$serverId');
    return response.data;
  }

  /// Gets quality profiles for a specific Sonarr server.
  Future<Map<String, dynamic>> getSonarrProfiles(int serverId) async {
    final response = await _client.get('/api/v1/service/sonarr/$serverId');
    return response.data;
  }

  /// Creates a new media request.
  /// [mediaType] should be 'movie' or 'tv'.
  /// [mediaId] is the TMDB ID of the media.
  Future<void> createRequest({
    required String mediaType,
    required int mediaId,
    int? profileId,
    String? rootFolder, // Root folder path
    int? serverId,
    bool is4k = false,
    List<int>? seasons, // For TV shows - if null, requests all seasons
  }) async {
    final body = <String, dynamic>{
      'mediaType': mediaType,
      'mediaId': mediaId,
      'is4k': is4k,
    };

    // For TV shows, seasons is required - use 'all' or specific season numbers
    if (mediaType == 'tv') {
      if (seasons != null && seasons.isNotEmpty) {
        body['seasons'] = seasons;
      } else {
        body['seasons'] = 'all';
      }
    }

    if (profileId != null) body['profileId'] = profileId;
    if (rootFolder != null) body['rootFolder'] = rootFolder;
    if (serverId != null) body['serverId'] = serverId;

    await _client.post('/api/v1/request', data: body);
  }

  /// Deletes a media item from Seerr tracking.
  /// This removes the media record but does NOT delete files from Radarr/Sonarr.
  /// [mediaId] is the Seerr internal media ID (not TMDB ID).
  Future<void> deleteMedia(int mediaId) async {
    await _client.delete('/api/v1/media/$mediaId');
  }

  /// Deletes the media files from Radarr/Sonarr via Seerr.
  /// This removes the actual files from the media server.
  /// [mediaId] is the Seerr internal media ID (not TMDB ID).
  Future<void> deleteMediaFile(int mediaId) async {
    await _client.delete('/api/v1/media/$mediaId/file');
  }
}
