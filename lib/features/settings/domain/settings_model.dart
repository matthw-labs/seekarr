import 'package:flutter/material.dart' show ThemeMode;

import 'package:seekarr/features/settings/domain/service_key.dart';

enum AppThemeMode {
  system(label: 'System'),
  light(label: 'Light'),
  dark(label: 'Dark');

  const AppThemeMode({required this.label});

  final String label;

  static final Map<String, AppThemeMode> _modesByName = {
    for (final mode in values) mode.name: mode,
  };

  ThemeMode get materialThemeMode {
    return switch (this) {
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
      AppThemeMode.system => ThemeMode.system,
    };
  }

  static AppThemeMode fromName(String? value) =>
      _modesByName[value] ?? AppThemeMode.system;
}

class SettingsModel {
  final String seerrUrl;
  final String seerrApiKey;
  final String radarrUrl;
  final String radarrApiKey;
  final String sonarrUrl;
  final String sonarrApiKey;
  final String lidarrUrl;
  final String lidarrApiKey;
  final String qbittorrentUrl;
  final String qbittorrentUsername;
  final String qbittorrentPassword;
  final String bazarrUrl;
  final String bazarrApiKey;
  final String region;
  final AppThemeMode themeMode;

  static final Map<ServiceKey, _ServiceSettingsAccess> _serviceSettingsAccess =
      {
        ServiceKey.seerr: _ServiceSettingsAccess(
          url: (settings) => settings.seerrUrl,
          apiKey: (settings) => settings.seerrApiKey,
          update: (settings, {url, apiKey}) =>
              settings.copyWith(seerrUrl: url, seerrApiKey: apiKey),
        ),
        ServiceKey.radarr: _ServiceSettingsAccess(
          url: (settings) => settings.radarrUrl,
          apiKey: (settings) => settings.radarrApiKey,
          update: (settings, {url, apiKey}) =>
              settings.copyWith(radarrUrl: url, radarrApiKey: apiKey),
        ),
        ServiceKey.sonarr: _ServiceSettingsAccess(
          url: (settings) => settings.sonarrUrl,
          apiKey: (settings) => settings.sonarrApiKey,
          update: (settings, {url, apiKey}) =>
              settings.copyWith(sonarrUrl: url, sonarrApiKey: apiKey),
        ),
        ServiceKey.lidarr: _ServiceSettingsAccess(
          url: (settings) => settings.lidarrUrl,
          apiKey: (settings) => settings.lidarrApiKey,
          update: (settings, {url, apiKey}) =>
              settings.copyWith(lidarrUrl: url, lidarrApiKey: apiKey),
        ),
        ServiceKey.qbittorrent: _ServiceSettingsAccess(
          url: (settings) => settings.qbittorrentUrl,
          apiKey: (settings) => settings.qbittorrentPassword,
          update: (settings, {url, apiKey}) => settings.copyWith(
            qbittorrentUrl: url,
            qbittorrentPassword: apiKey,
          ),
        ),
        ServiceKey.bazarr: _ServiceSettingsAccess(
          url: (settings) => settings.bazarrUrl,
          apiKey: (settings) => settings.bazarrApiKey,
          update: (settings, {url, apiKey}) =>
              settings.copyWith(bazarrUrl: url, bazarrApiKey: apiKey),
        ),
      };

  static String normalizeRegion(String? region) {
    final normalized = region?.trim().toUpperCase() ?? '';
    return normalized.isEmpty ? 'US' : normalized;
  }

  const SettingsModel({
    this.seerrUrl = '',
    this.seerrApiKey = '',
    this.radarrUrl = '',
    this.radarrApiKey = '',
    this.sonarrUrl = '',
    this.sonarrApiKey = '',
    this.lidarrUrl = '',
    this.lidarrApiKey = '',
    this.qbittorrentUrl = '',
    this.qbittorrentUsername = '',
    this.qbittorrentPassword = '',
    this.bazarrUrl = '',
    this.bazarrApiKey = '',
    this.region = 'US',
    this.themeMode = AppThemeMode.system,
  });

  SettingsModel copyWith({
    String? seerrUrl,
    String? seerrApiKey,
    String? radarrUrl,
    String? radarrApiKey,
    String? sonarrUrl,
    String? sonarrApiKey,
    String? lidarrUrl,
    String? lidarrApiKey,
    String? qbittorrentUrl,
    String? qbittorrentUsername,
    String? qbittorrentPassword,
    String? bazarrUrl,
    String? bazarrApiKey,
    String? region,
    AppThemeMode? themeMode,
  }) {
    return SettingsModel(
      seerrUrl: seerrUrl ?? this.seerrUrl,
      seerrApiKey: seerrApiKey ?? this.seerrApiKey,
      radarrUrl: radarrUrl ?? this.radarrUrl,
      radarrApiKey: radarrApiKey ?? this.radarrApiKey,
      sonarrUrl: sonarrUrl ?? this.sonarrUrl,
      sonarrApiKey: sonarrApiKey ?? this.sonarrApiKey,
      lidarrUrl: lidarrUrl ?? this.lidarrUrl,
      lidarrApiKey: lidarrApiKey ?? this.lidarrApiKey,
      qbittorrentUrl: qbittorrentUrl ?? this.qbittorrentUrl,
      qbittorrentUsername: qbittorrentUsername ?? this.qbittorrentUsername,
      qbittorrentPassword: qbittorrentPassword ?? this.qbittorrentPassword,
      bazarrUrl: bazarrUrl ?? this.bazarrUrl,
      bazarrApiKey: bazarrApiKey ?? this.bazarrApiKey,
      region: region ?? this.region,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  ThemeMode get resolvedThemeMode => themeMode.materialThemeMode;

  _ServiceSettingsAccess _serviceAccessFor(ServiceKey service) {
    return _serviceSettingsAccess[service]!;
  }

  /// Returns the URL configured for [service].
  String urlFor(ServiceKey service) {
    return _serviceAccessFor(service).url(this);
  }

  /// Returns the API key configured for [service].
  String apiKeyFor(ServiceKey service) {
    return _serviceAccessFor(service).apiKey(this);
  }

  /// Returns a copy with the URL and/or API key updated for [service].
  SettingsModel copyWithService(
    ServiceKey service, {
    String? url,
    String? apiKey,
  }) {
    return _serviceAccessFor(service).update(this, url: url, apiKey: apiKey);
  }

  SettingsModel copyWithQbittorrent({
    String? url,
    String? username,
    String? password,
  }) {
    return copyWith(
      qbittorrentUrl: url,
      qbittorrentUsername: username,
      qbittorrentPassword: password,
    );
  }

  String usernameFor(ServiceKey service) {
    if (service == ServiceKey.qbittorrent) return qbittorrentUsername;
    return '';
  }

  String passwordFor(ServiceKey service) {
    if (service == ServiceKey.qbittorrent) return qbittorrentPassword;
    return '';
  }

  bool isServiceConfigured(ServiceKey service) {
    if (service == ServiceKey.qbittorrent) {
      return qbittorrentUrl.isNotEmpty;
    }
    return urlFor(service).isNotEmpty && apiKeyFor(service).isNotEmpty;
  }
}

class _ServiceSettingsAccess {
  final String Function(SettingsModel settings) url;
  final String Function(SettingsModel settings) apiKey;
  final SettingsModel Function(
    SettingsModel settings, {
    String? url,
    String? apiKey,
  })
  update;

  const _ServiceSettingsAccess({
    required this.url,
    required this.apiKey,
    required this.update,
  });
}
