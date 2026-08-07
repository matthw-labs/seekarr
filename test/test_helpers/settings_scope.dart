import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import 'fake_secure_settings_store.dart';

/// The pieces needed to make `settingsProvider` readable in a test.
///
/// `sharedPreferencesProvider` and `initialSettingsProvider` throw unless
/// overridden (they are wired in `main.dart`), and `SettingsNotifier.build`
/// watches both — so any screen that asks `settings.isServiceConfigured(...)`
/// needs all of this. The Activity screen does, because it distinguishes "this
/// service is not set up" from "this service did not answer".
///
/// Returned as a record rather than a ready-made override list because
/// `flutter_riverpod` 3.x does not export the `Override` type, so a helper
/// cannot name it. Spread the four lines at the call site:
///
/// ```dart
/// final scope = await settingsScope(configured: activityServiceKeys);
/// ProviderScope(
///   overrides: [
///     sharedPreferencesProvider.overrideWith((ref) => scope.prefs),
///     secureSettingsStoreProvider.overrideWith((ref) => scope.secureStore),
///     initialSettingsProvider.overrideWith((ref) => scope.settings),
///     initialOnboardingCompletedProvider.overrideWith((ref) => true),
///     // …the test's own overrides
///   ],
/// );
/// ```
typedef SettingsScope = ({
  SharedPreferences prefs,
  SecureSettingsStore secureStore,
  SettingsModel settings,
});

Future<SettingsScope> settingsScope({
  List<ServiceKey> configured = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  return (
    prefs: prefs,
    secureStore: FakeSecureSettingsStore(),
    settings: settingsWithServices(configured),
  );
}

/// A [SettingsModel] where each of [configured] has both a URL and an API key,
/// which is what `isServiceConfigured` requires for the API-key services.
SettingsModel settingsWithServices(List<ServiceKey> configured) {
  var settings = const SettingsModel();

  for (final service in configured) {
    final url = 'https://${service.name}.test';
    final key = '${service.name}-key';
    settings = switch (service) {
      ServiceKey.seerr => settings.copyWith(seerrUrl: url, seerrApiKey: key),
      ServiceKey.radarr => settings.copyWith(radarrUrl: url, radarrApiKey: key),
      ServiceKey.sonarr => settings.copyWith(sonarrUrl: url, sonarrApiKey: key),
      ServiceKey.lidarr => settings.copyWith(lidarrUrl: url, lidarrApiKey: key),
      _ => settings,
    };
  }

  return settings;
}

/// The four services that can appear in the global Activity feed.
const activityServiceKeys = [
  ServiceKey.radarr,
  ServiceKey.sonarr,
  ServiceKey.lidarr,
  ServiceKey.seerr,
];
