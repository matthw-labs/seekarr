import 'package:seekarr/core/utils/dynamic_map_utils.dart';

/// Authenticated system status from `GET /api/v1/system/status`.
///
/// Prowlarr returns a flat object (no `data` wrapper); the `version` field is
/// used for the services status card.
class ProwlarrSystemStatus {
  final String? version;
  final String? appName;
  final String? instanceName;
  final String? osName;
  final String? startTime;

  const ProwlarrSystemStatus({
    this.version,
    this.appName,
    this.instanceName,
    this.osName,
    this.startTime,
  });

  factory ProwlarrSystemStatus.fromJson(Map<String, dynamic> json) {
    return ProwlarrSystemStatus(
      version: stringOrNull(json['version']),
      appName: stringOrNull(json['appName']),
      instanceName: stringOrNull(json['instanceName']),
      osName: stringOrNull(json['osName']),
      startTime: stringOrNull(json['startTime']),
    );
  }
}

/// A single entry from `GET /api/v1/health` (flat list, no `data` wrapper).
class ProwlarrHealthIssue {
  final String? source;
  final String? type;
  final String? message;

  const ProwlarrHealthIssue({this.source, this.type, this.message});

  bool get isError => (type ?? '').toLowerCase() == 'error';

  factory ProwlarrHealthIssue.fromJson(Map<String, dynamic> json) {
    return ProwlarrHealthIssue(
      source: stringOrNull(json['source']),
      type: stringOrNull(json['type']),
      message: stringOrNull(json['message']),
    );
  }
}

/// An indexer configured in Prowlarr, from `GET /api/v1/indexer`.
class ProwlarrIndexer {
  final int id;
  final String? name;
  final String? definitionName;
  final String? description;
  final String? language;
  final bool enable;
  final bool supportsRss;
  final bool supportsSearch;

  /// `torrent` or `usenet`.
  final String? protocol;

  /// `public`, `private` or `semiPrivate`.
  final String? privacy;
  final int? priority;
  final List<int> tags;

  const ProwlarrIndexer({
    required this.id,
    this.name,
    this.definitionName,
    this.description,
    this.language,
    this.enable = false,
    this.supportsRss = false,
    this.supportsSearch = false,
    this.protocol,
    this.privacy,
    this.priority,
    this.tags = const [],
  });

  factory ProwlarrIndexer.fromJson(Map<String, dynamic> json) {
    final tagsRaw = json['tags'];
    final tags = tagsRaw is List
        ? tagsRaw.map(intOrNull).whereType<int>().toList(growable: false)
        : const <int>[];

    return ProwlarrIndexer(
      id: intOrNull(json['id']) ?? 0,
      name: stringOrNull(json['name']),
      definitionName: stringOrNull(json['definitionName']),
      description: stringOrNull(json['description']),
      language: stringOrNull(json['language']),
      enable: json['enable'] == true,
      supportsRss: json['supportsRss'] == true,
      supportsSearch: json['supportsSearch'] == true,
      protocol: stringOrNull(json['protocol']),
      privacy: stringOrNull(json['privacy']),
      priority: intOrNull(json['priority']),
      tags: tags,
    );
  }
}

/// Per-indexer usage statistics, from the `indexers` list nested inside
/// `GET /api/v1/indexerstats`.
class ProwlarrIndexerStat {
  final int indexerId;
  final String? indexerName;
  final int averageResponseTime;
  final int numberOfQueries;
  final int numberOfGrabs;
  final int numberOfRssQueries;
  final int numberOfAuthQueries;
  final int numberOfFailedQueries;
  final int numberOfFailedGrabs;
  final int numberOfFailedRssQueries;
  final int numberOfFailedAuthQueries;

  const ProwlarrIndexerStat({
    required this.indexerId,
    this.indexerName,
    this.averageResponseTime = 0,
    this.numberOfQueries = 0,
    this.numberOfGrabs = 0,
    this.numberOfRssQueries = 0,
    this.numberOfAuthQueries = 0,
    this.numberOfFailedQueries = 0,
    this.numberOfFailedGrabs = 0,
    this.numberOfFailedRssQueries = 0,
    this.numberOfFailedAuthQueries = 0,
  });

  /// Total failures across query and grab operations.
  int get numberOfFailures => numberOfFailedQueries + numberOfFailedGrabs;

  factory ProwlarrIndexerStat.fromJson(Map<String, dynamic> json) {
    return ProwlarrIndexerStat(
      indexerId: intOrNull(json['indexerId']) ?? 0,
      indexerName: stringOrNull(json['indexerName']),
      averageResponseTime: intOrNull(json['averageResponseTime']) ?? 0,
      numberOfQueries: intOrNull(json['numberOfQueries']) ?? 0,
      numberOfGrabs: intOrNull(json['numberOfGrabs']) ?? 0,
      numberOfRssQueries: intOrNull(json['numberOfRssQueries']) ?? 0,
      numberOfAuthQueries: intOrNull(json['numberOfAuthQueries']) ?? 0,
      numberOfFailedQueries: intOrNull(json['numberOfFailedQueries']) ?? 0,
      numberOfFailedGrabs: intOrNull(json['numberOfFailedGrabs']) ?? 0,
      numberOfFailedRssQueries:
          intOrNull(json['numberOfFailedRssQueries']) ?? 0,
      numberOfFailedAuthQueries:
          intOrNull(json['numberOfFailedAuthQueries']) ?? 0,
    );
  }
}

/// Aggregated indexer statistics from `GET /api/v1/indexerstats`.
///
/// The endpoint wraps the per-indexer stats in `{indexers: [...], ...}`; only
/// the indexer breakdown is modeled here.
class ProwlarrIndexerStats {
  final List<ProwlarrIndexerStat> indexers;

  const ProwlarrIndexerStats({this.indexers = const []});

  int get totalQueries => indexers.fold(0, (sum, s) => sum + s.numberOfQueries);
  int get totalGrabs => indexers.fold(0, (sum, s) => sum + s.numberOfGrabs);
  int get totalFailures =>
      indexers.fold(0, (sum, s) => sum + s.numberOfFailures);

  factory ProwlarrIndexerStats.fromJson(Map<String, dynamic> json) {
    final raw = json['indexers'];
    final indexers = raw is List
        ? raw
              .whereType<Map>()
              .map(stringKeyMap)
              .map(ProwlarrIndexerStat.fromJson)
              .toList(growable: false)
        : const <ProwlarrIndexerStat>[];
    return ProwlarrIndexerStats(indexers: indexers);
  }
}

/// Failure state for an indexer, from `GET /api/v1/indexerstatus`.
///
/// Only indexers with an active problem are returned by the endpoint.
class ProwlarrIndexerStatus {
  final int indexerId;
  final String? disabledTill;
  final String? mostRecentFailure;
  final String? initialFailure;

  const ProwlarrIndexerStatus({
    required this.indexerId,
    this.disabledTill,
    this.mostRecentFailure,
    this.initialFailure,
  });

  factory ProwlarrIndexerStatus.fromJson(Map<String, dynamic> json) {
    return ProwlarrIndexerStatus(
      indexerId: intOrNull(json['indexerId']) ?? 0,
      disabledTill: stringOrNull(json['disabledTill']),
      mostRecentFailure: stringOrNull(json['mostRecentFailure']),
      initialFailure: stringOrNull(json['initialFailure']),
    );
  }
}

/// A single history event from `GET /api/v1/history`.
///
/// The `data` map is heterogeneous per [eventType] and contains string values
/// even for numeric-looking fields; it is kept raw for lenient consumption.
class ProwlarrHistoryItem {
  final int id;
  final int? indexerId;
  final String? eventType;
  final String? date;
  final bool successful;
  final Map<String, dynamic> data;

  const ProwlarrHistoryItem({
    required this.id,
    this.indexerId,
    this.eventType,
    this.date,
    this.successful = false,
    this.data = const {},
  });

  factory ProwlarrHistoryItem.fromJson(Map<String, dynamic> json) {
    return ProwlarrHistoryItem(
      id: intOrNull(json['id']) ?? 0,
      indexerId: intOrNull(json['indexerId']),
      eventType: stringOrNull(json['eventType']),
      date: stringOrNull(json['date']),
      successful: json['successful'] == true,
      data: mapOrNull(json['data']) ?? const <String, dynamic>{},
    );
  }
}

/// Paged history result from `GET /api/v1/history`.
class ProwlarrHistoryPage {
  final List<ProwlarrHistoryItem> records;
  final int totalRecords;
  final int page;
  final int pageSize;

  const ProwlarrHistoryPage({
    this.records = const [],
    this.totalRecords = 0,
    this.page = 1,
    this.pageSize = 0,
  });

  bool get hasMore => page * pageSize < totalRecords;

  factory ProwlarrHistoryPage.fromJson(Map<String, dynamic> json) {
    final raw = json['records'];
    final records = raw is List
        ? raw
              .whereType<Map>()
              .map(stringKeyMap)
              .map(ProwlarrHistoryItem.fromJson)
              .toList(growable: false)
        : const <ProwlarrHistoryItem>[];
    return ProwlarrHistoryPage(
      records: records,
      totalRecords: intOrNull(json['totalRecords']) ?? 0,
      page: intOrNull(json['page']) ?? 1,
      pageSize: intOrNull(json['pageSize']) ?? 0,
    );
  }
}

/// An application synced by Prowlarr (Radarr/Sonarr/Lidarr), from
/// `GET /api/v1/applications`.
class ProwlarrApplication {
  final int id;
  final String? name;
  final String? syncLevel;
  final String? implementation;
  final bool enable;

  const ProwlarrApplication({
    required this.id,
    this.name,
    this.syncLevel,
    this.implementation,
    this.enable = false,
  });

  factory ProwlarrApplication.fromJson(Map<String, dynamic> json) {
    return ProwlarrApplication(
      id: intOrNull(json['id']) ?? 0,
      name: stringOrNull(json['name']),
      syncLevel: stringOrNull(json['syncLevel']),
      implementation: stringOrNull(json['implementation']),
      enable: json['enable'] == true,
    );
  }
}
