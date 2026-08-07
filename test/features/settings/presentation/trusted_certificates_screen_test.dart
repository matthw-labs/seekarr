import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/trusted_certificates_screen.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

const _fingerprint =
    'ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab1';

void main() {
  group('TrustedCertificatesScreen', () {
    testWidgets('shows an empty state when nothing is trusted', (tester) async {
      await _pumpScreen(tester);

      expect(find.text('Nothing trusted yet'), findsOneWidget);
      expect(find.text('nas.local:8443'), findsNothing);
    });

    testWidgets('lists the origin, its fingerprint, and its services', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        settings: const SettingsModel(
          radarrUrl: 'https://nas.local:8443',
          radarrApiKey: 'radarr-key',
          sonarrUrl: 'https://nas.local:8443',
          sonarrApiKey: 'sonarr-key',
          trustedCertificates: {'https://nas.local:8443': _fingerprint},
        ),
      );

      expect(find.text('nas.local:8443'), findsOneWidget);
      expect(find.text('Used by Radarr, Sonarr.'), findsOneWidget);
      // Uppercased and colon-grouped, matching the trust prompt's own format.
      expect(find.textContaining('AB:12:CD:34'), findsOneWidget);
    });

    testWidgets(
      'an orphaned pin — every service that used it is gone — still shows',
      (tester) async {
        // The whole reason this screen exists: forgetting the last service on
        // an origin must not make the pin unreachable.
        await _pumpScreen(
          tester,
          settings: const SettingsModel(
            trustedCertificates: {'https://nas.local:8443': _fingerprint},
          ),
        );

        expect(find.text('nas.local:8443'), findsOneWidget);
        expect(
          find.text('No configured service currently uses this address.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('forgetting removes the origin and falls back to empty', (
      tester,
    ) async {
      final container = await _pumpScreen(
        tester,
        settings: const SettingsModel(
          trustedCertificates: {'https://nas.local:8443': _fingerprint},
        ),
      );

      await tester.tap(find.widgetWithText(TextButton, 'Forget'));
      await tester.pumpAndSettle();
      // The confirmation dialog's own action is a FilledButton, so it cannot
      // be confused with the card's TextButton trigger of the same label.
      await tester.tap(find.widgetWithText(FilledButton, 'Forget'));
      await tester.pumpAndSettle();

      expect(
        container.read(currentSettingsProvider).trustedCertificates,
        isEmpty,
      );
      expect(find.text('Nothing trusted yet'), findsOneWidget);
      expect(find.text('Certificate forgotten'), findsOneWidget);
    });

    testWidgets('cancelling the confirmation keeps the certificate', (
      tester,
    ) async {
      final container = await _pumpScreen(
        tester,
        settings: const SettingsModel(
          trustedCertificates: {'https://nas.local:8443': _fingerprint},
        ),
      );

      await tester.tap(find.widgetWithText(TextButton, 'Forget'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(container.read(currentSettingsProvider).trustedCertificates, {
        'https://nas.local:8443': _fingerprint,
      });
      expect(find.text('nas.local:8443'), findsOneWidget);
    });
  });
}

Future<ProviderContainer> _pumpScreen(
  WidgetTester tester, {
  SettingsModel settings = const SettingsModel(),
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final settingsService = SettingsService(prefs, FakeSecureSettingsStore());
  final container = ProviderContainer(
    overrides: [
      initialSettingsProvider.overrideWith((ref) => settings),
      settingsServiceProvider.overrideWith((ref) => settingsService),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: TrustedCertificatesScreen()),
    ),
  );
  await tester.pumpAndSettle();

  return container;
}
