import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_episode.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

final sonarrServiceProvider = Provider<SonarrService>((ref) {
  final settings = ref.watch(currentSettingsProvider);
  if (settings.sonarrUrl.isEmpty || settings.sonarrApiKey.isEmpty) {
    throw Exception('Sonarr not configured');
  }
  return SonarrService(
    ApiClient(
      baseUrl: settings.sonarrUrl,
      apiKey: settings.sonarrApiKey,
      pinnedCertFingerprint: settings.pinForUrl(settings.sonarrUrl),
    ),
  );
});

/// Service for interacting with Sonarr API.
///
/// Provides series-specific operations plus shared activity operations
/// via [ArrActivityMixin].
class SonarrService with ArrActivityMixin {
  @override
  final ApiClient client;

  @override
  final ArrServiceConfig config = ArrServiceConfig.sonarr;

  SonarrService(this.client);

  @override
  Future<List<dynamic>> getQueue({Map<String, dynamic>? queryParameters}) {
    return super.getQueue(
      queryParameters: {
        'includeSeries': true,
        'includeEpisode': true,
        'includeUnknownSeriesItems': true,
        ...?queryParameters,
      },
    );
  }

  /// Fetches all series from Sonarr.
  Future<List<SonarrSeries>> getSeries() async {
    return fetchAllItems('series', SonarrSeries.fromJson);
  }

  /// Fetches a single series by its Sonarr ID.
  Future<SonarrSeries?> getSeriesById(int seriesId) async {
    try {
      final response = await client.get('/api/v3/series/$seriesId');
      return SonarrSeries.fromJson(response.data as Map<String, dynamic>);
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
      queryParameters: {
        'includeSeries': true,
        'includeEpisode': true,
        ...?queryParameters,
      },
    );
  }

  @override
  Future<List<dynamic>> getAllHistory({Map<String, dynamic>? queryParameters}) {
    return super.getAllHistory(
      queryParameters: {
        'includeSeries': true,
        'includeEpisode': true,
        ...?queryParameters,
      },
    );
  }

  /// Triggers an automatic search for the given series ID (entire series).
  Future<void> searchSeries(int seriesId) async {
    await _postCommand({'name': 'SeriesSearch', 'seriesId': seriesId});
  }

  /// Triggers an automatic search for a specific season.
  Future<void> searchSeason(int seriesId, int seasonNumber) async {
    await _postCommand({
      'name': 'SeasonSearch',
      'seriesId': seriesId,
      'seasonNumber': seasonNumber,
    });
  }

  /// Triggers an automatic search for specific episodes.
  Future<void> searchEpisodes(List<int> episodeIds) async {
    await _postCommand({'name': 'EpisodeSearch', 'episodeIds': episodeIds});
  }

  Future<void> _postCommand(Map<String, dynamic> data) async {
    await client.post('/api/v3/command', data: data);
  }

  /// Fetches all episodes for a series.
  Future<List<SonarrEpisode>> getEpisodes(int seriesId) async {
    final response = await client.get(
      '/api/v3/episode',
      queryParameters: {'seriesId': seriesId},
    );
    final data = response.data as List<dynamic>;
    return data
        .map(
          (episode) => SonarrEpisode.fromJson(episode as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  /// Fetches releases for interactive search.
  /// Note: Sonarr requires either episodeId or seriesId+seasonNumber for proper results.
  Future<List<dynamic>> getReleases({
    int? seriesId,
    int? seasonNumber,
    int? episodeId,
    CancelToken? cancelToken,
  }) async {
    final params = <String, dynamic>{};
    if (seriesId != null) params['seriesId'] = seriesId;
    if (seasonNumber != null) params['seasonNumber'] = seasonNumber;
    if (episodeId != null) params['episodeId'] = episodeId;

    return fetchReleases(params, cancelToken: cancelToken);
  }

  /// Grabs a specific release for download.
  Future<void> grabRelease({
    required String guid,
    required int indexerId,
  }) async {
    await grabReleaseByGuid(guid: guid, indexerId: indexerId);
  }

  /// Searches for series by term using the lookup API.
  ///
  /// [cancelToken] aborts the request once the search that asked for it has
  /// been superseded — see [ArrActivityMixin.lookupItems], which owns the
  /// empty-term guard, the isolate mapping and the degrade-to-`[]` rule the
  /// three arr lookups share.
  Future<List<SonarrSeries>> lookupSeries(
    String term, {
    CancelToken? cancelToken,
  }) {
    return lookupItems(
      'series/lookup',
      term,
      SonarrSeries.fromJson,
      cancelToken: cancelToken,
    );
  }

  /// Finds a series in the library by its TVDB ID.
  /// Returns null if not found in the library.
  Future<SonarrSeries?> getSeriesByTvdbId(int tvdbId) async {
    try {
      final series = await getSeries();
      return series.where((s) => s.tvdbId == tvdbId).firstOrNull;
    } catch (_) {
      return null;
    }
  }

  /// Fetches all quality profiles.
  Future<List<Map<String, dynamic>>> getQualityProfiles() async {
    return fetchQualityProfiles();
  }

  /// Updates a series's quality profile.
  Future<void> updateSeriesProfile(int seriesId, int qualityProfileId) async {
    await updateItemProfile('series', seriesId, qualityProfileId);
  }

  /// Updates a series's monitored state.
  Future<void> updateSeriesMonitored(int seriesId, bool monitored) async {
    await updateItemMonitored('series', seriesId, monitored);
  }

  /// Deletes a series from Sonarr.
  Future<void> deleteSeries(
    int seriesId, {
    bool deleteFiles = false,
    bool addImportListExclusion = false,
  }) async {
    await client.delete(
      '/api/v3/series/$seriesId',
      queryParameters: {
        'deleteFiles': deleteFiles,
        'addImportListExclusion': addImportListExclusion,
      },
    );
  }
}
