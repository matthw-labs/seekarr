import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/api/api_client.dart';
import 'package:seekarr/core/status/arr_queue_snapshot.dart';
import 'package:seekarr/core/utils/arr_activity_display.dart';
import 'package:seekarr/core/utils/dynamic_map_utils.dart';
import 'package:seekarr/features/bazarr/presentation/bazarr_provider.dart';
import 'package:seekarr/features/dockge/presentation/dockge_provider.dart';
import 'package:seekarr/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:seekarr/features/nzbget/data/nzbget_client.dart';
import 'package:seekarr/features/nzbget/presentation/nzbget_provider.dart';
import 'package:seekarr/features/readarr/presentation/readarr_provider.dart';
import 'package:seekarr/features/sabnzbd/data/sabnzbd_client.dart';
import 'package:seekarr/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:seekarr/features/discover/data/seerr_service.dart';
import 'package:seekarr/features/discover/presentation/discover_provider.dart';
import 'package:seekarr/features/movies/data/radarr_service.dart';
import 'package:seekarr/features/movies/presentation/movies_provider.dart';
import 'package:seekarr/features/music/data/lidarr_service.dart';
import 'package:seekarr/features/music/domain/lidarr_queue_snapshots.dart';
import 'package:seekarr/features/music/presentation/music_provider.dart';
import 'package:seekarr/features/series/data/sonarr_service.dart';
import 'package:seekarr/features/series/presentation/series_provider.dart';
import 'package:seekarr/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:seekarr/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:seekarr/features/services/domain/service_summary.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';
import 'package:seekarr/features/truenas/presentation/truenas_provider.dart';
import 'package:seekarr/features/unraid/data/unraid_client.dart';
import 'package:seekarr/features/unraid/presentation/unraid_provider.dart';

final serviceSummaryProvider =
    FutureProvider.family<ServiceSummary, ServiceKey>((ref, service) async {
      final settings = ref.watch(currentSettingsProvider);
      return _loadServiceSummary(ref, service, settings);
    });

typedef ServiceStatusClientFactory =
    ApiClient Function({required String baseUrl, required String apiKey});

final serviceStatusClientFactoryProvider = Provider<ServiceStatusClientFactory>(
  (ref) =>
      ({required String baseUrl, required String apiKey}) =>
          ApiClient(baseUrl: baseUrl, apiKey: apiKey),
);

Future<ServiceSummary> _loadServiceSummary(
  Ref ref,
  ServiceKey service,
  SettingsModel settings,
) async {
  final host = service.extractHost(settings.urlFor(service)) ?? '';
  if (!settings.isServiceConfigured(service)) {
    return _offlineSummary(service, host: host);
  }

  final String? version;
  try {
    version = await _loadVersion(ref, settings, service);
  } catch (_) {
    return _offlineSummary(service, host: host);
  }

  final itemCount = await _loadItemCountOrNull(ref, service);

  return ServiceSummary(
    service: service,
    status: ServiceSummaryStatus.online,
    host: host,
    version: version,
    itemCount: itemCount,
    itemLabel: service.itemLabel,
  );
}

ServiceSummary _offlineSummary(ServiceKey service, {required String host}) {
  return ServiceSummary(
    service: service,
    status: ServiceSummaryStatus.offline,
    host: host,
    version: null,
    itemCount: null,
    itemLabel: service.itemLabel,
  );
}

Future<String?> _loadVersion(
  Ref ref,
  SettingsModel settings,
  ServiceKey service,
) async {
  if (service == ServiceKey.qbittorrent) {
    final client = QbittorrentClient(
      url: settings.qbittorrentUrl,
      username: settings.qbittorrentUsername.isNotEmpty
          ? settings.qbittorrentUsername
          : null,
      password: settings.qbittorrentPassword.isNotEmpty
          ? settings.qbittorrentPassword
          : null,
    );
    try {
      final version = await client.getVersion().timeout(
        const Duration(seconds: 5),
      );
      client.close();
      return version.isNotEmpty ? version : null;
    } catch (_) {
      client.close();
      return null;
    }
  }

  if (service == ServiceKey.truenas) {
    final info = await ref
        .watch(truenasServiceProvider)
        .getSystemInfo()
        .timeout(const Duration(seconds: 8));
    return info.version;
  }

  if (service == ServiceKey.dockge) {
    return ref
        .watch(dockgeServiceProvider)
        .fetchVersion()
        .timeout(const Duration(seconds: 8));
  }

  if (service == ServiceKey.sabnzbd) {
    final client = SabnzbdClient(
      url: settings.sabnzbdUrl,
      apiKey: settings.sabnzbdApiKey,
    );
    try {
      final version = await client.getVersion().timeout(
        const Duration(seconds: 5),
      );
      return version.isNotEmpty ? version : null;
    } finally {
      client.close();
    }
  }

  if (service == ServiceKey.nzbget) {
    final client = NzbgetClient(
      url: settings.nzbgetUrl,
      username: settings.nzbgetUsername.isEmpty
          ? null
          : settings.nzbgetUsername,
      password: settings.nzbgetPassword.isEmpty
          ? null
          : settings.nzbgetPassword,
    );
    try {
      final version = await client.version().timeout(
        const Duration(seconds: 5),
      );
      return version.isNotEmpty ? version : null;
    } finally {
      client.close();
    }
  }

  if (service == ServiceKey.unraid) {
    final client = UnraidClient(
      url: settings.unraidUrl,
      apiKey: settings.unraidApiKey,
    );
    try {
      final version = await client.version().timeout(
        const Duration(seconds: 6),
      );
      return version.isNotEmpty ? version : null;
    } finally {
      client.close();
    }
  }

  final createClient = ref.watch(serviceStatusClientFactoryProvider);
  final client = createClient(
    baseUrl: settings.urlFor(service),
    apiKey: settings.apiKeyFor(service),
  );

  try {
    final response = await client
        .get(_statusEndpointFor(service))
        .timeout(const Duration(seconds: 5));
    final data = response.data;
    if (data is Map<String, dynamic>) {
      if (service == ServiceKey.bazarr) {
        final nested = mapOrNull(data['data']);
        return stringOrNull(nested?['bazarr_version']);
      }
      return (data['version'] ?? data['appVersion'])?.toString();
    }
    return null;
  } finally {
    client.close();
  }
}

String _statusEndpointFor(ServiceKey service) {
  switch (service) {
    case ServiceKey.seerr:
      return '/api/v1/status';
    case ServiceKey.radarr:
    case ServiceKey.sonarr:
      return '/api/v3/system/status';
    case ServiceKey.lidarr:
      return '/api/v1/system/status';
    case ServiceKey.qbittorrent:
      return '/api/v2/app/version';
    case ServiceKey.bazarr:
      return '/api/system/status';
    case ServiceKey.truenas:
      // Handled over WebSocket in _loadVersion; no REST endpoint.
      return '';
    case ServiceKey.dockge:
      // Handled over Socket.IO in _loadVersion; no REST endpoint.
      return '';
    case ServiceKey.prowlarr:
      return '/api/v1/system/status';
    case ServiceKey.readarr:
      return '/api/v1/system/status';
    case ServiceKey.sabnzbd:
      // Handled over the query-string API in _loadVersion; no REST endpoint.
      return '';
    case ServiceKey.nzbget:
      // Handled over JSON-RPC in _loadVersion; no REST endpoint.
      return '';
    case ServiceKey.unraid:
      // Handled over GraphQL in _loadVersion; no REST endpoint.
      return '';
  }
}

Future<int> _loadItemCount(Ref ref, ServiceKey service) async {
  switch (service) {
    case ServiceKey.seerr:
      return (await ref.watch(seerrServiceProvider).getRequests()).length;
    case ServiceKey.radarr:
      return (await ref.watch(radarrServiceProvider).getMovies()).length;
    case ServiceKey.sonarr:
      return (await ref.watch(sonarrServiceProvider).getSeries()).length;
    case ServiceKey.lidarr:
      return (await ref.watch(lidarrServiceProvider).getArtists()).length;
    case ServiceKey.qbittorrent:
      return (await ref.watch(qbittorrentServiceProvider).getTorrents()).length;
    case ServiceKey.bazarr:
      return (await ref.watch(bazarrServiceProvider).getBadges()).totalWanted;
    case ServiceKey.truenas:
      return (await ref.watch(truenasServiceProvider).getPools()).length;
    case ServiceKey.dockge:
      return (await ref.watch(dockgeServiceProvider).fetchStacks()).length;
    case ServiceKey.prowlarr:
      return (await ref.watch(prowlarrServiceProvider).getIndexers()).length;
    case ServiceKey.readarr:
      return (await ref.watch(readarrServiceProvider).getAuthors()).length;
    case ServiceKey.sabnzbd:
      return (await ref.watch(sabnzbdQueueProvider.future)).slots.length;
    case ServiceKey.nzbget:
      return (await ref.watch(nzbgetQueueProvider.future)).length;
    case ServiceKey.unraid:
      return (await ref.watch(unraidDockerProvider.future)).length;
  }
}

Future<int?> _loadItemCountOrNull(Ref ref, ServiceKey service) async {
  try {
    return await _loadItemCount(ref, service);
  } catch (_) {
    return null;
  }
}

final servicesTrendingProvider = discoverTrendingProvider;
final servicesRequestsProvider = requestsProvider;
final servicesMoviesProvider = moviesProvider;
final servicesSeriesProvider = seriesProvider;
final servicesMusicProvider = musicProvider;

/// The Radarr queue indexed by movie id.
///
/// Every surface that badges a movie — grid, poster rail, detail page — reads
/// this one snapshot, so they cannot disagree about what is downloading.
final radarrQueueSnapshotProvider = FutureProvider<ArrQueueSnapshot>((
  ref,
) async {
  return _loadArrQueueSnapshot(
    () => ref.watch(radarrServiceProvider).getQueue(),
    (item) => [intOrNull(mapOrNull(item['movie'])?['id'] ?? item['movieId'])],
  );
});

/// The Sonarr queue indexed by series id.
final sonarrQueueSnapshotProvider = FutureProvider<ArrQueueSnapshot>((
  ref,
) async {
  return _loadArrQueueSnapshot(
    () => ref.watch(sonarrServiceProvider).getQueue(),
    (item) => [intOrNull(mapOrNull(item['series'])?['id'] ?? item['seriesId'])],
  );
});

/// The Lidarr queue indexed by artist *and* album id.
final lidarrQueueSnapshotsProvider = FutureProvider<LidarrQueueSnapshots>((
  ref,
) async {
  final service = ref.watch(lidarrServiceProvider);

  int? directArtistId(Map<String, dynamic> item) => intOrNull(
    mapOrNull(item['artist'])?['id'] ??
        mapOrNull(item['album'])?['artistId'] ??
        item['artistId'],
  );
  int? albumIdOf(Map<String, dynamic> item) =>
      intOrNull(mapOrNull(item['album'])?['id'] ?? item['albumId']);

  try {
    final queueItems = (await service.getQueue())
        .whereType<Map>()
        .map(stringKeyMap)
        .toList(growable: false);
    if (queueItems.isEmpty) {
      return LidarrQueueSnapshots.empty;
    }

    // Only records that do not already name their artist are worth the album
    // lookup below, which costs one request per artist.
    final unresolvedAlbumIds = <int>{};
    for (final item in queueItems) {
      final artistId = directArtistId(item);
      if (artistId != null && artistId > 0) continue;

      final albumId = albumIdOf(item);
      if (albumId != null && albumId > 0) {
        unresolvedAlbumIds.add(albumId);
      }
    }

    final albumToArtist = <int, int>{};
    if (unresolvedAlbumIds.isNotEmpty) {
      final pending = {...unresolvedAlbumIds};
      for (final artist in await service.getArtists()) {
        if (pending.isEmpty) break;
        if (artist.albumCount <= 0) continue;

        try {
          for (final album in await service.getAlbums(artist.id)) {
            if (pending.remove(album.id)) {
              albumToArtist[album.id] = artist.id;
            }
          }
        } catch (_) {
          continue;
        }
      }
    }

    return LidarrQueueSnapshots(
      byArtist: ArrQueueSnapshot.fromQueueItems(
        queueItems,
        idsFor: (item) {
          final direct = directArtistId(item);
          if (direct != null && direct > 0) return [direct];

          final albumId = albumIdOf(item);
          final resolved = albumId == null ? null : albumToArtist[albumId];
          return resolved == null ? const <int>[] : [resolved];
        },
      ),
      byAlbum: ArrQueueSnapshot.fromQueueItems(
        queueItems,
        idsFor: (item) {
          final albumId = albumIdOf(item);
          return albumId == null ? const <int>[] : [albumId];
        },
      ),
    );
  } catch (_) {
    return LidarrQueueSnapshots.empty;
  }
});

/// Queued movie ids, derived from [radarrQueueSnapshotProvider].
final radarrQueuedMovieIdsProvider = FutureProvider<Set<int>>((ref) async {
  final snapshot = await ref.watch(radarrQueueSnapshotProvider.future);
  return snapshot.entriesById.keys.toSet();
});

/// Queued series ids, derived from [sonarrQueueSnapshotProvider].
final sonarrQueuedSeriesIdsProvider = FutureProvider<Set<int>>((ref) async {
  final snapshot = await ref.watch(sonarrQueueSnapshotProvider.future);
  return snapshot.entriesById.keys.toSet();
});

/// Queued artist ids, derived from [lidarrQueueSnapshotsProvider].
final lidarrQueuedArtistIdsProvider = FutureProvider<Set<int>>((ref) async {
  final snapshots = await ref.watch(lidarrQueueSnapshotsProvider.future);
  return snapshots.byArtist.entriesById.keys.toSet();
});

final servicesQueueProvider = FutureProvider<List<ServiceQueueItem>>((
  ref,
) async {
  final results = await Future.wait([
    _loadServiceQueueItems(ref, ServiceKey.radarr),
    _loadServiceQueueItems(ref, ServiceKey.sonarr),
  ]);

  return results.expand((items) => items).take(3).toList(growable: false);
});

class ServiceQueueItem {
  final ServiceKey service;
  final String title;
  final String subtitle;
  final double? progress;
  final String? warning;

  const ServiceQueueItem({
    required this.service,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.warning,
  });
}

/// Fetches a `/queue` and indexes it, degrading to an empty snapshot on failure
/// so a badge never blocks on an unreachable service.
Future<ArrQueueSnapshot> _loadArrQueueSnapshot(
  Future<List<dynamic>> Function() loadItems,
  Iterable<int?> Function(Map<String, dynamic> item) idsFor,
) async {
  try {
    return ArrQueueSnapshot.fromQueueItems(
      await loadItems(),
      idsFor: (item) => idsFor(item).whereType<int>(),
    );
  } catch (_) {
    return ArrQueueSnapshot.empty;
  }
}

Future<List<ServiceQueueItem>> _loadServiceQueueItems(
  Ref ref,
  ServiceKey service,
) async {
  try {
    final items = switch (service) {
      ServiceKey.radarr => await ref.watch(radarrServiceProvider).getQueue(),
      ServiceKey.sonarr => await ref.watch(sonarrServiceProvider).getQueue(),
      ServiceKey.seerr ||
      ServiceKey.lidarr ||
      ServiceKey.qbittorrent ||
      ServiceKey.bazarr ||
      ServiceKey.truenas ||
      ServiceKey.dockge ||
      ServiceKey.prowlarr ||
      ServiceKey.readarr ||
      ServiceKey.sabnzbd ||
      ServiceKey.nzbget ||
      ServiceKey.unraid => const <dynamic>[],
    };
    return items
        .whereType<Map>()
        .map((item) => _queueItemFromMap(service, item))
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

ServiceQueueItem _queueItemFromMap(ServiceKey service, Map item) {
  final typedItem = stringKeyMap(item);
  final title =
      arrPrimaryMediaTitle(typedItem) ??
      arrReleaseTitle(typedItem) ??
      'Unknown release';
  final quality = _queueQualityLabel(typedItem['quality']);
  final subtitle = joinDisplayParts([
    _queueTypeLabel(service),
    if (service == ServiceKey.sonarr) arrEpisodeCode(typedItem),
    quality,
    arrReleaseTitle(typedItem),
  ]);

  return ServiceQueueItem(
    service: service,
    title: title,
    subtitle: subtitle,
    progress: queueProgress(typedItem),
    warning: arrQueueWarningMessage(typedItem),
  );
}

String _queueTypeLabel(ServiceKey service) {
  return switch (service) {
    ServiceKey.radarr => 'Movie',
    ServiceKey.sonarr => 'Series',
    ServiceKey.lidarr => 'Music',
    ServiceKey.seerr ||
    ServiceKey.qbittorrent ||
    ServiceKey.bazarr ||
    ServiceKey.truenas ||
    ServiceKey.dockge ||
    ServiceKey.prowlarr ||
    ServiceKey.readarr ||
    ServiceKey.sabnzbd ||
    ServiceKey.nzbget ||
    ServiceKey.unraid => service.title,
  };
}

String? _queueQualityLabel(dynamic value) {
  if (value is Map) {
    final quality = mapOrNull(value['quality']);
    return stringOrNull(quality?['name']) ?? stringOrNull(value['name']);
  }

  return stringOrNull(value);
}
