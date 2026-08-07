import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/header_action_row.dart';

void main() {
  group('HeaderActionRow.buttonHeight', () {
    test('clears the platform touch-target minimums', () {
      // 44pt is iOS' floor and the number this codebase writes down for itself
      // on the detail back button; 48dp is Android's. One shared constant has to
      // clear the larger of the two. It used to be 42.
      expect(HeaderActionRow.buttonHeight, greaterThanOrEqualTo(44));
      expect(HeaderActionRow.buttonHeight, greaterThanOrEqualTo(48));
    });
  });

  group('HeaderActionButton', () {
    testWidgets('the button itself is a full touch target', (tester) async {
      await _pumpButtons(tester);

      for (final size
          in tester
              .widgetList<OutlinedButton>(find.byType(OutlinedButton))
              .map((button) => tester.getSize(find.byWidget(button)))) {
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }
    });

    testWidgets('adjacent targets keep at least 8dp between them', (
      tester,
    ) async {
      for (final scale in const [1.0, 1.6]) {
        await _pumpButtons(tester, textScale: scale);

        final buttons = find.byType(OutlinedButton);
        expect(buttons, findsNWidgets(2));
        final first = tester.getRect(buttons.at(0));
        final second = tester.getRect(buttons.at(1));

        expect(
          second.left - first.right,
          greaterThanOrEqualTo(AppSpacing.sm),
          reason: 'targets must stay apart at ${scale}x reading size',
        );
      }
    });

    testWidgets('a two-word caption wraps instead of eliding', (tester) async {
      await _pumpButtons(tester);

      final wide = tester.renderObject<RenderParagraph>(
        find.text('Auto search'),
      );
      final narrow = tester.renderObject<RenderParagraph>(find.text('Open'));

      // Two lines used, nothing dropped. The column this replaced set the same
      // label at 9pt with maxLines: 1 and shipped "Auto…".
      expect(wide.didExceedMaxLines, isFalse);
      expect(narrow.didExceedMaxLines, isFalse);
      expect(
        tester.getSize(find.text('Auto search')).height,
        greaterThan(tester.getSize(find.text('Open')).height),
        reason: 'the long caption should have taken a second line',
      );
    });

    testWidgets('captions wrap rather than elide, at every reading size', (
      tester,
    ) async {
      for (final scale in const [1.0, 1.6, 3.0]) {
        await _pumpButtons(tester, textScale: scale);

        final caption = tester.widget<Text>(find.text('Auto search'));
        // Wrapping is the behaviour and eliding is only the floor. maxLines: 1
        // plus an ellipsis is what shipped "Auto…" at an accessibility size.
        expect(caption.maxLines, 2);
        expect(caption.softWrap ?? true, isTrue);
        expect(find.text('Open'), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'no overflow at ${scale}x reading size',
        );
      }
    });

    testWidgets('the caption stops growing at the 1.6x clamp', (tester) async {
      await _pumpButtons(tester, textScale: 1.0);
      final base = tester.getSize(find.byType(HeaderActionButton).first);

      await _pumpButtons(tester, textScale: 1.6);
      final atClamp = tester.getSize(find.byType(HeaderActionButton).first);

      await _pumpButtons(tester, textScale: 3.0);
      final past = tester.getSize(find.byType(HeaderActionButton).first);

      // The caption follows the reading size...
      expect(atClamp.height, greaterThan(base.height));
      // ...and then stops, rather than growing without bound and eliding.
      expect(past.height, atClamp.height);
      // The measure never moves: a widening column would take its extra room
      // off the primary action beside it.
      expect(base.width, HeaderActionButton.captionMeasure);
      expect(past.width, HeaderActionButton.captionMeasure);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the icon names the button and the caption is not read twice', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpButtons(tester);

      expect(find.semantics.byLabel('Auto search'), findsOne);
      expect(find.semantics.byLabel('Open in Radarr'), findsOne);
      // The caption is a duplicate for the ear, so it is excluded — while
      // staying fully legible for the eye.
      expect(find.semantics.byLabel('Open'), findsNothing);
      handle.dispose();
    });
  });

  group('ActionStateGlyph', () {
    testWidgets('morphs idle to busy to a held confirmation', (tester) async {
      await _pumpGlyph(tester);
      expect(find.byIcon(Icons.saved_search_rounded), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await _pumpGlyph(tester, isBusy: true);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await _pumpGlyph(tester, isConfirmed: true);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byIcon(Icons.saved_search_rounded), findsNothing);
    });

    testWidgets('the confirmation says so out loud', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpGlyph(tester, isConfirmed: true);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.semantics.byLabel('Auto search complete'), findsOne);
      handle.dispose();
    });

    testWidgets('reduce motion removes the animator, not its duration', (
      tester,
    ) async {
      await _pumpGlyph(tester, isConfirmed: true, reduceMotion: true);

      expect(find.byType(AnimatedSwitcher), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });
  });
}

Future<void> _pumpButtons(WidgetTester tester, {double textScale = 1.0}) {
  return _pump(
    tester,
    textScale: textScale,
    child: HeaderActionRow(
      expanded: const SizedBox(height: HeaderActionRow.buttonHeight),
      crossAxisAlignment: CrossAxisAlignment.start,
      trailing: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          HeaderActionButton(
            icon: Icons.saved_search_rounded,
            label: 'Auto search',
          ),
          SizedBox(width: AppSpacing.sm),
          HeaderActionButton(
            icon: Icons.open_in_new_rounded,
            label: 'Open',
            semanticLabel: 'Open in Radarr',
          ),
        ],
      ),
    ),
  );
}

Future<void> _pumpGlyph(
  WidgetTester tester, {
  bool isBusy = false,
  bool isConfirmed = false,
  bool reduceMotion = false,
}) {
  return _pump(
    tester,
    reduceMotion: reduceMotion,
    child: ActionStateGlyph(
      icon: Icons.saved_search_rounded,
      label: 'Auto search',
      isBusy: isBusy,
      isConfirmed: isConfirmed,
    ),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required Widget child,
  double textScale = 1.0,
  bool reduceMotion = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, inner) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: inner!,
      ),
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pump();
}
