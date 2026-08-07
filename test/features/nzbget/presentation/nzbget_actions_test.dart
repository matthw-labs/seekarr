import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/features/nzbget/data/nzbget_client.dart';
import 'package:seekarr/features/nzbget/presentation/nzbget_actions.dart';
import 'package:seekarr/features/nzbget/presentation/nzbget_provider.dart';

import '../../../test_helpers/capturing_http_adapter.dart';

NzbgetClient _client(CapturingHttpAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://nzbget.local:6789'))
    ..httpClientAdapter = adapter;
  return NzbgetClient(url: 'https://nzbget.local:6789', dio: dio);
}

/// Pumps a host that fires [action] through [runNzbgetAction] and records the
/// outcome, so a test can assert on both the return value and the snackbar.
Future<List<bool>> _run(
  WidgetTester tester,
  CapturingHttpAdapter adapter,
  Future<Object?> Function(NzbgetClient client) action,
) async {
  final outcomes = <bool>[];

  await tester.pumpWidget(
    ProviderScope(
      overrides: [nzbgetClientProvider.overrideWith((ref) => _client(adapter))],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () async {
                outcomes.add(
                  await runNzbgetAction(
                    context,
                    ref,
                    action: action,
                    successMessage: 'Job paused',
                    failureMessage: 'Failed to pause the job',
                  ),
                );
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return outcomes;
}

void main() {
  group('runNzbgetAction', () {
    testWidgets('a refused command reports failure instead of success', (
      tester,
    ) async {
      // Regression: the callback was typed `Future<void> Function(NzbgetClient)`
      // and `void` is a top type, so `Future<bool>` satisfied it and the result
      // was discarded — this wrapper returned `true` unconditionally. NZBGet
      // answers HTTP 200 with `{"result": false}` when it declines a command,
      // so the UI said "Job paused" while nothing had happened.
      final adapter = CapturingHttpAdapter(
        response: {'jsonrpc': '2.0', 'result': false, 'id': 1},
      );

      final outcomes = await _run(tester, adapter, (c) => c.pauseGroup(5));

      expect(outcomes, [isFalse]);
      expect(find.text('Job paused'), findsNothing);
      expect(find.textContaining('Failed to pause the job'), findsOneWidget);
      expect(find.textContaining('rejected'), findsOneWidget);
    });

    testWidgets('a rejected append (NZBID 0) is a failure too', (tester) async {
      final adapter = CapturingHttpAdapter(
        response: {'jsonrpc': '2.0', 'result': 0, 'id': 1},
      );

      final outcomes = await _run(
        tester,
        adapter,
        (c) => c.append('x.nzb', 'https://indexer.local/x.nzb'),
      );

      expect(outcomes, [isFalse]);
      expect(find.textContaining('rejected'), findsOneWidget);
    });

    testWidgets('an accepted command still reports success', (tester) async {
      final adapter = CapturingHttpAdapter(
        response: {'jsonrpc': '2.0', 'result': true, 'id': 1},
      );

      final outcomes = await _run(tester, adapter, (c) => c.pauseGroup(5));

      expect(outcomes, [isTrue]);
      expect(find.text('Job paused'), findsOneWidget);
    });

    testWidgets('a void client method has no failure to report', (
      tester,
    ) async {
      // `pausedownload` answers with a result the client throws away, so the
      // absence of an answer must not be read as a refusal.
      final adapter = CapturingHttpAdapter(
        response: {'jsonrpc': '2.0', 'result': true, 'id': 1},
      );

      final outcomes = await _run(tester, adapter, (c) => c.pauseDownload());

      expect(outcomes, [isTrue]);
      expect(find.text('Job paused'), findsOneWidget);
    });

    testWidgets('an unreachable service still reports the transport failure', (
      tester,
    ) async {
      final adapter = CapturingHttpAdapter(
        response: 'not json',
        statusCode: 200,
      );

      final outcomes = await _run(tester, adapter, (c) => c.pauseGroup(5));

      expect(outcomes, [isFalse]);
      expect(find.textContaining('Failed to pause the job'), findsOneWidget);
    });
  });
}
