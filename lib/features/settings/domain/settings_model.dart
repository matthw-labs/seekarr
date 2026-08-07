import 'package:flutter/material.dart' show ThemeMode;

import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

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
  final String transmissionUrl;
  final String transmissionUsername;
  final String transmissionPassword;
  final String npmUrl;

  /// The Nginx Proxy Manager account's email address.
  ///
  /// Held in the generic username slot because that is structurally what it is
  /// — the non-secret half of a credential pair — but NPM calls it an email and
  /// so does the field, via [ServiceKeyExtension.usernameLabel]. Typing a bare
  /// username into `POST /api/tokens` is rejected, so labelling it "Username"
  /// would have been an invitation to fail the login.
  final String npmUsername;
  final String npmPassword;
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

  /// Trusted self-signed/untrusted TLS certificates (trust-on-first-use),
  /// keyed by [UrlUtils.certOrigin] rather than by service — a certificate
  /// belongs to the host that presents it, not to any one service reached
  /// through it, so two services behind the same reverse proxy share one
  /// trust decision. Value is the lowercase SHA-256 fingerprint of the
  /// trusted certificate's DER encoding. An origin with no entry gets
  /// standard certificate verification. Integrity-critical — this is the
  /// value that says "this exact certificate is the one to trust" — so it is
  /// kept in secure storage, never in plain `SharedPreferences`.
  final Map<String, String> trustedCertificates;

  final String region;
  final AppThemeMode themeMode;

  static final Map<ServiceKey, _ServiceSettingsAccess>
  _serviceSettingsAccess = {
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
      username: (settings) => settings.qbittorrentUsername,
      update: (settings, {url, apiKey}) =>
          settings.copyWith(qbittorrentUrl: url, qbittorrentPassword: apiKey),
      updateUsername: (settings, username) =>
          settings.copyWith(qbittorrentUsername: username),
    ),
    ServiceKey.transmission: _ServiceSettingsAccess(
      url: (settings) => settings.transmissionUrl,
      apiKey: (settings) => settings.transmissionPassword,
      username: (settings) => settings.transmissionUsername,
      update: (settings, {url, apiKey}) =>
          settings.copyWith(transmissionUrl: url, transmissionPassword: apiKey),
      updateUsername: (settings, username) =>
          settings.copyWith(transmissionUsername: username),
    ),
    ServiceKey.nginxProxyManager: _ServiceSettingsAccess(
      url: (settings) => settings.npmUrl,
      apiKey: (settings) => settings.npmPassword,
      username: (settings) => settings.npmUsername,
      update: (settings, {url, apiKey}) =>
          settings.copyWith(npmUrl: url, npmPassword: apiKey),
      updateUsername: (settings, username) =>
          settings.copyWith(npmUsername: username),
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
      username: (settings) => settings.dockgeUsername,
      update: (settings, {url, apiKey}) =>
          settings.copyWith(dockgeUrl: url, dockgePassword: apiKey),
      updateUsername: (settings, username) =>
          settings.copyWith(dockgeUsername: username),
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
      username: (settings) => settings.nzbgetUsername,
      update: (settings, {url, apiKey}) =>
          settings.copyWith(nzbgetUrl: url, nzbgetPassword: apiKey),
      updateUsername: (settings, username) =>
          settings.copyWith(nzbgetUsername: username),
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
    // `{url, apiKey}` and both stand alone as third values already handled
    // outside it, the same way `trustedCertificates` is keyed by origin
    // rather than by service and so cannot live in a per-service map at all.
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
    this.transmissionUrl = '',
    this.transmissionUsername = '',
    this.transmissionPassword = '',
    this.npmUrl = '',
    this.npmUsername = '',
    this.npmPassword = '',
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
    this.trustedCertificates = const {},
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
    String? transmissionUrl,
    String? transmissionUsername,
    String? transmissionPassword,
    String? npmUrl,
    String? npmUsername,
    String? npmPassword,
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
    Map<String, String>? trustedCertificates,
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
      transmissionUrl: transmissionUrl ?? this.transmissionUrl,
      transmissionUsername: transmissionUsername ?? this.transmissionUsername,
      transmissionPassword: transmissionPassword ?? this.transmissionPassword,
      npmUrl: npmUrl ?? this.npmUrl,
      npmUsername: npmUsername ?? this.npmUsername,
      npmPassword: npmPassword ?? this.npmPassword,
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
      trustedCertificates: trustedCertificates ?? this.trustedCertificates,
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

  /// Returns a copy with [service]'s URL, username and/or password updated.
  ///
  /// The credential-authenticated counterpart to [copyWithService], and the
  /// replacement for the `copyWithQbittorrent`/`copyWithDockge`/`copyWithNzbget`
  /// family this grew out of. That shape did not scale honestly: each new
  /// credential service added a near-identical method here **and** a `switch`
  /// arm in onboarding **and** one in the settings screen, and the compiler
  /// checked none of the three. It has already failed once in exactly that way —
  /// NZBGet shipped with a username field that persisted correctly and was
  /// rendered by no screen at all, because two of the three sites were updated
  /// and the third was not.
  ///
  /// Now the registry answers it: the username half is written through
  /// [_ServiceSettingsAccess.updateUsername], which exists for precisely the
  /// services [ServiceKeyExtension.usesApiKey] excludes.
  ///
  /// Asserts rather than silently no-ops on an API-key service, because passing
  /// one here is a programming error — the caller meant [copyWithService], and
  /// quietly dropping the write is how a credential goes missing.
  SettingsModel copyWithCredentials(
    ServiceKey service, {
    String? url,
    String? username,
    String? password,
  }) {
    final access = _serviceAccessFor(service);
    assert(
      access.updateUsername != null,
      '${service.name} authenticates with an API key — use copyWithService.',
    );
    var updated = access.update(this, url: url, apiKey: password);
    if (username != null && access.updateUsername != null) {
      updated = access.updateUsername!(updated, username);
    }
    return updated;
  }

  /// The username configured for [service], or `''` for the services that
  /// authenticate with an API key and so have none.
  String usernameFor(ServiceKey service) {
    return _serviceAccessFor(service).username?.call(this) ?? '';
  }

  /// The password configured for [service], or `''` for the services that
  /// authenticate with an API key and so have none.
  ///
  /// A credential-authenticated service keeps its password in the generic
  /// credential slot [apiKeyFor] reads, exactly as the Plex token does — so the
  /// registry capability is the whole of the decision here, rather than a
  /// second copy of the "is it one of these three" list.
  String passwordFor(ServiceKey service) {
    return service.usesApiKey ? '' : apiKeyFor(service);
  }

  /// Returns a copy with [service]'s per-server extras cleared.
  ///
  /// The `{url, apiKey}` pair [copyWithService] reaches is not all of what
  /// describes a connection: Jellyfin also stores *which user* the library is
  /// read through, and that value belongs to the server that was removed. Left
  /// behind, re-adding a different Jellyfin binds every per-viewer query to a
  /// user id that does not exist there, and the picker shows nothing selected.
  ///
  /// `plexClientId` is deliberately **not** cleared and is not the same kind of
  /// value: it identifies this *install* rather than any one server, is minted
  /// exactly once, and `SettingsService.saveSettings` refuses to overwrite it
  /// for that reason.
  SettingsModel copyWithoutServiceExtras(ServiceKey service) {
    if (service.needsViewerSelection) return copyWith(jellyfinUserId: '');
    return this;
  }

  /// The trusted fingerprint for the TLS origin [rawUrl] belongs to, or null
  /// when nothing is pinned there (or [rawUrl] cannot carry a certificate at
  /// all — see [UrlUtils.certOrigin]).
  ///
  /// Every service is reachable through this — see ADR-6 in
  /// `context/decisions.md`. There is deliberately no per-`ServiceKey`
  /// overload: a certificate belongs to the origin, and looking one up by
  /// service would need that service's *own* saved URL anyway, which the
  /// caller already has.
  String? pinForUrl(String rawUrl) {
    final origin = UrlUtils.certOrigin(rawUrl);
    if (origin == null) return null;
    final pin = trustedCertificates[origin];
    return (pin == null || pin.isEmpty) ? null : pin;
  }

  /// Returns a copy with the trusted fingerprint for [url]'s origin set to
  /// [fingerprint]. Every service sharing that origin is trusted or forgotten
  /// together — see [servicesSharingOriginOf].
  ///
  /// An empty [fingerprint] **removes** the entry rather than storing an
  /// empty string, which is what makes it "forget" this origin: [pinForUrl]
  /// treats a missing key and an empty value as the same "not pinned", but
  /// only removal actually shrinks the stored map.
  ///
  /// A no-op (returns `this`) when [url] cannot resolve to a TLS origin.
  SettingsModel copyWithTrustedCertificate({
    required String url,
    required String fingerprint,
  }) {
    final origin = UrlUtils.certOrigin(url);
    if (origin == null) return this;

    final updated = Map<String, String>.of(trustedCertificates);
    final trimmed = fingerprint.trim();
    if (trimmed.isEmpty) {
      updated.remove(origin);
    } else {
      updated[origin] = trimmed.toLowerCase();
    }
    return copyWith(trustedCertificates: updated);
  }

  /// Returns a copy that forgets [priorUrl]'s pinned certificate unless some
  /// service *still configured in this copy* is reached at that origin.
  ///
  /// The one guard for every path that stops using an address — removing a
  /// connection, editing a URL to point somewhere else — because all of them
  /// need the same answer and getting it wrong is a security bug in both
  /// directions. Forgetting unconditionally breaks Radarr's trust in the
  /// reverse proxy when Sonarr is removed from behind it; never forgetting
  /// leaves a pin keyed to an origin nothing uses any more, and since
  /// [pinForUrl] is keyed purely by origin, the next service pointed at that
  /// address would silently reuse it with no trust prompt.
  ///
  /// Call it *after* writing the new (or cleared) values, so "still
  /// configured" describes the state being saved rather than the one being
  /// left. A no-op for an empty [priorUrl] or one that carries no TLS origin.
  SettingsModel copyWithoutUnusedCertificate(String priorUrl) {
    if (priorUrl.trim().isEmpty) return this;
    final stillUsed = servicesSharingOriginOf(
      priorUrl,
    ).any(isServiceConfigured);
    if (stillUsed) return this;
    return copyWithTrustedCertificate(url: priorUrl, fingerprint: '');
  }

  /// Every configured service whose saved URL resolves to the same TLS
  /// origin as [rawUrl] — the set one trust decision on that origin actually
  /// covers, and so the set a "forget this certificate" also breaks.
  List<ServiceKey> servicesSharingOriginOf(String rawUrl) {
    final origin = UrlUtils.certOrigin(rawUrl);
    if (origin == null) return const [];
    return ServiceKey.values
        .where((service) {
          final serviceUrl = urlFor(service);
          return serviceUrl.isNotEmpty &&
              UrlUtils.certOrigin(serviceUrl) == origin;
        })
        .toList(growable: false);
  }

  bool isServiceConfigured(ServiceKey service) {
    // A credential-authenticated service can legitimately run without auth
    // behind a reverse proxy, so only the URL is strictly required there. Which
    // services those are is the registry's answer, not a list repeated here.
    if (!service.usesApiKey) return urlFor(service).isNotEmpty;
    return urlFor(service).isNotEmpty && apiKeyFor(service).isNotEmpty;
  }
}

class _ServiceSettingsAccess {
  final String Function(SettingsModel settings) url;
  final String Function(SettingsModel settings) apiKey;

  /// Only for the services [ServiceKeyExtension.usesApiKey] excludes, whose
  /// credential is a username/password pair — the password takes the generic
  /// [apiKey] slot and this carries the other half. Null everywhere else, which
  /// is what makes [SettingsModel.usernameFor] a table lookup instead of a
  /// second hand-maintained list of the credential-authenticated services.
  final String Function(SettingsModel settings)? username;

  final SettingsModel Function(
    SettingsModel settings, {
    String? url,
    String? apiKey,
  })
  update;

  /// Writes the username half of a credential pair. Non-null exactly when
  /// [username] is, so [SettingsModel.copyWithCredentials] can read the
  /// registry instead of switching on the service — the same reason [username]
  /// itself exists.
  final SettingsModel Function(SettingsModel settings, String username)?
  updateUsername;

  const _ServiceSettingsAccess({
    required this.url,
    required this.apiKey,
    required this.update,
    this.username,
    this.updateUsername,
  });
}
