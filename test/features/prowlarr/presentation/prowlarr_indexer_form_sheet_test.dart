import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/prowlarr/data/prowlarr_service.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/prowlarr/presentation/widgets/prowlarr_field_inputs.dart';
import 'package:cupola/features/prowlarr/presentation/widgets/prowlarr_indexer_form_sheet.dart';

import '../../../test_helpers/fake_api_client.dart';

/// A Cardigann-shaped definition: a hidden `definitionFile` that must survive
/// the save, a visible textbox, an HTML `info` block, a select and an advanced
/// field that stays folded away until asked for.
ProwlarrIndexer _definition() => ProwlarrIndexer.fromJson({
  'name': 'Test Tracker',
  'implementation': 'Cardigann',
  'implementationName': 'Cardigann',
  'configContract': 'CardigannSettings',
  'definitionName': 'testtracker',
  'protocol': 'torrent',
  'privacy': 'private',
  'supportsRss': true,
  'supportsSearch': true,
  'appProfileId': 1,
  'priority': 25,
  'fields': [
    {
      'order': 0,
      'name': 'definitionFile',
      'hidden': 'hidden',
      'value': 'testtracker',
    },
    {'order': 1, 'name': 'cookie', 'label': 'Cookie', 'type': 'textbox'},
    {
      'order': 2,
      'name': 'cookieInfo',
      'label': 'How to get the Cookie',
      'type': 'info',
      'value': '<ol><li>Login to this tracker</li></ol>',
    },
    {
      'order': 3,
      'name': 'sort',
      'label': 'Sort requested from site',
      'type': 'select',
      'value': 0,
      'selectOptions': [
        {'value': 0, 'name': 'created'},
        {'value': 1, 'name': 'seeders'},
      ],
    },
    {
      'order': 4,
      'name': 'flaresolverr',
      'label': 'FlareSolverr URL',
      'type': 'textbox',
      'advanced': true,
      'value': '',
    },
  ],
});

/// Prowlarr's answer to a save it refuses: HTTP 400 with the reasons in the
/// body.
DioException _rejectedSave(String message) {
  final request = RequestOptions(path: '/api/v1/indexer');
  return DioException(
    requestOptions: request,
    response: Response<dynamic>(
      requestOptions: request,
      statusCode: 400,
      data: [
        {'propertyName': 'Cookie', 'errorMessage': message},
      ],
    ),
  );
}

Future<void> _pumpSheet(
  WidgetTester tester,
  FakeApiClient client, {
  required ProwlarrIndexer indexer,
  bool isNew = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        prowlarrServiceProvider.overrideWithValue(ProwlarrService(client)),
        prowlarrTagsProvider.overrideWith(
          (ref) async => const [ProwlarrTag(id: 1, label: 'italian')],
        ),
        prowlarrAppProfilesProvider.overrideWith(
          (ref) async => const [ProwlarrAppProfile(id: 1, name: 'Standard')],
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showProwlarrIndexerFormSheet(
                context: context,
                indexer: indexer,
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

void main() {
  setUp(() {
    // A tall surface so the whole generated form is reachable without
    // scrolling; the sheet itself is scrollable either way.
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

  testWidgets('generates one input per visible provider field', (tester) async {
    await _pumpSheet(tester, FakeApiClient(), indexer: _definition());

    expect(find.text('Add indexer'), findsOneWidget);
    expect(find.text('Cookie'), findsOneWidget);
    expect(find.text('Sort requested from site'), findsOneWidget);
    // Info fields are rendered as prose, with Prowlarr's HTML flattened.
    expect(find.text('How to get the Cookie'), findsOneWidget);
    expect(find.textContaining('Login to this tracker'), findsOneWidget);
    // Hidden and advanced fields stay out of the form until asked for.
    expect(find.text('definitionFile'), findsNothing);
    expect(find.text('FlareSolverr URL'), findsNothing);

    await tester.tap(find.text('Show advanced settings'));
    await tester.pumpAndSettle();
    expect(find.text('FlareSolverr URL'), findsOneWidget);
  });

  testWidgets('posts the edited fields and keeps the hidden ones', (
    tester,
  ) async {
    final client = FakeApiClient()..postResponseData = {'id': 12};
    await _pumpSheet(tester, client, indexer: _definition());

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'My Tracker',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Cookie'),
      'uid=42;',
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    final payload = client.lastPostData as Map<String, dynamic>;
    expect(client.lastPostPath, '/api/v1/indexer');
    // An add carries no id — that is what turns a definition into an indexer.
    expect(payload.containsKey('id'), isFalse);
    expect(payload['name'], 'My Tracker');
    expect(payload['enable'], isTrue);
    expect(payload['appProfileId'], 1);
    expect(payload['priority'], 25);
    expect(payload['implementation'], 'Cardigann');
    expect(payload['configContract'], 'CardigannSettings');

    final fields = (payload['fields'] as List)
        .cast<Map<String, dynamic>>()
        .fold<Map<String, dynamic>>(
          {},
          (map, field) => map..[field['name'] as String] = field['value'],
        );
    expect(fields['cookie'], 'uid=42;');
    expect(fields['definitionFile'], 'testtracker');
    expect(fields['sort'], 0);
  });

  testWidgets('reports the validation failure and stays open', (tester) async {
    final client = FakeApiClient()
      ..postException = _rejectedSave('Unable to connect: invalid cookie');
    await _pumpSheet(tester, client, indexer: _definition());

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.textContaining('invalid cookie'), findsOneWidget);
    expect(find.text('Add indexer'), findsOneWidget);
  });

  testWidgets('an existing indexer can request its own deletion', (
    tester,
  ) async {
    final indexer = ProwlarrIndexer.fromJson({
      ..._definition().raw,
      'id': 7,
      'enable': true,
    });
    ProwlarrFormOutcome? outcome;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prowlarrServiceProvider.overrideWithValue(
            ProwlarrService(FakeApiClient()),
          ),
          prowlarrTagsProvider.overrideWith(
            (ref) async => const <ProwlarrTag>[],
          ),
          prowlarrAppProfilesProvider.overrideWith(
            (ref) async => const <ProwlarrAppProfile>[],
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  outcome = await showProwlarrIndexerFormSheet(
                    context: context,
                    indexer: indexer,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Save'), findsOneWidget);
    await tester.tap(find.text('Delete indexer'));
    await tester.pumpAndSettle();

    expect(outcome, ProwlarrFormOutcome.deleteRequested);
  });

  group('prowlarrPlainText', () {
    test('flattens the HTML Prowlarr ships in info fields', () {
      expect(
        prowlarrPlainText('<ol><li>One</li><li>Two &amp; three</li></ol>'),
        '• One\n• Two & three',
      );
    });
  });
}
