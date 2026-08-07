import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/truenas/domain/models/app.dart';
import 'package:cupola/features/truenas/presentation/apps/truenas_app_detail_screen.dart';
import 'package:cupola/features/truenas/presentation/apps/truenas_apps_providers.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';

/// The channel `url_launcher` dispatches on. Mocking it is how the test sees
/// whether a portal tap reached the OS at all.
const _urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');

/// Records every `launch` the app asked the platform to perform.
List<String> _installLauncherSpy() {
  final launched = <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_urlLauncherChannel, (call) async {
        switch (call.method) {
          case 'launch':
            launched.add((call.arguments as Map)['url']! as String);
            return true;
          case 'canLaunch':
            return true;
        }
        return null;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_urlLauncherChannel, null),
  );
  return launched;
}

TrueNasApp _app(Map<String, String> portals) =>
    TrueNasApp(name: 'plex', title: 'Plex', state: 'RUNNING', portals: portals);

Future<void> _pump(WidgetTester tester, TrueNasApp app) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        truenasAppProvider.overrideWith((ref, name) async => app),
        // The section chrome asks for the server version; the test has no
        // server.
        truenasVersionProvider.overrideWith((ref) async => null),
      ],
      child: const MaterialApp(home: TrueNasAppDetailScreen(name: 'plex')),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('opens an http portal', (tester) async {
    final launched = _installLauncherSpy();
    await _pump(tester, _app({'Web UI': 'https://nas.local:32400/web'}));

    await tester.tap(find.text('Web UI'));
    await tester.pumpAndSettle();

    expect(launched, ['https://nas.local:32400/web']);
  });

  testWidgets('refuses a portal URL that is not a web address', (tester) async {
    // Portal strings come from the server: a compromised TrueNAS — or a
    // hostile chart in a third-party catalog — controls both the label and the
    // target, and these used to go straight to `launchUrl`.
    final launched = _installLauncherSpy();
    await _pump(tester, _app({'Web UI': 'intent://evil#Intent;end'}));

    await tester.tap(find.text('Web UI'));
    await tester.pumpAndSettle();

    expect(launched, isEmpty);
    expect(find.text('Portal link is not a web address'), findsOneWidget);
  });

  testWidgets('refuses a scheme-less or unparseable portal URL', (
    tester,
  ) async {
    final launched = _installLauncherSpy();
    await _pump(tester, _app({'Portal': '::not a uri::'}));

    await tester.tap(find.text('Portal'));
    await tester.pumpAndSettle();

    expect(launched, isEmpty);
    expect(find.text('Portal link is not a web address'), findsOneWidget);
  });

  testWidgets('refuses a file:// portal URL', (tester) async {
    final launched = _installLauncherSpy();
    await _pump(tester, _app({'Config': 'file:///etc/passwd'}));

    await tester.tap(find.text('Config'));
    await tester.pumpAndSettle();

    expect(launched, isEmpty);
  });
}
