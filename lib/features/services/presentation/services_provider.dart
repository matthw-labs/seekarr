import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/api/api_client.dart';
import 'package:seekarr/core/utils/arr_activity_display.dart';
import 'package:seekarr/core/utils/dynamic_map_utils.dart';
import 'package:seekarr/features/bazarr/presentation/bazarr_provider.dart';
import 'package:seekarr/features/discover/data/seerr_service.dart';
import 'package:seekarr/features/discover/presentation/discover_provider.dart';
import 'package:seekarr/features/movies/data/radarr_service.dart';
import 'package:seekarr/features/movies/presentation/movies_provider.dart';
import 'package:seekarr/features/music/data/lidarr_service.dart';
import 'package:seekarr/features/music/presentation/music_provider.dart';
import 'package:seekarr/features/series/data/sonarr_service.dart';
import 'package:seekarr/features/series/presentation/series_provider.dart';
import 'package:seekarr/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:seekarr/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:seekarr/features/services/domain/service_summary.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';

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

final radarrQueuedMovieIdsProvider = FutureProvider<Set<int>>((ref) async {
  return _loadQueuedIds(
    () => ref.watch(radarrServiceProvider).getQueue(),
    (item) => intOrNull(mapOrNull(item['movie'])?['id'] ?? item['movieId']),
  );
});

final sonarrQueuedSeriesIdsProvider = FutureProvider<Set<int>>((ref) async {
  return _loadQueuedIds(
    () => ref.watch(sonarrServiceProvider).getQueue(),
    (item) => intOrNull(mapOrNull(item['series'])?['id'] ?? item['seriesId']),
  );
});

final lidarrQueuedArtistIdsProvider = FutureProvider<Set<int>>((ref) async {
  final service = ref.watch(lidarrServiceProvider);

  try {
    final queueItems = (await service.getQueue())
        .whereType<Map>()
        .map(stringKeyMap)
        .toList(growable: false);
    final artistIds = <int>{};
    final unresolvedAlbumIds = <int>{};

    for (final item in queueItems) {
      final artistId = intOrNull(
        mapOrNull(item['artist'])?['id'] ??
            mapOrNull(item['album'])?['artistId'] ??
            item['artistId'],
      );
      if (artistId != null && artistId > 0) {
        artistIds.add(artistId);
      }

      final albumId = intOrNull(
        mapOrNull(item['album'])?['id'] ?? item['albumId'],
      );
      if (albumId != null && albumId > 0) {
        unresolvedAlbumIds.add(albumId);
      }
    }

    if (unresolvedAlbumIds.isEmpty) {
      return artistIds;
    }

    final artists = await service.getArtists();
    for (final artist in artists) {
      if (unresolvedAlbumIds.isEmpty) {
        break;
      }
      if (artist.albumCount <= 0) {
        continue;
      }

      try {
        final albums = await service.getAlbums(artist.id);
        final matchedAlbumIds = albums
            .where((album) => unresolvedAlbumIds.contains(album.id))
            .map((album) => album.id)
            .toSet();
        if (matchedAlbumIds.isEmpty) {
          continue;
        }

        artistIds.add(artist.id);
        unresolvedAlbumIds.removeAll(matchedAlbumIds);
      } catch (_) {
        continue;
      }
    }

    return artistIds;
  } catch (_) {
    return const <int>{};
  }
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

Future<Set<int>> _loadQueuedIds(
  Future<List<dynamic>> Function() loadItems,
  int? Function(Map<String, dynamic> item) idExtractor,
) async {
  try {
    return (await loadItems())
        .whereType<Map>()
        .map(stringKeyMap)
        .map(idExtractor)
        .whereType<int>()
        .where((id) => id > 0)
        .toSet();
  } catch (_) {
    return const <int>{};
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
      ServiceKey.bazarr => const <dynamic>[],
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
    ServiceKey.bazarr => service.title,
  };
}

String? _queueQualityLabel(dynamic value) {
  if (value is Map) {
    final quality = mapOrNull(value['quality']);
    return stringOrNull(quality?['name']) ?? stringOrNull(value['name']);
  }

  return stringOrNull(value);
}
