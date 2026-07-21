import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/models/service_kpi.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/features/bazarr/presentation/bazarr_provider.dart';
import 'package:seekarr/features/dockge/domain/models/dockge_stack.dart';
import 'package:seekarr/features/dockge/presentation/dockge_provider.dart';
import 'package:seekarr/features/discover/domain/models/seerr_request.dart';
import 'package:seekarr/features/discover/presentation/discover_provider.dart';
import 'package:seekarr/features/movies/presentation/movies_provider.dart';
import 'package:seekarr/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:seekarr/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:seekarr/features/nzbget/domain/models/nzbget_models.dart';
import 'package:seekarr/features/nzbget/presentation/nzbget_provider.dart';
import 'package:seekarr/features/readarr/presentation/readarr_provider.dart';
import 'package:seekarr/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:seekarr/features/music/presentation/music_provider.dart';
import 'package:seekarr/features/qbittorrent/domain/models/parse_utils.dart';
import 'package:seekarr/features/qbittorrent/domain/models/torrent.dart';
import 'package:seekarr/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:seekarr/features/series/presentation/series_provider.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/truenas/presentation/truenas_provider.dart';
import 'package:seekarr/features/unraid/domain/models/unraid_models.dart';
import 'package:seekarr/features/unraid/presentation/unraid_provider.dart';

/// KPIs shown in the [ServiceKpiPeek] at the top of each service page.
///
/// Derives metrics from the library providers the pages already load, so it
/// adds no extra network calls and stays live-consistent with the list views.
final serviceKpiProvider = FutureProvider.autoDispose
    .family<List<ServiceKpi>, ServiceKey>((ref, service) async {
      switch (service) {
        case ServiceKey.radarr:
          return _radarrKpis(ref);
        case ServiceKey.sonarr:
          return _sonarrKpis(ref);
        case ServiceKey.lidarr:
          return _lidarrKpis(ref);
        case ServiceKey.qbittorrent:
          return _qbittorrentKpis(ref);
        case ServiceKey.seerr:
          return _seerrKpis(ref);
        case ServiceKey.bazarr:
          return _bazarrKpis(ref);
        case ServiceKey.truenas:
          return _truenasKpis(ref);
        case ServiceKey.dockge:
          return _dockgeKpis(ref);
        case ServiceKey.prowlarr:
          return _prowlarrKpis(ref);
        case ServiceKey.readarr:
          return _readarrKpis(ref);
        case ServiceKey.sabnzbd:
          return _sabnzbdKpis(ref);
        case ServiceKey.nzbget:
          return _nzbgetKpis(ref);
        case ServiceKey.unraid:
          return _unraidKpis(ref);
      }
    });

int _statInt(Map<String, dynamic>? stats, String key) =>
    (stats?[key] as num?)?.toInt() ?? 0;

Color? _warnIf(bool condition) => condition ? AppColors.warning : null;

Future<List<ServiceKpi>> _radarrKpis(Ref ref) async {
  final movies = await ref.watch(moviesProvider.future);
  final queued = await ref.watch(radarrQueuedMovieIdsProvider.future);
  final monitored = movies.where((m) => m.monitored).length;
  final missing = movies.where((m) => m.monitored && !m.hasFile).length;
  return [
    ServiceKpi(
      label: 'Movies',
      value: '${movies.length}',
      icon: Icons.movie_rounded,
    ),
    ServiceKpi(
      label: 'Monitored',
      value: '$monitored',
      icon: Icons.visibility_rounded,
    ),
    ServiceKpi(
      label: 'Missing',
      value: '$missing',
      icon: Icons.report_gmailerrorred_rounded,
      accent: _warnIf(missing > 0),
    ),
    ServiceKpi(
      label: 'Queue',
      value: '${queued.length}',
      icon: Icons.download_rounded,
    ),
  ];
}

Future<List<ServiceKpi>> _sonarrKpis(Ref ref) async {
  final series = await ref.watch(seriesProvider.future);
  var epHave = 0;
  var epTotal = 0;
  var monitored = 0;
  for (final s in series) {
    if (s.monitored) monitored++;
    epHave += _statInt(s.statistics, 'episodeFileCount');
    epTotal += _statInt(s.statistics, 'episodeCount');
  }
  final missing = (epTotal - epHave).clamp(0, epTotal);
  return [
    ServiceKpi(
      label: 'Series',
      value: '${series.length}',
      icon: Icons.tv_rounded,
    ),
    ServiceKpi(
      label: 'Episodes',
      value: '$epHave/$epTotal',
      icon: Icons.playlist_play_rounded,
    ),
    ServiceKpi(
      label: 'Missing',
      value: '$missing',
      icon: Icons.report_gmailerrorred_rounded,
      accent: _warnIf(missing > 0),
    ),
    ServiceKpi(
      label: 'Monitored',
      value: '$monitored',
      icon: Icons.visibility_rounded,
    ),
  ];
}

Future<List<ServiceKpi>> _lidarrKpis(Ref ref) async {
  final artists = await ref.watch(musicProvider.future);
  var albums = 0;
  var trackHave = 0;
  var trackTotal = 0;
  for (final a in artists) {
    albums += a.albumCount;
    trackHave += a.trackFileCount;
    trackTotal += a.trackCount;
  }
  final missing = (trackTotal - trackHave).clamp(0, trackTotal);
  return [
    ServiceKpi(
      label: 'Artists',
      value: '${artists.length}',
      icon: Icons.person_rounded,
    ),
    ServiceKpi(label: 'Albums', value: '$albums', icon: Icons.album_rounded),
    ServiceKpi(
      label: 'Tracks',
      value: '$trackHave/$trackTotal',
      icon: Icons.music_note_rounded,
    ),
    ServiceKpi(
      label: 'Missing',
      value: '$missing',
      icon: Icons.report_gmailerrorred_rounded,
      accent: _warnIf(missing > 0),
    ),
  ];
}

Future<List<ServiceKpi>> _qbittorrentKpis(Ref ref) async {
  final torrents = await ref.watch(allTorrentsProvider.future);
  var active = 0;
  var downloading = 0;
  var seeding = 0;
  var dl = 0;
  var up = 0;
  for (final t in torrents) {
    final state = TorrentState.fromString(t.state);
    if (state.isActive) active++;
    if (state == TorrentState.downloading ||
        state == TorrentState.metaDownloading) {
      downloading++;
    }
    if (state == TorrentState.seeding) seeding++;
    dl += t.dlSpeed;
    up += t.upSpeed;
  }
  return [
    ServiceKpi(label: 'Active', value: '$active', icon: Icons.bolt_rounded),
    ServiceKpi(
      label: 'Down',
      value: formatSpeed(dl),
      icon: Icons.south_rounded,
      accent: _warnIf(dl > 0),
    ),
    ServiceKpi(label: 'Up', value: formatSpeed(up), icon: Icons.north_rounded),
    ServiceKpi(label: 'Seeding', value: '$seeding', icon: Icons.upload_rounded),
    ServiceKpi(
      label: 'Downloading',
      value: '$downloading',
      icon: Icons.download_rounded,
    ),
  ];
}

Future<List<ServiceKpi>> _seerrKpis(Ref ref) async {
  final requests = await ref.watch(requestsProvider.future);
  var pending = 0;
  var processing = 0;
  var available = 0;
  for (final r in requests) {
    switch (r.displayStatus.kind) {
      case SeerrRequestDisplayKind.pending:
        pending++;
      case SeerrRequestDisplayKind.approved:
      case SeerrRequestDisplayKind.processing:
        processing++;
      case SeerrRequestDisplayKind.available:
      case SeerrRequestDisplayKind.partiallyAvailable:
      case SeerrRequestDisplayKind.completed:
        available++;
      case SeerrRequestDisplayKind.declined:
      case SeerrRequestDisplayKind.failed:
      case SeerrRequestDisplayKind.deleted:
      case SeerrRequestDisplayKind.unknown:
        break;
    }
  }
  return [
    ServiceKpi(
      label: 'Requests',
      value: '${requests.length}',
      icon: Icons.inbox_rounded,
    ),
    ServiceKpi(
      label: 'Pending',
      value: '$pending',
      icon: Icons.hourglass_top_rounded,
      accent: _warnIf(pending > 0),
    ),
    ServiceKpi(
      label: 'Processing',
      value: '$processing',
      icon: Icons.sync_rounded,
    ),
    ServiceKpi(
      label: 'Available',
      value: '$available',
      icon: Icons.check_circle_rounded,
    ),
  ];
}

Future<List<ServiceKpi>> _truenasKpis(Ref ref) async {
  final dashboard = await ref.watch(truenasDashboardProvider.future);
  final pools = dashboard.pools;
  final maxUsed = pools
      .map((p) => p.usedFraction ?? 0)
      .fold<double>(0, (max, v) => v > max ? v : max);
  final activeAlerts = dashboard.activeAlerts.length;
  final running = dashboard.services.where((s) => s.running).length;
  return [
    ServiceKpi(
      label: 'Pools',
      value: '${pools.length}',
      icon: Icons.dns_rounded,
    ),
    ServiceKpi(
      label: 'Used',
      value: '${(maxUsed * 100).round()}%',
      icon: Icons.pie_chart_rounded,
      accent: _warnIf(maxUsed >= 0.8),
    ),
    ServiceKpi(
      label: 'Alerts',
      value: '$activeAlerts',
      icon: Icons.warning_amber_rounded,
      accent: _warnIf(activeAlerts > 0),
    ),
    ServiceKpi(label: 'Services', value: '$running', icon: Icons.bolt_rounded),
  ];
}

Future<List<ServiceKpi>> _dockgeKpis(Ref ref) async {
  final stacks = await ref.watch(dockgeStackListProvider.future);
  final running = stacks
      .where((s) => s.status == DockgeStackStatus.running)
      .length;
  final exited = stacks
      .where((s) => s.status == DockgeStackStatus.exited)
      .length;
  final inactive = stacks.length - running - exited;
  return [
    ServiceKpi(
      label: 'Stacks',
      value: '${stacks.length}',
      icon: Icons.layers_rounded,
    ),
    ServiceKpi(
      label: 'Running',
      value: '$running',
      icon: Icons.play_circle_rounded,
    ),
    ServiceKpi(
      label: 'Exited',
      value: '$exited',
      icon: Icons.stop_circle_rounded,
      accent: _warnIf(exited > 0),
    ),
    ServiceKpi(
      label: 'Inactive',
      value: '$inactive',
      icon: Icons.pause_circle_rounded,
    ),
  ];
}

Future<List<ServiceKpi>> _bazarrKpis(Ref ref) async {
  final b = await ref.watch(bazarrBadgesProvider.future);
  return [
    ServiceKpi(
      label: 'Wanted',
      value: '${b.totalWanted}',
      icon: Icons.subtitles_off_rounded,
      accent: _warnIf(b.totalWanted > 0),
    ),
    ServiceKpi(
      label: 'Episodes',
      value: '${b.episodes}',
      icon: Icons.tv_rounded,
    ),
    ServiceKpi(
      label: 'Movies',
      value: '${b.movies}',
      icon: Icons.movie_rounded,
    ),
    ServiceKpi(
      label: 'Providers',
      value: '${b.providers}',
      icon: Icons.cloud_rounded,
    ),
  ];
}

Future<List<ServiceKpi>> _prowlarrKpis(Ref ref) async {
  // The two fetches are independent; run them in parallel.
  final results = await Future.wait([
    ref.watch(prowlarrIndexersProvider.future),
    ref.watch(prowlarrIndexerStatsProvider.future),
  ]);
  final indexers = results[0] as List<ProwlarrIndexer>;
  final stats = results[1] as ProwlarrIndexerStats;
  final active = indexers.where((i) => i.enable).length;
  return [
    ServiceKpi(
      label: 'Indexers',
      value: '$active',
      icon: Icons.travel_explore_rounded,
    ),
    ServiceKpi(
      label: 'Queries',
      value: '${stats.totalQueries}',
      icon: Icons.search_rounded,
    ),
    ServiceKpi(
      label: 'Grabs',
      value: '${stats.totalGrabs}',
      icon: Icons.download_rounded,
    ),
    ServiceKpi(
      label: 'Fails',
      value: '${stats.totalFailures}',
      icon: Icons.error_outline_rounded,
      accent: _warnIf(stats.totalFailures > 0),
    ),
  ];
}

Future<List<ServiceKpi>> _readarrKpis(Ref ref) async {
  final authors = await ref.watch(readarrAuthorsProvider.future);
  var books = 0;
  var have = 0;
  for (final a in authors) {
    books += a.bookCount;
    have += a.bookFileCount;
  }
  final missing = (books - have).clamp(0, books);
  final queue = await ref.watch(readarrQueueProvider.future);
  return [
    ServiceKpi(
      label: 'Authors',
      value: '${authors.length}',
      icon: Icons.person_rounded,
    ),
    ServiceKpi(label: 'Books', value: '$books', icon: Icons.menu_book_rounded),
    ServiceKpi(
      label: 'Missing',
      value: '$missing',
      icon: Icons.report_gmailerrorred_rounded,
      accent: _warnIf(missing > 0),
    ),
    ServiceKpi(
      label: 'Queue',
      value: '${queue.length}',
      icon: Icons.download_rounded,
    ),
  ];
}

Future<List<ServiceKpi>> _sabnzbdKpis(Ref ref) async {
  final queue = await ref.watch(sabnzbdQueueProvider.future);
  return [
    ServiceKpi(
      label: 'Down',
      value: queue.speedLabel,
      icon: Icons.south_rounded,
      accent: _warnIf(queue.kbPerSec > 0),
    ),
    ServiceKpi(
      label: 'Queue',
      value: '${queue.slots.length}',
      icon: Icons.list_rounded,
    ),
    ServiceKpi(
      label: 'Remaining',
      value: queue.sizeLeftLabel,
      icon: Icons.hourglass_bottom_rounded,
    ),
    ServiceKpi(
      label: 'Status',
      value: queue.paused ? 'Paused' : 'Active',
      icon: queue.paused
          ? Icons.pause_circle_rounded
          : Icons.play_circle_rounded,
      accent: _warnIf(queue.paused),
    ),
  ];
}

Future<List<ServiceKpi>> _nzbgetKpis(Ref ref) async {
  final results = await Future.wait([
    ref.watch(nzbgetStatusProvider.future),
    ref.watch(nzbgetQueueProvider.future),
  ]);
  final status = results[0] as NzbgetStatus;
  final groups = results[1] as List<NzbgetGroup>;
  return [
    ServiceKpi(
      label: 'Down',
      value: status.rateLabel,
      icon: Icons.south_rounded,
      accent: _warnIf(status.downloadRateBytes > 0),
    ),
    ServiceKpi(
      label: 'Queue',
      value: '${groups.length}',
      icon: Icons.list_rounded,
    ),
    ServiceKpi(
      label: 'Remaining',
      value: status.remainingLabel,
      icon: Icons.hourglass_bottom_rounded,
    ),
    ServiceKpi(
      label: 'Status',
      value: status.paused ? 'Paused' : 'Active',
      icon: status.paused
          ? Icons.pause_circle_rounded
          : Icons.play_circle_rounded,
      accent: _warnIf(status.paused),
    ),
  ];
}

Future<List<ServiceKpi>> _unraidKpis(Ref ref) async {
  final results = await Future.wait([
    ref.watch(unraidArrayProvider.future),
    ref.watch(unraidDockerProvider.future),
  ]);
  final array = results[0] as UnraidArray;
  final containers = results[1] as List<UnraidDockerContainer>;
  final running = containers.where((c) => c.running).length;
  return [
    ServiceKpi(label: 'Array', value: array.state, icon: Icons.dns_rounded),
    ServiceKpi(
      label: 'Used',
      value: '${array.usedPercent}%',
      icon: Icons.pie_chart_rounded,
      accent: _warnIf(array.usedPercent >= 80),
    ),
    ServiceKpi(
      label: 'Containers',
      value: '$running/${containers.length}',
      icon: Icons.widgets_rounded,
    ),
    ServiceKpi(
      label: 'Disks',
      value: '${array.disks.length}',
      icon: Icons.storage_rounded,
    ),
  ];
}
