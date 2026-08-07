import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/reel_command_button.dart';

void main() {
  testWidgets('a throwing action is handled at the button, not dropped', (
    tester,
  ) async {
    // `FilledButton.onPressed` is a `VoidCallback`, so the future `_run` returns
    // is discarded the moment it is handed over: a `rethrow` from the button
    // landed in nothing and escaped as an unhandled async exception, because
    // `main()` runs a plain `runApp` with no zone guard.
    final reported = _captureErrors(tester);

    var presses = 0;
    await _pumpButton(
      tester,
      busyLabel: 'Testing',
      failureLabel: 'Test again',
      onPressed: () async {
        presses++;
        throw StateError('malformed URL');
      },
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(presses, 1);
    expect(reported, hasLength(1));
    expect(reported.single.exception, isStateError);
    // Reported deliberately, through the framework's own channel, rather than
    // arriving as an uncaught async error from a dropped future.
    expect(reported.single.library, 'cupola');
    expect(reported.single.context.toString(), contains('Test connection'));
    // And the button is usable again rather than stuck in its waiting state.
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('a throwing action with no waiting state is caught too', (
    tester,
  ) async {
    // The `busyLabel == null` branch never took over the label, and had no
    // `try` at all.
    final reported = _captureErrors(tester);

    await _pumpButton(
      tester,
      onPressed: () async => throw StateError('no route for that press'),
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(reported, hasLength(1));
    expect(reported.single.exception, isStateError);
    expect(reported.single.library, 'cupola');
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('the button is disabled only while its action runs', (
    tester,
  ) async {
    final completer = Completer<void>();
    await _pumpButton(
      tester,
      busyLabel: 'Testing',
      onPressed: () => completer.future,
    );

    FilledButton button() =>
        tester.widget<FilledButton>(find.byType(FilledButton));

    expect(button().onPressed, isNotNull);

    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(button().onPressed, isNull);

    completer.complete();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(button().onPressed, isNotNull);
  });
}

/// Takes over [FlutterError.onError] so a reported failure can be inspected
/// instead of failing the test at teardown.
List<FlutterErrorDetails> _captureErrors(WidgetTester tester) {
  final reported = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = reported.add;
  addTearDown(() => FlutterError.onError = previous);
  return reported;
}

Future<void> _pumpButton(
  WidgetTester tester, {
  required Future<void> Function()? onPressed,
  String label = 'Test connection',
  String? busyLabel,
  String? failureLabel,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ReelCommandButton(
            label: label,
            busyLabel: busyLabel,
            failureLabel: failureLabel,
            onPressed: onPressed,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
