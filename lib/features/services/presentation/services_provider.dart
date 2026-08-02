import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/api/api_client.dart';
import 'package:seekarr/core/status/arr_queue_snapshot.dart';
import 'package:seekarr/core/utils/arr_activity_display.dart';
import 'package:seekarr/core/utils/dynamic_map_utils.dart';
import 'package:seekarr/core/utils/image_utils.dart';
import 'package:seekarr/features/dockge/presentation/dockge_provider.dart';
import 'package:seekarr/features/nzbget/data/nzbget_client.dart';
import 'package:seekarr/features/nzbget/presentation/nzbget_provider.dart';
import 'package:seekarr/features/readarr/presentation/readarr_provider.dart';
import 'package:seekarr/features/sabnzbd/data/sabnzbd_client.dart';
import 'package:seekarr/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:seekarr/features/discover/presentation/discover_provider.dart';
import 'package:seekarr/features/movies/data/radarr_service.dart';
import 'package:seekarr/features/movies/presentation/movies_provider.dart';
import 'package:seekarr/features/music/data/lidarr_service.dart';
import 'package:seekarr/features/music/domain/lidarr_queue_snapshots.dart';
import 'package:seekarr/features/music/presentation/music_provider.dart';
import 'package:seekarr/features/series/data/sonarr_service.dart';
import 'package:seekarr/features/series/presentation/series_provider.dart';
import 'package:seekarr/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:seekarr/features/qbittorrent/domain/models/parse_utils.dart';
import 'package:seekarr/features/qbittorrent/domain/models/torrent.dart';
import 'package:seekarr/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:seekarr/features/services/domain/recently_added.dart';
import 'package:seekarr/features/services/domain/service_summary.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';
import 'package:seekarr/features/truenas/presentation/truenas_provider.dart';
import 'package:seekarr/features/unraid/data/unraid_client.dart';

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

  return ServiceSummary(
    service: service,
    status: ServiceSummaryStatus.online,
    host: host,
    version: version,
  );
}

ServiceSummary _offlineSummary(ServiceKey service, {required String host}) {
  return ServiceSummary(
    service: service,
    status: ServiceSummaryStatus.offline,
    host: host,
    version: null,
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

/// How many items the merged Recently Added rail shows.
const int servicesRecentlyAddedLimit = 12;

/// Newest library additions across Radarr, Sonarr and Lidarr, actually sorted.
///
/// One rail instead of the two it replaces, so Lidarr finally appears: the hub
/// already fetched `servicesMusicProvider` on every pull-to-refresh and rendered
/// it nowhere, paying for the whole artist library and discarding it.
///
/// Readarr is deliberately absent. `ReadarrAuthor` carries no `added` timestamp
/// and there is no per-author detail route to open, so including it would mean
/// either inventing an order or shipping a tile that goes nowhere. Both are worse
/// than its absence; adding the field and the route is its own change.
final servicesRecentlyAddedProvider = FutureProvider<List<RecentlyAddedItem>>((
  ref,
) async {
  final settings = ref.watch(currentSettingsProvider);

  Future<List<RecentlyAddedItem>> from(
    ServiceKey service,
    Future<List<RecentlyAddedItem>> Function() load,
  ) async {
    if (!settings.isServiceConfigured(service)) return const [];
    try {
      return await load();
    } catch (_) {
      return const [];
    }
  }

  final results = await Future.wait([
    from(ServiceKey.radarr, () async {
      final movies = await ref.watch(moviesProvider.future);
      return movies
          .map(
            (movie) => RecentlyAddedItem(
              service: ServiceKey.radarr,
              id: movie.id,
              title: movie.title,
              // `year` is an int defaulting to 0, so an item with no year
              // printed "0" and announced "Zero".
              subtitle: movie.year == 0 ? '' : movie.year.toString(),
              posterUrl: ImageUtils.extractPosterUrl(
                movie.images,
                baseUrl: settings.radarrUrl,
                apiKey: settings.radarrApiKey,
              ).url,
              addedAt: parseAddedTimestamp(movie.added),
            ),
          )
          .toList(growable: false);
    }),
    from(ServiceKey.sonarr, () async {
      final series = await ref.watch(seriesProvider.future);
      return series
          .map(
            (show) => RecentlyAddedItem(
              service: ServiceKey.sonarr,
              id: show.id,
              title: show.title,
              subtitle: show.year == 0 ? '' : show.year.toString(),
              posterUrl: ImageUtils.extractPosterUrl(
                show.images,
                baseUrl: settings.sonarrUrl,
                apiKey: settings.sonarrApiKey,
              ).url,
              addedAt: parseAddedTimestamp(show.added),
            ),
          )
          .toList(growable: false);
    }),
    from(ServiceKey.lidarr, () async {
      final artists = await ref.watch(musicProvider.future);
      return artists
          .map(
            (artist) => RecentlyAddedItem(
              service: ServiceKey.lidarr,
              id: artist.id,
              title: artist.artistName,
              // An artist has no year, so the qualifier is its scale.
              subtitle: artist.albumCount == 1
                  ? '1 album'
                  : '${artist.albumCount} albums',
              posterUrl: ImageUtils.extractPosterUrl(
                artist.images,
                baseUrl: settings.lidarrUrl,
                apiKey: settings.lidarrApiKey,
              ).url,
              addedAt: parseAddedTimestamp(artist.added),
            ),
          )
          .toList(growable: false);
    }),
  ]);

  return sortRecentlyAdded(
    results.expand((items) => items).toList(),
    limit: servicesRecentlyAddedLimit,
  );
});

/// How many in-flight items the hub shows before deferring to `/activity`.
///
/// Raised from three when the provider stopped being Radarr-plus-Sonarr: with
/// seven possible sources, three slots meant a busy usenet queue could hide every
/// torrent on the screen.
const int servicesQueuePreviewLimit = 5;

/// Everything currently transferring, across every configured source.
///
/// This is the region the old dashboard put *last*, below three browse rails,
/// while sourcing it from Radarr and Sonarr only — so the most time-sensitive
/// thing on a control-room screen was both buried and mostly blind. It now covers
/// the two arr services it always did, plus Lidarr and Readarr, plus the three
/// download clients that actually move the bytes.
///
/// Every source is gated on being configured and degrades to `[]` on failure, so
/// one unreachable client cannot empty or block the region.
final servicesQueueProvider = FutureProvider<List<ServiceQueueItem>>((
  ref,
) async {
  final settings = ref.watch(currentSettingsProvider);

  Future<List<ServiceQueueItem>> from(
    ServiceKey service,
    Future<List<ServiceQueueItem>> Function() load,
  ) async {
    if (!settings.isServiceConfigured(service)) return const [];
    try {
      return await load();
    } catch (_) {
      return const [];
    }
  }

  final results = await Future.wait([
    from(
      ServiceKey.radarr,
      () => _loadServiceQueueItems(ref, ServiceKey.radarr),
    ),
    from(
      ServiceKey.sonarr,
      () => _loadServiceQueueItems(ref, ServiceKey.sonarr),
    ),
    from(
      ServiceKey.lidarr,
      () => _loadServiceQueueItems(ref, ServiceKey.lidarr),
    ),
    from(
      ServiceKey.readarr,
      () => _loadServiceQueueItems(ref, ServiceKey.readarr),
    ),
    from(ServiceKey.qbittorrent, () => _loadQbittorrentQueueItems(ref)),
    from(ServiceKey.sabnzbd, () => _loadSabnzbdQueueItems(ref)),
    from(ServiceKey.nzbget, () => _loadNzbgetQueueItems(ref)),
  ]);

  final items = results.expand((items) => items).toList();

  // Closest to landing first. An item whose client reports no progress sorts
  // last rather than as zero: unknown is not the same as "just started", and
  // pushing it to the top would bury the transfer that is about to finish.
  //
  // Decorated with the source index because `List.sort` is not guaranteed
  // stable. Without it, several progress-less items — normal for a usenet queue
  // that has not started — could come back in a different order on each build,
  // which reads on screen as rows shuffling for no reason.
  final ordered =
      List.generate(
        items.length,
        (index) => (index: index, item: items[index]),
        growable: false,
      )..sort((a, b) {
        final progressA = a.item.progress;
        final progressB = b.item.progress;
        if (progressA != progressB) {
          if (progressA == null) return 1;
          if (progressB == null) return -1;
          final byProgress = progressB.compareTo(progressA);
          if (byProgress != 0) return byProgress;
        }
        return a.index.compareTo(b.index);
      });

  return ordered
      .take(servicesQueuePreviewLimit)
      .map((entry) => entry.item)
      .toList(growable: false);
});

/// Active torrents, as in-flight items.
///
/// Filters to transfers that are genuinely moving or waiting to: a seeding
/// library of four hundred torrents is not "in flight", and unfiltered it would
/// crowd out every other source.
Future<List<ServiceQueueItem>> _loadQbittorrentQueueItems(Ref ref) async {
  final torrents = await ref.watch(allTorrentsProvider.future);
  return torrents
      .where(
        (torrent) => switch (torrent.parsedState) {
          // `stalled` is only ever `stalledDL` — a stalled *upload* parses as
          // seeding — so it belongs here rather than being filtered out with the
          // rest of the seeding library.
          TorrentState.downloading ||
          TorrentState.metaDownloading ||
          TorrentState.stalled ||
          TorrentState.queuedDl => true,
          TorrentState.seeding ||
          TorrentState.checking ||
          TorrentState.paused ||
          TorrentState.queuedUp ||
          TorrentState.error ||
          TorrentState.unknown => false,
        },
      )
      .map(
        (torrent) => ServiceQueueItem(
          service: ServiceKey.qbittorrent,
          title: torrent.name,
          subtitle: joinDisplayParts([
            _queueTypeLabel(ServiceKey.qbittorrent),
            torrent.category.isEmpty ? null : torrent.category,
            formatSpeed(torrent.dlSpeed),
          ]),
          progress: torrent.progress.clamp(0, 1).toDouble(),
          // A stalled transfer is the one qBittorrent state worth surfacing on a
          // hub: it looks identical to a slow download until you notice it has
          // not moved.
          warning: torrent.parsedState == TorrentState.stalled
              ? 'Stalled'
              : null,
        ),
      )
      .toList(growable: false);
}

Future<List<ServiceQueueItem>> _loadSabnzbdQueueItems(Ref ref) async {
  final queue = await ref.watch(sabnzbdQueueProvider.future);
  return queue.slots
      .map(
        (slot) => ServiceQueueItem(
          service: ServiceKey.sabnzbd,
          title: slot.filename,
          subtitle: joinDisplayParts([
            _queueTypeLabel(ServiceKey.sabnzbd),
            slot.category.isEmpty ? null : slot.category,
            slot.sizeLeftLabel,
          ]),
          progress: slot.progress,
          warning: queue.paused ? 'Paused' : null,
        ),
      )
      .toList(growable: false);
}

Future<List<ServiceQueueItem>> _loadNzbgetQueueItems(Ref ref) async {
  final groups = await ref.watch(nzbgetQueueProvider.future);
  return groups
      .map(
        (group) => ServiceQueueItem(
          service: ServiceKey.nzbget,
          title: group.name,
          subtitle: joinDisplayParts([
            _queueTypeLabel(ServiceKey.nzbget),
            group.category.isEmpty ? null : group.category,
            group.remainingLabel,
          ]),
          progress: group.progress,
          warning: null,
        ),
      )
      .toList(growable: false);
}

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
      ServiceKey.lidarr => await ref.watch(lidarrServiceProvider).getQueue(),
      ServiceKey.readarr => await ref.watch(readarrServiceProvider).getQueue(),
      // The download clients are not `/queue` shaped and have their own loaders;
      // the rest have no queue at all.
      ServiceKey.seerr ||
      ServiceKey.qbittorrent ||
      ServiceKey.bazarr ||
      ServiceKey.truenas ||
      ServiceKey.dockge ||
      ServiceKey.prowlarr ||
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
    ServiceKey.readarr => 'Book',
    // The download clients name themselves: the row's whole point is that the
    // bytes are coming through this client rather than through an arr, and the
    // media type is already in the release name.
    ServiceKey.seerr ||
    ServiceKey.qbittorrent ||
    ServiceKey.bazarr ||
    ServiceKey.truenas ||
    ServiceKey.dockge ||
    ServiceKey.prowlarr ||
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
