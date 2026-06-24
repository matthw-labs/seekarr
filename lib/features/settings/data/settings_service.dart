import 'dart:ui';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:seekarr/features/settings/domain/settings_model.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

SecureSettingsStore createSecureSettingsStore() {
  return FlutterSecureSettingsStore(
    FlutterSecureStorage(
      // flutter_secure_storage 10.x migrates away from the old
      // encryptedSharedPreferences path. Keep migration enabled for existing
      // installs and write a backup during algorithm upgrades.
      aOptions: AndroidOptions(migrateWithBackup: true),
    ),
  );
}

abstract interface class SecureSettingsStore {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
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

  Future<SettingsModel> loadSettings() async {
    final serviceSettings = await _loadServiceSettings();
    final qbUsername =
        _prefs.getString(
          _serviceStorageKeys[ServiceKey.qbittorrent]!.username!,
        ) ??
        '';
    final qbPassword = await _loadApiKey(
      _serviceStorageKeys[ServiceKey.qbittorrent]!.secureApiKey,
    );

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
      if (service == ServiceKey.qbittorrent) {
        await _saveApiKey(
          storageKeys.secureApiKey,
          settings.qbittorrentPassword,
        );
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

  /// Prefs key for the username (used by qBittorrent).
  final String? username;

  const _ServiceStorageKeys({
    required this.url,
    required this.legacyApiKey,
    required this.secureApiKey,
    this.legacyUrl,
    this.legacyPlaintextApiKey,
    this.legacySecureApiKey,
    this.username,
  });
}
