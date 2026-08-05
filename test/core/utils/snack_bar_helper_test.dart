import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seekarr/core/utils/snack_bar_helper.dart';

/// Pumps a host whose only job is to give the helper a `ScaffoldMessenger`, then
/// fires [show] and settles the snackbar in.
Future<void> _fire(
  WidgetTester tester,
  void Function(BuildContext context) show,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => show(context),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
}

/// Reads the snackbar's rendered string, so an assertion sees exactly what the
/// user does — including the newline that separates the two registers.
String _snackText(WidgetTester tester) {
  final content = tester.widget<Text>(
    find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)),
  );
  return content.data!;
}

void main() {
  group('SnackBarHelper.error detail', () {
    testWidgets('leads with the human sentence and demotes the exception', (
      tester,
    ) async {
      await _fire(
        tester,
        (context) => SnackBarHelper.error(
          context,
          "Couldn't start a search in Radarr.",
          detail: Exception('404 Not Found'),
        ),
      );

      // The sentence is the opening, not a suffix after a raw type name: the
      // first thing read aloud has to be the thing the user can act on.
      expect(
        _snackText(tester),
        "Couldn't start a search in Radarr.\n404 Not Found",
      );
    });

    testWidgets('strips the Exception prefix Dart adds itself', (tester) async {
      await _fire(
        tester,
        (context) => SnackBarHelper.error(
          context,
          'Failed.',
          detail: Exception('connection refused'),
        ),
      );

      expect(_snackText(tester), 'Failed.\nconnection refused');
      expect(_snackText(tester), isNot(contains('Exception:')));
    });

    testWidgets(
      'omits the second line entirely when nothing legible survives',
      (tester) async {
        // A bare `Exception('')` demotes to an empty string; a blank second row
        // is worse than none, so the helper drops it.
        await _fire(
          tester,
          (context) =>
              SnackBarHelper.error(context, 'Failed.', detail: Exception('')),
        );

        expect(_snackText(tester), 'Failed.');
      },
    );

    testWidgets('a null detail is the plain single-register message', (
      tester,
    ) async {
      await _fire(
        tester,
        (context) => SnackBarHelper.error(context, 'Failed.'),
      );

      expect(_snackText(tester), 'Failed.');
    });

    testWidgets('keeps the error background so tone is not the only signal', (
      tester,
    ) async {
      await _fire(
        tester,
        (context) => SnackBarHelper.error(context, 'Failed.', detail: 'why'),
      );

      final context = tester.element(find.byType(Scaffold));
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
        Theme.of(context).colorScheme.error,
      );
    });
  });

  group('SnackBarHelper.info detail', () {
    testWidgets('carries a demoted diagnostic the same way error does', (
      tester,
    ) async {
      await _fire(
        tester,
        (context) => SnackBarHelper.info(
          context,
          'Nothing to import.',
          detail: Exception('empty folder'),
        ),
      );

      expect(_snackText(tester), 'Nothing to import.\nempty folder');
    });
  });
}
