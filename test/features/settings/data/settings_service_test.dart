import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:seekarr/features/settings/data/settings_service.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

void main() {
  group('SettingsService', () {
    late SharedPreferences prefs;
    late FakeSecureSettingsStore secureStore;
    late SettingsService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      secureStore = FakeSecureSettingsStore();
      service = SettingsService(prefs, secureStore);
    });

    test('migrateFromPlaintext moves keys to secure storage', () async {
      await prefs.setString('jellyseerr_api_key', 'jelly-key');
      await prefs.setString('radarr_api_key', 'radarr-key');
      await prefs.setString('sonarr_api_key', 'sonarr-key');
      await prefs.setString('lidarr_api_key', 'lidarr-key');

      await service.migrateFromPlaintext();

      expect(await secureStore.read(key: 'secure_seerr_api_key'), 'jelly-key');
      expect(
        await secureStore.read(key: 'secure_radarr_api_key'),
        'radarr-key',
      );
      expect(
        await secureStore.read(key: 'secure_sonarr_api_key'),
        'sonarr-key',
      );
      expect(
        await secureStore.read(key: 'secure_lidarr_api_key'),
        'lidarr-key',
      );

      expect(prefs.getString('jellyseerr_api_key'), isNull);
      expect(prefs.getString('radarr_api_key'), isNull);
      expect(prefs.getString('sonarr_api_key'), isNull);
      expect(prefs.getString('lidarr_api_key'), isNull);
    });

    test('migrateFromPlaintext is idempotent', () async {
      await prefs.setString('radarr_api_key', 'radarr-key');

      await service.migrateFromPlaintext();
      await service.migrateFromPlaintext();

      expect(
        await secureStore.read(key: 'secure_radarr_api_key'),
        'radarr-key',
      );
      expect(prefs.getString('radarr_api_key'), isNull);
    });

    test('migrateFromPlaintext skips empty keys', () async {
      await prefs.setString('radarr_api_key', '   ');

      await service.migrateFromPlaintext();

      expect(await secureStore.read(key: 'secure_radarr_api_key'), isNull);
      expect(prefs.getString('radarr_api_key'), isNull);
    });

    test('migrateFromPlaintext preserves existing secure seerr key', () async {
      await secureStore.write(
        key: 'secure_seerr_api_key',
        value: 'existing-seerr-key',
      );
      await prefs.setString('jellyseerr_api_key', 'legacy-jellyseerr-key');

      await service.migrateFromPlaintext();

      expect(
        await secureStore.read(key: 'secure_seerr_api_key'),
        'existing-seerr-key',
      );
      expect(prefs.getString('jellyseerr_api_key'), isNull);
    });

    test('saveSettings and loadSettings round-trip', () async {
      const settings = SettingsModel(
        seerrUrl: 'https://jelly.example.com',
        seerrApiKey: 'jelly-key',
        radarrUrl: 'https://radarr.example.com',
        radarrApiKey: 'radarr-key',
        sonarrUrl: 'https://sonarr.example.com',
        sonarrApiKey: 'sonarr-key',
        lidarrUrl: 'https://lidarr.example.com',
        lidarrApiKey: 'lidarr-key',
        bazarrUrl: 'https://bazarr.example.com',
        bazarrApiKey: 'bazarr-key',
        region: 'IT',
        themeMode: AppThemeMode.dark,
      );

      await service.saveSettings(settings);

      final loaded = await service.loadSettings();

      expect(loaded.seerrUrl, settings.seerrUrl);
      expect(loaded.seerrApiKey, settings.seerrApiKey);
      expect(loaded.radarrUrl, settings.radarrUrl);
      expect(loaded.radarrApiKey, settings.radarrApiKey);
      expect(loaded.sonarrUrl, settings.sonarrUrl);
      expect(loaded.sonarrApiKey, settings.sonarrApiKey);
      expect(loaded.lidarrUrl, settings.lidarrUrl);
      expect(loaded.lidarrApiKey, settings.lidarrApiKey);
      expect(loaded.bazarrUrl, settings.bazarrUrl);
      expect(loaded.bazarrApiKey, settings.bazarrApiKey);
      expect(loaded.region, settings.region);
      expect(loaded.themeMode, settings.themeMode);
    });

    test('loadSettings returns empty defaults on fresh storage', () async {
      final loaded = await service.loadSettings();

      expect(loaded.seerrUrl, isEmpty);
      expect(loaded.seerrApiKey, isEmpty);
      expect(loaded.radarrUrl, isEmpty);
      expect(loaded.radarrApiKey, isEmpty);
      expect(loaded.sonarrUrl, isEmpty);
      expect(loaded.sonarrApiKey, isEmpty);
      expect(loaded.lidarrUrl, isEmpty);
      expect(loaded.lidarrApiKey, isEmpty);
      expect(loaded.bazarrUrl, isEmpty);
      expect(loaded.bazarrApiKey, isEmpty);
      expect(loaded.themeMode, AppThemeMode.system);
    });

    test('loadSettings reads Bazarr API key from secure storage', () async {
      await prefs.setString('bazarr_url', 'https://bazarr.example.com');
      await secureStore.write(
        key: 'secure_bazarr_api_key',
        value: 'bazarr-key',
      );

      final loaded = await service.loadSettings();

      expect(loaded.bazarrUrl, 'https://bazarr.example.com');
      expect(loaded.bazarrApiKey, 'bazarr-key');
    });

    test('loadSettings falls back to legacy Jellyseerr keys', () async {
      await prefs.setString('jellyseerr_url', 'https://legacy.example.com');
      await secureStore.write(
        key: 'secure_jellyseerr_api_key',
        value: 'legacy-seerr-key',
      );

      final loaded = await service.loadSettings();

      expect(loaded.seerrUrl, 'https://legacy.example.com');
      expect(loaded.seerrApiKey, 'legacy-seerr-key');
    });

    test('saveSettings removes secure keys when values are empty', () async {
      const populatedSettings = SettingsModel(radarrApiKey: 'radarr-key');
      const clearedSettings = SettingsModel();

      await service.saveSettings(populatedSettings);
      await service.saveSettings(clearedSettings);

      expect(await secureStore.read(key: 'secure_radarr_api_key'), isNull);
    });

    test('saveOnboardingComplete persists the onboarding flag', () async {
      expect(await service.loadOnboardingComplete(), isFalse);

      await service.saveOnboardingComplete();

      expect(await service.loadOnboardingComplete(), isTrue);
    });
  });
}
