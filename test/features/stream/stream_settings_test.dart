import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/service_settings_screen.dart';

import '../../test_helpers/fake_secure_settings_store.dart';

void main() {
  group('the Stream services persist through the ordinary API-key path', () {
    late SettingsService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      service = SettingsService(
        await SharedPreferences.getInstance(),
        FakeSecureSettingsStore(),
      );
    });

    test('Jellyfin round-trips its URL, key and chosen viewer', () async {
      await service.saveSettings(
        const SettingsModel(
          jellyfinUrl: 'https://jelly.local:8096',
          jellyfinApiKey: 'jf-key',
          jellyfinUserId: 'a1b2c3',
        ),
      );

      final loaded = await service.loadSettings();
      expect(loaded.jellyfinUrl, 'https://jelly.local:8096');
      expect(loaded.jellyfinApiKey, 'jf-key');
      // The third value is the whole reason the credential model grew: an API key
      // authenticates as an administrator with no user attached, so watch state
      // is unreadable without it.
      expect(loaded.jellyfinUserId, 'a1b2c3');
      expect(loaded.isServiceConfigured(ServiceKey.jellyfin), isTrue);
    });

    test('Plex round-trips its token in the generic credential slot', () async {
      await service.saveSettings(
        const SettingsModel(
          plexUrl: 'https://plex.local:32400',
          plexToken: 'plex-device-token',
        ),
      );

      final loaded = await service.loadSettings();
      expect(loaded.plexUrl, 'https://plex.local:32400');
      expect(loaded.plexToken, 'plex-device-token');
      // `apiKeyFor` is what every generic caller uses, so the token has to answer
      // to it — the same way qBittorrent's password does.
      expect(loaded.apiKeyFor(ServiceKey.plex), 'plex-device-token');
      expect(loaded.isServiceConfigured(ServiceKey.plex), isTrue);
    });

    test('the Plex client id is minted once and never changes', () async {
      final first = await service.loadSettings();
      expect(first.plexClientId, isNotEmpty);
      // v4 UUID shape, which is what every Plex client sends.
      expect(
        first.plexClientId,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );

      final second = await service.loadSettings();
      expect(second.plexClientId, first.plexClientId);
    });

    test('an unrelated save cannot clear the client id', () async {
      final minted = (await service.loadSettings()).plexClientId;

      // The danger is real and specific: every `SettingsModel()` default carries
      // an empty `plexClientId`, so a save that honoured an incoming empty value
      // would wipe it — and the next load would mint a new one, registering a
      // fresh "device" on the user's Plex server on every such save.
      await service.saveSettings(const SettingsModel(radarrUrl: 'http://r'));

      expect((await service.loadSettings()).plexClientId, minted);
    });
  });

  group('the Plex token field refuses a JSON Web Token', () {
    Future<void> pump(WidgetTester tester, ServiceKey service) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            currentSettingsProvider.overrideWith(
              (ref) => const SettingsModel(),
            ),
          ],
          child: MaterialApp(home: ServiceSettingsScreen(service: service)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('names the token kind rather than reporting a bad key', (
      tester,
    ) async {
      await pump(tester, ServiceKey.plex);

      // The field is labelled for what Plex calls it, not "API Key".
      expect(find.text('Plex token'), findsOneWidget);

      await tester.enterText(
        find.byType(TextFormField).last,
        'eyJhbGciOiJIUzI1NiJ9.e30.x',
      );
      // Trigger validation the way saving does.
      await tester.pumpAndSettle();
      final form = tester.state<FormState>(find.byType(Form)).validate();

      expect(form, isFalse);
      await tester.pumpAndSettle();
      // Accepting it would ship software that works for a week and then fails
      // with a 401 the user cannot interpret.
      expect(find.textContaining('expires in 7 days'), findsOneWidget);
    });

    testWidgets('a device token passes', (tester) async {
      await pump(tester, ServiceKey.plex);

      await tester.enterText(
        find.byType(TextFormField).last,
        'sXxYzDeviceToken1234567890',
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('expires in 7 days'), findsNothing);
    });

    testWidgets('Jellyfin keeps the ordinary API-key wording', (tester) async {
      await pump(tester, ServiceKey.jellyfin);

      expect(find.text('API Key'), findsOneWidget);
      expect(find.text('Plex token'), findsNothing);
      // The setup note has to say the key carries no user, because that is what
      // makes the viewer picker necessary rather than optional.
      expect(find.textContaining('no user of its own'), findsOneWidget);
    });
  });
}
