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

      expect(find.textContaining('Manage your self-hosted'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Step 2 of 3'), findsOneWidget);

      await _tapServicesContinue(tester);
      await tester.pumpAndSettle();

      expect(find.text('Step 3 of 3'), findsOneWidget);
      expect(find.text("You're all set."), findsOneWidget);
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
  await tester.tap(
    find.descendant(
      of: find.byType(Row),
      matching: find.widgetWithText(ElevatedButton, 'Continue'),
    ),
  );
}

Future<void> _enableService(WidgetTester tester, String title) async {
  // Each service card ends with a toggle GestureDetector. The toggle widget
  // tree under the card header exposes the title text in a Column above the
  // toggle; tapping the row's toggle area flips the state.
  final header = find.text(title).first;
  // Toggle is the last GestureDetector in the card's header Row.
  await tester.tap(header);
  await tester.pumpAndSettle();
}
