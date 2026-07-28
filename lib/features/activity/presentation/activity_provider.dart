import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

import 'package:seekarr/core/api/base_arr_service.dart';
import 'package:seekarr/core/utils/arr_activity_display.dart';
import 'package:seekarr/core/utils/dynamic_map_utils.dart';
import 'package:seekarr/features/discover/domain/models/seerr_request.dart';
import 'package:seekarr/features/discover/presentation/discover_provider.dart';
import 'package:seekarr/features/activity/presentation/activity_screen.dart';
import 'package:seekarr/features/activity/presentation/widgets/activity_formatters.dart';
import 'package:seekarr/features/movies/data/radarr_service.dart';
import 'package:seekarr/features/music/data/lidarr_service.dart';
import 'package:seekarr/features/series/data/sonarr_service.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

final activityRefreshVersionProvider = StateProvider<int>((ref) => 0);

const _globalActivityPageSize = 50;

enum GlobalActivityKind { request, queue, history, blocklist, missing, cutoff }

class GlobalActivityItem {
  final GlobalActivityKind kind;
  final ServiceKey service;
  final ServiceType serviceType;
  final String title;
  final String subtitle;
  final String status;
  final double? progress;
  final String? warning;
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
    this.progress,
    this.warning,
    this.sortDate,
    this.raw,
    this.request,
  });
}

final globalActivityFeedProvider = FutureProvider<List<GlobalActivityItem>>((
  ref,
) async {
  ref.watch(activityRefreshVersionProvider);
  final results = await Future.wait([
    _loadRequestItems(ref),
    _loadArrItems(ref, GlobalActivityKind.queue),
    _loadArrItems(ref, GlobalActivityKind.history),
  ]);

  return _sortItems(results.expand((items) => items).toList(growable: false));
});

final globalQueueItemsProvider = FutureProvider<List<GlobalActivityItem>>((
  ref,
) async {
  ref.watch(activityRefreshVersionProvider);
  return _loadArrItems(ref, GlobalActivityKind.queue);
});

/// "Now" bucket for the global Activity screen: active downloads (queue) plus
/// current Seerr requests, so requests remain first-class in the unified view.
final globalNowItemsProvider = FutureProvider<List<GlobalActivityItem>>((
  ref,
) async {
  ref.watch(activityRefreshVersionProvider);
  final results = await Future.wait([
    _loadRequestItems(ref),
    _loadArrItems(ref, GlobalActivityKind.queue),
  ]);
  return _sortItems(results.expand((items) => items).toList(growable: false));
});

/// Seerr requests only — the "Requests" sub-segment of the global "Now" bucket.
final globalRequestItemsProvider = FutureProvider<List<GlobalActivityItem>>((
  ref,
) async {
  ref.watch(activityRefreshVersionProvider);
  return _sortItems(await _loadRequestItems(ref));
});

final globalHistoryItemsProvider = FutureProvider<List<GlobalActivityItem>>((
  ref,
) async {
  ref.watch(activityRefreshVersionProvider);
  return _loadArrItems(ref, GlobalActivityKind.history);
});

final globalWantedItemsProvider = FutureProvider<List<GlobalActivityItem>>((
  ref,
) async {
  ref.watch(activityRefreshVersionProvider);
  final results = await Future.wait([
    _loadArrItems(ref, GlobalActivityKind.missing),
    _loadArrItems(ref, GlobalActivityKind.cutoff),
  ]);
  return _sortItems(results.expand((items) => items).toList(growable: false));
});

final globalBlocklistItemsProvider = FutureProvider<List<GlobalActivityItem>>((
  ref,
) async {
  ref.watch(activityRefreshVersionProvider);
  return _loadArrItems(ref, GlobalActivityKind.blocklist);
});

final globalMissingItemsProvider = FutureProvider<List<GlobalActivityItem>>((
  ref,
) async {
  ref.watch(activityRefreshVersionProvider);
  return _loadArrItems(ref, GlobalActivityKind.missing);
});

final globalCutoffItemsProvider = FutureProvider<List<GlobalActivityItem>>((
  ref,
) async {
  ref.watch(activityRefreshVersionProvider);
  return _loadArrItems(ref, GlobalActivityKind.cutoff);
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

Future<List<GlobalActivityItem>> _loadRequestItems(Ref ref) async {
  try {
    final requests = await ref.read(requestsProvider.future);
    return requests.map(_requestItem).toList(growable: false);
  } catch (_) {
    return const [];
  }
}

Future<List<GlobalActivityItem>> _loadArrItems(
  Ref ref,
  GlobalActivityKind kind,
) async {
  final results = await Future.wait(
    const [ServiceType.movies, ServiceType.series, ServiceType.music].map((
      serviceType,
    ) async {
      try {
        final service = ref.read(resolvedArrServiceProvider(serviceType));
        final items = await _loadRawItems(service, kind);
        return items
            .whereType<Map>()
            .map((item) => _arrItem(kind, serviceType, stringKeyMap(item)))
            .toList(growable: false);
      } catch (_) {
        return const <GlobalActivityItem>[];
      }
    }),
  );

  return _sortItems(results.expand((items) => items).toList(growable: false));
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
    status: request.displayStatus.label,
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
    status: _statusFor(kind, item),
    progress: kind == GlobalActivityKind.queue ? queueProgress(item) : null,
    warning: kind == GlobalActivityKind.queue
        ? arrQueueWarningMessage(item)
        : null,
    sortDate: _sortDateFor(kind, item),
    raw: item,
  );
}

List<GlobalActivityItem> _sortItems(List<GlobalActivityItem> items) {
  return [...items]..sort((a, b) {
    final left = a.sortDate;
    final right = b.sortDate;
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return right.compareTo(left);
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

String _statusFor(GlobalActivityKind kind, Map<String, dynamic> item) {
  return switch (kind) {
    GlobalActivityKind.queue => queueDisplayLabel(
      resolveQueueDisplayStatus(item),
      includeWarningSuffix: false,
    ),
    GlobalActivityKind.history => humanizeEventType(
      stringOrNull(item['eventType']) ?? 'History',
    ),
    GlobalActivityKind.blocklist => 'Blocked',
    GlobalActivityKind.missing => 'Missing',
    GlobalActivityKind.cutoff => 'Cutoff',
    GlobalActivityKind.request => 'Request',
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
