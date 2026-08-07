import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/features/prowlarr/data/prowlarr_service.dart';
import 'package:seekarr/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:seekarr/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:seekarr/features/prowlarr/presentation/widgets/prowlarr_provider_form_sheet.dart';

import '../../../test_helpers/fake_api_client.dart';

Future<void> _pumpForm(
  WidgetTester tester,
  FakeApiClient client, {
  required ProwlarrProviderKind kind,
  required ProwlarrProviderResource resource,
  bool isNew = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        prowlarrServiceProvider.overrideWithValue(ProwlarrService(client)),
        prowlarrTagsProvider.overrideWith((ref) async => const <ProwlarrTag>[]),
        prowlarrAppProfilesProvider.overrideWith(
          (ref) async => const <ProwlarrAppProfile>[],
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showProwlarrProviderFormSheet(
                context: context,
                kind: kind,
                resource: resource,
                isNew: isNew,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Map<String, dynamic> _postedPayload(FakeApiClient client) =>
    client.lastPostData as Map<String, dynamic>;

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1200, 2600);
    view.devicePixelRatio = 1.0;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });
  });

  testWidgets('a notification only offers the events it supports', (
    tester,
  ) async {
    final client = FakeApiClient()..postResponseData = {'id': 3};
    // Telegram-shaped: grabs and health issues, no health-restored event.
    final resource = ProwlarrProviderResource.fromJson({
      'name': 'Telegram',
      'implementation': 'Telegram',
      'implementationName': 'Telegram',
      'configContract': 'TelegramSettings',
      'supportsOnGrab': true,
      'supportsOnHealthIssue': true,
      'supportsOnHealthRestored': false,
      'supportsOnApplicationUpdate': true,
      'fields': [
        {
          'order': 0,
          'name': 'botToken',
          'label': 'Bot token',
          'type': 'textbox',
        },
      ],
    });

    await _pumpForm(
      tester,
      client,
      kind: ProwlarrProviderKind.notification,
      resource: resource,
    );

    expect(find.text('On grab'), findsOneWidget);
    expect(find.text('On health issue'), findsOneWidget);
    expect(find.text('On application update'), findsOneWidget);
    // Advertised as unsupported, so offering it would do nothing.
    expect(find.text('On health restored'), findsNothing);
    expect(find.text('Bot token'), findsOneWidget);

    await tester.tap(find.text('On grab'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Bot token'),
      '123:abc',
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    final payload = _postedPayload(client);
    expect(client.lastPostPath, '/api/v1/notification');
    expect(payload['onGrab'], isTrue);
    expect(payload['onHealthIssue'], isFalse);
    expect(payload.containsKey('id'), isFalse);
    final fields = (payload['fields'] as List).cast<Map<String, dynamic>>();
    expect(fields.single['value'], '123:abc');
  });

  testWidgets('an app posts the sync level the user picked', (tester) async {
    final client = FakeApiClient()..postResponseData = {'id': 4};
    final resource = ProwlarrProviderResource.fromJson({
      'name': 'Sonarr',
      'implementation': 'Sonarr',
      'implementationName': 'Sonarr',
      'configContract': 'SonarrSettings',
      'syncLevel': 'fullSync',
      'fields': [
        {'order': 0, 'name': 'baseUrl', 'label': 'Sonarr server', 'value': ''},
      ],
    });

    await _pumpForm(
      tester,
      client,
      kind: ProwlarrProviderKind.application,
      resource: resource,
    );

    expect(find.text('Sync level'), findsOneWidget);
    await tester.tap(find.text('Add only'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(_postedPayload(client)['syncLevel'], 'addOnly');
  });

  testWidgets('a download client carries its enable flag and priority', (
    tester,
  ) async {
    final client = FakeApiClient()..putResponseData = {'id': 6};
    final resource = ProwlarrProviderResource.fromJson({
      'id': 6,
      'name': 'qBittorrent',
      'implementation': 'QBittorrent',
      'implementationName': 'qBittorrent',
      'configContract': 'QBittorrentSettings',
      'enable': true,
      'protocol': 'torrent',
      'priority': 1,
      'fields': [
        {'order': 0, 'name': 'host', 'label': 'Host', 'value': 'localhost'},
      ],
    });

    await _pumpForm(
      tester,
      client,
      kind: ProwlarrProviderKind.downloadClient,
      resource: resource,
      isNew: false,
    );

    await tester.tap(find.text('Enable'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Client priority'),
      '3',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final payload = client.lastPutData as Map<String, dynamic>;
    expect(client.lastPutPath, '/api/v1/downloadclient/6');
    expect(payload['enable'], isFalse);
    expect(payload['priority'], 3);
    // An edit keeps its id, unlike an add.
    expect(payload['id'], 6);
  });
}
