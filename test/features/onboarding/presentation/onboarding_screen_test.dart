import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:seekarr/features/onboarding/data/onboarding_provider.dart';
import 'package:seekarr/features/onboarding/presentation/onboarding_screen.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

void main() {
  group('OnboardingScreen', () {
    // Mirrors the exact scenarios from issue #4:
    //  "I tried not entering anything, entering everything, and entering
    //   just the Sonarr details and the Continue button never allowed me
    //   to move forward"
    testWidgets('empty form: Welcome → Services → Continue advances to Ready', (
      tester,
    ) async {
      await _pumpOnboarding(tester);

      expect(find.textContaining('Your whole homelab'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Step 2 of 3'), findsOneWidget);

      await _tapServicesContinue(tester);
      await tester.pumpAndSettle();

      expect(find.text('Step 3 of 3'), findsOneWidget);
      // Nothing was configured, so the final step must not congratulate the
      // user on connected services it does not have.
      expect(find.text('Ready when you are.'), findsOneWidget);
      expect(find.textContaining('Nothing is connected yet'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, "Let's go"), findsOneWidget);
    });

    testWidgets(
      'every service enabled: Welcome → Services → Continue advances to Ready',
      (tester) async {
        await _pumpOnboarding(tester);

        await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
        await tester.pumpAndSettle();

        // Enable every toggle.
        for (final title in const ['Seerr', 'Radarr', 'Sonarr', 'Lidarr']) {
          await _enableService(tester, title);
        }
        // Proof the taps landed: tapping the row used to do nothing at all, so
        // this test passed while enabling none of them.
        expect(find.textContaining(' configuration'), findsNWidgets(4));

        await _tapServicesContinue(tester);
        await tester.pumpAndSettle();

        expect(find.text('Step 3 of 3'), findsOneWidget);
      },
    );

    testWidgets(
      'only Sonarr toggled on: Welcome → Services → Continue advances to Ready',
      (tester) async {
        await _pumpOnboarding(tester);

        await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
        await tester.pumpAndSettle();

        await _enableService(tester, 'Sonarr');
        expect(find.text('Sonarr configuration'), findsOneWidget);
        expect(find.textContaining(' configuration'), findsOneWidget);

        await _tapServicesContinue(tester);
        await tester.pumpAndSettle();

        expect(find.text('Step 3 of 3'), findsOneWidget);
      },
    );

    testWidgets('Ready step: Review settings returns to Services step', (
      tester,
    ) async {
      await _pumpOnboarding(tester);

      // Advance to Ready step.
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();
      await _tapServicesContinue(tester);
      await tester.pumpAndSettle();

      expect(find.text('Step 3 of 3'), findsOneWidget);

      // "Review settings" should go back to Services, not finish onboarding.
      await tester.tap(find.widgetWithText(OutlinedButton, 'Review settings'));
      await tester.pumpAndSettle();

      expect(find.text('Step 2 of 3'), findsOneWidget);
      expect(find.text('Step 3 of 3'), findsNothing);
    });

    testWidgets('Verify with an empty form reports Incomplete, not Unreachable', (
      tester,
    ) async {
      await _pumpOnboarding(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();
      await _enableService(tester, 'Sonarr');

      await tester.ensureVisible(find.text('Verify service'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verify service'));
      await tester.pumpAndSettle();

      // Nothing was typed, so blaming the network is wrong — and the old binary
      // badge left the user with a red "Unreachable" and no explanation.
      expect(find.text('Incomplete'), findsOneWidget);
      expect(find.text('Unreachable'), findsNothing);
      expect(
        find.textContaining('Enter the base URL and the API key'),
        findsOneWidget,
      );
    });

    testWidgets('Verify with a scheme-less host completes instead of hanging', (
      tester,
    ) async {
      await _pumpOnboarding(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();
      await _enableService(tester, 'Sonarr');

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '192.168.1.100:8989');
      await tester.enterText(fields.at(1), 'abcdef1234567890');
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Verify service'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verify service'));
      await tester.pumpAndSettle();

      // Regression: `BaseOptions.baseUrl` threw on the bare host from inside the
      // client constructor, so the spinner never cleared and no message
      // appeared. Any settled outcome is fine here — a stuck spinner is not.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Unreachable'), findsOneWidget);
    });

    testWidgets('the Ready step checks services nobody verified by hand', (
      tester,
    ) async {
      await _pumpOnboarding(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();
      await _enableService(tester, 'Sonarr');

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'sonarr.lan:8989');
      await tester.enterText(fields.at(1), 'abcdef1234567890');
      await tester.pumpAndSettle();

      // Straight to the summary — Verify was never pressed. Pumped in stages so
      // the checks finish while the page transition is still in flight, which is
      // the window where a reveal that walks up into the pager drags it back.
      await _tapServicesContinue(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();

      // The automatic checks must not drag the PageView back: each finishing
      // verification reveals its card, and an unscoped ensureVisible walked up
      // into the pager and cancelled the transition, pinning setup on step 2.
      expect(find.text('Step 3 of 3'), findsOneWidget);
      expect(find.text('Step 2 of 3'), findsNothing);

      // The summary reports what it found rather than only "Configured": under
      // test the transport refuses every request, so the verdict is OFFLINE.
      expect(find.text('OFFLINE'), findsOneWidget);
      expect(find.text('Configured, but not answering'), findsOneWidget);
      // And it never blocks the way out.
      expect(find.widgetWithText(ElevatedButton, "Let's go"), findsOneWidget);
    });

    testWidgets('every step survives an accessibility text size', (
      tester,
    ) async {
      // 34pt headlines and a fixed footer on a 4.7" phone: the combination that
      // overflows first at an accessibility reading size.
      tester.view.physicalSize = const Size(750, 1334); // iPhone SE class
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            secureSettingsStoreProvider.overrideWithValue(
              FakeSecureSettingsStore(),
            ),
            initialSettingsProvider.overrideWith(
              (ref) => const SettingsModel(
                radarrUrl: 'https://radarr.example.com',
                radarrApiKey: 'k',
                sonarrUrl: 'https://sonarr.example.com',
                sonarrApiKey: 'k',
              ),
            ),
            initialOnboardingCompletedProvider.overrideWith((ref) => false),
          ],
          child: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: MaterialApp(home: OnboardingScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'welcome step');

      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'services step');

      await _tapServicesContinue(tester);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'ready step');
      expect(find.widgetWithText(ElevatedButton, "Let's go"), findsOneWidget);
    });

    testWidgets('the Ready step fits a full configuration on a phone', (
      tester,
    ) async {
      // A real setup — nine services — overflowed the step by 151px and pushed
      // "Let's go" off the screen, so onboarding could not be finished at all.
      // Only a full configuration is long enough to reach it.
      tester.view.physicalSize = const Size(1179, 2556); // iPhone 15/17 class
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            secureSettingsStoreProvider.overrideWithValue(
              FakeSecureSettingsStore(),
            ),
            initialSettingsProvider.overrideWith(
              (ref) => const SettingsModel(
                seerrUrl: 'https://seerr.example.com',
                seerrApiKey: 'k',
                radarrUrl: 'https://radarr.example.com',
                radarrApiKey: 'k',
                sonarrUrl: 'https://sonarr.example.com',
                sonarrApiKey: 'k',
                lidarrUrl: 'https://lidarr.example.com',
                lidarrApiKey: 'k',
                bazarrUrl: 'https://bazarr.example.com',
                bazarrApiKey: 'k',
                prowlarrUrl: 'https://prowlarr.example.com',
                prowlarrApiKey: 'k',
                sabnzbdUrl: 'https://sab.example.com',
                sabnzbdApiKey: 'k',
                readarrUrl: 'https://readarr.example.com',
                readarrApiKey: 'k',
                // Nine services, all over HTTP: TrueNAS and Dockge speak
                // WebSocket, which the widget-test transport cannot mock, and
                // this test is about the layout of nine rows.
                qbittorrentUrl: 'https://qb.example.com',
                nzbgetUrl: 'https://nzbget.example.com',
              ),
            ),
            initialOnboardingCompletedProvider.overrideWith((ref) => false),
          ],
          child: const MaterialApp(home: OnboardingScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();
      await _tapServicesContinue(tester);
      await tester.pumpAndSettle();

      expect(find.text('Step 3 of 3'), findsOneWidget);
      // The way out has to be on screen and tappable.
      expect(find.widgetWithText(ElevatedButton, "Let's go"), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, "Let's go"));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a second run resumes the saved configuration', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            secureSettingsStoreProvider.overrideWithValue(
              FakeSecureSettingsStore(),
            ),
            initialSettingsProvider.overrideWith(
              (ref) => const SettingsModel(
                radarrUrl: 'https://192.168.1.50',
                radarrApiKey: 'abcdef1234567890',
              ),
            ),
            initialOnboardingCompletedProvider.overrideWith((ref) => false),
          ],
          child: const MaterialApp(home: OnboardingScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();

      // Radarr comes back on, with its address in the field. Starting blank meant
      // a Continue on this second pass wrote empty values over the saved ones.
      expect(find.text('Radarr configuration'), findsOneWidget);
      expect(find.text('https://192.168.1.50'), findsOneWidget);

      await _tapServicesContinue(tester);
      await tester.pumpAndSettle();
      expect(find.text('Radarr'), findsOneWidget);
      expect(find.textContaining('No services configured'), findsNothing);
    });

    testWidgets('the Ready step lists what was actually filled in', (
      tester,
    ) async {
      await _pumpOnboarding(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();
      await _enableService(tester, 'Sonarr');

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'sonarr.lan:8989');
      await tester.enterText(fields.at(1), 'abcdef1234567890');
      await tester.pumpAndSettle();

      await _tapServicesContinue(tester);
      await tester.pumpAndSettle();

      // Regression: typing changes only the controllers, so this screen did not
      // rebuild between the last toggle and Continue — the summary was built from
      // the state as of the toggle and reported nothing configured, while the
      // settings had in fact been saved.
      expect(find.text('Step 3 of 3'), findsOneWidget);
      expect(find.text("You're all set."), findsOneWidget);
      expect(find.text('Sonarr'), findsOneWidget);
      expect(find.textContaining('No services configured'), findsNothing);
    });

    testWidgets('the step headline stands down while the keyboard is up', (
      tester,
    ) async {
      await _pumpOnboarding(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();

      expect(
        find.text('Connect the services you already host.'),
        findsOneWidget,
      );

      // Simulate the keyboard taking the bottom of the screen: the headline and
      // its paragraph are 150pt of fixed chrome above a scroll view the keyboard
      // has already cut to a sliver. The inset has to be read above the
      // Scaffold, which strips it from its own body — this test is what caught
      // the first attempt reading it from inside.
      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      expect(find.text('Connect the services you already host.'), findsNothing);
      // The step is still named, and the form is still there.
      expect(find.text('Step 2 of 3'), findsOneWidget);
      expect(find.text('Seerr'), findsOneWidget);
    });

    // Regression for issue #4: if the underlying secure-storage write throws
    // (e.g. the macOS Keychain prompt was denied) the user must see an error
    // instead of a silently-broken Continue button.
    testWidgets(
      'keychain write fails: shows snackbar and stays on Services step',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final secureStore = FakeSecureSettingsStore()
          ..failureMessage = 'Keychain permission denied';

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              secureSettingsStoreProvider.overrideWithValue(secureStore),
              initialSettingsProvider.overrideWith(
                (ref) => const SettingsModel(),
              ),
              initialOnboardingCompletedProvider.overrideWith((ref) => false),
            ],
            child: const MaterialApp(home: OnboardingScreen()),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
        await tester.pumpAndSettle();
        expect(find.text('Step 2 of 3'), findsOneWidget);

        await _tapServicesContinue(tester);
        await tester.pumpAndSettle();

        expect(find.textContaining("Couldn't save"), findsOneWidget);
        expect(find.text('Step 2 of 3'), findsOneWidget);
        expect(find.text('Step 3 of 3'), findsNothing);
      },
    );
  });
}

Future<void> _pumpOnboarding(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final secureStore = FakeSecureSettingsStore();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        secureSettingsStoreProvider.overrideWithValue(secureStore),
        initialSettingsProvider.overrideWith((ref) => const SettingsModel()),
        initialOnboardingCompletedProvider.overrideWith((ref) => false),
      ],
      child: const MaterialApp(home: OnboardingScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapServicesContinue(WidgetTester tester) async {
  // The welcome step's Continue is still in the PageView, so scope to the later
  // one. (Matching "inside a Row" broke as soon as the footer learned to stack
  // its buttons at an accessibility reading size.)
  await tester.tap(find.widgetWithText(ElevatedButton, 'Continue').last);
}

Future<void> _enableService(WidgetTester tester, String title) async {
  // Each service card ends with a toggle GestureDetector. The toggle widget
  // tree under the card header exposes the title text in a Column above the
  // toggle; tapping the row's toggle area flips the state.
  final header = find.text(title).first;
  // The service list scrolls; bring the target row on-screen before tapping so
  // the test stays robust as more services are added.
  await tester.ensureVisible(header);
  await tester.pumpAndSettle();
  // Toggle is the last GestureDetector in the card's header Row.
  await tester.tap(header);
  await tester.pumpAndSettle();
}
