import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/core/router.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/release_search/data/release_search_transport.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final secureSettingsStore = createSecureSettingsStore();
  final settingsService = SettingsService(prefs, secureSettingsStore);

  await _configureBackgroundSearch();

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
      child: const CupolaApp(),
    ),
  );
}

/// Two library defaults that are actively wrong for a release search.
///
/// **`requestTimeout`** is the one that decides whether Phase 2 works at all. It
/// defaults to 60 seconds and measures the gap *between received bytes* — and our
/// request is the pathological case, because the server sends nothing while it
/// queries indexers. Left alone, every search over a minute would fail on iOS. It
/// can only be set **once, before the first task is enqueued**, which is why it
/// lives here rather than beside the setting it relates to: the library's ceiling
/// is infrastructure, and the user's own timeout always sits below it.
///
/// **`resourceTimeout`** is the only ceiling that still applies while the app is
/// suspended, when no Dart timer can fire — so it is what actually bounds the
/// life of a task whose headers carry the service's API key, and the plugin
/// keeps that task record in plaintext (Android `taskMap`, iOS `UserDefaults`)
/// until it reaches a final state. An hour let a credential-bearing task outlive
/// the user's own ceiling by ~50 minutes for no benefit: nothing here ever
/// downloads a large file, only a JSON release list. It is set to the longest
/// search the settings screen permits plus a grace, so the backstop sits just
/// above the user's maximum instead of far beyond it.
///
/// **`doRescheduleKilledTasks`** would silently re-issue a task the OS killed —
/// re-running a full search against the user's indexers with nobody watching. A
/// killed search surfaces as a state to retry by hand instead.
Future<void> _configureBackgroundSearch() async {
  if (!backgroundSearchSupported()) return;
  try {
    await FileDownloader().configure(
      globalConfig: [
        (Config.requestTimeout, const Duration(minutes: 15)),
        (Config.resourceTimeout, kBackgroundSearchResourceTimeout),
      ],
    );
    await FileDownloader().start(doRescheduleKilledTasks: false);
  } catch (_) {
    // A platform without the plugin still runs the foreground path, which is the
    // whole point of keeping the transport behind an interface.
  }
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

class CupolaApp extends ConsumerWidget {
  const CupolaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    // Keeps `CertTrustRegistry` in sync for the leaf image widgets that
    // cannot watch a provider themselves — see its doc for why. The `read`
    // populates the snapshot before the first poster ever asks (`listen`
    // alone only fires on a *change*); `listen`, registered every build per
    // the standard `ref.listen` idiom, keeps it current after that.
    CertTrustRegistry.update(
      ref.read(currentSettingsProvider).trustedCertificates,
    );
    ref.listen(
      currentSettingsProvider.select((s) => s.trustedCertificates),
      (previous, next) => CertTrustRegistry.update(next),
    );

    // No DynamicColorBuilder: the palette is fixed on purpose so per-service
    // accents stay recognisable and the experience is identical on every OS.
    // See AppTheme.darkTheme.
    return MaterialApp.router(
      title: 'Cupola',
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
