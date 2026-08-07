import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/movies/presentation/movies_provider.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/nzbget/domain/models/nzbget_models.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_provider.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/music/presentation/music_provider.dart';
import 'package:cupola/features/qbittorrent/domain/models/parse_utils.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/series/presentation/series_provider.dart';
import 'package:cupola/features/services/domain/service_signal.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_provider.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';
import 'package:cupola/features/unraid/domain/models/unraid_models.dart';
import 'package:cupola/features/unraid/presentation/unraid_provider.dart';

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
        case ServiceKey.transmission:
          return _transmissionKpis(ref);
        case ServiceKey.nginxProxyManager:
          return _npmKpis(ref);
        case ServiceKey.jellyfin:
          return _streamKpis(
            ref.watch(jellyfinSessionsProvider.future),
            ref.watch(jellyfinLibrariesProvider.future),
          );
        case ServiceKey.plex:
          return _streamKpis(
            ref.watch(plexSessionsProvider.future),
            ref.watch(plexLibrariesProvider.future),
          );
      }
    });

/// The single live figure a service contributes to the stack matrix on
/// `/services`.
///
/// Reads [serviceKpiProvider] and reduces it through [resolveServiceSignal], so
/// the matrix costs nothing beyond what the KPI rails already fetch and the
/// hub's cell agrees with the service page's peek by construction.
///
/// Note the deliberate lack of error handling: an unreachable service leaves
/// this in `AsyncError`, and the cell renders its reachability instead of a
/// signal. Swallowing the error into a null signal here would make "no metric to
/// report" and "this service is down" the same value.
final serviceSignalProvider = FutureProvider.autoDispose
    .family<ServiceSignal?, ServiceKey>((ref, service) async {
      final kpis = await ref.watch(serviceKpiProvider(service).future);
      return resolveServiceSignal(kpis);
    });

int _statInt(Map<String, dynamic>? stats, String key) =>
    (stats?[key] as num?)?.toInt() ?? 0;

Color? _warnIf(bool condition) => condition ? AppColors.warning : null;

/// Flags a metric as *activity* rather than as a problem.
///
/// The tone a flagged KPI resolves to is decided by `resolveServiceSignal` from
/// the KPI's **label**, not from this colour — `_activityLabels` is what makes
/// `Streams` read as `StatusTone.info`. This exists so the peek's own icon agrees
/// with the matrix cell instead of painting an amber glyph beside a blue phrase.
Color? _infoIf(bool condition) => condition ? AppColors.info : null;

/// The shared KPI set for a media server, identical for Jellyfin and Plex.
///
/// Three metrics, and the order is load-bearing in two ways that
/// `resolveServiceSignal` depends on.
///
/// **`Streams` is first, so it is the resting fallback.** With nothing flagged
/// the matrix cell shows `kpis.first`, and `0 streams` is both true and live —
/// unlike a library total, which DESIGN.md rightly calls the least live thing you
/// could put on a control-room screen.
///
/// **`Streams` is only flagged while nothing is transcoding.** The cell shows the
/// *first* flagged KPI, so gating it this way lets the more urgent fact win
/// without teaching the resolver about precedence: idle reads `0 streams` in
/// neutral, a healthy stream reads `2 streaming` in info blue, and the moment the
/// box starts re-encoding it reads `1 transcode` in warning amber. One rule, three
/// correct readings, no special-casing in the shared resolver.
///
/// **There is no aggregate bitrate metric, deliberately.** Neither server reports
/// measured outbound throughput: Jellyfin only carries a bitrate while
/// transcoding, and Plex's `Session.bandwidth` is a reservation. Summing those
/// would add two different units together and present the result as the box's
/// egress — a fabricated number. Per-session bitrate is shown on the board, where
/// `StreamSession.bitrateIsNominal` can say what it actually is.
Future<List<ServiceKpi>> _streamKpis(
  Future<List<StreamSession>> sessionsFuture,
  Future<List<StreamLibrary>> librariesFuture,
) async {
  final sessions = await sessionsFuture;
  final libraries = await librariesFuture;
  final transcodes = sessions.where((s) => s.playMethod.isTranscode).length;

  return [
    ServiceKpi(
      label: 'Streams',
      value: '${sessions.length}',
      icon: Icons.play_circle_outline_rounded,
      accent: _infoIf(sessions.isNotEmpty && transcodes == 0),
    ),
    ServiceKpi(
      label: 'Transcodes',
      value: '$transcodes',
      icon: Icons.memory_rounded,
      accent: _warnIf(transcodes > 0),
    ),
    ServiceKpi(
      label: 'Libraries',
      value: '${libraries.length}',
      icon: Icons.video_library_outlined,
    ),
  ];
}

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
    // Pending counts the requests that still need a decision, so it reads the
    // request's OWN status — the same source `request_ordering.dart`,
    // `seerr_request_filter.dart` and the /activity tiles read, and for the same
    // documented reason. `displayStatus` answers a different question: it lets
    // the media's availability override the request, so a request still in
    // pendingApproval whose media Radarr already holds reports "Available" —
    // which is how this KPI came to show "Pending 0" while /activity was
    // offering an Approve button for that very record.
    if (r.status == RequestStatus.pendingApproval) pending++;

    // The other two stay on displayStatus, which is the right source for them:
    // they describe where the media is, not what the request needs.
    switch (r.displayStatus.kind) {
      case SeerrRequestDisplayKind.approved:
      case SeerrRequestDisplayKind.processing:
        processing++;
      case SeerrRequestDisplayKind.available:
      case SeerrRequestDisplayKind.partiallyAvailable:
      case SeerrRequestDisplayKind.completed:
        available++;
      case SeerrRequestDisplayKind.pending:
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
  final kpis = [
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
  // Lifetime total is a nice-to-have; a stats failure must not drop the whole
  // KPI row, so it is fetched defensively and simply omitted on error.
  try {
    final stats = await ref.watch(sabnzbdServerStatsProvider.future);
    kpis.add(
      ServiceKpi(
        label: 'Total',
        value: stats.totalLabel,
        icon: Icons.download_done_rounded,
      ),
    );
  } catch (_) {
    // Ignore — the four queue KPIs above are enough.
  }
  return kpis;
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

/// Transmission's rail, shaped like qBittorrent's so the two torrent clients
/// read the same way in the matrix — `Down` first, flagged while bytes are
/// actually moving, so the resting cell says "0 B/s" rather than a library
/// total.
Future<List<ServiceKpi>> _transmissionKpis(Ref ref) async {
  final results = await Future.wait([
    ref.watch(transmissionStatsProvider.future),
    ref.watch(transmissionTorrentsProvider.future),
  ]);
  final stats = results[0] as TransmissionStats;
  final torrents = results[1] as List<TransmissionTorrent>;
  final downloading = torrents.where((t) => t.status.isIncoming).length;
  final stalled = torrents.where((t) => t.warning != null).length;

  return [
    ServiceKpi(
      label: 'Down',
      value: stats.downloadSpeedLabel,
      icon: Icons.south_rounded,
      accent: _warnIf(stats.downloadSpeed > 0),
    ),
    ServiceKpi(
      label: 'Up',
      value: stats.uploadSpeedLabel,
      icon: Icons.north_rounded,
    ),
    ServiceKpi(
      label: 'Active',
      value: '${stats.activeTorrentCount}',
      icon: Icons.bolt_rounded,
    ),
    ServiceKpi(
      label: 'Downloading',
      value: '$downloading',
      icon: Icons.download_rounded,
    ),
    ServiceKpi(
      label: 'Stalled',
      value: '$stalled',
      icon: Icons.report_gmailerrorred_rounded,
      accent: _warnIf(stalled > 0),
    ),
  ];
}

/// Nginx Proxy Manager's rail.
///
/// `Offline` is the metric that earns its place: a reverse proxy is either
/// serving every hostname it claims or it is not, and a host that is switched on
/// while nginx has refused its configuration is invisible from every other
/// screen in the app — the site simply stops answering. Expiring certificates
/// are the second, for the same reason a day later.
Future<List<ServiceKpi>> _npmKpis(Ref ref) async {
  final results = await Future.wait([
    ref.watch(npmProxyHostsProvider.future),
    ref.watch(npmCertificatesProvider.future),
  ]);
  final hosts = results[0] as List<NpmProxyHost>;
  final certificates = results[1] as List<NpmCertificate>;
  final now = DateTime.now();
  final broken = hosts.where((h) => h.hasConfigError).length;
  final disabled = hosts.where((h) => !h.enabled).length;
  final expiring = certificates.where((c) => c.isExpiringSoon(now)).length;

  return [
    ServiceKpi(
      label: 'Offline',
      value: '$broken',
      icon: Icons.error_outline_rounded,
      accent: _warnIf(broken > 0),
    ),
    ServiceKpi(
      label: 'Hosts',
      value: '${hosts.length}',
      icon: Icons.alt_route_rounded,
    ),
    ServiceKpi(
      label: 'Expiring',
      value: '$expiring',
      icon: Icons.lock_clock_rounded,
      accent: _warnIf(expiring > 0),
    ),
    ServiceKpi(
      label: 'Certificates',
      value: '${certificates.length}',
      icon: Icons.lock_outline_rounded,
    ),
    ServiceKpi(
      label: 'Disabled',
      value: '$disabled',
      icon: Icons.pause_circle_rounded,
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
