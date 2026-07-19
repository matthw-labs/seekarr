import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/features/onboarding/data/onboarding_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/data/settings_service.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';
import 'package:seekarr/features/settings/presentation/settings_home_screen.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

void main() {
  group('SettingsHomeScreen', () {
    testWidgets('renders the main settings sections', (tester) async {
      await _pumpSettingsHome(tester);

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('GENERAL'), findsOneWidget);
      expect(find.text('SERVICES'), findsNothing);
      expect(find.text('ABOUT'), findsOneWidget);
      expect(find.text('Seekarr v1.0.0'), findsNothing);
    });

    testWidgets('formats the selected region label', (tester) async {
      await _pumpSettingsHome(
        tester,
        settings: const SettingsModel(region: 'gb'),
      );

      expect(find.text('United Kingdom (GB)'), findsOneWidget);
    });

    testWidgets('dashboard navigates to the services settings screen', (
      tester,
    ) async {
      await _pumpSettingsHome(tester);

      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();

      expect(find.text('ServicesPage'), findsOneWidget);
    });

    testWidgets('shows configured services on the home screen', (tester) async {
      await _pumpSettingsHome(
        tester,
        settings: const SettingsModel(
          radarrUrl: 'https://radarr.local:7878',
          radarrApiKey: 'radarr-key',
        ),
      );

      expect(find.text('SERVICES'), findsOneWidget);
      expect(
        _settingsCard('Radarr', subtitle: 'radarr.local:7878'),
        findsOneWidget,
      );
      expect(find.text('radarr.local:7878'), findsOneWidget);
    });

    testWidgets('tapping Region navigates to the region screen', (
      tester,
    ) async {
      await _pumpSettingsHome(tester);

      await tester.tap(find.text('Region'));
      await tester.pumpAndSettle();

      expect(find.text('RegionPage'), findsOneWidget);
    });

    testWidgets('tapping a service card navigates to its route', (
      tester,
    ) async {
      await _pumpSettingsHome(
        tester,
        settings: const SettingsModel(
          radarrUrl: 'https://radarr.local:7878',
          radarrApiKey: 'radarr-key',
        ),
      );

      await tester.tap(find.text('Radarr'));
      await tester.pumpAndSettle();

      expect(find.text('ServicePage:radarr'), findsOneWidget);
    });

    testWidgets('Share App shows the coming soon snackbar', (tester) async {
      await _pumpSettingsHome(tester);

      await tester.scrollUntilVisible(find.text('Share App'), 300);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Share App'));
      await tester.pumpAndSettle();

      expect(find.text('Coming soon!'), findsOneWidget);
    });

    testWidgets('renders tappable settings cards', (tester) async {
      await _pumpSettingsHome(tester);

      expect(find.byType(SettingsCard), findsAtLeastNWidgets(6));
      expect(find.byType(SettingsGroupCard), findsNWidgets(3));

      await tester.scrollUntilVisible(find.text('Send Feedback'), 300);
      await tester.pumpAndSettle();

      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('Send Feedback'), findsOneWidget);
    });

    testWidgets('reset tile shows Danger Zone section', (tester) async {
      await _pumpSettingsHome(tester);

      await tester.scrollUntilVisible(find.text('DANGER ZONE'), 300);
      await tester.pumpAndSettle();

      expect(find.text('DANGER ZONE'), findsOneWidget);
      expect(find.text('Reset app data'), findsOneWidget);
    });

    testWidgets('confirming reset clears data and restarts onboarding', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final secureStore = FakeSecureSettingsStore();
      final service = SettingsService(prefs, secureStore);
      await service.saveSettings(
        const SettingsModel(
          radarrUrl: 'https://radarr.local:7878',
          radarrApiKey: 'radarr-key',
          region: 'IT',
          themeMode: AppThemeMode.dark,
        ),
      );
      await service.saveOnboardingComplete();
      final initialSettings = await service.loadSettings();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => prefs),
          secureSettingsStoreProvider.overrideWith((ref) => secureStore),
          initialSettingsProvider.overrideWith((ref) => initialSettings),
          initialOnboardingCompletedProvider.overrideWith((ref) => true),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(settingsProvider).radarrUrl,
        'https://radarr.local:7878',
      );
      expect(container.read(onboardingCompletedProvider), isTrue);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: GoRouter(
              initialLocation: '/settings',
              routes: [
                GoRoute(
                  path: '/settings',
                  builder: (_, __) => const SettingsHomeScreen(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Reset app data'), 300);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset app data'));
      await tester.pumpAndSettle();

      expect(find.text('Reset all data?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
      await tester.pumpAndSettle();

      expect(container.read(settingsProvider).radarrUrl, isEmpty);
      expect(container.read(settingsProvider).radarrApiKey, isEmpty);
      expect(container.read(settingsProvider).themeMode, AppThemeMode.system);
      expect(container.read(onboardingCompletedProvider), isFalse);
      expect(await secureStore.read(key: 'secure_radarr_api_key'), isNull);
    });

    testWidgets('canceling reset keeps data intact', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final secureStore = FakeSecureSettingsStore();
      final service = SettingsService(prefs, secureStore);
      await service.saveSettings(
        const SettingsModel(radarrUrl: 'https://radarr.local:7878'),
      );
      await service.saveOnboardingComplete();
      final initialSettings = await service.loadSettings();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => prefs),
          secureSettingsStoreProvider.overrideWith((ref) => secureStore),
          initialSettingsProvider.overrideWith((ref) => initialSettings),
          initialOnboardingCompletedProvider.overrideWith((ref) => true),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: GoRouter(
              initialLocation: '/settings',
              routes: [
                GoRoute(
                  path: '/settings',
                  builder: (_, __) => const SettingsHomeScreen(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Reset app data'), 300);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset app data'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Reset all data?'), findsNothing);
      expect(
        container.read(settingsProvider).radarrUrl,
        'https://radarr.local:7878',
      );
      expect(container.read(onboardingCompletedProvider), isTrue);
    });
  });
}

Future<void> _pumpSettingsHome(
  WidgetTester tester, {
  SettingsModel settings = const SettingsModel(),
}) async {
  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(
        path: '/settings',
        builder: (_, __) => const SettingsHomeScreen(),
        routes: [
          GoRoute(
            path: 'region',
            builder: (_, __) => const Scaffold(body: Text('RegionPage')),
          ),
          GoRoute(
            path: 'services',
            builder: (_, __) => const Scaffold(body: Text('ServicesPage')),
          ),
          GoRoute(
            path: 'service/:service',
            builder: (context, state) {
              final service = state.pathParameters['service'] ?? 'unknown';
              return Scaffold(body: Text('ServicePage:$service'));
            },
          ),
        ],
      ),
    ],
  );

  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [currentSettingsProvider.overrideWith((ref) => settings)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _settingsCard(String title, {String? subtitle}) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is SettingsCard &&
        widget.title == title &&
        (subtitle == null || widget.subtitle == subtitle),
    skipOffstage: false,
  );
}
