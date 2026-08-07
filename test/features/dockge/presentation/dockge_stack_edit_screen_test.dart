import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/dockge/data/dockge_client.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack_detail.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';
import 'package:cupola/features/dockge/presentation/dockge_stack_edit_screen.dart';

const _existingYaml = '''services:
  immich:
    image: immich:latest
''';

/// A [DockgeClient] that records writes instead of performing them. Neither
/// `deployStack` nor `saveStack` validates its YAML server-side, so "was it
/// called, and with what" is the only thing standing between the editor and a
/// wiped stack.
class _RecordingClient extends DockgeClient {
  _RecordingClient() : super(baseUrl: 'https://dockge.local');

  final List<String> writes = [];

  @override
  Future<void> deployStack({
    required String name,
    required String composeYAML,
    String composeENV = '',
    required bool isAdd,
  }) async {
    writes.add('deploy|$name|$composeYAML');
  }

  @override
  Future<void> saveStack({
    required String name,
    required String composeYAML,
    String composeENV = '',
    required bool isAdd,
  }) async {
    writes.add('save|$name|$composeYAML');
  }
}

DockgeStackDetail _detail(String name, String yaml) => DockgeStackDetail(
  stack: DockgeStack(name: name, status: DockgeStackStatus.running),
  composeYAML: yaml,
);

Future<_RecordingClient> _pump(
  WidgetTester tester, {
  String? name,
  required Future<DockgeStackDetail> Function() detail,
}) async {
  final client = _RecordingClient();
  // The compose editor is tall; give the surface room so the action row is
  // laid out rather than being scrolled out of the lazy ListView.
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      // No automatic retry: a thrown provider must settle into AsyncError
      // instead of looping through retry-loading.
      retry: (retryCount, error) => null,
      overrides: [
        dockgeClientProvider.overrideWith((ref) => client),
        dockgeStackDetailProvider.overrideWith((ref, arg) => detail()),
      ],
      child: MaterialApp(home: DockgeStackEditScreen(name: name)),
    ),
  );
  await tester.pump();
  return client;
}

/// The button carrying [label]. `find.byType` matches the exact runtime type,
/// and `FilledButton.icon`/`OutlinedButton.icon` build private subclasses, so
/// this matches on the shared base instead.
Finder _button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

Finder get _deployButton => _button('Deploy');
Finder get _saveButton => _button('Save');

void main() {
  testWidgets('editing shows no editor until the existing compose loads', (
    tester,
  ) async {
    // The data-loss path: the editor used to render empty while the detail
    // future was still pending, with Save/Deploy live. One tap wrote an empty
    // compose.yaml over the real stack and ran `up -d` on it.
    final pending = Completer<DockgeStackDetail>();
    final client = await _pump(
      tester,
      name: 'immich',
      detail: () => pending.future,
    );

    expect(find.byType(TextField), findsNothing);
    expect(_deployButton, findsNothing);
    expect(_saveButton, findsNothing);
    expect(client.writes, isEmpty);

    pending.complete(_detail('immich', _existingYaml));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNWidgets(2));
    final deploy = tester.widget<ButtonStyleButton>(_deployButton);
    final save = tester.widget<ButtonStyleButton>(_saveButton);
    expect(deploy.onPressed, isNotNull);
    expect(save.onPressed, isNotNull);
    expect(find.text(_existingYaml), findsOneWidget);
  });

  testWidgets('editing surfaces a load failure instead of an empty editor', (
    tester,
  ) async {
    await _pump(
      tester,
      name: 'immich',
      detail: () => Future<DockgeStackDetail>.error(
        const DockgeException('socket closed'),
      ),
    );
    await tester.pump();

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(_deployButton, findsNothing);
  });

  testWidgets('editing refuses to write an emptied compose file', (
    tester,
  ) async {
    final client = await _pump(
      tester,
      name: 'immich',
      detail: () async => _detail('immich', _existingYaml),
    );
    await tester.pumpAndSettle();

    // The compose field is the first of the two code fields.
    await tester.enterText(find.byType(TextField).first, '   ');
    await tester.pump();

    await tester.tap(_deployButton);
    await tester.pumpAndSettle();

    expect(client.writes, isEmpty);
    expect(
      find.text('compose.yaml is empty — that would wipe the stack'),
      findsOneWidget,
    );
  });

  testWidgets('adding a stack edits straight away from the template', (
    tester,
  ) async {
    final client = await _pump(
      tester,
      detail: () async => _detail('unused', ''),
    );
    await tester.pump();

    // Name + compose + env.
    expect(find.byType(TextField), findsNWidgets(3));
    expect(
      tester.widget<ButtonStyleButton>(_deployButton).onPressed,
      isNotNull,
    );

    // A new stack still needs a name before anything is sent.
    await tester.tap(_deployButton);
    await tester.pumpAndSettle();
    expect(client.writes, isEmpty);
    expect(find.text('Stack name is required'), findsOneWidget);
  });
}
