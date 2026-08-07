import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

SecureSettingsStore createSecureSettingsStore() {
  // Keep secrets (API keys/passwords) out of iCloud/device backups by pinning
  // Keychain accessibility to this device only. Without this the default
  // accessibility lets credentials sync to backups.
  const deviceOnly = KeychainAccessibility.first_unlock_this_device;
  return FlutterSecureSettingsStore(
    FlutterSecureStorage(
      // flutter_secure_storage 10.x migrates away from the old
      // encryptedSharedPreferences path. Keep migration enabled for existing
      // installs and write a backup during algorithm upgrades.
      aOptions: AndroidOptions(migrateWithBackup: true),
      iOptions: const IOSOptions(accessibility: deviceOnly),
      mOptions: const MacOsOptions(accessibility: deviceOnly),
    ),
  );
}

abstract interface class SecureSettingsStore {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});

  Future<void> deleteAll();
}

class FlutterSecureSettingsStore implements SecureSettingsStore {
  final FlutterSecureStorage _storage;

  const FlutterSecureSettingsStore(this._storage);

  @override
  Future<String?> read({required String key}) {
    return _storage.read(key: key);
  }

  @override
  Future<void> write({required String key, required String value}) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete({required String key}) {
    return _storage.delete(key: key);
  }

  @override
  Future<void> deleteAll() {
    return _storage.deleteAll();
  }
}

class SettingsService {
  static const _kRegion = 'region';
  static const _kThemeMode = 'theme_mode';
  static const _kOnboardingComplete = 'onboarding_complete';

  /// Secure-storage key for the whole origin→fingerprint trust map (ADR-6).
  /// One entry, JSON-encoded, rather than one key per service — the map is
  /// keyed by TLS origin, not by `ServiceKey`, so there is no per-service key
  /// to hang it on.
  static const _kTrustedCertificates = 'secure_trusted_certificates';

  /// Where TrueNAS's and Dockge's fingerprints lived under ADR-5, kept only
  /// so [_loadTrustedCertificates] can migrate an existing install once.
  static const _legacyTrueNasCertFingerprint = 'truenas_cert_fingerprint';
  static const _legacyDockgeCertFingerprint = 'dockge_cert_fingerprint';

  static const Map<ServiceKey, _ServiceStorageKeys> _serviceStorageKeys = {
    ServiceKey.seerr: _ServiceStorageKeys(
      url: 'seerr_url',
      legacyApiKey: 'seerr_api_key',
      secureApiKey: 'secure_seerr_api_key',
      legacyUrl: 'jellyseerr_url',
      legacyPlaintextApiKey: 'jellyseerr_api_key',
      legacySecureApiKey: 'secure_jellyseerr_api_key',
    ),
    ServiceKey.radarr: _ServiceStorageKeys(
      url: 'radarr_url',
      legacyApiKey: 'radarr_api_key',
      secureApiKey: 'secure_radarr_api_key',
    ),
    ServiceKey.sonarr: _ServiceStorageKeys(
      url: 'sonarr_url',
      legacyApiKey: 'sonarr_api_key',
      secureApiKey: 'secure_sonarr_api_key',
    ),
    ServiceKey.lidarr: _ServiceStorageKeys(
      url: 'lidarr_url',
      legacyApiKey: 'lidarr_api_key',
      secureApiKey: 'secure_lidarr_api_key',
    ),
    ServiceKey.qbittorrent: _ServiceStorageKeys(
      url: 'qbittorrent_url',
      legacyApiKey: '',
      secureApiKey: 'secure_qbittorrent_password',
      username: 'qbittorrent_username',
    ),
    ServiceKey.transmission: _ServiceStorageKeys(
      url: 'transmission_url',
      legacyApiKey: '',
      secureApiKey: 'secure_transmission_password',
      username: 'transmission_username',
    ),
    // Keyed `npm_*` to match `routeParam`, so a storage key, a route segment
    // and a fixture directory all spell the service the same way.
    ServiceKey.nginxProxyManager: _ServiceStorageKeys(
      url: 'npm_url',
      legacyApiKey: '',
      secureApiKey: 'secure_npm_password',
      username: 'npm_username',
    ),
    ServiceKey.bazarr: _ServiceStorageKeys(
      url: 'bazarr_url',
      legacyApiKey: '',
      secureApiKey: 'secure_bazarr_api_key',
    ),
    ServiceKey.truenas: _ServiceStorageKeys(
      url: 'truenas_url',
      legacyApiKey: '',
      secureApiKey: 'secure_truenas_api_key',
    ),
    ServiceKey.dockge: _ServiceStorageKeys(
      url: 'dockge_url',
      legacyApiKey: '',
      secureApiKey: 'secure_dockge_password',
      username: 'dockge_username',
    ),
    ServiceKey.prowlarr: _ServiceStorageKeys(
      url: 'prowlarr_url',
      legacyApiKey: '',
      secureApiKey: 'secure_prowlarr_api_key',
    ),
    ServiceKey.readarr: _ServiceStorageKeys(
      url: 'readarr_url',
      legacyApiKey: '',
      secureApiKey: 'secure_readarr_api_key',
    ),
    ServiceKey.sabnzbd: _ServiceStorageKeys(
      url: 'sabnzbd_url',
      legacyApiKey: '',
      secureApiKey: 'secure_sabnzbd_api_key',
    ),
    ServiceKey.nzbget: _ServiceStorageKeys(
      url: 'nzbget_url',
      legacyApiKey: '',
      secureApiKey: 'secure_nzbget_password',
      username: 'nzbget_username',
    ),
    ServiceKey.unraid: _ServiceStorageKeys(
      url: 'unraid_url',
      legacyApiKey: '',
      secureApiKey: 'secure_unraid_api_key',
    ),
    ServiceKey.jellyfin: _ServiceStorageKeys(
      url: 'jellyfin_url',
      legacyApiKey: '',
      secureApiKey: 'secure_jellyfin_api_key',
      userId: 'jellyfin_user_id',
    ),
    ServiceKey.plex: _ServiceStorageKeys(
      url: 'plex_url',
      legacyApiKey: '',
      secureApiKey: 'secure_plex_token',
      clientId: 'plex_client_id',
    ),
  };

  final SharedPreferences _prefs;
  final SecureSettingsStore _secureStore;

  SettingsService(this._prefs, this._secureStore);

  Future<void> migrateFromPlaintext() async {
    for (final storageKeys in _serviceStorageKeys.values) {
      // Migrate legacy plaintext API keys from before the Seerr rename.
      if (storageKeys.legacyPlaintextApiKey != null) {
        final legacyPlaintext = _prefs.getString(
          storageKeys.legacyPlaintextApiKey!,
        );
        if (legacyPlaintext != null) {
          final normalized = legacyPlaintext.trim();
          if (normalized.isNotEmpty) {
            final existing = await _secureStore.read(
              key: storageKeys.secureApiKey,
            );
            if (existing == null || existing.isEmpty) {
              await _secureStore.write(
                key: storageKeys.secureApiKey,
                value: normalized,
              );
            }
          }
          await _prefs.remove(storageKeys.legacyPlaintextApiKey!);
        }
      }

      // Migrate current plaintext API keys to secure storage.
      final plaintextValue = _prefs.getString(storageKeys.legacyApiKey);
      if (plaintextValue == null) {
        continue;
      }

      final normalizedValue = plaintextValue.trim();
      final secureValue = await _secureStore.read(
        key: storageKeys.secureApiKey,
      );

      if (normalizedValue.isNotEmpty &&
          (secureValue == null || secureValue.isEmpty)) {
        await _secureStore.write(
          key: storageKeys.secureApiKey,
          value: normalizedValue,
        );
      }

      await _prefs.remove(storageKeys.legacyApiKey);
    }
  }

  Future<bool> loadOnboardingComplete() async {
    return _prefs.getBool(_kOnboardingComplete) ?? false;
  }

  Future<void> saveOnboardingComplete() async {
    await _prefs.setBool(_kOnboardingComplete, true);
  }

  /// Wipes all Cupola-persisted data: SharedPreferences keys (service URLs,
  /// credentials, region, theme, onboarding flag, legacy keys) and every
  /// secure-storage entry. Clears secure storage first so a Keychain failure
  /// leaves prefs intact and the caller can surface an error.
  Future<void> clearAll() async {
    await _secureStore.deleteAll();

    for (final storageKeys in _serviceStorageKeys.values) {
      await _prefs.remove(storageKeys.url);
      await _prefs.remove(storageKeys.legacyApiKey);
      if (storageKeys.legacyUrl != null) {
        await _prefs.remove(storageKeys.legacyUrl!);
      }
      if (storageKeys.legacyPlaintextApiKey != null) {
        await _prefs.remove(storageKeys.legacyPlaintextApiKey!);
      }
      if (storageKeys.username != null) {
        await _prefs.remove(storageKeys.username!);
      }
      if (storageKeys.userId != null) {
        await _prefs.remove(storageKeys.userId!);
      }
      // The client id goes too. It is not a credential, but leaving it behind
      // would tie a freshly set-up install to the device row the old one
      // registered on the user's Plex server.
      if (storageKeys.clientId != null) {
        await _prefs.remove(storageKeys.clientId!);
      }
    }

    // `_secureStore.deleteAll()` above already wipes the secure copy of the
    // trust map and of both legacy fingerprints; only a plaintext-prefs
    // fallback left by an older build needs an explicit remove here.
    await _prefs.remove(_legacyTrueNasCertFingerprint);
    await _prefs.remove(_legacyDockgeCertFingerprint);

    await _prefs.remove(_kRegion);
    await _prefs.remove(_kThemeMode);
    await _prefs.remove(_kOnboardingComplete);
    await _prefs.remove('hidden_tabs');
  }

  Future<SettingsModel> loadSettings() async {
    final serviceSettings = await _loadServiceSettings();
    // The passwords come out of the same generic credential slot every other
    // service's key does — see [_loadServiceSettings]. The usernames need their
    // own pass, because they are the half of the pair that has no generic slot;
    // driving it off the storage table rather than naming each service means a
    // new credential service is one map entry rather than a line here that is
    // easy to forget and that nothing would fail without.
    final usernames = _loadUsernames();
    final trustedCertificates = await _loadTrustedCertificates(serviceSettings);
    final jellyfinKeys = _serviceStorageKeys[ServiceKey.jellyfin]!;
    final jellyfinUserId = _prefs.getString(jellyfinKeys.userId!) ?? '';
    final plexClientId = await _loadOrCreatePlexClientId();

    return SettingsModel(
      seerrUrl: serviceSettings[ServiceKey.seerr]!.$1,
      seerrApiKey: serviceSettings[ServiceKey.seerr]!.$2,
      radarrUrl: serviceSettings[ServiceKey.radarr]!.$1,
      radarrApiKey: serviceSettings[ServiceKey.radarr]!.$2,
      sonarrUrl: serviceSettings[ServiceKey.sonarr]!.$1,
      sonarrApiKey: serviceSettings[ServiceKey.sonarr]!.$2,
      lidarrUrl: serviceSettings[ServiceKey.lidarr]!.$1,
      lidarrApiKey: serviceSettings[ServiceKey.lidarr]!.$2,
      qbittorrentUrl: serviceSettings[ServiceKey.qbittorrent]!.$1,
      qbittorrentUsername: usernames[ServiceKey.qbittorrent]!,
      qbittorrentPassword: serviceSettings[ServiceKey.qbittorrent]!.$2,
      transmissionUrl: serviceSettings[ServiceKey.transmission]!.$1,
      transmissionUsername: usernames[ServiceKey.transmission]!,
      transmissionPassword: serviceSettings[ServiceKey.transmission]!.$2,
      npmUrl: serviceSettings[ServiceKey.nginxProxyManager]!.$1,
      npmUsername: usernames[ServiceKey.nginxProxyManager]!,
      npmPassword: serviceSettings[ServiceKey.nginxProxyManager]!.$2,
      bazarrUrl: serviceSettings[ServiceKey.bazarr]!.$1,
      bazarrApiKey: serviceSettings[ServiceKey.bazarr]!.$2,
      truenasUrl: serviceSettings[ServiceKey.truenas]!.$1,
      truenasApiKey: serviceSettings[ServiceKey.truenas]!.$2,
      dockgeUrl: serviceSettings[ServiceKey.dockge]!.$1,
      dockgeUsername: usernames[ServiceKey.dockge]!,
      dockgePassword: serviceSettings[ServiceKey.dockge]!.$2,
      prowlarrUrl: serviceSettings[ServiceKey.prowlarr]!.$1,
      prowlarrApiKey: serviceSettings[ServiceKey.prowlarr]!.$2,
      readarrUrl: serviceSettings[ServiceKey.readarr]!.$1,
      readarrApiKey: serviceSettings[ServiceKey.readarr]!.$2,
      sabnzbdUrl: serviceSettings[ServiceKey.sabnzbd]!.$1,
      sabnzbdApiKey: serviceSettings[ServiceKey.sabnzbd]!.$2,
      nzbgetUrl: serviceSettings[ServiceKey.nzbget]!.$1,
      nzbgetUsername: usernames[ServiceKey.nzbget]!,
      nzbgetPassword: serviceSettings[ServiceKey.nzbget]!.$2,
      unraidUrl: serviceSettings[ServiceKey.unraid]!.$1,
      unraidApiKey: serviceSettings[ServiceKey.unraid]!.$2,
      jellyfinUrl: serviceSettings[ServiceKey.jellyfin]!.$1,
      jellyfinApiKey: serviceSettings[ServiceKey.jellyfin]!.$2,
      jellyfinUserId: jellyfinUserId,
      plexUrl: serviceSettings[ServiceKey.plex]!.$1,
      plexToken: serviceSettings[ServiceKey.plex]!.$2,
      plexClientId: plexClientId,
      trustedCertificates: trustedCertificates,
      region: _loadRegion(),
      themeMode: AppThemeMode.fromName(_prefs.getString(_kThemeMode)),
    );
  }

  Future<void> saveSettings(SettingsModel settings) async {
    final normalizedRegion = SettingsModel.normalizeRegion(settings.region);

    await _saveServiceUrls(settings);
    await _prefs.setString(_kRegion, normalizedRegion);
    await _prefs.setString(_kThemeMode, settings.themeMode.name);
    await _prefs.remove('hidden_tabs');

    await _saveServiceApiKeys(settings);

    await _saveUsernames(settings);

    await _saveTrustedCertificates(settings.trustedCertificates);

    final jellyfinKeys = _serviceStorageKeys[ServiceKey.jellyfin]!;
    if (settings.jellyfinUserId.isNotEmpty) {
      await _prefs.setString(jellyfinKeys.userId!, settings.jellyfinUserId);
    } else {
      await _prefs.remove(jellyfinKeys.userId!);
    }

    // Deliberately *not* written from `settings`. The client id is owned by
    // `_loadOrCreatePlexClientId`, which mints it once; honouring an incoming
    // empty value here — which every `SettingsModel()` default carries — would
    // clear it on the next unrelated save and hand the user's Plex server a new
    // device row on the following load.
    if (settings.plexClientId.isNotEmpty) {
      final plexKeys = _serviceStorageKeys[ServiceKey.plex]!;
      await _prefs.setString(plexKeys.clientId!, settings.plexClientId);
    }
  }

  /// Every service's saved username, `''` for those that have none.
  ///
  /// Keyed by [ServiceKey] and complete for all of them, so [loadSettings] can
  /// index it with `!` for the credential services without deciding anywhere
  /// else which services those are — the presence of a `username` storage key
  /// is the whole of that decision.
  Map<ServiceKey, String> _loadUsernames() {
    return {
      for (final entry in _serviceStorageKeys.entries)
        entry.key: entry.value.username == null
            ? ''
            : _prefs.getString(entry.value.username!) ?? '',
    };
  }

  /// Writes every credential service's username, clearing the key when the
  /// value is empty so a removed connection leaves nothing behind.
  ///
  /// A username is not a secret and stays in [SharedPreferences] beside the
  /// URL; only the password half goes to the Keychain, via [_saveServiceApiKeys].
  Future<void> _saveUsernames(SettingsModel settings) async {
    for (final entry in _serviceStorageKeys.entries) {
      final key = entry.value.username;
      if (key == null) continue;
      final value = settings.usernameFor(entry.key);
      if (value.isEmpty) {
        await _prefs.remove(key);
      } else {
        await _prefs.setString(key, value);
      }
    }
  }

  /// Reads the persisted `X-Plex-Client-Identifier`, minting one on first use.
  ///
  /// Write-on-read is unusual but correct here and already precedented in this
  /// file by [_loadCertFingerprint]'s prefs→secure migration. The alternative —
  /// generating at connect time — leaves a window where two concurrent requests
  /// each mint their own id, and Plex would record both as separate devices.
  ///
  /// Shaped as a v4 UUID because that is what every Plex client sends, but built
  /// from [Random.secure] rather than a `uuid` dependency: the project does not
  /// take new packages without approval, and nothing here needs more than 122
  /// random bits.
  Future<String> _loadOrCreatePlexClientId() async {
    final key = _serviceStorageKeys[ServiceKey.plex]!.clientId!;
    final existing = _prefs.getString(key)?.trim() ?? '';
    if (existing.isNotEmpty) return existing;

    final generated = _randomUuidV4();
    await _prefs.setString(key, generated);
    return generated;
  }

  static String _randomUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  /// Persists the whole trust-on-first-use map (ADR-6).
  ///
  /// Stored in secure storage rather than SharedPreferences: a fingerprint is
  /// not a secret, but it *is* integrity-critical — whoever can write one can
  /// pin their own certificate, after which `buildPinnedHttpClient` accepts
  /// it and every credential sent to that origin is captured. An empty map
  /// deletes the key outright rather than writing `'{}'`, so an install that
  /// never trusts anything never gains a secure-storage entry.
  Future<void> _saveTrustedCertificates(Map<String, String> value) async {
    if (value.isEmpty) {
      await _secureStore.delete(key: _kTrustedCertificates);
      return;
    }
    await _secureStore.write(
      key: _kTrustedCertificates,
      value: jsonEncode(value),
    );
  }

  /// Reads the trust map, migrating ADR-5's two per-service fingerprints
  /// (TrueNAS, Dockge) into ADR-6's origin-keyed map on an existing install.
  ///
  /// [serviceSettings] is the caller's already-loaded URLs — reused rather
  /// than re-read, since resolving a legacy fingerprint to an origin needs
  /// that service's saved URL. A legacy fingerprint whose URL is empty or
  /// unparseable as a TLS origin cannot be placed anywhere and is dropped;
  /// the user re-trusts on next connect (accepted in ADR-6, not a bug).
  /// Migration writes the new key and removes both legacy ones so it runs
  /// exactly once per install.
  Future<Map<String, String>> _loadTrustedCertificates(
    Map<ServiceKey, (String, String)> serviceSettings,
  ) async {
    final stored = await _loadApiKey(_kTrustedCertificates);
    if (stored.isNotEmpty) {
      try {
        final decoded = jsonDecode(stored) as Map<String, dynamic>;
        return decoded.map(
          (origin, fingerprint) => MapEntry(origin, fingerprint as String),
        );
      } catch (_) {
        // A future build's shape, or a hand-edited value — treated as no
        // trusted certificates rather than crashing startup.
        return {};
      }
    }

    const legacyKeysByService = {
      ServiceKey.truenas: _legacyTrueNasCertFingerprint,
      ServiceKey.dockge: _legacyDockgeCertFingerprint,
    };
    final migrated = <String, String>{};
    var foundLegacy = false;

    for (final entry in legacyKeysByService.entries) {
      final fingerprint = await _loadLegacyCertFingerprint(entry.value);
      if (fingerprint.isEmpty) continue;
      foundLegacy = true;

      final url = serviceSettings[entry.key]?.$1 ?? '';
      final origin = UrlUtils.certOrigin(url);
      if (origin != null) migrated[origin] = fingerprint;
    }

    if (foundLegacy) {
      await _saveTrustedCertificates(migrated);
      await _secureStore.delete(key: _legacyTrueNasCertFingerprint);
      await _secureStore.delete(key: _legacyDockgeCertFingerprint);
      await _prefs.remove(_legacyTrueNasCertFingerprint);
      await _prefs.remove(_legacyDockgeCertFingerprint);
    }

    return migrated;
  }

  /// Mirrors ADR-5's `_loadCertFingerprint` prefs→secure fallback, kept only
  /// so [_loadTrustedCertificates] can migrate a value an older build may
  /// have left in either store.
  Future<String> _loadLegacyCertFingerprint(String key) async {
    final secure = await _loadApiKey(key);
    if (secure.isNotEmpty) return secure;
    return _prefs.getString(key)?.trim() ?? '';
  }

  /// The only services whose stored scheme-less URL ever meant `http://`.
  ///
  /// Both clients prepended `http://` to a scheme-less address until 9128220
  /// ("default qBittorrent/Dockge to TLS") changed them to `https://`. Every
  /// other service either always resolved a scheme-less value to `https://`
  /// (SABnzbd, NZBGet, Unraid, TrueNAS — all shipped with the https default) or
  /// never worked without a scheme at all: the \*arrs go through `ApiClient`,
  /// which handed the raw value to `BaseOptions.baseUrl`, and Dio's own setter
  /// throws `ArgumentError` on `sonarr.lan:8989`.
  ///
  /// So this set is the exact blast radius of that one commit, and it is what
  /// keeps [_schemeQualified] from being a downgrade — see its doc.
  static const Set<ServiceKey> _cleartextByDefaultBeforeTls = {
    ServiceKey.qbittorrent,
    ServiceKey.dockge,
  };

  /// One-shot migration for a stored service URL saved before addresses were
  /// normalised on the way in — returns the rewritten value, or null when there
  /// is nothing to migrate.
  ///
  /// Older builds wrote the address field verbatim, and qBittorrent's own field
  /// had no validator at all, so a perfectly working install can hold
  /// `192.168.1.5:8080`. Nothing writes such a value any more: both the settings
  /// form and onboarding run [UrlUtils.normalizeBaseUrl] before saving, so a
  /// scheme-less value in storage is by definition pre-normalisation data.
  ///
  /// It is rewritten to **`http://`**, and only for
  /// [_cleartextByDefaultBeforeTls]. The direction is the whole point of the
  /// migration for those two: their clients prepended `http://` themselves, so
  /// the stored value ran over cleartext, and once the app-wide rule became
  /// `https://` that same value silently started meaning a different address and
  /// died in the TLS handshake with no fallback. Writing the scheme the config
  /// actually ran on preserves what the user set up, and the settings form warns
  /// about cleartext to a non-local host if they ever open it.
  ///
  /// Applying it to every service was the bug this scoping fixes: for everything
  /// else a scheme-less value has always resolved to `https://`, so rewriting it
  /// destroyed a working TLS config — sending the TrueNAS API key over `ws://`
  /// and the Dockge login over cleartext, and orphaning the origin's trusted
  /// certificate, since [UrlUtils.certOrigin] returns null for an `http://` URL
  /// and the pin is stored under `https://host:443`.
  ///
  /// Returns null — leaving the value untouched — when the service is not one of
  /// the two, when the URL already carries a scheme, is empty, or does not
  /// resolve to a host once one is added, since there is then no working
  /// configuration to preserve.
  static String? _schemeQualified(ServiceKey service, String url) {
    if (!_cleartextByDefaultBeforeTls.contains(service)) return null;
    return _httpQualified(url);
  }

  static String? _httpQualified(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    // The same "has a scheme" test the clients apply, and deliberately not a
    // general scheme regex: `sonarr.lan:8989` matches one of those, which is the
    // whole reason a host and a scheme cannot be told apart by the colon alone.
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)) {
      return null;
    }
    // Some other scheme entirely — never a working Cupola address, and not
    // this migration's business to rewrite.
    if (trimmed.contains('://')) return null;

    final candidate = 'http://$trimmed';
    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.host.isEmpty) return null;
    return candidate;
  }

  Future<Map<ServiceKey, (String, String)>> _loadServiceSettings() async {
    final settingsByService = <ServiceKey, (String, String)>{};

    for (final service in ServiceKey.values) {
      final storageKeys = _serviceStorageKeys[service]!;

      // Load URL, falling back to legacy key if the new key is empty.
      var url = _loadString(storageKeys.url);
      if (url.isEmpty && storageKeys.legacyUrl != null) {
        url = _loadString(storageKeys.legacyUrl!);
      }

      final schemed = _schemeQualified(service, url);
      if (schemed != null) {
        url = schemed;
        // Written back so the rewrite happens once rather than on every load,
        // the same one-shot shape `_loadTrustedCertificates` uses for ADR-5's
        // fingerprints. `_saveServiceUrls` would eventually persist it too, but
        // only if the user saves something — and a config that has stopped
        // connecting is exactly the one nobody opens settings for.
        await _prefs.setString(storageKeys.url, url);
      }

      // Load the credential, falling back to the legacy secure key.
      //
      // One read per service, whatever the auth model: a credential-
      // authenticated service keeps its *password* under `secureApiKey`, which
      // is exactly what `SettingsModel.apiKeyFor` returns for it. Special-casing
      // those three here was a third copy of a decision the registry already
      // owns, and it bought nothing — the read it skipped had to happen in
      // `loadSettings` instead.
      var apiKey = await _loadApiKey(storageKeys.secureApiKey);
      if (apiKey.isEmpty && storageKeys.legacySecureApiKey != null) {
        apiKey = await _loadApiKey(storageKeys.legacySecureApiKey!);
      }

      settingsByService[service] = (url, apiKey);
    }

    return settingsByService;
  }

  Future<void> _saveServiceUrls(SettingsModel settings) async {
    for (final service in ServiceKey.values) {
      final storageKeys = _serviceStorageKeys[service]!;
      await _prefs.setString(storageKeys.url, settings.urlFor(service));

      // Remove legacy URL key after writing to the new key.
      if (storageKeys.legacyUrl != null) {
        await _prefs.remove(storageKeys.legacyUrl!);
      }
    }
  }

  Future<void> _saveServiceApiKeys(SettingsModel settings) async {
    for (final service in ServiceKey.values) {
      final storageKeys = _serviceStorageKeys[service]!;
      // `apiKeyFor` already resolves to the password for a credential-
      // authenticated service (that is what the generic credential slot is
      // for), so there is one branch here rather than one per such service.
      await _saveApiKey(storageKeys.secureApiKey, settings.apiKeyFor(service));

      // Remove legacy secure API key after writing to the new key.
      if (storageKeys.legacySecureApiKey != null) {
        await _secureStore.delete(key: storageKeys.legacySecureApiKey!);
      }
    }
  }

  String _loadString(String key) {
    return _prefs.getString(key) ?? '';
  }

  String _loadRegion() {
    return SettingsModel.normalizeRegion(
      _prefs.getString(_kRegion) ??
          PlatformDispatcher.instance.locale.countryCode,
    );
  }

  Future<String> _loadApiKey(String key) async {
    return await _secureStore.read(key: key) ?? '';
  }

  Future<void> _saveApiKey(String key, String value) async {
    final normalizedValue = value.trim();

    if (normalizedValue.isEmpty) {
      await _secureStore.delete(key: key);
      return;
    }

    await _secureStore.write(key: key, value: normalizedValue);
  }
}

class _ServiceStorageKeys {
  final String url;
  final String legacyApiKey;
  final String secureApiKey;

  /// Legacy URL key for backward compatibility (Jellyseerr → Seerr rename).
  final String? legacyUrl;

  /// Legacy plaintext API key from before the rename.
  final String? legacyPlaintextApiKey;

  /// Legacy secure API key from before the rename.
  final String? legacySecureApiKey;

  /// Prefs key for the username (used by qBittorrent and Dockge).
  final String? username;

  /// Prefs key for the chosen viewer's user id (Jellyfin).
  ///
  /// A selection, not a credential: it says whose watch state the library reads
  /// through. Changes whenever the user picks a different household member.
  final String? userId;

  /// Prefs key for the persisted per-install client identifier (Plex).
  ///
  /// Machine-generated exactly once and then immutable — the opposite lifecycle
  /// to [userId]. Regenerating it registers a new device against the user's
  /// server, so it must survive every launch, update and settings edit.
  final String? clientId;

  const _ServiceStorageKeys({
    required this.url,
    required this.legacyApiKey,
    required this.secureApiKey,
    this.legacyUrl,
    this.legacyPlaintextApiKey,
    this.legacySecureApiKey,
    this.username,
    this.userId,
    this.clientId,
  });
}
