import 'package:flutter/material.dart';

import 'package:seekarr/core/theme.dart';

enum ServiceKey { seerr, radarr, sonarr, lidarr, qbittorrent, bazarr, truenas }

extension ServiceKeyExtension on ServiceKey {
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
    }
  }

  bool get usesApiKey {
    return this != ServiceKey.qbittorrent;
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
