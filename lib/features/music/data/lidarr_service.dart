import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/domain/models/lidarr_track.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

final lidarrServiceProvider = Provider<LidarrService>((ref) {
  final settings = ref.watch(currentSettingsProvider);
  if (settings.lidarrUrl.isEmpty || settings.lidarrApiKey.isEmpty) {
    throw Exception('Lidarr not configured');
  }
  return LidarrService(
    ApiClient(
      baseUrl: settings.lidarrUrl,
      apiKey: settings.lidarrApiKey,
      pinnedCertFingerprint: settings.pinForUrl(settings.lidarrUrl),
    ),
  );
});

/// Service for interacting with Lidarr API.
///
/// Provides artist-specific operations plus shared activity operations
/// via [ArrActivityMixin].
class LidarrService with ArrActivityMixin {
  @override
  final ApiClient client;

  @override
  final ArrServiceConfig config = ArrServiceConfig.lidarr;

  LidarrService(this.client);

  /// Fetches all artists from Lidarr.
  Future<List<LidarrArtist>> getArtists() async {
    return fetchAllItems('artist', LidarrArtist.fromJson);
  }

  /// Fetches a single artist by ID, returning a typed model.
  Future<LidarrArtist?> getArtistById(int artistId) async {
    try {
      final response = await client.get('/api/v1/artist/$artistId');
      return LidarrArtist.fromJson(response.data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Fetches all albums for an artist.
  Future<List<LidarrAlbum>> getAlbums(int artistId) async {
    final response = await client.get(
      '/api/v1/album',
      queryParameters: {'artistId': artistId},
    );
    final data = response.data as List<dynamic>;
    return data
        .map((album) => LidarrAlbum.fromJson(album as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Fetches all tracks for an album.
  Future<List<LidarrTrack>> getTracks(int albumId) async {
    final response = await client.get(
      '/api/v1/track',
      queryParameters: {'albumId': albumId},
    );
    final data = response.data as List<dynamic>;
    return data
        .map((track) => LidarrTrack.fromJson(track as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Triggers an automatic search for an artist.
  Future<void> searchArtist(int artistId) async {
    await client.post(
      '/api/v1/command',
      data: {'name': 'ArtistSearch', 'artistId': artistId},
    );
  }

  /// Triggers an automatic search for albums.
  Future<void> searchAlbums(List<int> albumIds) async {
    await client.post(
      '/api/v1/command',
      data: {'name': 'AlbumSearch', 'albumIds': albumIds},
    );
  }

  /// Fetches releases for interactive search.
  Future<List<dynamic>> getReleases({
    int? artistId,
    int? albumId,
    CancelToken? cancelToken,
  }) async {
    final params = <String, dynamic>{};
    if (artistId != null) params['artistId'] = artistId;
    if (albumId != null) params['albumId'] = albumId;

    return fetchReleases(params, cancelToken: cancelToken);
  }

  /// Grabs a specific release for download.
  Future<void> grabRelease({
    required String guid,
    required int indexerId,
  }) async {
    await grabReleaseByGuid(guid: guid, indexerId: indexerId);
  }

  /// Searches for artists by term using the lookup API.
  ///
  /// [cancelToken] aborts the request once the search that asked for it has
  /// been superseded — see [ArrActivityMixin.lookupItems], which owns the
  /// empty-term guard, the isolate mapping and the degrade-to-`[]` rule the
  /// three arr lookups share.
  Future<List<LidarrArtist>> lookupArtists(
    String term, {
    CancelToken? cancelToken,
  }) {
    return lookupItems(
      'artist/lookup',
      term,
      LidarrArtist.fromJson,
      cancelToken: cancelToken,
    );
  }

  /// Fetches all quality profiles.
  Future<List<Map<String, dynamic>>> getQualityProfiles() async {
    return fetchQualityProfiles();
  }

  /// Updates an artist's quality profile.
  Future<void> updateArtistProfile(int artistId, int qualityProfileId) async {
    await updateItemProfile('artist', artistId, qualityProfileId);
  }

  /// Updates an artist's monitored state.
  Future<void> updateArtistMonitored(int artistId, bool monitored) async {
    await updateItemMonitored('artist', artistId, monitored);
  }

  /// Deletes an artist from Lidarr.
  Future<void> deleteArtist(
    int artistId, {
    bool deleteFiles = false,
    bool addImportListExclusion = false,
  }) async {
    await client.delete(
      '/api/v1/artist/$artistId',
      queryParameters: {
        'deleteFiles': deleteFiles,
        'addImportListExclusion': addImportListExclusion,
      },
    );
  }
}
