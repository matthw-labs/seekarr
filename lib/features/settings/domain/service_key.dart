import 'package:flutter/material.dart';

import 'package:seekarr/core/theme.dart';

enum ServiceKey {
  seerr,
  radarr,
  sonarr,
  lidarr,
  qbittorrent,
  bazarr,
  truenas,
  dockge,
  prowlarr,
  readarr,
  sabnzbd,
  nzbget,
  unraid,
  jellyfin,
  plex,
}

/// High-level grouping used to organise services across the app.
///
/// Seekarr started as a media companion but is growing into a homelab hub, so
/// services are grouped by the kind of job they do. This enum is the single
/// source of truth for that grouping — the Home dashboard, Settings and the
/// onboarding flow all read from it, so a new service only needs a [domain]
/// assignment in one place.
enum ServiceDomain {
  media(label: 'Media'),
  downloads(label: 'Downloads'),

  /// Media servers — the only services in the app that know about *people*.
  ///
  /// Every other domain answers questions about objects: is this film owned,
  /// grabbed, subtitled, on disk. A media server is the only source of
  /// subject-and-time state — who is watching, where they stopped, what is next
  /// for them, what nobody has played. That is why this is its own domain and
  /// not more Media, and it is the guard against re-rendering Radarr's library
  /// under a second name.
  ///
  /// Ordered between [downloads] and [infrastructure] deliberately: the bands
  /// then read as the pipeline they are — catalogue, acquire, watch, and the box
  /// it all runs on.
  stream(label: 'Stream'),
  infrastructure(label: 'Infrastructure');

  const ServiceDomain({required this.label});

  final String label;

  /// The configured services belonging to this domain, in declaration order.
  List<ServiceKey> get services =>
      ServiceKey.values.where((s) => s.domain == this).toList(growable: false);
}

extension ServiceKeyExtension on ServiceKey {
  /// Which [ServiceDomain] this service belongs to. See [ServiceDomain].
  ServiceDomain get domain {
    switch (this) {
      case ServiceKey.seerr:
      case ServiceKey.radarr:
      case ServiceKey.sonarr:
      case ServiceKey.lidarr:
      case ServiceKey.bazarr:
      case ServiceKey.readarr:
        return ServiceDomain.media;
      case ServiceKey.qbittorrent:
      case ServiceKey.prowlarr:
      case ServiceKey.sabnzbd:
      case ServiceKey.nzbget:
        return ServiceDomain.downloads;
      case ServiceKey.jellyfin:
      case ServiceKey.plex:
        return ServiceDomain.stream;
      case ServiceKey.truenas:
      case ServiceKey.dockge:
      case ServiceKey.unraid:
        return ServiceDomain.infrastructure;
    }
  }

  /// Whether tapping this service opens a full multi-screen console (with its
  /// own inner navigation) rather than a single detail screen. Heavy services
  /// like TrueNAS and Dockge are effectively sub-apps.
  bool get isFullConsole =>
      this == ServiceKey.truenas || this == ServiceKey.dockge;

  String get title {
    switch (this) {
      case ServiceKey.seerr:
        return 'Seerr';
      case ServiceKey.radarr:
        return 'Radarr';
      case ServiceKey.sonarr:
        return 'Sonarr';
      case ServiceKey.lidarr:
        return 'Lidarr';
      case ServiceKey.qbittorrent:
        return 'qBittorrent';
      case ServiceKey.bazarr:
        return 'Bazarr';
      case ServiceKey.truenas:
        return 'TrueNAS';
      case ServiceKey.dockge:
        return 'Dockge';
      case ServiceKey.prowlarr:
        return 'Prowlarr';
      case ServiceKey.readarr:
        return 'Readarr';
      case ServiceKey.sabnzbd:
        return 'SABnzbd';
      case ServiceKey.nzbget:
        return 'NZBGet';
      case ServiceKey.unraid:
        return 'Unraid';
      case ServiceKey.jellyfin:
        return 'Jellyfin';
      case ServiceKey.plex:
        return 'Plex';
    }
  }

  IconData get icon {
    switch (this) {
      case ServiceKey.seerr:
        return Icons.search_rounded;
      case ServiceKey.radarr:
        return Icons.movie_rounded;
      case ServiceKey.sonarr:
        return Icons.tv_rounded;
      case ServiceKey.lidarr:
        return Icons.music_note_rounded;
      case ServiceKey.qbittorrent:
        return Icons.download_rounded;
      case ServiceKey.bazarr:
        return Icons.subtitles_rounded;
      case ServiceKey.truenas:
        return Icons.storage_rounded;
      case ServiceKey.dockge:
        return Icons.layers_rounded;
      case ServiceKey.prowlarr:
        return Icons.travel_explore_rounded;
      case ServiceKey.readarr:
        return Icons.menu_book_rounded;
      case ServiceKey.sabnzbd:
        return Icons.cloud_download_rounded;
      case ServiceKey.nzbget:
        return Icons.cloud_sync_rounded;
      case ServiceKey.unraid:
        return Icons.developer_board_rounded;
      // The two media servers do the same job, so they are told apart by
      // *silhouette* rather than by detail: a circle against a rounded
      // rectangle survives the 18pt glyph on an expanded matrix cell and the
      // 32pt one on a folded card, where two screen-shaped glyphs would not.
      // Neither may be `live_tv_rounded` — that is a TV outline with signal
      // arcs and collides with Sonarr's `tv_rounded` at cell size.
      case ServiceKey.jellyfin:
        return Icons.play_circle_rounded;
      case ServiceKey.plex:
        return Icons.smart_display_rounded;
    }
  }

  Color get accent {
    switch (this) {
      case ServiceKey.seerr:
        return AppColors.seerr;
      case ServiceKey.radarr:
        return AppColors.radarr;
      case ServiceKey.sonarr:
        return AppColors.sonarr;
      case ServiceKey.lidarr:
        return AppColors.lidarr;
      case ServiceKey.qbittorrent:
        return AppColors.qbittorrent;
      case ServiceKey.bazarr:
        return AppColors.bazarr;
      case ServiceKey.truenas:
        return AppColors.truenas;
      case ServiceKey.dockge:
        return AppColors.dockge;
      case ServiceKey.prowlarr:
        return AppColors.prowlarr;
      case ServiceKey.readarr:
        return AppColors.readarr;
      case ServiceKey.sabnzbd:
        return AppColors.sabnzbd;
      case ServiceKey.nzbget:
        return AppColors.nzbget;
      case ServiceKey.unraid:
        return AppColors.unraid;
      case ServiceKey.jellyfin:
        return AppColors.jellyfin;
      case ServiceKey.plex:
        return AppColors.plex;
    }
  }

  bool get usesApiKey {
    return this != ServiceKey.qbittorrent &&
        this != ServiceKey.dockge &&
        this != ServiceKey.nzbget;
  }

  /// Whether the global search tab fans out to this service.
  ///
  /// **Jellyfin and Plex are deliberately excluded, and this is a design
  /// decision rather than an omission.** Adding them would make the same film
  /// return in up to six sections: Radarr and Sonarr "search" is `movie/lookup`
  /// and `series/lookup` — a TMDB/TVDB lookup, not a library search — so "Dune"
  /// already produces four groups, in `Future.wait` declaration order with no
  /// relevance ranking, and `_SearchSection` renders every group including the
  /// empty ones. A Stream match is worth strictly more as a *decoration* on the
  /// Radarr/Sonarr/Seerr row that is already there — "On Jellyfin · 34 min in" —
  /// joined on `tmdbId`, which is the same move `arrMediaExtrasSlots` already
  /// makes for Seerr data inside an arr screen.
  bool get isSearchable {
    return this == ServiceKey.seerr ||
        this == ServiceKey.radarr ||
        this == ServiceKey.sonarr ||
        this == ServiceKey.lidarr ||
        this == ServiceKey.bazarr;
  }

  bool get supportsManualImport {
    return this == ServiceKey.radarr ||
        this == ServiceKey.sonarr ||
        this == ServiceKey.lidarr;
  }

  String get apiVersion {
    switch (this) {
      case ServiceKey.seerr:
      case ServiceKey.lidarr:
      case ServiceKey.readarr:
        return 'v1';
      case ServiceKey.radarr:
      case ServiceKey.sonarr:
        return 'v3';
      case ServiceKey.qbittorrent:
        return 'WebUI';
      case ServiceKey.bazarr:
        return 'v1';
      case ServiceKey.truenas:
        return 'v25';
      case ServiceKey.dockge:
        return 'Socket.IO';
      case ServiceKey.prowlarr:
        return 'v1';
      case ServiceKey.sabnzbd:
        return 'API';
      case ServiceKey.nzbget:
        return 'JSON-RPC';
      case ServiceKey.unraid:
        return 'GraphQL';
      case ServiceKey.jellyfin:
        return 'v10';
      case ServiceKey.plex:
        return 'v1';
    }
  }

  String get itemLabel {
    switch (this) {
      case ServiceKey.seerr:
        return 'requests';
      case ServiceKey.radarr:
        return 'movies';
      case ServiceKey.sonarr:
        return 'series';
      case ServiceKey.lidarr:
        return 'artists';
      case ServiceKey.qbittorrent:
        return 'torrents';
      case ServiceKey.bazarr:
        return 'subtitles';
      case ServiceKey.truenas:
        return 'pools';
      case ServiceKey.dockge:
        return 'stacks';
      case ServiceKey.prowlarr:
        return 'indexers';
      case ServiceKey.readarr:
        return 'authors';
      case ServiceKey.sabnzbd:
        return 'downloads';
      case ServiceKey.nzbget:
        return 'downloads';
      case ServiceKey.unraid:
        return 'containers';
      // The top-level thing you enumerate on a media server. Not "movies" —
      // a single Jellyfin or Plex instance mixes films, shows and music, and
      // naming one of them would both misdescribe the server and read as a
      // duplicate of Radarr's or Sonarr's own label.
      case ServiceKey.jellyfin:
      case ServiceKey.plex:
        return 'libraries';
    }
  }

  String get routeParam {
    switch (this) {
      case ServiceKey.seerr:
        return 'seerr';
      case ServiceKey.radarr:
      case ServiceKey.sonarr:
      case ServiceKey.lidarr:
      case ServiceKey.qbittorrent:
      case ServiceKey.bazarr:
      case ServiceKey.truenas:
      case ServiceKey.dockge:
      case ServiceKey.prowlarr:
      case ServiceKey.readarr:
      case ServiceKey.sabnzbd:
      case ServiceKey.nzbget:
      case ServiceKey.unraid:
      case ServiceKey.jellyfin:
      case ServiceKey.plex:
        return name;
    }
  }

  String? extractHost(String? url) {
    final value = url?.trim() ?? '';
    if (value.isEmpty) return null;
    final parseableValue = value.contains('://') ? value : 'http://$value';

    try {
      final uri = Uri.parse(parseableValue);
      if (uri.host.isNotEmpty) {
        return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
      }

      return uri.path.isEmpty ? null : uri.path;
    } catch (_) {
      return null;
    }
  }
}
