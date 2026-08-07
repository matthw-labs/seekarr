import 'dart:isolate';

import 'package:dio/dio.dart';

import 'package:cupola/core/api/api_client.dart';

/// Configuration for *arr service activity endpoints.
class ArrServiceConfig {
  /// API version string (e.g., 'v3' for Radarr/Sonarr, 'v1' for Lidarr)
  final String apiVersion;

  /// Sort key for wanted endpoints (e.g., 'airDateUtc' for Radarr/Sonarr, 'releaseDate' for Lidarr)
  final String sortKey;

  /// Extra query parameters required for cutoff endpoints.
  final Map<String, dynamic> cutoffParams;

  const ArrServiceConfig({
    required this.apiVersion,
    required this.sortKey,
    this.cutoffParams = const {},
  });

  static const radarr = ArrServiceConfig(
    apiVersion: 'v3',
    sortKey: 'airDateUtc',
  );
  static const sonarr = ArrServiceConfig(
    apiVersion: 'v3',
    sortKey: 'airDateUtc',
    cutoffParams: {'includeEpisodeFile': true},
  );
  static const lidarr = ArrServiceConfig(
    apiVersion: 'v1',
    sortKey: 'releaseDate',
  );
  static const readarr = ArrServiceConfig(
    apiVersion: 'v1',
    sortKey: 'releaseDate',
  );
}

/// Mixin providing shared activity endpoints and common service helpers for
/// *arr services (Radarr, Sonarr, Lidarr).
mixin ArrActivityMixin {
  /// The API client used for requests.
  ApiClient get client;

  /// The service configuration (API version, sort key).
  ArrServiceConfig get config;

  /// Fetches the download queue.
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async {
    final response = await client.get(
      '/api/${config.apiVersion}/queue',
      queryParameters: queryParameters,
    );
    return response.data['records'] as List<dynamic>;
  }

  /// Fetches recent history.
  Future<List<dynamic>> getHistory({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async {
    final response = await client.get(
      '/api/${config.apiVersion}/history',
      queryParameters: {
        'page': page,
        'pageSize': pageSize,
        ...?queryParameters,
      },
    );
    return response.data['records'] as List<dynamic>;
  }

  Future<List<dynamic>> _fetchAllPages(
    String endpoint, {
    Map<String, dynamic> extraParams = const {},
    int pageSize = 250,
    int maxPages = 50,
  }) async {
    final records = <dynamic>[];

    for (var page = 1; page <= maxPages; page++) {
      final response = await client.get(
        '/api/${config.apiVersion}/$endpoint',
        queryParameters: {'page': page, 'pageSize': pageSize, ...extraParams},
      );

      final data = response.data as Map<String, dynamic>;
      final pageRecords = (data['records'] as List<dynamic>? ?? const []);
      final totalRecords = switch (data['totalRecords']) {
        final int value => value,
        final num value => value.toInt(),
        final String value => int.tryParse(value) ?? records.length,
        _ => records.length + pageRecords.length,
      };

      records.addAll(pageRecords);

      if (pageRecords.isEmpty || records.length >= totalRecords) {
        break;
      }
    }

    return records;
  }

  /// Fetches all history records across all pages.
  Future<List<dynamic>> getAllHistory({
    Map<String, dynamic>? queryParameters,
  }) async {
    return _fetchAllPages('history', extraParams: queryParameters ?? const {});
  }

  Map<String, dynamic> _wantedParams({bool includeCutoffParams = false}) {
    return {
      'sortKey': config.sortKey,
      'sortDirection': 'descending',
      'includeSeries': true,
      if (includeCutoffParams) ...config.cutoffParams,
    };
  }

  /// Fetches the blocklist.
  Future<List<dynamic>> getBlocklist() async {
    final response = await client.get('/api/${config.apiVersion}/blocklist');
    return response.data['records'] as List<dynamic>;
  }

  /// Fetches missing items (wanted).
  Future<List<dynamic>> getMissing({int page = 1, int pageSize = 20}) async {
    final response = await client.get(
      '/api/${config.apiVersion}/wanted/missing',
      queryParameters: {'page': page, 'pageSize': pageSize, ..._wantedParams()},
    );
    return response.data['records'] as List<dynamic>;
  }

  /// Fetches all missing items across all pages.
  Future<List<dynamic>> getAllMissing() async {
    return _fetchAllPages('wanted/missing', extraParams: _wantedParams());
  }

  /// Fetches items with cutoff unmet.
  Future<List<dynamic>> getCutoff({int page = 1, int pageSize = 20}) async {
    try {
      final response = await client.get(
        '/api/${config.apiVersion}/wanted/cutoff',
        queryParameters: {
          'page': page,
          'pageSize': pageSize,
          ..._wantedParams(includeCutoffParams: true),
        },
      );
      return response.data['records'] as List<dynamic>;
    } catch (e) {
      // Cutoff endpoint may not be available on all *arr variants
      return [];
    }
  }

  /// Fetches all cutoff unmet items across all pages.
  Future<List<dynamic>> getAllCutoff() async {
    try {
      return await _fetchAllPages(
        'wanted/cutoff',
        extraParams: _wantedParams(includeCutoffParams: true),
      );
    } catch (_) {
      return [];
    }
  }

  /// Fetches all items from a list endpoint and maps them in an isolate.
  Future<List<T>> fetchAllItems<T>(
    String endpoint,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    try {
      final response = await client.get('/api/${config.apiVersion}/$endpoint');
      final data = response.data as List<dynamic>;
      return await Isolate.run(
        () =>
            data.map((item) => fromJson(item as Map<String, dynamic>)).toList(),
      );
    } catch (_) {
      return [];
    }
  }

  /// Searches by term using a lookup endpoint and maps results in an isolate.
  ///
  /// [cancelToken] aborts the request once the search that asked for it has
  /// been superseded: global search re-runs every service leg on each debounced
  /// keystroke, and a discarded round should stop paying for itself rather than
  /// run to completion. Failures — cancellation included — degrade to an empty
  /// list, like every other browse path.
  Future<List<T>> lookupItems<T>(
    String endpoint,
    String term,
    T Function(Map<String, dynamic>) fromJson, {
    CancelToken? cancelToken,
  }) async {
    if (term.isEmpty) {
      return [];
    }

    try {
      final encodedTerm = Uri.encodeComponent(term);
      final response = await client.get(
        '/api/${config.apiVersion}/$endpoint',
        queryParameters: {'term': encodedTerm},
        cancelToken: cancelToken,
      );
      final data = response.data as List<dynamic>;
      return await Isolate.run(
        () =>
            data.map((item) => fromJson(item as Map<String, dynamic>)).toList(),
      );
    } catch (_) {
      return [];
    }
  }

  /// Fetches release candidates for interactive search.
  ///
  /// Takes [kReleaseSearchReceiveTimeout] rather than the client default: the
  /// server fans out to every enabled indexer and answers only once the slowest
  /// one has, so this is the one arr endpoint that legitimately runs for minutes.
  Future<List<dynamic>> fetchReleases(
    Map<String, dynamic> queryParameters, {
    CancelToken? cancelToken,
  }) async {
    final response = await client.get(
      '/api/${config.apiVersion}/release',
      queryParameters: queryParameters,
      cancelToken: cancelToken,
      receiveTimeout: kReleaseSearchReceiveTimeout,
    );
    return response.data as List<dynamic>;
  }

  /// Describes the release-search request without performing it.
  ///
  /// For the Phase 2 background transport, which runs the request in native code
  /// and therefore needs a URL and headers rather than this client.
  ({Uri url, Map<String, String> headers}) releaseSearchRequest(
    Map<String, dynamic> queryParameters,
  ) {
    final base = client.baseUrl.endsWith('/')
        ? client.baseUrl.substring(0, client.baseUrl.length - 1)
        : client.baseUrl;
    return (
      url: Uri.parse('$base/api/${config.apiVersion}/release').replace(
        queryParameters: {
          for (final entry in queryParameters.entries)
            entry.key: '${entry.value}',
        },
      ),
      headers: client.headers,
    );
  }

  /// Asks for the service's own status and returns the raw response, so a caller
  /// can read *who answered* from the headers.
  ///
  /// The cheapest endpoint that is guaranteed to exist and to travel the full
  /// path, which is the point: the interesting information is the `server` and
  /// `cf-ray` headers a reverse proxy or CDN adds on the way back, not the body.
  Future<Response<dynamic>> probeHeaders() {
    return client.get('/api/${config.apiVersion}/system/status');
  }

  /// Fetches all quality profiles.
  Future<List<Map<String, dynamic>>> fetchQualityProfiles() async {
    try {
      final response = await client.get(
        '/api/${config.apiVersion}/qualityprofile',
      );
      final data = response.data as List<dynamic>;
      return data.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Updates an item's quality profile.
  Future<void> updateItemProfile(
    String resourcePath,
    int itemId,
    int qualityProfileId,
  ) async {
    final response = await client.get(
      '/api/${config.apiVersion}/$resourcePath/$itemId',
    );
    final item = response.data as Map<String, dynamic>;
    item['qualityProfileId'] = qualityProfileId;
    await client.put(
      '/api/${config.apiVersion}/$resourcePath/$itemId',
      data: item,
    );
  }

  /// Updates an item's monitored state.
  Future<void> updateItemMonitored(
    String resourcePath,
    int itemId,
    bool monitored,
  ) async {
    final response = await client.get(
      '/api/${config.apiVersion}/$resourcePath/$itemId',
    );
    final item = response.data as Map<String, dynamic>;
    item['monitored'] = monitored;
    await client.put(
      '/api/${config.apiVersion}/$resourcePath/$itemId',
      data: item,
    );
  }

  /// Grabs a specific release for download.
  Future<void> grabReleaseByGuid({
    required String guid,
    required int indexerId,
  }) async {
    await client.post(
      '/api/${config.apiVersion}/release',
      data: {'guid': guid, 'indexerId': indexerId},
    );
  }

  /// Removes a record from the download queue.
  ///
  /// The activity surfaces were read-only until now: this mixin exposed five
  /// getters and no mutation, so a user who found a stalled download in Seekarr
  /// had to open the service's own web UI to do anything about it.
  ///
  /// [removeFromClient] also deletes the download from the connected client
  /// (qBittorrent, SABnzbd…) rather than only from the \*arr queue.
  /// [blocklist] additionally records the release so the same one is not grabbed
  /// again — which, combined with a fresh search, is how a retry is expressed in
  /// the \*arr API. There is no dedicated "retry" endpoint.
  Future<void> removeFromQueue(
    int id, {
    bool removeFromClient = true,
    bool blocklist = false,
  }) async {
    await client.delete(
      '/api/${config.apiVersion}/queue/$id',
      queryParameters: {
        'removeFromClient': removeFromClient,
        'blocklist': blocklist,
      },
    );
  }

  /// Removes a release from the blocklist, allowing it to be grabbed again.
  Future<void> deleteBlocklistItem(int id) async {
    await client.delete('/api/${config.apiVersion}/blocklist/$id');
  }
}
