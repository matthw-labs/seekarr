import 'dart:ui';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:seekarr/features/settings/domain/settings_model.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

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
    ServiceKey.bazarr: _ServiceStorageKeys(
      url: 'bazarr_url',
      legacyApiKey: '',
      secureApiKey: 'secure_bazarr_api_key',
    ),
    ServiceKey.truenas: _ServiceStorageKeys(
      url: 'truenas_url',
      legacyApiKey: '',
      secureApiKey: 'secure_truenas_api_key',
      certFingerprint: 'truenas_cert_fingerprint',
    ),
    ServiceKey.dockge: _ServiceStorageKeys(
      url: 'dockge_url',
      legacyApiKey: '',
      secureApiKey: 'secure_dockge_password',
      username: 'dockge_username',
      certFingerprint: 'dockge_cert_fingerprint',
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

  /// Wipes all Seekarr-persisted data: SharedPreferences keys (service URLs,
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
      if (storageKeys.certFingerprint != null) {
        await _prefs.remove(storageKeys.certFingerprint!);
      }
    }

    await _prefs.remove(_kRegion);
    await _prefs.remove(_kThemeMode);
    await _prefs.remove(_kOnboardingComplete);
    await _prefs.remove('hidden_tabs');
  }

  Future<SettingsModel> loadSettings() async {
    final serviceSettings = await _loadServiceSettings();
    final qbKeys = _serviceStorageKeys[ServiceKey.qbittorrent]!;
    final qbUsername = _prefs.getString(qbKeys.username!) ?? '';
    final qbPassword = await _loadApiKey(qbKeys.secureApiKey);
    final dockgeKeys = _serviceStorageKeys[ServiceKey.dockge]!;
    final dockgeUsername = _prefs.getString(dockgeKeys.username!) ?? '';
    final dockgePassword = await _loadApiKey(dockgeKeys.secureApiKey);
    final nzbgetKeys = _serviceStorageKeys[ServiceKey.nzbget]!;
    final nzbgetUsername = _prefs.getString(nzbgetKeys.username!) ?? '';
    final nzbgetPassword = await _loadApiKey(nzbgetKeys.secureApiKey);
    final truenasKeys = _serviceStorageKeys[ServiceKey.truenas]!;

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
      qbittorrentUsername: qbUsername,
      qbittorrentPassword: qbPassword,
      bazarrUrl: serviceSettings[ServiceKey.bazarr]!.$1,
      bazarrApiKey: serviceSettings[ServiceKey.bazarr]!.$2,
      truenasUrl: serviceSettings[ServiceKey.truenas]!.$1,
      truenasApiKey: serviceSettings[ServiceKey.truenas]!.$2,
      dockgeUrl: serviceSettings[ServiceKey.dockge]!.$1,
      dockgeUsername: dockgeUsername,
      dockgePassword: dockgePassword,
      prowlarrUrl: serviceSettings[ServiceKey.prowlarr]!.$1,
      prowlarrApiKey: serviceSettings[ServiceKey.prowlarr]!.$2,
      readarrUrl: serviceSettings[ServiceKey.readarr]!.$1,
      readarrApiKey: serviceSettings[ServiceKey.readarr]!.$2,
      sabnzbdUrl: serviceSettings[ServiceKey.sabnzbd]!.$1,
      sabnzbdApiKey: serviceSettings[ServiceKey.sabnzbd]!.$2,
      nzbgetUrl: serviceSettings[ServiceKey.nzbget]!.$1,
      nzbgetUsername: nzbgetUsername,
      nzbgetPassword: nzbgetPassword,
      unraidUrl: serviceSettings[ServiceKey.unraid]!.$1,
      unraidApiKey: serviceSettings[ServiceKey.unraid]!.$2,
      truenasCertFingerprint:
          _prefs.getString(truenasKeys.certFingerprint!) ?? '',
      dockgeCertFingerprint:
          _prefs.getString(dockgeKeys.certFingerprint!) ?? '',
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

    final qbKeys = _serviceStorageKeys[ServiceKey.qbittorrent]!;
    if (settings.qbittorrentUsername.isNotEmpty) {
      await _prefs.setString(qbKeys.username!, settings.qbittorrentUsername);
    } else {
      await _prefs.remove(qbKeys.username!);
    }

    final dockgeKeys = _serviceStorageKeys[ServiceKey.dockge]!;
    if (settings.dockgeUsername.isNotEmpty) {
      await _prefs.setString(dockgeKeys.username!, settings.dockgeUsername);
    } else {
      await _prefs.remove(dockgeKeys.username!);
    }

    final nzbgetKeys = _serviceStorageKeys[ServiceKey.nzbget]!;
    if (settings.nzbgetUsername.isNotEmpty) {
      await _prefs.setString(nzbgetKeys.username!, settings.nzbgetUsername);
    } else {
      await _prefs.remove(nzbgetKeys.username!);
    }

    await _saveCertFingerprint(
      ServiceKey.truenas,
      settings.truenasCertFingerprint,
    );
    await _saveCertFingerprint(
      ServiceKey.dockge,
      settings.dockgeCertFingerprint,
    );
  }

  Future<void> _saveCertFingerprint(ServiceKey service, String value) async {
    final key = _serviceStorageKeys[service]!.certFingerprint;
    if (key == null) return;
    final normalized = value.trim();
    if (normalized.isEmpty) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, normalized);
    }
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

      // Load API key, falling back to legacy secure key.
      // qBittorrent and Dockge use username/password instead of an API key, so
      // their secure keys are loaded separately in loadSettings() to avoid a
      // second secure store read here.
      var apiKey = '';
      if (service != ServiceKey.qbittorrent &&
          service != ServiceKey.dockge &&
          service != ServiceKey.nzbget) {
        apiKey = await _loadApiKey(storageKeys.secureApiKey);
        if (apiKey.isEmpty && storageKeys.legacySecureApiKey != null) {
          apiKey = await _loadApiKey(storageKeys.legacySecureApiKey!);
        }
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
      if (service == ServiceKey.qbittorrent) {
        await _saveApiKey(
          storageKeys.secureApiKey,
          settings.qbittorrentPassword,
        );
        continue;
      }
      if (service == ServiceKey.dockge) {
        await _saveApiKey(storageKeys.secureApiKey, settings.dockgePassword);
        continue;
      }
      if (service == ServiceKey.nzbget) {
        await _saveApiKey(storageKeys.secureApiKey, settings.nzbgetPassword);
        continue;
      }
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

  /// Prefs key for a trusted self-signed cert fingerprint (TrueNAS, Dockge).
  /// Not a secret, so kept in SharedPreferences rather than secure storage.
  final String? certFingerprint;

  const _ServiceStorageKeys({
    required this.url,
    required this.legacyApiKey,
    required this.secureApiKey,
    this.legacyUrl,
    this.legacyPlaintextApiKey,
    this.legacySecureApiKey,
    this.username,
    this.certFingerprint,
  });
}
