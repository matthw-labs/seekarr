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
  final String readarrUrl;
  final String readarrApiKey;
  final String sabnzbdUrl;
  final String sabnzbdApiKey;
  final String nzbgetUrl;
  final String nzbgetUsername;
  final String nzbgetPassword;
  final String unraidUrl;
  final String unraidApiKey;
  final String jellyfinUrl;
  final String jellyfinApiKey;
  final String plexUrl;

  /// The user's own `X-Plex-Token`, pasted by hand.
  ///
  /// Named for what Plex calls it rather than squeezed into an `apiKey` field,
  /// though it occupies the generic credential slot in [_serviceSettingsAccess]
  /// exactly as `qbittorrentPassword` does. Seekarr never mints this: every
  /// documented way to obtain a Plex token is a plex.tv call, and reaching for
  /// one would break the product's first principle. A pasted token is validated
  /// by the user's own server.
  final String plexToken;

  /// Opaque per-install identifier sent as `X-Plex-Client-Identifier`.
  ///
  /// Generated once and then persisted forever — **not** per launch. Plex
  /// registers a new "device" against the user's server for every distinct
  /// identifier it sees, so a value regenerated on startup would litter their
  /// admin panel with a permanent row per app launch. Not a secret, so it lives
  /// in plain [SharedPreferences] beside the URL.
  final String plexClientId;

  /// Which Jellyfin user's watch state the library is read through.
  ///
  /// Required rather than optional, and the reason is structural: a Jellyfin API
  /// key authenticates as Administrator with **no user attached** (an empty
  /// `UserId` claim), so it can see every session but cannot answer "have I
  /// watched this". Resume positions, next-up and unplayed filters are all
  /// user-scoped, so the library has to be entered through a person chosen from
  /// `/Users`. Plex has no equivalent field because its token *is* the user and
  /// `/library/*` takes no impersonation parameter — that asymmetry is a real
  /// property of the two APIs, not a gap here.
  final String jellyfinUserId;

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
        ServiceKey.readarr: _ServiceSettingsAccess(
          url: (settings) => settings.readarrUrl,
          apiKey: (settings) => settings.readarrApiKey,
          update: (settings, {url, apiKey}) =>
              settings.copyWith(readarrUrl: url, readarrApiKey: apiKey),
        ),
        ServiceKey.sabnzbd: _ServiceSettingsAccess(
          url: (settings) => settings.sabnzbdUrl,
          apiKey: (settings) => settings.sabnzbdApiKey,
          update: (settings, {url, apiKey}) =>
              settings.copyWith(sabnzbdUrl: url, sabnzbdApiKey: apiKey),
        ),
        ServiceKey.nzbget: _ServiceSettingsAccess(
          url: (settings) => settings.nzbgetUrl,
          apiKey: (settings) => settings.nzbgetPassword,
          update: (settings, {url, apiKey}) =>
              settings.copyWith(nzbgetUrl: url, nzbgetPassword: apiKey),
        ),
        ServiceKey.unraid: _ServiceSettingsAccess(
          url: (settings) => settings.unraidUrl,
          apiKey: (settings) => settings.unraidApiKey,
          update: (settings, {url, apiKey}) =>
              settings.copyWith(unraidUrl: url, unraidApiKey: apiKey),
        ),
        ServiceKey.jellyfin: _ServiceSettingsAccess(
          url: (settings) => settings.jellyfinUrl,
          apiKey: (settings) => settings.jellyfinApiKey,
          update: (settings, {url, apiKey}) =>
              settings.copyWith(jellyfinUrl: url, jellyfinApiKey: apiKey),
        ),
        // The token takes the generic credential slot, the same way
        // `qbittorrentPassword` does — `plexClientId` and `jellyfinUserId` stay
        // off this map on purpose, because `update` is hard-wired to
        // `{url, apiKey}` and every third value in this codebase (both cert
        // fingerprints) is already handled outside it.
        ServiceKey.plex: _ServiceSettingsAccess(
          url: (settings) => settings.plexUrl,
          apiKey: (settings) => settings.plexToken,
          update: (settings, {url, apiKey}) =>
              settings.copyWith(plexUrl: url, plexToken: apiKey),
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
    this.readarrUrl = '',
    this.readarrApiKey = '',
    this.sabnzbdUrl = '',
    this.sabnzbdApiKey = '',
    this.nzbgetUrl = '',
    this.nzbgetUsername = '',
    this.nzbgetPassword = '',
    this.unraidUrl = '',
    this.unraidApiKey = '',
    this.jellyfinUrl = '',
    this.jellyfinApiKey = '',
    this.jellyfinUserId = '',
    this.plexUrl = '',
    this.plexToken = '',
    this.plexClientId = '',
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
    String? readarrUrl,
    String? readarrApiKey,
    String? sabnzbdUrl,
    String? sabnzbdApiKey,
    String? nzbgetUrl,
    String? nzbgetUsername,
    String? nzbgetPassword,
    String? unraidUrl,
    String? unraidApiKey,
    String? jellyfinUrl,
    String? jellyfinApiKey,
    String? jellyfinUserId,
    String? plexUrl,
    String? plexToken,
    String? plexClientId,
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
      readarrUrl: readarrUrl ?? this.readarrUrl,
      readarrApiKey: readarrApiKey ?? this.readarrApiKey,
      sabnzbdUrl: sabnzbdUrl ?? this.sabnzbdUrl,
      sabnzbdApiKey: sabnzbdApiKey ?? this.sabnzbdApiKey,
      nzbgetUrl: nzbgetUrl ?? this.nzbgetUrl,
      nzbgetUsername: nzbgetUsername ?? this.nzbgetUsername,
      nzbgetPassword: nzbgetPassword ?? this.nzbgetPassword,
      unraidUrl: unraidUrl ?? this.unraidUrl,
      unraidApiKey: unraidApiKey ?? this.unraidApiKey,
      jellyfinUrl: jellyfinUrl ?? this.jellyfinUrl,
      jellyfinApiKey: jellyfinApiKey ?? this.jellyfinApiKey,
      jellyfinUserId: jellyfinUserId ?? this.jellyfinUserId,
      plexUrl: plexUrl ?? this.plexUrl,
      plexToken: plexToken ?? this.plexToken,
      plexClientId: plexClientId ?? this.plexClientId,
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

  SettingsModel copyWithNzbget({
    String? url,
    String? username,
    String? password,
  }) {
    return copyWith(
      nzbgetUrl: url,
      nzbgetUsername: username,
      nzbgetPassword: password,
    );
  }

  String usernameFor(ServiceKey service) {
    if (service == ServiceKey.qbittorrent) return qbittorrentUsername;
    if (service == ServiceKey.dockge) return dockgeUsername;
    if (service == ServiceKey.nzbget) return nzbgetUsername;
    return '';
  }

  String passwordFor(ServiceKey service) {
    if (service == ServiceKey.qbittorrent) return qbittorrentPassword;
    if (service == ServiceKey.dockge) return dockgePassword;
    if (service == ServiceKey.nzbget) return nzbgetPassword;
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
    // qBittorrent, Dockge and NZBGet authenticate with username/password (some
    // can even run without auth behind a reverse proxy), so only the URL is
    // strictly required to consider them configured.
    if (service == ServiceKey.qbittorrent ||
        service == ServiceKey.dockge ||
        service == ServiceKey.nzbget) {
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
