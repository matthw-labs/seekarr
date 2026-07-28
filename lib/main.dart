import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:seekarr/core/router.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/features/onboarding/data/onboarding_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/data/settings_service.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final secureSettingsStore = createSecureSettingsStore();
  final settingsService = SettingsService(prefs, secureSettingsStore);

  await settingsService.migrateFromPlaintext();
  final initialSettings = await _loadInitialSettings(settingsService);
  final onboardingCompleted = await settingsService.loadOnboardingComplete();

  runApp(
    ProviderScope(
      overrides: _buildProviderOverrides(
        prefs: prefs,
        secureSettingsStore: secureSettingsStore,
        initialSettings: initialSettings,
        onboardingCompleted: onboardingCompleted,
      ),
      child: const SeekarrApp(),
    ),
  );
}

Future<SettingsModel> _loadInitialSettings(SettingsService settingsService) {
  return settingsService.loadSettings();
}

_buildProviderOverrides({
  required SharedPreferences prefs,
  required SecureSettingsStore secureSettingsStore,
  required SettingsModel initialSettings,
  required bool onboardingCompleted,
}) {
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    secureSettingsStoreProvider.overrideWithValue(secureSettingsStore),
    initialSettingsProvider.overrideWithValue(initialSettings),
    initialOnboardingCompletedProvider.overrideWithValue(onboardingCompleted),
  ];
}

class SeekarrApp extends ConsumerWidget {
  const SeekarrApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    // No DynamicColorBuilder: the palette is fixed on purpose so per-service
    // accents stay recognisable and the experience is identical on every OS.
    // See AppTheme.darkTheme.
    return MaterialApp.router(
      title: 'Seekarr',
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
