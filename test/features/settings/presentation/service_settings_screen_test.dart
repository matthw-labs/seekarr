import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/platform/secure_clipboard.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/service_settings_screen.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

void main() {
  String? clipboardText;

  setUp(() {
    clipboardText = null;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final arguments = call.arguments as Map<dynamic, dynamic>?;
            clipboardText = arguments?['text'] as String?;
          }
          // A real clipboard, not a write-only sink: the timed clear reads the
          // contents back before touching them, so a fake that always answered
          // null would let a broken clear look like a working one.
          if (call.method == 'Clipboard.getData') {
            return clipboardText == null ? null : {'text': clipboardText};
          }
          return null;
        });
    // Default host: one with no native clipboard hardening. From Dart an absent
    // handler and a platform that never registered one are the same thing — a
    // MissingPluginException — and modelling it explicitly keeps the case
    // deterministic, since an unanswered channel would simply leave the copy
    // pending forever inside a widget test.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SecureClipboard.channel,
          (call) async => throw MissingPluginException(),
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(SystemChannels.platform, null)
      ..setMockMethodCallHandler(SecureClipboard.channel, null);
  });

  group('ServiceSettingsScreen', () {
    testWidgets('renders the selected service title, save action, and fields', (
      tester,
    ) async {
      await _pumpServiceSettings(tester, service: ServiceKey.radarr);

      expect(find.text('Radarr Settings'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Server URL'), findsOneWidget);
      expect(find.text('API Key'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(2));
    });

    testWidgets('pre-populates the URL and API key fields', (tester) async {
      await _pumpServiceSettings(
        tester,
        service: ServiceKey.radarr,
        settings: const SettingsModel(
          radarrUrl: 'https://radarr.local',
          radarrApiKey: 'radarr-key',
        ),
      );

      final urlField = tester.widget<TextField>(_fieldByLabel('Server URL'));
      final apiKeyField = tester.widget<TextField>(_fieldByLabel('API Key'));

      expect(urlField.controller?.text, 'https://radarr.local');
      expect(apiKeyField.controller?.text, 'radarr-key');
    });

    testWidgets('renders the service icon in the header', (tester) async {
      await _pumpServiceSettings(tester, service: ServiceKey.lidarr);

      expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    });

    testWidgets('validates that the server URL is required', (tester) async {
      await _pumpServiceSettings(tester, service: ServiceKey.radarr);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Server URL is required'), findsOneWidget);
    });

    testWidgets('validates that the API key is required', (tester) async {
      await _pumpServiceSettings(tester, service: ServiceKey.radarr);

      await tester.enterText(
        _fieldByLabel('Server URL'),
        'https://radarr.local',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('API Key is required'), findsOneWidget);
    });

    testWidgets('copy button writes the API key to the clipboard', (
      tester,
    ) async {
      // The host declines the hardened copy (see setUp), so this is the fallback
      // path: a platform with no native side, or an OS below the version that
      // has the sensitive-clip flags. It must still copy.
      await _pumpServiceSettings(
        tester,
        service: ServiceKey.radarr,
        settings: const SettingsModel(radarrApiKey: 'copy-me'),
      );

      await tester.tap(find.byTooltip('Copy API key'));
      await tester.pumpAndSettle();

      expect(clipboardText, 'copy-me');
      // The confirmation says the key will be taken back, because the clipboard
      // is a shared surface: Android 13+ shows a preview of what was copied, and
      // Apple's general pasteboard syncs to the user's other devices.
      expect(
        find.textContaining('the clipboard is cleared in'),
        findsOneWidget,
      );

      // …and it is actually taken back, rather than sitting there until the next
      // copy. On the platforms with no sensitive-clip flag this expiry is the
      // whole mitigation.
      await tester.pump(const Duration(seconds: 60));
      expect(clipboardText, isEmpty);
    });

    testWidgets('a host that can hide the clip is used instead of a plain copy', (
      tester,
    ) async {
      // The point of the native path: the key must not also go out through
      // Flutter's plain clipboard, which is the write that Android previews on
      // screen and that Apple syncs to the user's other devices.
      String? hardenedSecret;
      int? hardenedLifetimeSeconds;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SecureClipboard.channel, (call) async {
            final arguments = call.arguments as Map<dynamic, dynamic>?;
            hardenedSecret = arguments?['secret'] as String?;
            hardenedLifetimeSeconds = arguments?['expiresInSeconds'] as int?;
            // The host really does put it on the system clipboard, so the fake
            // one has to show it there too — otherwise the timed clear below
            // would have nothing to find and would pass vacuously.
            clipboardText = hardenedSecret;
            return true;
          });

      await _pumpServiceSettings(
        tester,
        service: ServiceKey.radarr,
        settings: const SettingsModel(radarrApiKey: 'copy-me'),
      );

      var plainCopies = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              final arguments = call.arguments as Map<dynamic, dynamic>?;
              clipboardText = arguments?['text'] as String?;
              plainCopies++;
            }
            if (call.method == 'Clipboard.getData') {
              return clipboardText == null ? null : {'text': clipboardText};
            }
            return null;
          });

      await tester.tap(find.byTooltip('Copy API key'));
      await tester.pumpAndSettle();

      expect(hardenedSecret, 'copy-me');
      expect(hardenedLifetimeSeconds, 45);
      expect(plainCopies, isZero);
      expect(
        find.textContaining('the clipboard is cleared in'),
        findsOneWidget,
      );

      // Defence in depth: the timed clear runs over the hardened copy too, since
      // only iOS can expire a clip on its own.
      await tester.pump(const Duration(seconds: 60));
      expect(clipboardText, isEmpty);
      expect(plainCopies, 1);
    });

    testWidgets('a clipboard the user has since reused is left alone', (
      tester,
    ) async {
      await _pumpServiceSettings(
        tester,
        service: ServiceKey.radarr,
        settings: const SettingsModel(radarrApiKey: 'copy-me'),
      );

      await tester.tap(find.byTooltip('Copy API key'));
      await tester.pumpAndSettle();

      // Whatever they copied next is theirs; the expiry must never destroy it.
      clipboardText = 'a shopping list';
      await tester.pump(const Duration(seconds: 60));

      expect(clipboardText, 'a shopping list');
    });

    testWidgets('a clipboard that cannot be read back is still cleared', (
      tester,
    ) async {
      await _pumpServiceSettings(
        tester,
        service: ServiceKey.radarr,
        settings: const SettingsModel(radarrApiKey: 'copy-me'),
      );

      await tester.tap(find.byTooltip('Copy API key'));
      await tester.pumpAndSettle();
      expect(clipboardText, 'copy-me');

      // Since Android 10 `getPrimaryClip` answers null to any app that does not
      // have window focus — which is exactly where the user is 45 seconds after
      // leaving to paste the key somewhere. Reading that null as "the user has
      // copied something else" made the clear a no-op on Android in precisely
      // the case it exists for, under a SnackBar promising it would run.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              final arguments = call.arguments as Map<dynamic, dynamic>?;
              clipboardText = arguments?['text'] as String?;
            }
            if (call.method == 'Clipboard.getData') return null;
            return null;
          });

      await tester.pump(const Duration(seconds: 60));

      expect(clipboardText, isEmpty);
    });

    testWidgets('removing Jellyfin clears the chosen viewer with it', (
      tester,
    ) async {
      // `jellyfinUserId` lives outside the per-service {url, apiKey} pair, so
      // the clear could not reach it. Re-adding a *different* Jellyfin then
      // bound every per-viewer query to a user id that server never had.
      final harness = await _pumpServiceSettings(
        tester,
        service: ServiceKey.jellyfin,
        settings: const SettingsModel(
          jellyfinUrl: 'https://jelly.local:8096',
          jellyfinApiKey: 'jf-key',
          jellyfinUserId: 'a1b2c3',
        ),
        // Tall enough that the remove row — which sits below the viewer picker
        // on a configured Jellyfin — is built without scrolling.
        viewport: const Size(800, 2400),
      );

      await tester.tap(find.text('Remove Jellyfin'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      final updated = harness.container.read(settingsProvider);
      expect(updated.jellyfinUrl, isEmpty);
      expect(updated.jellyfinApiKey, isEmpty);
      expect(updated.jellyfinUserId, isEmpty);
    });

    testWidgets('editing the URL forgets the abandoned origin pin', (
      tester,
    ) async {
      // `_maybePromptCertTrust` can only ever *add* a pin, so without this the
      // entry outlives the address — and pins are keyed purely by origin, so a
      // service later pointed back there would reuse the stale trust silently.
      const fingerprint = 'aa:bb:cc';
      final harness = await _pumpServiceSettings(
        tester,
        service: ServiceKey.sonarr,
        settings: const SettingsModel(
          sonarrUrl: 'https://old-nas.local:8989',
          sonarrApiKey: 'sonarr-key',
          trustedCertificates: {'https://old-nas.local:8989': fingerprint},
        ),
      );

      await tester.enterText(
        _fieldByLabel('Server URL'),
        'https://new-nas.local:8989',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final updated = harness.container.read(settingsProvider);
      expect(updated.sonarrUrl, 'https://new-nas.local:8989');
      expect(updated.pinForUrl('https://old-nas.local:8989'), isNull);
    });

    testWidgets('a pin another service still shares survives a URL edit', (
      tester,
    ) async {
      // Moving Sonarr off the reverse proxy must not break Radarr's trust in it.
      const fingerprint = 'aa:bb:cc';
      final harness = await _pumpServiceSettings(
        tester,
        service: ServiceKey.sonarr,
        settings: const SettingsModel(
          sonarrUrl: 'https://nas.local:443',
          sonarrApiKey: 'sonarr-key',
          radarrUrl: 'https://nas.local:443',
          radarrApiKey: 'radarr-key',
          trustedCertificates: {'https://nas.local:443': fingerprint},
        ),
      );

      await tester.enterText(
        _fieldByLabel('Server URL'),
        'https://direct.local:8989',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final updated = harness.container.read(settingsProvider);
      expect(updated.pinForUrl('https://nas.local:443'), fingerprint);
    });

    testWidgets('save updates only the selected service and pops the route', (
      tester,
    ) async {
      final harness = await _pumpServiceSettings(
        tester,
        service: ServiceKey.sonarr,
        settings: const SettingsModel(
          radarrUrl: 'https://radarr.local',
          radarrApiKey: 'radarr-key',
          sonarrUrl: 'https://old-sonarr.local',
          sonarrApiKey: 'old-key',
        ),
      );

      await tester.enterText(
        _fieldByLabel('Server URL'),
        'https://sonarr.local',
      );
      await tester.enterText(_fieldByLabel('API Key'), 'sonarr-key');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final updated = harness.container.read(settingsProvider);
      expect(updated.radarrUrl, 'https://radarr.local');
      expect(updated.radarrApiKey, 'radarr-key');
      expect(updated.sonarrUrl, 'https://sonarr.local');
      expect(updated.sonarrApiKey, 'sonarr-key');

      expect(find.text('LauncherPage'), findsOneWidget);
      expect(find.text('Sonarr settings saved'), findsOneWidget);
    });

    testWidgets('the connection verdict is a live region that names the outcome', (
      tester,
    ) async {
      // The verdict is the whole point of the action, but it appears below the
      // button while focus stays on it. Under the test binding every request
      // returns 400, so this exercises the failure verdict.
      await _pumpServiceSettings(
        tester,
        service: ServiceKey.radarr,
        settings: const SettingsModel(
          radarrUrl: 'https://radarr.local:7878',
          radarrApiKey: 'key',
        ),
      );

      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();

      // Icon + text were two nodes and neither said "failed" — the tint carried
      // it. liveRegion is what makes the panel announce itself on both platforms;
      // a programmatic announcement would be dropped on Android.
      expect(
        find.semantics.byLabel(RegExp(r'^Connection test failed\. ')),
        containsSemantics(isLiveRegion: true),
      );
    });
  });
}

Finder _fieldByLabel(String labelText) {
  return find.byWidgetPredicate((widget) {
    if (widget is! TextField) {
      return false;
    }

    return widget.decoration?.labelText == labelText;
  });
}

/// The default certificate prober for every case here.
///
/// The real one opens a live `SecureSocket`, which `flutter_test` cannot
/// intercept the way it does an `HttpClient`, so a save that fails in a
/// probe-worthy way would otherwise reach a real socket and hang the test on a
/// pending timer. None of these cases exercise the trust prompt itself.
Future<UntrustedCertificateProbe?> _neverFindsACertificate(
  String rawUrl, {
  String pinnedFingerprint = '',
}) async => null;

Future<_SettingsHarness> _pumpServiceSettings(
  WidgetTester tester, {
  required ServiceKey service,
  SettingsModel settings = const SettingsModel(),
  Size? viewport,
}) async {
  if (viewport != null) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = viewport;
    addTearDown(tester.view.reset);
  }
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
      child: MaterialApp(home: _ServiceSettingsLauncher(service: service)),
    ),
  );
  await tester.pumpAndSettle();

  return _SettingsHarness(container);
}

class _ServiceSettingsLauncher extends StatefulWidget {
  const _ServiceSettingsLauncher({required this.service});

  final ServiceKey service;

  @override
  State<_ServiceSettingsLauncher> createState() =>
      _ServiceSettingsLauncherState();
}

class _ServiceSettingsLauncherState extends State<_ServiceSettingsLauncher> {
  bool _pushed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_pushed) {
      return;
    }

    _pushed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ServiceSettingsScreen(
            service: widget.service,
            certificateProber: _neverFindsACertificate,
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('LauncherPage')));
  }
}

class _SettingsHarness {
  const _SettingsHarness(this.container);

  final ProviderContainer container;
}
