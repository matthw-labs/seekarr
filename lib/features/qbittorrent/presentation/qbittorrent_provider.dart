import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

import 'package:seekarr/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:seekarr/features/qbittorrent/data/qbittorrent_service.dart';
import 'package:seekarr/features/qbittorrent/domain/models/torrent.dart';
import 'package:seekarr/features/qbittorrent/domain/models/torrent_file.dart';
import 'package:seekarr/features/qbittorrent/domain/models/torrent_properties.dart';
import 'package:seekarr/features/qbittorrent/domain/models/torrent_tracker.dart';
import 'package:seekarr/features/qbittorrent/domain/models/transfer_info.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';

final qbittorrentServiceProvider = Provider<QbittorrentService>((ref) {
  final settings = ref.watch(currentSettingsProvider);
  if (settings.qbittorrentUrl.isEmpty) {
    throw Exception('qBittorrent not configured');
  }
  final client = QbittorrentClient(
    url: settings.qbittorrentUrl,
    username: settings.qbittorrentUsername.isNotEmpty
        ? settings.qbittorrentUsername
        : null,
    password: settings.qbittorrentPassword.isNotEmpty
        ? settings.qbittorrentPassword
        : null,
    certFingerprint: settings.pinForUrl(settings.qbittorrentUrl),
  );
  return QbittorrentService(client);
});

enum TorrentFilter { all, downloading, seeding, completed, paused, queued }

enum TorrentSort {
  name,
  size,
  progress,
  dlSpeed,
  upSpeed,
  eta,
  addedOn,
  state;

  String get apiValue {
    switch (this) {
      case TorrentSort.name:
        return 'name';
      case TorrentSort.size:
        return 'size';
      case TorrentSort.progress:
        return 'progress';
      case TorrentSort.dlSpeed:
        return 'dlspeed';
      case TorrentSort.upSpeed:
        return 'upspeed';
      case TorrentSort.eta:
        return 'eta';
      case TorrentSort.addedOn:
        return 'added_on';
      case TorrentSort.state:
        return 'state';
    }
  }

  String get label {
    switch (this) {
      case TorrentSort.name:
        return 'Name';
      case TorrentSort.size:
        return 'Size';
      case TorrentSort.progress:
        return 'Progress';
      case TorrentSort.dlSpeed:
        return '↓ Speed';
      case TorrentSort.upSpeed:
        return '↑ Speed';
      case TorrentSort.eta:
        return 'ETA';
      case TorrentSort.addedOn:
        return 'Added';
      case TorrentSort.state:
        return 'State';
    }
  }
}

final torrentFilterProvider = StateProvider<TorrentFilter>(
  (ref) => TorrentFilter.all,
);

final torrentSortProvider = StateProvider<TorrentSort>(
  (ref) => TorrentSort.addedOn,
);

final torrentSortReverseProvider = StateProvider<bool>((ref) => true);

final torrentCategoryFilterProvider = StateProvider<String?>((ref) => null);

final torrentTagFilterProvider = StateProvider<String?>((ref) => null);

final torrentTrackerFilterProvider = StateProvider<String?>((ref) => null);

final torrentSearchQueryProvider = StateProvider<String>((ref) => '');

final allTorrentsProvider = FutureProvider<List<Torrent>>((ref) async {
  final service = ref.watch(qbittorrentServiceProvider);
  final sort = ref.watch(torrentSortProvider);
  final reverse = ref.watch(torrentSortReverseProvider);
  return service.getTorrents(sort: sort.apiValue, reverse: reverse);
});

final availableCategoriesProvider = Provider<List<String>>((ref) {
  final torrents = ref.watch(allTorrentsProvider).asData?.value;
  if (torrents == null) return [];
  return torrents
      .where((t) => t.category.isNotEmpty)
      .map((t) => t.category)
      .toSet()
      .toList()
    ..sort();
});

final availableTagsProvider = Provider<List<String>>((ref) {
  final torrents = ref.watch(allTorrentsProvider).asData?.value;
  if (torrents == null) return [];
  final tags = <String>{};
  for (final t in torrents) {
    tags.addAll(t.tags);
  }
  return tags.toList()..sort();
});

final availableTrackersProvider = Provider<List<String>>((ref) {
  final torrents = ref.watch(allTorrentsProvider).asData?.value;
  if (torrents == null) return [];
  final trackers = <String>{};
  for (final t in torrents) {
    if (t.trackerDomain.isNotEmpty) trackers.add(t.trackerDomain);
  }
  return trackers.toList()..sort();
});

final torrentsProvider = FutureProvider<List<Torrent>>((ref) async {
  final service = ref.watch(qbittorrentServiceProvider);
  final filter = ref.watch(torrentFilterProvider);
  final sort = ref.watch(torrentSortProvider);
  final reverse = ref.watch(torrentSortReverseProvider);
  final categoryFilter = ref.watch(torrentCategoryFilterProvider);
  final tagFilter = ref.watch(torrentTagFilterProvider);
  final trackerFilter = ref.watch(torrentTrackerFilterProvider);
  final searchQuery = ref
      .watch(torrentSearchQueryProvider)
      .trim()
      .toLowerCase();

  final hasSubFilters =
      (categoryFilter != null && categoryFilter.isNotEmpty) ||
      (tagFilter != null && tagFilter.isNotEmpty) ||
      trackerFilter != null;

  // Fast path: when status filter is "All" and no sub-filters or search
  // query are active, reuse allTorrentsProvider so we don't double-fetch
  // /torrents/info.
  if (filter == TorrentFilter.all && !hasSubFilters && searchQuery.isEmpty) {
    return await ref.watch(allTorrentsProvider.future);
  }

  final apiFilter = switch (filter) {
    TorrentFilter.downloading => 'downloading',
    TorrentFilter.seeding => 'seeding',
    TorrentFilter.completed => 'completed',
    TorrentFilter.paused => 'stopped',
    _ => 'all',
  };

  var torrents = await service.getTorrents(
    filter: apiFilter,
    sort: sort.apiValue,
    reverse: reverse,
  );

  if (filter == TorrentFilter.queued) {
    torrents = torrents.where((t) => t.parsedState.isQueued).toList();
  }

  if (categoryFilter != null && categoryFilter.isNotEmpty) {
    torrents = torrents.where((t) => t.category == categoryFilter).toList();
  }

  if (tagFilter != null && tagFilter.isNotEmpty) {
    torrents = torrents.where((t) => t.tags.contains(tagFilter)).toList();
  }

  if (trackerFilter != null) {
    torrents = torrents.where((t) => t.trackerDomain == trackerFilter).toList();
  }

  if (searchQuery.isNotEmpty) {
    torrents = torrents
        .where(
          (t) =>
              t.name.toLowerCase().contains(searchQuery) ||
              t.category.toLowerCase().contains(searchQuery) ||
              t.tags.any((tag) => tag.toLowerCase().contains(searchQuery)),
        )
        .toList();
  }

  return torrents;
});

final qbittorrentTorrentsProvider =
    FutureProvider.family<List<Torrent>, String>((ref, hash) async {
      final service = ref.watch(qbittorrentServiceProvider);
      return service.getTorrents(hashes: hash);
    });

final torrentFilesProvider = FutureProvider.family<List<TorrentFile>, String>((
  ref,
  hash,
) async {
  final service = ref.watch(qbittorrentServiceProvider);
  return service.getTorrentFiles(hash);
});

final torrentTrackersProvider =
    FutureProvider.family<List<TorrentTracker>, String>((ref, hash) async {
      final service = ref.watch(qbittorrentServiceProvider);
      return service.getTorrentTrackers(hash);
    });

final torrentPropertiesProvider =
    FutureProvider.family<TorrentProperties, String>((ref, hash) async {
      final service = ref.watch(qbittorrentServiceProvider);
      return service.getTorrentProperties(hash);
    });

final transferInfoProvider = FutureProvider<TransferInfo>((ref) async {
  final service = ref.watch(qbittorrentServiceProvider);
  return service.getTransferInfo();
});

final selectedTorrentHashesProvider = StateProvider.autoDispose<Set<String>>(
  (ref) => {},
);

final torrentPollingEnabledProvider = StateProvider<bool>((ref) => true);

final torrentPollingProvider = Provider.autoDispose<void>((ref) {
  final enabled = ref.watch(torrentPollingEnabledProvider);
  if (!enabled) return;
  final timer = Timer.periodic(const Duration(seconds: 3), (_) {
    ref.invalidate(allTorrentsProvider);
    ref.invalidate(torrentsProvider);
    ref.invalidate(transferInfoProvider);
  });
  ref.onDispose(() => timer.cancel());
});

final torrentDetailPollingProvider = Provider.autoDispose.family<void, String>((
  ref,
  hash,
) {
  // The underlying QbittorrentScreen keeps running torrentPollingProvider
  // (which already invalidates allTorrentsProvider / torrentsProvider /
  // transferInfoProvider). Here we only refresh the detail-scoped
  // providers so we don't double-fetch /torrents/info on every tick.
  final timer = Timer.periodic(const Duration(seconds: 3), (_) {
    ref.invalidate(qbittorrentTorrentsProvider(hash));
    ref.invalidate(torrentFilesProvider(hash));
    ref.invalidate(torrentTrackersProvider(hash));
    ref.invalidate(torrentPropertiesProvider(hash));
  });
  ref.onDispose(() => timer.cancel());
});
