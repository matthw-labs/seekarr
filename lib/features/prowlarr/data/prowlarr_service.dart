import 'dart:isolate';

import 'package:dio/dio.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';

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
///
/// Write actions (add/edit/delete/test/bulk/sync) mirror what the Prowlarr web
/// UI does with the same endpoints; see `lib/features/prowlarr/AGENTS.md` for
/// the payload contracts they rely on.
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

  /// Recent activity for a single indexer.
  ///
  /// `history/indexer` is a flat, server-filtered array — unlike the paged
  /// `history` endpoint it takes an `indexerId`, so the detail screen no longer
  /// has to over-fetch and filter client side.
  Future<List<ProwlarrHistoryItem>> getIndexerHistory(
    int indexerId, {
    int limit = 30,
    String? eventType,
  }) async {
    final response = await client.get(
      '/api/v1/history/indexer',
      queryParameters: {
        'indexerId': indexerId,
        'limit': limit,
        if (eventType != null) 'eventType': eventType,
      },
    );
    return _mapList(response.data, ProwlarrHistoryItem.fromJson);
  }

  /// Newznab categories, used as an indexer filter.
  Future<List<ProwlarrCategory>> getIndexerCategories() async {
    final response = await client.get('/api/v1/indexer/categories');
    return _mapList(response.data, ProwlarrCategory.fromJson);
  }

  /// Configured providers of one [kind] (apps, download clients,
  /// notifications, indexer proxies).
  Future<List<ProwlarrProviderResource>> getProviders(
    ProwlarrProviderKind kind,
  ) async {
    final response = await client.get('/api/v1/${kind.path}');
    return _mapList(response.data, ProwlarrProviderResource.fromJson);
  }

  /// Implementations of [kind] that can be added, from `<kind>/schema`.
  ///
  /// Unlike the indexer schema these lists are small (tens of entries), so they
  /// are parsed inline.
  Future<List<ProwlarrProviderResource>> getProviderSchema(
    ProwlarrProviderKind kind,
  ) async {
    final response = await client.get('/api/v1/${kind.path}/schema');
    return _mapList(response.data, ProwlarrProviderResource.fromJson);
  }

  /// Adds (no `id`) or updates (`id` present) one provider.
  Future<ProwlarrProviderResource> saveProvider(
    ProwlarrProviderKind kind,
    Map<String, dynamic> payload,
  ) async {
    final id = intOrNull(payload['id']) ?? 0;
    final response = await _mutate(
      () => id > 0
          ? client.put('/api/v1/${kind.path}/$id', data: payload)
          : client.post('/api/v1/${kind.path}', data: payload),
      'Could not save the ${kind.singular}',
    );
    return ProwlarrProviderResource.fromJson(
      mapOrNull(response.data) ?? payload,
    );
  }

  Future<void> deleteProvider(ProwlarrProviderKind kind, int id) async {
    await _mutate(
      () => client.delete('/api/v1/${kind.path}/$id'),
      'Could not delete the ${kind.singular}',
    );
  }

  /// Tests one provider configuration without saving it.
  Future<void> testProvider(
    ProwlarrProviderKind kind,
    Map<String, dynamic> payload,
  ) async {
    await _mutate(
      () => client.post(
        '/api/v1/${kind.path}/test',
        data: payload,
        receiveTimeout: _testReceiveTimeout,
      ),
      'Test failed',
    );
  }

  Future<List<ProwlarrTestResult>> testAllProviders(ProwlarrProviderKind kind) {
    return _testAll(
      '/api/v1/${kind.path}/testall',
      'Could not test the ${kind.title.toLowerCase()}',
    );
  }

  /// Applications synced by Prowlarr (Radarr/Sonarr/Lidarr…).
  Future<List<ProwlarrProviderResource>> getApplications() =>
      getProviders(ProwlarrProviderKind.application);

  /// Adds or updates a sync profile.
  Future<ProwlarrAppProfile> saveAppProfile(
    Map<String, dynamic> payload,
  ) async {
    final id = intOrNull(payload['id']) ?? 0;
    final response = await _mutate(
      () => id > 0
          ? client.put('/api/v1/appprofile/$id', data: payload)
          : client.post('/api/v1/appprofile', data: payload),
      'Could not save the sync profile',
    );
    return ProwlarrAppProfile.fromJson(mapOrNull(response.data) ?? payload);
  }

  Future<void> deleteAppProfile(int id) async {
    await _mutate(
      () => client.delete('/api/v1/appprofile/$id'),
      'Could not delete the sync profile',
    );
  }

  /// Tags with what currently references them, for the tag manager.
  Future<List<ProwlarrTagDetail>> getTagDetails() async {
    final response = await client.get('/api/v1/tag/detail');
    return _mapList(response.data, ProwlarrTagDetail.fromJson);
  }

  Future<void> deleteTag(int id) async {
    await _mutate(
      () => client.delete('/api/v1/tag/$id'),
      'Could not delete the tag',
    );
  }

  Future<ProwlarrTag> renameTag(int id, String label) async {
    final response = await _mutate(
      () => client.put('/api/v1/tag/$id', data: {'id': id, 'label': label}),
      'Could not rename the tag',
    );
    return ProwlarrTag.fromJson(
      mapOrNull(response.data) ?? {'id': id, 'label': label},
    );
  }

  /// Tags, used both as an indexer filter and in the edit form.
  Future<List<ProwlarrTag>> getTags() async {
    final response = await client.get('/api/v1/tag');
    return _mapList(response.data, ProwlarrTag.fromJson);
  }

  /// Creates a tag and returns it with its server-assigned id.
  Future<ProwlarrTag> createTag(String label) async {
    final response = await _mutate(
      () => client.post('/api/v1/tag', data: {'label': label}),
      'Could not create the tag',
    );
    return ProwlarrTag.fromJson(mapOrNull(response.data) ?? const {});
  }

  /// Sync profiles offered by the indexer edit form (`appProfileId`).
  Future<List<ProwlarrAppProfile>> getAppProfiles() async {
    final response = await client.get('/api/v1/appprofile');
    return _mapList(response.data, ProwlarrAppProfile.fromJson);
  }

  /// A single indexer, including its `fields`.
  Future<ProwlarrIndexer?> getIndexer(int id) async {
    final response = await client.get('/api/v1/indexer/$id');
    final json = mapOrNull(response.data);
    return json == null ? null : ProwlarrIndexer.fromJson(json);
  }

  /// Every indexer definition Prowlarr can add, from `indexer/schema`.
  ///
  /// This is by far the largest response the app fetches — well over a thousand
  /// definitions — so it gets a longer receive timeout, is parsed off the main
  /// isolate, and has `capabilities`/`presets` stripped before the maps are
  /// retained: both are recomputed server side on save and together account for
  /// most of the payload's weight.
  Future<List<ProwlarrIndexer>> getIndexerSchema() async {
    final response = await client.get(
      '/api/v1/indexer/schema',
      receiveTimeout: _schemaReceiveTimeout,
    );
    final data = response.data;
    return Isolate.run(() => _parseSchema(data));
  }

  /// Adds a new indexer from an edited schema definition (`id` absent) or
  /// updates an existing one (`id` present).
  Future<ProwlarrIndexer> saveIndexer(Map<String, dynamic> payload) async {
    final id = intOrNull(payload['id']) ?? 0;
    final response = await _mutate(
      () => id > 0
          ? client.put('/api/v1/indexer/$id', data: payload)
          : client.post('/api/v1/indexer', data: payload),
      id > 0 ? 'Could not save the indexer' : 'Could not add the indexer',
    );
    return ProwlarrIndexer.fromJson(mapOrNull(response.data) ?? payload);
  }

  Future<void> deleteIndexer(int id) async {
    await _mutate(
      () => client.delete('/api/v1/indexer/$id'),
      'Could not delete the indexer',
    );
  }

  /// Tests one indexer configuration without saving it.
  ///
  /// Prowlarr answers a failing test with HTTP 400 and the validation failures
  /// in the body, so success here means "the indexer answered".
  Future<void> testIndexer(Map<String, dynamic> payload) async {
    await _mutate(
      () => client.post(
        '/api/v1/indexer/test',
        data: payload,
        receiveTimeout: _testReceiveTimeout,
      ),
      'Test failed',
    );
  }

  /// Tests every configured indexer; each entry reports its own validity.
  Future<List<ProwlarrTestResult>> testAllIndexers() {
    return _testAll('/api/v1/indexer/testall', 'Could not test the indexers');
  }

  /// Applies one change to many indexers at once (`indexer/bulk`).
  ///
  /// Only the passed properties are sent: Prowlarr treats an absent key as
  /// "leave alone", which is what the web UI's "No change" options map to.
  /// [applyTags] is `add`, `remove` or `replace` and only matters with [tags].
  Future<void> bulkUpdateIndexers({
    required List<int> ids,
    bool? enable,
    int? priority,
    int? appProfileId,
    List<int>? tags,
    String applyTags = 'add',
    int? minimumSeeders,
    double? seedRatio,
    int? seedTime,
    int? packSeedTime,
    bool? preferMagnetUrl,
  }) async {
    await _mutate(
      () => client.put(
        '/api/v1/indexer/bulk',
        data: {
          'ids': ids,
          if (enable != null) 'enable': enable,
          if (priority != null) 'priority': priority,
          if (appProfileId != null) 'appProfileId': appProfileId,
          if (tags != null) ...{'tags': tags, 'applyTags': applyTags},
          if (minimumSeeders != null) 'minimumSeeders': minimumSeeders,
          if (seedRatio != null) 'seedRatio': seedRatio,
          if (seedTime != null) 'seedTime': seedTime,
          if (packSeedTime != null) 'packSeedTime': packSeedTime,
          if (preferMagnetUrl != null) 'preferMagnetUrl': preferMagnetUrl,
        },
      ),
      'Could not update the selected indexers',
    );
  }

  Future<void> bulkDeleteIndexers(List<int> ids) async {
    await _mutate(
      () => client.delete('/api/v1/indexer/bulk', data: {'ids': ids}),
      'Could not delete the selected indexers',
    );
  }

  /// Queues a Prowlarr command (e.g. `ApplicationIndexerSync`).
  Future<ProwlarrCommand> runCommand(String name) async {
    final response = await _mutate(
      () => client.post('/api/v1/command', data: {'name': name}),
      'Could not start $name',
    );
    return ProwlarrCommand.fromJson(mapOrNull(response.data) ?? const {});
  }

  /// Pushes the current indexer set to every configured application — the
  /// "Sync App Indexers" button of the web UI.
  Future<ProwlarrCommand> syncAppIndexers() =>
      runCommand('ApplicationIndexerSync');

  /// Polls a queued command so a sync can report its real outcome.
  Future<ProwlarrCommand> getCommand(int id) async {
    final response = await client.get('/api/v1/command/$id');
    return ProwlarrCommand.fromJson(mapOrNull(response.data) ?? const {});
  }

  /// The schema list is fetched over a slow link often enough that the client's
  /// 15s default fires on a healthy instance.
  static const _schemaReceiveTimeout = Duration(seconds: 90);

  /// A test walks out to the tracker (and possibly through FlareSolverr), so it
  /// is bounded by the tracker's latency, not Prowlarr's.
  static const _testReceiveTimeout = Duration(seconds: 60);

  /// Runs a mutating call, turning Prowlarr's HTTP 400 validation body into a
  /// message worth showing.
  ///
  /// A rejected save/test answers with `[{propertyName, errorMessage}, …]`,
  /// none of which survives `DioException.toString()` — the user would see
  /// "status code of 400" instead of "Unable to connect: invalid API key".
  Future<Response> _mutate(
    Future<Response> Function() call,
    String fallback,
  ) async {
    try {
      return await call();
    } on DioException catch (error) {
      final detail = _validationDetail(error.response?.data);
      throw Exception(detail ?? '$fallback (${_statusLabel(error)})');
    }
  }

  /// POSTs a `testall` endpoint and returns the per-provider report.
  ///
  /// Servarr's `ProviderControllerBase.TestAll` answers `BadRequest(result)` —
  /// **body included** — the moment any one provider comes back invalid, and
  /// [ApiClient]'s `validateStatus` rejects anything >= 400, so Dio throws and
  /// the report never reaches the caller. That made the partial-failure report
  /// unreachable in exactly the case it was written for: the UI fell through to
  /// its outer catch and said "status code of 400" instead of "3 of 12 indexers
  /// failed: invalid API key".
  ///
  /// [_mutate] is *not* the fix here — it turns the 400 into an `Exception`
  /// carrying a message, which is right for a save but throws away the very
  /// structure this call exists to read. So the body is claimed back directly,
  /// and only when it is actually the report: a 401 or a proxy's HTML error page
  /// still fails as a failure.
  Future<List<ProwlarrTestResult>> _testAll(
    String path,
    String fallback,
  ) async {
    try {
      final response = await client.post(
        path,
        receiveTimeout: _testReceiveTimeout,
      );
      return _mapList(response.data, ProwlarrTestResult.fromJson);
    } on DioException catch (error) {
      final data = error.response?.data;
      if (_isTestReport(data)) {
        return _mapList(data, ProwlarrTestResult.fromJson);
      }
      final detail = _validationDetail(data);
      throw Exception(detail ?? '$fallback (${_statusLabel(error)})');
    }
  }

  /// Whether [data] is a `testall` report rather than an ordinary error body.
  ///
  /// The report is a list of `{id, isValid, validationFailures}`; a rejected
  /// save is a list of `{propertyName, errorMessage}` and a failed request is
  /// usually a `{message}` map. `isValid` is what tells them apart.
  static bool _isTestReport(dynamic data) {
    if (data is! List || data.isEmpty) return false;
    return data.every((entry) => entry is Map && entry.containsKey('isValid'));
  }

  static String _statusLabel(DioException error) {
    final status = error.response?.statusCode;
    return status == null ? error.type.name : 'HTTP $status';
  }

  static String? _validationDetail(dynamic data) {
    final entries = <Map<String, dynamic>>[
      if (data is List) ...data.whereType<Map>().map(stringKeyMap),
      if (mapOrNull(data) case final map?) map,
    ];
    final messages = entries
        .map(ProwlarrValidationFailure.fromJson)
        .map((failure) => failure.errorMessage)
        .whereType<String>()
        .toList(growable: false);
    return messages.isEmpty ? null : messages.join('\n');
  }

  /// Top-level so it can run inside [Isolate.run].
  static List<ProwlarrIndexer> _parseSchema(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(stringKeyMap)
        .map((json) {
          // Parse first — that flattens `capabilities.categories` into plain ids
          // for the category filter — then strip the heavy keys from the very map
          // the model's `raw` points at. Mutating after the parse is what keeps the
          // retained payload small while the derived ids survive.
          final indexer = ProwlarrIndexer.fromJson(json);
          json.removeWhere(_isHeavySchemaKey);
          return indexer;
        })
        .toList(growable: false);
  }

  static bool _isHeavySchemaKey(String key, dynamic _) =>
      key == 'capabilities' || key == 'presets';

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
