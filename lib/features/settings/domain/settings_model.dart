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
  final String truenasUrl;
  final String truenasApiKey;
  final String dockgeUrl;
  final String dockgeUsername;
  final String dockgePassword;
  final String prowlarrUrl;
  final String prowlarrApiKey;

  /// SHA-256 fingerprint of a self-signed/untrusted TLS certificate the user
  /// explicitly chose to trust for this server (trust-on-first-use). Empty
  /// means standard certificate verification applies. Not a secret, so stored
  /// in plain [SharedPreferences] alongside the URL.
  final String truenasCertFingerprint;
  final String dockgeCertFingerprint;

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
        ServiceKey.truenas: _ServiceSettingsAccess(
          url: (settings) => settings.truenasUrl,
          apiKey: (settings) => settings.truenasApiKey,
          update: (settings, {url, apiKey}) =>
              settings.copyWith(truenasUrl: url, truenasApiKey: apiKey),
        ),
        ServiceKey.dockge: _ServiceSettingsAccess(
          url: (settings) => settings.dockgeUrl,
          apiKey: (settings) => settings.dockgePassword,
          update: (settings, {url, apiKey}) =>
              settings.copyWith(dockgeUrl: url, dockgePassword: apiKey),
        ),
        ServiceKey.prowlarr: _ServiceSettingsAccess(
          url: (settings) => settings.prowlarrUrl,
          apiKey: (settings) => settings.prowlarrApiKey,
          update: (settings, {url, apiKey}) =>
              settings.copyWith(prowlarrUrl: url, prowlarrApiKey: apiKey),
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
    this.truenasUrl = '',
    this.truenasApiKey = '',
    this.dockgeUrl = '',
    this.dockgeUsername = '',
    this.dockgePassword = '',
    this.prowlarrUrl = '',
    this.prowlarrApiKey = '',
    this.truenasCertFingerprint = '',
    this.dockgeCertFingerprint = '',
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
    String? truenasUrl,
    String? truenasApiKey,
    String? dockgeUrl,
    String? dockgeUsername,
    String? dockgePassword,
    String? prowlarrUrl,
    String? prowlarrApiKey,
    String? truenasCertFingerprint,
    String? dockgeCertFingerprint,
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
      truenasUrl: truenasUrl ?? this.truenasUrl,
      truenasApiKey: truenasApiKey ?? this.truenasApiKey,
      dockgeUrl: dockgeUrl ?? this.dockgeUrl,
      dockgeUsername: dockgeUsername ?? this.dockgeUsername,
      dockgePassword: dockgePassword ?? this.dockgePassword,
      prowlarrUrl: prowlarrUrl ?? this.prowlarrUrl,
      prowlarrApiKey: prowlarrApiKey ?? this.prowlarrApiKey,
      truenasCertFingerprint:
          truenasCertFingerprint ?? this.truenasCertFingerprint,
      dockgeCertFingerprint:
          dockgeCertFingerprint ?? this.dockgeCertFingerprint,
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

  SettingsModel copyWithDockge({
    String? url,
    String? username,
    String? password,
  }) {
    return copyWith(
      dockgeUrl: url,
      dockgeUsername: username,
      dockgePassword: password,
    );
  }

  String usernameFor(ServiceKey service) {
    if (service == ServiceKey.qbittorrent) return qbittorrentUsername;
    if (service == ServiceKey.dockge) return dockgeUsername;
    return '';
  }

  String passwordFor(ServiceKey service) {
    if (service == ServiceKey.qbittorrent) return qbittorrentPassword;
    if (service == ServiceKey.dockge) return dockgePassword;
    return '';
  }

  /// Trusted self-signed certificate fingerprint for [service], if any.
  /// Only the WebSocket-based services (TrueNAS, Dockge) support pinning.
  String certFingerprintFor(ServiceKey service) {
    if (service == ServiceKey.truenas) return truenasCertFingerprint;
    if (service == ServiceKey.dockge) return dockgeCertFingerprint;
    return '';
  }

  /// Returns a copy with the trusted certificate fingerprint updated for
  /// [service]. Ignored for services that do not support pinning.
  SettingsModel copyWithCertFingerprint(
    ServiceKey service,
    String fingerprint,
  ) {
    return switch (service) {
      ServiceKey.truenas => copyWith(truenasCertFingerprint: fingerprint),
      ServiceKey.dockge => copyWith(dockgeCertFingerprint: fingerprint),
      _ => this,
    };
  }

  bool isServiceConfigured(ServiceKey service) {
    // qBittorrent and Dockge authenticate with username/password (Dockge can
    // even run without auth behind a reverse proxy), so only the URL is
    // strictly required to consider them configured.
    if (service == ServiceKey.qbittorrent || service == ServiceKey.dockge) {
      return urlFor(service).isNotEmpty;
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
