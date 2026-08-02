import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/data/settings_service.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';
import 'package:seekarr/features/settings/presentation/service_settings_screen.dart';

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
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
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
      await _pumpServiceSettings(
        tester,
        service: ServiceKey.radarr,
        settings: const SettingsModel(radarrApiKey: 'copy-me'),
      );

      await tester.tap(find.byTooltip('Copy API key'));
      await tester.pumpAndSettle();

      expect(clipboardText, 'copy-me');
      expect(find.text('API key copied to clipboard'), findsOneWidget);
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

Future<_SettingsHarness> _pumpServiceSettings(
  WidgetTester tester, {
  required ServiceKey service,
  SettingsModel settings = const SettingsModel(),
}) async {
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
          builder: (_) => ServiceSettingsScreen(service: widget.service),
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
