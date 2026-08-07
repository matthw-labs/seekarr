import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/settings_home_screen.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

void main() {
  group('SettingsHomeScreen', () {
    testWidgets('renders the main settings sections', (tester) async {
      await _pumpSettingsHome(tester);

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('CONNECTIONS'), findsOneWidget);
      expect(find.text('GENERAL'), findsOneWidget);
      expect(find.text('ABOUT'), findsOneWidget);
      expect(find.text('Cupola v1.0.0'), findsNothing);
    });

    testWidgets('the connections summary says when nothing is set up', (
      tester,
    ) async {
      await _pumpSettingsHome(tester);

      expect(find.text('No services set up yet'), findsOneWidget);
    });

    testWidgets('the connections summary counts what is set up', (
      tester,
    ) async {
      await _pumpSettingsHome(
        tester,
        settings: const SettingsModel(
          radarrUrl: 'https://radarr.local:7878',
          radarrApiKey: 'radarr-key',
        ),
        diagnosis: const ServiceDiagnosis.connected(),
      );

      expect(find.text('1 service connected'), findsOneWidget);
    });

    testWidgets('healthy services stay off this screen', (tester) async {
      // Thirteen services means a list of the working ones is an inventory
      // nobody reads. Only trouble earns a row here.
      await _pumpSettingsHome(
        tester,
        settings: const SettingsModel(
          radarrUrl: 'https://radarr.local:7878',
          radarrApiKey: 'radarr-key',
          sonarrUrl: 'https://sonarr.local:8989',
          sonarrApiKey: 'sonarr-key',
        ),
        diagnosis: const ServiceDiagnosis.connected(),
      );

      expect(find.text('All 2 connected'), findsOneWidget);
      expect(find.text('Radarr'), findsNothing);
      expect(find.text('Sonarr'), findsNothing);
    });

    testWidgets('a failing service is promoted with its cause', (tester) async {
      await _pumpSettingsHome(
        tester,
        settings: const SettingsModel(
          radarrUrl: 'https://radarr.local:7878',
          radarrApiKey: 'radarr-key',
        ),
        diagnosis: ServiceDiagnosis.failed(_UnauthorizedFailure()),
      );

      expect(find.text('1 of 1 need attention'), findsOneWidget);
      expect(find.text('API key rejected · radarr.local:7878'), findsOneWidget);
    });

    testWidgets('tapping a promoted failure opens that service', (
      tester,
    ) async {
      await _pumpSettingsHome(
        tester,
        settings: const SettingsModel(
          radarrUrl: 'https://radarr.local:7878',
          radarrApiKey: 'radarr-key',
        ),
        diagnosis: ServiceDiagnosis.failed(_UnauthorizedFailure()),
      );

      await tester.tap(find.text('Radarr'));
      await tester.pumpAndSettle();

      expect(find.text('ServicePage:radarr'), findsOneWidget);
    });

    testWidgets('formats the selected region label', (tester) async {
      await _pumpSettingsHome(
        tester,
        settings: const SettingsModel(region: 'gb'),
      );

      expect(find.text('United Kingdom (GB)'), findsOneWidget);
    });

    testWidgets('the summary row opens the connections list', (tester) async {
      await _pumpSettingsHome(tester);

      await tester.tap(find.text('All connections'));
      await tester.pumpAndSettle();

      expect(find.text('ConnectionsPage'), findsOneWidget);
    });

    group('semantics', () {
      testWidgets('a promoted service speaks its connection state', (
        tester,
      ) async {
        // The indicator is a bare glyph — a cloud, a key, a spinner — so
        // without a label for it the connection state is simply unreadable:
        // the subtitle beside it is only the host.
        await _pumpSettingsHome(
          tester,
          settings: const SettingsModel(
            radarrUrl: 'https://radarr.local:7878',
            radarrApiKey: 'radarr-key',
          ),
          diagnosis: const ServiceDiagnosis(
            ServiceConnectionStatus.disconnected,
            ServiceFailureReason.unreachable,
          ),
        );

        expect(
          find.semantics.byLabel('Radarr, Unreachable, radarr.local:7878'),
          containsSemantics(
            isButton: true,
            hasTapAction: true,
            hint: 'opens Radarr settings',
          ),
        );
        // The host used to be its own focus stop.
        expect(find.semantics.byLabel('radarr.local:7878'), findsNothing);
      });

      testWidgets('section labels are headings, read without the caps', (
        tester,
      ) async {
        await _pumpSettingsHome(tester);

        expect(
          find.semantics.byLabel('General'),
          containsSemantics(isHeader: true),
        );
        expect(
          find.semantics.byLabel('Connections'),
          containsSemantics(isHeader: true),
        );
        // '.toUpperCase()' is typography; VoiceOver spells out all-caps tokens.
        expect(find.semantics.byLabel('GENERAL'), findsNothing);
        expect(find.text('GENERAL'), findsOneWidget);
      });
    });

    testWidgets('tapping Region navigates to the region screen', (
      tester,
    ) async {
      await _pumpSettingsHome(tester);

      await tester.tap(find.text('Region'));
      await tester.pumpAndSettle();

      expect(find.text('RegionPage'), findsOneWidget);
    });

    testWidgets('renders tappable settings cards', (tester) async {
      await _pumpSettingsHome(tester);

      expect(find.byType(SettingsCard), findsAtLeastNWidgets(6));
      // Connections, General, About, Danger Zone.
      expect(find.byType(SettingsGroupCard), findsNWidgets(4));

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
  ServiceDiagnosis? diagnosis,
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
            path: 'connections',
            builder: (_, __) => const Scaffold(body: Text('ConnectionsPage')),
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

  // A tall viewport so every section of this lazy ListView is built and
  // counted, independent of scroll position.
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSettingsProvider.overrideWith((ref) => settings),
        if (diagnosis != null)
          serviceDiagnosisProvider.overrideWith((ref, service) async {
            return diagnosis;
          }),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

/// An error that already knows why it failed, the way the service clients do.
class _UnauthorizedFailure implements HasFailureReason {
  @override
  ServiceFailureReason get reason => ServiceFailureReason.unauthorized;
}
