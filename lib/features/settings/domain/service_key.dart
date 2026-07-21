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
    }
  }

  bool get usesApiKey {
    return this != ServiceKey.qbittorrent &&
        this != ServiceKey.dockge &&
        this != ServiceKey.nzbget;
  }

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
