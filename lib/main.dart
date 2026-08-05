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
      // Leading is tightened at the top of the ramp (displayLarge sits at 1.06)
      // and opened at the bottom (bodyLarge at 1.55). Both ends need this, in
      // opposite directions, and one behaviour covers them:
      //
      // - A line box shorter than the glyph's ink lets the ink escape it. Inter
      //   needs its full 1.21em to contain an accented capital, so at 1.06 the
      //   acute on `Ý` pokes out the top — and media titles arrive from TMDB in
      //   every language. Inside anything that clips (the detail hero clips by
      //   design) that is a shaved accent.
      // - Extra leading below the last line is padding nobody asked for, and it
      //   would have pushed every fixed-height box in the app out by a couple of
      //   points, since those constants encode a measured line at the old 1.21.
      //
      // Declining to apply the height to the block's outer ascent and descent
      // fixes both: the *gaps between* lines carry the leading decision, while
      // the block's edges keep the font's natural metrics. Prose gets its air,
      // display type stays tight, single-line chrome measures exactly what it
      // measured before, and nothing clips.
      builder: (context, child) => DefaultTextHeightBehavior(
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: false,
          applyHeightToLastDescent: false,
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
