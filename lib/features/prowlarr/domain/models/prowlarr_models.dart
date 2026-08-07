import 'package:flutter/material.dart';

import 'package:cupola/core/utils/dynamic_map_utils.dart';

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

/// One option of a `select` [ProwlarrField].
class ProwlarrSelectOption {
  final int value;
  final String? name;
  final int? order;
  final String? hint;

  const ProwlarrSelectOption({
    required this.value,
    this.name,
    this.order,
    this.hint,
  });

  factory ProwlarrSelectOption.fromJson(Map<String, dynamic> json) {
    return ProwlarrSelectOption(
      value: intOrNull(json['value']) ?? 0,
      name: stringOrNull(json['name']),
      order: intOrNull(json['order']),
      hint: stringOrNull(json['hint']),
    );
  }
}

/// A provider setting from an indexer's `fields` array.
///
/// Prowlarr describes every indexer-specific setting (base URL, cookie, API
/// key, seed ratio…) through this one shape, so the edit form is generated from
/// it rather than hand-written per indexer. [raw] is kept verbatim because a
/// save must send the whole field object back — including keys this client does
/// not model — with only [value] replaced.
class ProwlarrField {
  final String name;
  final String? label;
  final String? unit;
  final String? helpText;
  final String? helpTextWarning;
  final String? helpLink;
  final String? placeholder;
  final String? section;

  /// `textbox`, `password`, `checkbox`, `select`, `number`, `info`, `textarea`…
  final String? type;

  /// `hidden`, `hiddenIfNotSet` or absent. Hidden fields (e.g. Cardigann's
  /// `definitionFile`) must still round-trip on save.
  final String? hidden;
  final int order;
  final bool advanced;
  final bool isFloat;
  final dynamic value;
  final List<ProwlarrSelectOption> selectOptions;
  final Map<String, dynamic> raw;

  const ProwlarrField({
    required this.name,
    this.label,
    this.unit,
    this.helpText,
    this.helpTextWarning,
    this.helpLink,
    this.placeholder,
    this.section,
    this.type,
    this.hidden,
    this.order = 0,
    this.advanced = false,
    this.isFloat = false,
    this.value,
    this.selectOptions = const [],
    this.raw = const {},
  });

  String get displayLabel => label ?? name;

  bool get isInfo => (type ?? '').toLowerCase() == 'info';
  bool get isCheckbox => type == 'checkbox';
  bool get isSelect => type == 'select' && selectOptions.isNotEmpty;
  bool get isNumber => type == 'number';
  bool get isPassword => type == 'password';
  bool get isTextArea => type == 'textarea';

  /// Fields Prowlarr hides from its own UI: rendered nowhere, sent on save.
  bool get isHidden => hidden == 'hidden';

  factory ProwlarrField.fromJson(Map<String, dynamic> json) {
    final optionsRaw = json['selectOptions'];
    final options = optionsRaw is List
        ? optionsRaw
              .whereType<Map>()
              .map(stringKeyMap)
              .map(ProwlarrSelectOption.fromJson)
              .toList(growable: false)
        : const <ProwlarrSelectOption>[];

    return ProwlarrField(
      name: stringOrNull(json['name']) ?? '',
      label: stringOrNull(json['label']),
      unit: stringOrNull(json['unit']),
      helpText: stringOrNull(json['helpText']),
      helpTextWarning: stringOrNull(json['helpTextWarning']),
      helpLink: stringOrNull(json['helpLink']),
      placeholder: stringOrNull(json['placeholder']),
      section: stringOrNull(json['section']),
      type: stringOrNull(json['type']),
      hidden: stringOrNull(json['hidden']),
      order: intOrNull(json['order']) ?? 0,
      advanced: json['advanced'] == true,
      isFloat: json['isFloat'] == true,
      value: json['value'],
      selectOptions: options,
      raw: json,
    );
  }

  ProwlarrField copyWithValue(dynamic newValue) {
    return ProwlarrField(
      name: name,
      label: label,
      unit: unit,
      helpText: helpText,
      helpTextWarning: helpTextWarning,
      helpLink: helpLink,
      placeholder: placeholder,
      section: section,
      type: type,
      hidden: hidden,
      order: order,
      advanced: advanced,
      isFloat: isFloat,
      value: newValue,
      selectOptions: selectOptions,
      raw: raw,
    );
  }

  /// The field as Prowlarr expects it back on save.
  Map<String, dynamic> toJson() => {...raw, 'name': name, 'value': value};
}

/// An indexer configured in Prowlarr, from `GET /api/v1/indexer`, or an
/// available definition from `GET /api/v1/indexer/schema`.
class ProwlarrIndexer {
  final int id;
  final String? name;
  final String? definitionName;
  final String? implementation;
  final String? implementationName;
  final String? configContract;
  final String? description;
  final String? language;
  final String? infoLink;
  final bool enable;
  final bool redirect;
  final bool supportsRss;
  final bool supportsSearch;
  final bool supportsRedirect;
  final bool supportsPagination;

  /// `torrent` or `usenet`.
  final String? protocol;

  /// `public`, `private` or `semiPrivate`.
  final String? privacy;
  final int? priority;

  /// Sync profile applied when Prowlarr pushes this indexer to its apps.
  final int appProfileId;
  final int downloadClientId;
  final List<int> tags;
  final List<String> indexerUrls;
  final List<ProwlarrField> fields;

  /// Newznab category ids this indexer advertises, flattened from
  /// `capabilities.categories`.
  ///
  /// Only the ids are kept: `getIndexerSchema` strips the `capabilities` object
  /// (it dominates a response of thousands of definitions) but the category
  /// filter still needs to know what each definition covers.
  final List<int> categoryIds;

  /// Provider message shown by Prowlarr above the edit form (e.g. "this
  /// indexer requires FlareSolverr"), with its `info`/`warning`/`error` type.
  final String? message;
  final String? messageType;

  /// The source JSON, so a save can round-trip every key this client does not
  /// model. `capabilities`/`presets` are stripped from schema payloads (see
  /// `ProwlarrService.getIndexerSchema`) because they are recomputed server
  /// side and dominate the response size.
  final Map<String, dynamic> raw;

  const ProwlarrIndexer({
    required this.id,
    this.name,
    this.definitionName,
    this.implementation,
    this.implementationName,
    this.configContract,
    this.description,
    this.language,
    this.infoLink,
    this.enable = false,
    this.redirect = false,
    this.supportsRss = false,
    this.supportsSearch = false,
    this.supportsRedirect = false,
    this.supportsPagination = false,
    this.protocol,
    this.privacy,
    this.priority,
    this.appProfileId = 1,
    this.downloadClientId = 0,
    this.tags = const [],
    this.indexerUrls = const [],
    this.fields = const [],
    this.categoryIds = const [],
    this.message,
    this.messageType,
    this.raw = const {},
  });

  /// `Implementation (definition)` when the two differ, as the web UI titles
  /// its edit modal; otherwise just the implementation name.
  String get displayImplementation {
    final impl = implementationName ?? implementation;
    if (impl == null) return definitionName ?? '';
    if (definitionName == null || definitionName == impl) return impl;
    return '$impl ($definitionName)';
  }

  factory ProwlarrIndexer.fromJson(Map<String, dynamic> json) {
    final tagsRaw = json['tags'];
    final tags = tagsRaw is List
        ? tagsRaw.map(intOrNull).whereType<int>().toList(growable: false)
        : const <int>[];
    final urlsRaw = json['indexerUrls'];
    final urls = urlsRaw is List
        ? urlsRaw.map(stringOrNull).whereType<String>().toList(growable: false)
        : const <String>[];
    final fieldsRaw = json['fields'];
    final fields = fieldsRaw is List
        ? (fieldsRaw
              .whereType<Map>()
              .map(stringKeyMap)
              .map(ProwlarrField.fromJson)
              .toList()
            ..sort((a, b) => a.order.compareTo(b.order)))
        : const <ProwlarrField>[];
    final message = mapOrNull(json['message']);

    return ProwlarrIndexer(
      id: intOrNull(json['id']) ?? 0,
      name: stringOrNull(json['name']),
      definitionName: stringOrNull(json['definitionName']),
      implementation: stringOrNull(json['implementation']),
      implementationName: stringOrNull(json['implementationName']),
      configContract: stringOrNull(json['configContract']),
      description: stringOrNull(json['description']),
      language: stringOrNull(json['language']),
      infoLink: stringOrNull(json['infoLink']),
      enable: json['enable'] == true,
      redirect: json['redirect'] == true,
      supportsRss: json['supportsRss'] == true,
      supportsSearch: json['supportsSearch'] == true,
      supportsRedirect: json['supportsRedirect'] == true,
      supportsPagination: json['supportsPagination'] == true,
      protocol: stringOrNull(json['protocol']),
      privacy: stringOrNull(json['privacy']),
      priority: intOrNull(json['priority']),
      appProfileId: intOrNull(json['appProfileId']) ?? 1,
      downloadClientId: intOrNull(json['downloadClientId']) ?? 0,
      tags: tags,
      indexerUrls: urls,
      fields: fields,
      categoryIds: _categoryIds(json),
      message: stringOrNull(message?['message']),
      messageType: stringOrNull(message?['type']),
      raw: json,
    );
  }

  /// Flattens `capabilities.categories` (parents and children) into plain ids.
  ///
  /// Accepts the already-flattened `categoryIds` too, which is what a payload
  /// rebuilt from [raw] carries once the capabilities object has been stripped.
  static List<int> _categoryIds(Map<String, dynamic> json) {
    final flattened = json['categoryIds'];
    if (flattened is List) {
      return flattened.map(intOrNull).whereType<int>().toList(growable: false);
    }
    final categories = mapOrNull(json['capabilities'])?['categories'];
    if (categories is! List) return const [];

    final ids = <int>[];
    void walk(List<dynamic> nodes) {
      for (final node in nodes.whereType<Map>()) {
        final map = stringKeyMap(node);
        final id = intOrNull(map['id']);
        if (id != null) ids.add(id);
        final subs = map['subCategories'];
        if (subs is List) walk(subs);
      }
    }

    walk(categories);
    return ids;
  }

  /// Builds the `IndexerResource` body for `POST`/`PUT /api/v1/indexer`.
  ///
  /// Starts from [raw] so untouched keys survive the round-trip, then applies
  /// the edited values. `id` is dropped when it is 0 (an add), which is how a
  /// schema definition becomes a new indexer.
  Map<String, dynamic> toPayload({
    String? name,
    bool? enable,
    bool? redirect,
    int? priority,
    int? appProfileId,
    int? downloadClientId,
    List<int>? tags,
    List<ProwlarrField>? fields,
    int? id,
  }) {
    final effectiveId = id ?? this.id;
    final payload = <String, dynamic>{
      ...raw,
      'name': name ?? this.name,
      'enable': enable ?? this.enable,
      'redirect': redirect ?? this.redirect,
      'priority': priority ?? this.priority ?? 25,
      'appProfileId': appProfileId ?? this.appProfileId,
      'downloadClientId': downloadClientId ?? this.downloadClientId,
      'tags': tags ?? this.tags,
      'fields': (fields ?? this.fields)
          .map((field) => field.toJson())
          .toList(growable: false),
    };
    if (effectiveId > 0) {
      payload['id'] = effectiveId;
    } else {
      payload.remove('id');
    }
    return payload;
  }
}

/// A tag from `GET /api/v1/tag`.
class ProwlarrTag {
  final int id;
  final String label;

  const ProwlarrTag({required this.id, required this.label});

  factory ProwlarrTag.fromJson(Map<String, dynamic> json) {
    return ProwlarrTag(
      id: intOrNull(json['id']) ?? 0,
      label: stringOrNull(json['label']) ?? '',
    );
  }
}

/// A sync profile from `GET /api/v1/appprofile`, applied per indexer through
/// `appProfileId`.
class ProwlarrAppProfile {
  final int id;
  final String? name;
  final bool enableRss;
  final bool enableAutomaticSearch;
  final bool enableInteractiveSearch;
  final int minimumSeeders;

  const ProwlarrAppProfile({
    required this.id,
    this.name,
    this.enableRss = false,
    this.enableAutomaticSearch = false,
    this.enableInteractiveSearch = false,
    this.minimumSeeders = 0,
  });

  factory ProwlarrAppProfile.fromJson(Map<String, dynamic> json) {
    return ProwlarrAppProfile(
      id: intOrNull(json['id']) ?? 0,
      name: stringOrNull(json['name']),
      enableRss: json['enableRss'] == true,
      enableAutomaticSearch: json['enableAutomaticSearch'] == true,
      enableInteractiveSearch: json['enableInteractiveSearch'] == true,
      minimumSeeders: intOrNull(json['minimumSeeders']) ?? 0,
    );
  }
}

/// A queued/running command from `POST /api/v1/command`.
class ProwlarrCommand {
  final int id;
  final String? name;

  /// `queued`, `started`, `completed`, `failed`, `aborted`.
  final String? status;
  final String? message;

  const ProwlarrCommand({
    required this.id,
    this.name,
    this.status,
    this.message,
  });

  bool get isFailed => (status ?? '').toLowerCase() == 'failed';
  bool get isFinished => const {
    'completed',
    'failed',
    'aborted',
    'cancelled',
  }.contains((status ?? '').toLowerCase());

  factory ProwlarrCommand.fromJson(Map<String, dynamic> json) {
    return ProwlarrCommand(
      id: intOrNull(json['id']) ?? 0,
      name: stringOrNull(json['name']) ?? stringOrNull(json['commandName']),
      status: stringOrNull(json['status']),
      message: stringOrNull(json['message']),
    );
  }
}

/// A single validation failure returned by a save/test call (HTTP 400 body).
class ProwlarrValidationFailure {
  final String? propertyName;
  final String? errorMessage;
  final bool isWarning;

  const ProwlarrValidationFailure({
    this.propertyName,
    this.errorMessage,
    this.isWarning = false,
  });

  factory ProwlarrValidationFailure.fromJson(Map<String, dynamic> json) {
    return ProwlarrValidationFailure(
      propertyName: stringOrNull(json['propertyName']),
      errorMessage:
          stringOrNull(json['errorMessage']) ?? stringOrNull(json['message']),
      isWarning:
          json['isWarning'] == true ||
          (stringOrNull(json['severity']) ?? '').toLowerCase() == 'warning',
    );
  }
}

/// One entry of `POST /api/v1/indexer/testall` (or the applications variant).
class ProwlarrTestResult {
  final int id;
  final bool isValid;
  final List<ProwlarrValidationFailure> failures;

  const ProwlarrTestResult({
    required this.id,
    this.isValid = false,
    this.failures = const [],
  });

  factory ProwlarrTestResult.fromJson(Map<String, dynamic> json) {
    final raw = json['validationFailures'];
    final failures = raw is List
        ? raw
              .whereType<Map>()
              .map(stringKeyMap)
              .map(ProwlarrValidationFailure.fromJson)
              .toList(growable: false)
        : const <ProwlarrValidationFailure>[];
    return ProwlarrTestResult(
      id: intOrNull(json['id']) ?? 0,
      isValid: json['isValid'] == true,
      failures: failures,
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

/// The four field-driven resources Prowlarr keeps under Settings.
///
/// They all share one server-side contract (`GET /<path>`, `/<path>/schema`,
/// `POST`, `PUT /<path>/{id}`, `DELETE /<path>/{id}`, `/<path>/test`,
/// `/<path>/testall`) and describe their own settings through `fields`, so this
/// client models them once — the differences are the handful of typed
/// properties named in [ProwlarrProviderResource].
enum ProwlarrProviderKind {
  application(
    path: 'applications',
    title: 'Apps',
    singular: 'app',
    icon: Icons.apps_rounded,
    routeSegment: 'apps',
  ),
  downloadClient(
    path: 'downloadclient',
    title: 'Download clients',
    singular: 'download client',
    icon: Icons.download_rounded,
    routeSegment: 'download-clients',
  ),
  notification(
    path: 'notification',
    title: 'Notifications',
    singular: 'notification',
    icon: Icons.notifications_active_outlined,
    routeSegment: 'notifications',
  ),
  indexerProxy(
    path: 'indexerproxy',
    title: 'Indexer proxies',
    singular: 'indexer proxy',
    icon: Icons.vpn_lock_rounded,
    routeSegment: 'proxies',
  );

  const ProwlarrProviderKind({
    required this.path,
    required this.title,
    required this.singular,
    required this.icon,
    required this.routeSegment,
  });

  /// Path segment under `/api/v1/`.
  final String path;
  final String title;
  final String singular;
  final IconData icon;

  /// Segment used by `/services/prowlarr/settings/<segment>`.
  final String routeSegment;

  static ProwlarrProviderKind? fromRouteSegment(String segment) {
    for (final kind in values) {
      if (kind.routeSegment == segment) return kind;
    }
    return null;
  }
}

/// One configured provider (app, download client, notification, proxy) or one
/// available implementation from `<kind>/schema`.
///
/// Like [ProwlarrIndexer] this keeps [raw] so a save round-trips every key the
/// client does not model; the typed getters cover what the forms actually edit.
class ProwlarrProviderResource {
  final int id;
  final String? name;
  final String? implementation;
  final String? implementationName;
  final String? configContract;
  final String? infoLink;
  final List<ProwlarrField> fields;
  final List<int> tags;
  final String? message;
  final String? messageType;
  final Map<String, dynamic> raw;

  const ProwlarrProviderResource({
    required this.id,
    this.name,
    this.implementation,
    this.implementationName,
    this.configContract,
    this.infoLink,
    this.fields = const [],
    this.tags = const [],
    this.message,
    this.messageType,
    this.raw = const {},
  });

  /// Applications only: `disabled`, `addOnly` or `fullSync`.
  String? get syncLevel => stringOrNull(raw['syncLevel']);

  /// Applications have no `enable` flag of their own — a sync level of
  /// `disabled` is what "off" means. Download clients do have one.
  bool get isActive {
    final level = syncLevel;
    if (level != null) return level != 'disabled';
    return raw.containsKey('enable') ? raw['enable'] == true : true;
  }

  /// Download clients only.
  bool get enable => raw['enable'] == true;
  int? get priority => intOrNull(raw['priority']);
  String? get protocol => stringOrNull(raw['protocol']);

  bool flag(String key) => raw[key] == true;

  String get displayImplementation =>
      implementationName ?? implementation ?? '';

  factory ProwlarrProviderResource.fromJson(Map<String, dynamic> json) {
    final tagsRaw = json['tags'];
    final tags = tagsRaw is List
        ? tagsRaw.map(intOrNull).whereType<int>().toList(growable: false)
        : const <int>[];
    final fieldsRaw = json['fields'];
    final fields = fieldsRaw is List
        ? (fieldsRaw
              .whereType<Map>()
              .map(stringKeyMap)
              .map(ProwlarrField.fromJson)
              .toList()
            ..sort((a, b) => a.order.compareTo(b.order)))
        : const <ProwlarrField>[];
    final message = mapOrNull(json['message']);

    return ProwlarrProviderResource(
      id: intOrNull(json['id']) ?? 0,
      name: stringOrNull(json['name']),
      implementation: stringOrNull(json['implementation']),
      implementationName: stringOrNull(json['implementationName']),
      configContract: stringOrNull(json['configContract']),
      infoLink: stringOrNull(json['infoLink']),
      fields: fields,
      tags: tags,
      message: stringOrNull(message?['message']),
      messageType: stringOrNull(message?['type']),
      raw: json,
    );
  }

  /// Builds the save body. [extras] carries the kind-specific properties the
  /// form edited (`syncLevel`, `enable`, `onGrab`…); `id` is dropped when 0, as
  /// an add.
  Map<String, dynamic> toPayload({
    String? name,
    List<ProwlarrField>? fields,
    List<int>? tags,
    Map<String, dynamic> extras = const {},
    int? id,
  }) {
    final effectiveId = id ?? this.id;
    final payload = <String, dynamic>{
      ...raw,
      'name': name ?? this.name,
      'tags': tags ?? this.tags,
      'fields': (fields ?? this.fields)
          .map((field) => field.toJson())
          .toList(growable: false),
      ...extras,
    };
    if (effectiveId > 0) {
      payload['id'] = effectiveId;
    } else {
      payload.remove('id');
    }
    return payload;
  }
}

/// A newznab category from `GET /api/v1/indexer/categories`.
///
/// Only the top level is used as a filter (Prowlarr's own add dialog filters on
/// categories with an id below 100000, i.e. the standard newznab tree).
class ProwlarrCategory {
  final int id;
  final String? name;
  final List<ProwlarrCategory> subCategories;

  const ProwlarrCategory({
    required this.id,
    this.name,
    this.subCategories = const [],
  });

  factory ProwlarrCategory.fromJson(Map<String, dynamic> json) {
    final raw = json['subCategories'];
    final subs = raw is List
        ? raw
              .whereType<Map>()
              .map(stringKeyMap)
              .map(ProwlarrCategory.fromJson)
              .toList(growable: false)
        : const <ProwlarrCategory>[];
    return ProwlarrCategory(
      id: intOrNull(json['id']) ?? 0,
      name: stringOrNull(json['name']),
      subCategories: subs,
    );
  }
}

/// A tag with what currently references it, from `GET /api/v1/tag/detail`.
class ProwlarrTagDetail {
  final int id;
  final String label;
  final List<int> indexerIds;
  final List<int> applicationIds;
  final List<int> notificationIds;
  final List<int> indexerProxyIds;

  const ProwlarrTagDetail({
    required this.id,
    required this.label,
    this.indexerIds = const [],
    this.applicationIds = const [],
    this.notificationIds = const [],
    this.indexerProxyIds = const [],
  });

  int get usageCount =>
      indexerIds.length +
      applicationIds.length +
      notificationIds.length +
      indexerProxyIds.length;

  bool get isUnused => usageCount == 0;

  factory ProwlarrTagDetail.fromJson(Map<String, dynamic> json) {
    List<int> ids(dynamic raw) => raw is List
        ? raw.map(intOrNull).whereType<int>().toList(growable: false)
        : const <int>[];
    return ProwlarrTagDetail(
      id: intOrNull(json['id']) ?? 0,
      label: stringOrNull(json['label']) ?? '',
      indexerIds: ids(json['indexerIds']),
      applicationIds: ids(json['applicationIds']),
      notificationIds: ids(json['notificationIds']),
      indexerProxyIds: ids(json['indexerProxyIds']),
    );
  }
}
