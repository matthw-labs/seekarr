import 'dart:isolate';

import 'package:seekarr/core/api/api_client.dart';
import 'package:seekarr/core/utils/dynamic_map_utils.dart';
import 'package:seekarr/features/prowlarr/domain/models/prowlarr_models.dart';

/// Service for interacting with the Prowlarr API (v1).
///
/// Prowlarr shares the *arr transport contract (`/api/v1/`, `X-Api-Key`) but
/// its domain is indexer management, so it is intentionally NOT modeled via
/// [ArrActivityMixin] (no wanted/blocklist/release/qualityprofile). The Riverpod
/// wiring lives in `prowlarr_provider.dart`; this file only defines transport.
///
/// Envelope shapes (verified against Prowlarr v2.5.0):
/// - `system/status`: flat object.
/// - `health`, `indexer`, `indexerstatus`, `applications`: bare JSON arrays.
/// - `indexerstats`: object with the per-indexer breakdown under `indexers`.
/// - `history`: paged object `{records, totalRecords, page, pageSize}`.
class ProwlarrService {
  final ApiClient client;

  ProwlarrService(this.client);

  /// Authenticated system status (version, OS, instance name...).
  Future<ProwlarrSystemStatus> getStatus() async {
    final response = await client.get('/api/v1/system/status');
    return ProwlarrSystemStatus.fromJson(mapOrNull(response.data) ?? const {});
  }

  /// Current health issues (missing definitions, failing indexers, updates...).
  Future<List<ProwlarrHealthIssue>> getHealth() async {
    final response = await client.get('/api/v1/health');
    return _mapList(response.data, ProwlarrHealthIssue.fromJson);
  }

  /// All configured indexers.
  Future<List<ProwlarrIndexer>> getIndexers() async {
    final response = await client.get('/api/v1/indexer');
    return _mapList(response.data, ProwlarrIndexer.fromJson);
  }

  /// Aggregated per-indexer usage statistics (queries/grabs/failures).
  Future<ProwlarrIndexerStats> getIndexerStats({
    String? startDate,
    String? endDate,
  }) async {
    final response = await client.get(
      '/api/v1/indexerstats',
      queryParameters: {
        if (startDate != null) 'startDate': startDate,
        if (endDate != null) 'endDate': endDate,
      },
    );
    return ProwlarrIndexerStats.fromJson(mapOrNull(response.data) ?? const {});
  }

  /// Failure state for indexers currently disabled due to errors.
  Future<List<ProwlarrIndexerStatus>> getIndexerStatus() async {
    final response = await client.get('/api/v1/indexerstatus');
    return _mapList(response.data, ProwlarrIndexerStatus.fromJson);
  }

  /// Paged history of indexer activity (queries, grabs, RSS, auth).
  Future<ProwlarrHistoryPage> getHistory({
    int page = 1,
    int pageSize = 20,
    String? eventType,
    String sortKey = 'date',
    String sortDirection = 'descending',
  }) async {
    final response = await client.get(
      '/api/v1/history',
      queryParameters: {
        'page': page,
        'pageSize': pageSize,
        'sortKey': sortKey,
        'sortDirection': sortDirection,
        if (eventType != null) 'eventType': eventType,
      },
    );
    // History pages can carry up to ~100 records; parse off the main isolate
    // to keep the UI thread responsive (mirrors `BaseArrService`).
    final data = response.data;
    return Isolate.run(
      () => ProwlarrHistoryPage.fromJson(mapOrNull(data) ?? const {}),
    );
  }

  /// Applications synced by Prowlarr (Radarr/Sonarr/Lidarr).
  Future<List<ProwlarrApplication>> getApplications() async {
    final response = await client.get('/api/v1/applications');
    return _mapList(response.data, ProwlarrApplication.fromJson);
  }

  static List<T> _mapList<T>(
    dynamic raw,
    T Function(Map<String, dynamic>) builder,
  ) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map(stringKeyMap)
          .map(builder)
          .toList(growable: false);
    }
    return const [];
  }
}
