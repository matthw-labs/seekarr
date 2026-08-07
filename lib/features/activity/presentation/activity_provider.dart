import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/activity/domain/global_activity_status.dart';
import 'package:cupola/features/activity/presentation/activity_screen.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

export 'package:cupola/features/activity/domain/global_activity_status.dart'
    show GlobalActivityKind;

final activityRefreshVersionProvider = StateProvider<int>((ref) => 0);

const _globalActivityPageSize = 50;

/// How often the "Now" bucket refreshes itself.
///
/// A bucket named "Now" that shows a snapshot from whenever the tab was last
/// opened is not a live readout — a download sat at 43% until the user pulled to
/// refresh. Deliberately far slower than qBittorrent's 3s: that polls one local
/// endpoint for one list, whereas each tick here fans out to three \*arr
/// services, over a LAN, VPN or Tailscale link where a request can take a
/// second. 15s keeps the number honest without hammering someone's home server.
const _nowPollInterval = Duration(seconds: 15);

/// One service's contribution to a feed load.
///
/// The whole point of this type is that a failure is *reportable*. Every service
/// used to be wrapped in `catch (_) { return const []; }`, so a dead Sonarr and
/// an idle Sonarr produced byte-identical output and the screen confidently
/// said "Nothing downloading right now". Errors are caught per service — one
/// unreachable instance must never blank the others — but they are carried, not
/// swallowed.
class ActivityServiceResult {
  final ServiceKey service;
  final List<GlobalActivityItem> items;

  /// Non-null when the service was configured but did not answer.
  final Object? error;

  /// False when the user has not set this service up at all.
  final bool configured;

  const ActivityServiceResult({
    required this.service,
    required this.items,
    required this.configured,
    this.error,
  });

  const ActivityServiceResult.unconfigured(this.service)
    : items = const [],
      error = null,
      configured = false;

  /// Configured, asked, and answered.
  bool get reached => configured && error == null;

  /// Configured, asked, and did not answer.
  bool get failed => configured && error != null;
}

/// A whole feed load: the merged items plus what happened to each service.
class ActivityFeed {
  final List<GlobalActivityItem> items;
  final List<ActivityServiceResult> results;

  const ActivityFeed({required this.items, required this.results});

  const ActivityFeed.empty() : items = const [], results = const [];

  Iterable<ActivityServiceResult> get configured =>
      results.where((r) => r.configured);

  Iterable<ActivityServiceResult> get failures =>
      results.where((r) => r.failed);

  Iterable<ActivityServiceResult> get unconfigured =>
      results.where((r) => !r.configured);

  bool get hasConfiguredService => configured.isNotEmpty;

  /// Nothing was actually reached — every configured service errored.
  ///
  /// This is the case that must surface as an error with a retry rather than as
  /// an empty state, because "no items" here means "we have no idea".
  bool get allConfiguredFailed =>
      hasConfiguredService && configured.every((r) => r.failed);

  /// Some services answered and some did not, so the list is incomplete.
  bool get isPartial => failures.isNotEmpty && !allConfiguredFailed;

  /// The first error, for the whole-feed error state.
  Object? get firstError => failures.isEmpty ? null : failures.first.error;
}

class GlobalActivityItem {
  final GlobalActivityKind kind;
  final ServiceKey service;
  final ServiceType serviceType;
  final String title;
  final String subtitle;

  /// The fully resolved status — tone, label, progress, warning and all.
  ///
  /// Replaces the previous `String status` + `double? progress` +
  /// `String? warning` triple. Those were flattened at load time, which left the
  /// tile with nothing to colour by except the row's *kind* — the bug that made
  /// a failed import render in the success green.
  final MediaStatusInfo status;

  final DateTime? sortDate;
  final Map<String, dynamic>? raw;
  final SeerrRequest? request;

  const GlobalActivityItem({
    required this.kind,
    required this.service,
    required this.serviceType,
    required this.title,
    required this.subtitle,
    required this.status,
    this.sortDate,
    this.raw,
    this.request,
  });

  double? get progress => status.progress;

  /// The service's own explanation, when it gave one.
  String? get detail => status.detail;

  /// Wants the user's eye: failed, stalled, blocked, missing.
  bool get needsAttention =>
      status.tone == StatusTone.error || status.tone == StatusTone.warning;

  /// The \*arr record id, used by the queue write actions.
  int? get recordId => intOrNull(raw?['id']);
}

/// Auto-refresh for the "Now" bucket.
///
/// `autoDispose` so the timer only runs while something is watching it — the
/// screen watches it exclusively from the Now section, so leaving the tab or
/// switching to History stops the polling instead of quietly refetching three
/// services forever.
final activityNowPollingProvider = Provider.autoDispose<void>((ref) {
  final timer = Timer.periodic(_nowPollInterval, (_) {
    ref.read(activityRefreshVersionProvider.notifier).state++;
  });
  ref.onDispose(timer.cancel);
});

/// The services that can appear in the global feed, in display order.
const globalActivityServices = [
  ServiceKey.radarr,
  ServiceKey.sonarr,
  ServiceKey.lidarr,
  ServiceKey.seerr,
];

/// Only the services the user has actually configured.
///
/// The filter row used to be a `static const` of four, so a user running Radarr
/// alone still got Sonarr, Lidarr and Seerr chips, each leading to a confident
/// "Nothing downloading right now".
final configuredActivityServicesProvider = Provider<List<ServiceKey>>((ref) {
  final settings = ref.watch(settingsProvider);
  return globalActivityServices
      .where(settings.isServiceConfigured)
      .toList(growable: false);
});

final globalActivityFeedProvider = FutureProvider<ActivityFeed>((ref) async {
  ref.watch(activityRefreshVersionProvider);
  return _merge(
    await Future.wait([
      _loadRequestResult(ref),
      ..._loadArrResults(ref, GlobalActivityKind.queue),
      ..._loadArrResults(ref, GlobalActivityKind.history),
    ]),
  );
});

final globalQueueItemsProvider = FutureProvider<ActivityFeed>((ref) async {
  ref.watch(activityRefreshVersionProvider);
  return _merge(
    await Future.wait(_loadArrResults(ref, GlobalActivityKind.queue)),
  );
});

/// "Now" bucket: active downloads (queue) plus current Seerr requests, so
/// requests remain first-class in the unified view.
final globalNowItemsProvider = FutureProvider<ActivityFeed>((ref) async {
  ref.watch(activityRefreshVersionProvider);
  return _merge(
    await Future.wait([
      _loadRequestResult(ref),
      ..._loadArrResults(ref, GlobalActivityKind.queue),
    ]),
  );
});

/// Seerr requests only — the "Requests" sub-segment of the global "Now" bucket.
final globalRequestItemsProvider = FutureProvider<ActivityFeed>((ref) async {
  ref.watch(activityRefreshVersionProvider);
  return _merge([await _loadRequestResult(ref)]);
});

final globalHistoryItemsProvider = FutureProvider<ActivityFeed>((ref) async {
  ref.watch(activityRefreshVersionProvider);
  return _merge(
    await Future.wait(_loadArrResults(ref, GlobalActivityKind.history)),
  );
});

final globalWantedItemsProvider = FutureProvider<ActivityFeed>((ref) async {
  ref.watch(activityRefreshVersionProvider);
  return _merge(
    await Future.wait([
      ..._loadArrResults(ref, GlobalActivityKind.missing),
      ..._loadArrResults(ref, GlobalActivityKind.cutoff),
    ]),
  );
});

final globalBlocklistItemsProvider = FutureProvider<ActivityFeed>((ref) async {
  ref.watch(activityRefreshVersionProvider);
  return _merge(
    await Future.wait(_loadArrResults(ref, GlobalActivityKind.blocklist)),
  );
});

final globalMissingItemsProvider = FutureProvider<ActivityFeed>((ref) async {
  ref.watch(activityRefreshVersionProvider);
  return _merge(
    await Future.wait(_loadArrResults(ref, GlobalActivityKind.missing)),
  );
});

final globalCutoffItemsProvider = FutureProvider<ActivityFeed>((ref) async {
  ref.watch(activityRefreshVersionProvider);
  return _merge(
    await Future.wait(_loadArrResults(ref, GlobalActivityKind.cutoff)),
  );
});

/// Resolves a [ServiceType] to the corresponding *arr service.
///
/// Discover uses Seerr rather than an *arr service, so it is not
/// supported by this provider.
final resolvedArrServiceProvider =
    Provider.family<ArrActivityMixin, ServiceType>((ref, serviceType) {
      ref.watch(activityRefreshVersionProvider);

      assert(
        serviceType.supportsArrActivity,
        'resolvedArrServiceProvider only supports movies, series, and music.',
      );

      switch (serviceType) {
        case ServiceType.movies:
          return ref.read(radarrServiceProvider);
        case ServiceType.series:
          return ref.read(sonarrServiceProvider);
        case ServiceType.music:
          return ref.read(lidarrServiceProvider);
        case ServiceType.discover:
          throw ArgumentError.value(
            serviceType,
            'serviceType',
            'ServiceType.discover does not have an *arr service',
          );
      }
    });

/// Folds per-service results into one feed, merging duplicate services.
///
/// A bucket can ask the same service for two kinds (Wanted asks for missing and
/// cutoff), so results arrive keyed by service more than once and have to be
/// combined before the health strip can report one row per service.
ActivityFeed _merge(List<ActivityServiceResult> results) {
  final byService = <ServiceKey, ActivityServiceResult>{};
  for (final result in results) {
    final existing = byService[result.service];
    if (existing == null) {
      byService[result.service] = result;
      continue;
    }
    byService[result.service] = ActivityServiceResult(
      service: result.service,
      items: [...existing.items, ...result.items],
      configured: existing.configured || result.configured,
      // Either half failing means the list for this service is incomplete.
      error: existing.error ?? result.error,
    );
  }

  final ordered = globalActivityServices
      .where(byService.containsKey)
      .map((service) => byService[service]!)
      .toList(growable: false);

  return ActivityFeed(
    items: _sortItems(
      ordered.expand((result) => result.items).toList(growable: false),
    ),
    results: ordered,
  );
}

Future<ActivityServiceResult> _loadRequestResult(Ref ref) async {
  final settings = ref.read(settingsProvider);
  if (!settings.isServiceConfigured(ServiceKey.seerr)) {
    return const ActivityServiceResult.unconfigured(ServiceKey.seerr);
  }

  try {
    final requests = await ref.read(requestsProvider.future);
    return ActivityServiceResult(
      service: ServiceKey.seerr,
      items: requests.map(_requestItem).toList(growable: false),
      configured: true,
    );
  } catch (error) {
    return ActivityServiceResult(
      service: ServiceKey.seerr,
      items: const [],
      configured: true,
      error: error,
    );
  }
}

List<Future<ActivityServiceResult>> _loadArrResults(
  Ref ref,
  GlobalActivityKind kind,
) {
  const serviceTypes = [
    ServiceType.movies,
    ServiceType.series,
    ServiceType.music,
  ];

  return serviceTypes
      .map((serviceType) async {
        final service = _serviceKeyFor(serviceType);
        final settings = ref.read(settingsProvider);
        if (!settings.isServiceConfigured(service)) {
          return ActivityServiceResult.unconfigured(service);
        }

        try {
          final arrService = ref.read(resolvedArrServiceProvider(serviceType));
          final items = await _loadRawItems(arrService, kind);
          return ActivityServiceResult(
            service: service,
            items: items
                .whereType<Map>()
                .map((item) => _arrItem(kind, serviceType, stringKeyMap(item)))
                .toList(growable: false),
            configured: true,
          );
        } catch (error) {
          return ActivityServiceResult(
            service: service,
            items: const [],
            configured: true,
            error: error,
          );
        }
      })
      .toList(growable: false);
}

Future<List<dynamic>> _loadRawItems(
  ArrActivityMixin service,
  GlobalActivityKind kind,
) {
  return switch (kind) {
    GlobalActivityKind.queue => service.getQueue(),
    GlobalActivityKind.history => service.getHistory(pageSize: 25),
    GlobalActivityKind.blocklist => service.getBlocklist(),
    GlobalActivityKind.missing => service.getMissing(
      pageSize: _globalActivityPageSize,
    ),
    GlobalActivityKind.cutoff => service.getCutoff(
      pageSize: _globalActivityPageSize,
    ),
    GlobalActivityKind.request => Future.value(const <dynamic>[]),
  };
}

GlobalActivityItem _requestItem(SeerrRequest request) {
  final title = request.media?.title ?? 'Unknown request';
  final requester = request.requestedBy?.displayName;
  final type = request.type == 'tv' ? 'Series' : 'Movie';
  return GlobalActivityItem(
    kind: GlobalActivityKind.request,
    service: ServiceKey.seerr,
    serviceType: ServiceType.discover,
    title: title,
    subtitle: [requester, type].whereType<String>().join(' · '),
    status: resolveRequestStatus(request),
    sortDate: DateTime.tryParse(request.createdAt),
    request: request,
  );
}

GlobalActivityItem _arrItem(
  GlobalActivityKind kind,
  ServiceType serviceType,
  Map<String, dynamic> item,
) {
  final service = _serviceKeyFor(serviceType);
  return GlobalActivityItem(
    kind: kind,
    service: service,
    serviceType: serviceType,
    title: _titleFor(kind, serviceType, item),
    subtitle: _subtitleFor(kind, serviceType, item),
    status: resolveActivityStatus(kind, item),
    sortDate: _sortDateFor(kind, item),
    raw: item,
  );
}

/// Orders a feed so trouble surfaces first.
///
/// The previous comparator sorted purely by date descending, which for the queue
/// meant `estimatedCompletionTime` descending: the download finishing soonest
/// went last, and anything stalled — no ETA at all — sorted dead last. The one
/// row the user opened the screen to find was at the bottom.
///
/// Three keys, in order:
///  1. severity: errors, then warnings, then everything calm;
///  2. liveness: an in-flight queue item outranks a request from last Tuesday;
///  3. time: soonest-first for the queue (an ETA counts down), newest-first for
///     everything else (history counts up). Undated rows go last.
///
/// Comparing dates only ever happens inside one liveness group, so the two
/// opposite directions never meet and the ordering stays a valid total order.
List<GlobalActivityItem> _sortItems(List<GlobalActivityItem> items) {
  int severity(GlobalActivityItem item) => switch (item.status.tone) {
    StatusTone.error => 0,
    StatusTone.warning => 1,
    _ => 2,
  };

  // Queue rows are live; everything else is a record of something settled.
  int liveness(GlobalActivityItem item) =>
      item.kind == GlobalActivityKind.queue ? 0 : 1;

  return [...items]..sort((a, b) {
    final bySeverity = severity(a).compareTo(severity(b));
    if (bySeverity != 0) return bySeverity;

    final byLiveness = liveness(a).compareTo(liveness(b));
    if (byLiveness != 0) return byLiveness;

    final left = a.sortDate;
    final right = b.sortDate;
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;

    final chronological = left.compareTo(right);
    // Ascending for the queue: the nearest ETA is the most imminent.
    return liveness(a) == 0 ? chronological : -chronological;
  });
}

ServiceKey _serviceKeyFor(ServiceType serviceType) {
  return switch (serviceType) {
    ServiceType.discover => ServiceKey.seerr,
    ServiceType.movies => ServiceKey.radarr,
    ServiceType.series => ServiceKey.sonarr,
    ServiceType.music => ServiceKey.lidarr,
  };
}

String _titleFor(
  GlobalActivityKind kind,
  ServiceType serviceType,
  Map<String, dynamic> item,
) {
  return switch (kind) {
    GlobalActivityKind.queue =>
      arrPrimaryMediaTitle(item) ?? arrReleaseTitle(item) ?? 'Unknown release',
    GlobalActivityKind.history =>
      arrPrimaryMediaTitle(item) ?? arrReleaseTitle(item) ?? 'History item',
    GlobalActivityKind.blocklist =>
      arrPrimaryMediaTitle(item) ?? arrReleaseTitle(item) ?? 'Blocked release',
    GlobalActivityKind.missing ||
    GlobalActivityKind.cutoff => _wantedTitle(serviceType, item),
    GlobalActivityKind.request => 'Request',
  };
}

String _subtitleFor(
  GlobalActivityKind kind,
  ServiceType serviceType,
  Map<String, dynamic> item,
) {
  final title = _titleFor(kind, serviceType, item);

  return switch (kind) {
    GlobalActivityKind.queue => _activitySecondaryLine(
      serviceType,
      item,
      title: title,
    ),
    GlobalActivityKind.history => _activitySecondaryLine(
      serviceType,
      item,
      title: title,
      releaseKey: 'sourceTitle',
    ),
    GlobalActivityKind.blocklist => _activitySecondaryLine(
      serviceType,
      item,
      title: title,
      releaseKey: 'sourceTitle',
    ),
    GlobalActivityKind.missing || GlobalActivityKind.cutoff => [
      _serviceKeyFor(serviceType).title,
      _wantedContext(serviceType, item),
    ].whereType<String>().join(' · '),
    GlobalActivityKind.request => _serviceKeyFor(serviceType).title,
  };
}

DateTime? _sortDateFor(GlobalActivityKind kind, Map<String, dynamic> item) {
  return switch (kind) {
    GlobalActivityKind.queue => DateTime.tryParse(
      stringOrNull(item['estimatedCompletionTime']) ?? '',
    ),
    GlobalActivityKind.history || GlobalActivityKind.blocklist =>
      DateTime.tryParse(stringOrNull(item['date']) ?? ''),
    GlobalActivityKind.missing ||
    GlobalActivityKind.cutoff => DateTime.tryParse(
      stringOrNull(
            item['airDateUtc'] ?? item['releaseDate'] ?? item['added'],
          ) ??
          '',
    ),
    GlobalActivityKind.request => null,
  };
}

String _wantedTitle(ServiceType serviceType, Map<String, dynamic> item) {
  return switch (serviceType) {
    ServiceType.movies => stringOrNull(item['title']) ?? 'Missing movie',
    ServiceType.series =>
      stringOrNull(mapOrNull(item['series'])?['title']) ??
          stringOrNull(item['title']) ??
          'Missing episode',
    ServiceType.music =>
      stringOrNull(item['title']) ??
          stringOrNull(mapOrNull(item['album'])?['title']) ??
          'Missing album',
    ServiceType.discover => 'Request',
  };
}

String? _wantedContext(ServiceType serviceType, Map<String, dynamic> item) {
  return switch (serviceType) {
    ServiceType.movies => _yearLabel(item),
    ServiceType.series => _episodeLabel(item),
    ServiceType.music => stringOrNull(mapOrNull(item['artist'])?['artistName']),
    ServiceType.discover => null,
  };
}

String _activitySecondaryLine(
  ServiceType serviceType,
  Map<String, dynamic> item, {
  required String title,
  String releaseKey = 'title',
}) {
  final release = stringOrNull(item[releaseKey]);
  final uniqueRelease = release == title ? null : release;

  return switch (serviceType) {
    ServiceType.series => joinDisplayParts([
      arrEpisodeCode(item),
      arrEpisodeTitle(item),
      uniqueRelease,
    ]),
    ServiceType.movies => joinDisplayParts([uniqueRelease]),
    ServiceType.music => joinDisplayParts([arrArtistName(item), uniqueRelease]),
    ServiceType.discover => '',
  };
}

String? _yearLabel(Map<String, dynamic> item) {
  final year = item['year'];
  if (year == null) return null;
  return year.toString();
}

String? _episodeLabel(Map<String, dynamic> item) {
  final season = intOrNull(item['seasonNumber']);
  final episode = intOrNull(item['episodeNumber']);
  if (season == null || episode == null) return stringOrNull(item['title']);
  return 'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';
}
