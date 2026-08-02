import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/widgets/selection_pills.dart';

enum _Segment { history, blocklist }

Future<void> _pump(
  WidgetTester tester, {
  _Segment selected = _Segment.history,
  ValueChanged<_Segment>? onSelected,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: Scaffold(
            body: SelectionPills<_Segment>(
              values: _Segment.values,
              selected: selected,
              labelBuilder: (value) => value.name,
              onSelected: onSelected ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('SelectionPills', () {
    testWidgets('each pill is a button that announces its own selected state', (
      tester,
    ) async {
      // The control this replaces had no semantics node at all: no button role,
      // no accessible name and no selected state, so a screen-reader user could
      // neither tell it was tappable nor which segment was active.
      await _pump(tester);

      expect(
        find.semantics.byLabel('history'),
        containsSemantics(isButton: true, isSelected: true, hasTapAction: true),
      );
      expect(
        find.semantics.byLabel('blocklist'),
        containsSemantics(
          isButton: true,
          isSelected: false,
          hasTapAction: true,
        ),
      );
    });

    testWidgets('tapping a pill reports that value', (tester) async {
      final tapped = <_Segment>[];
      await _pump(tester, onSelected: tapped.add);

      await tester.tap(find.text('blocklist'));
      await tester.pumpAndSettle();

      expect(tapped, [_Segment.blocklist]);
    });

    testWidgets('every pill clears the platform touch-target minimum', (
      tester,
    ) async {
      await _pump(tester);

      for (final label in _Segment.values.map((value) => value.name)) {
        expect(
          tester.getSize(find.text(label).hitTestable()).height,
          lessThanOrEqualTo(48.0),
          reason: '$label label should sit inside its pill',
        );
      }

      // 48dp is the stricter of the two platform minimums, and it is a floor on
      // the pill rather than a fixed height.
      for (final label in _Segment.values.map((value) => value.name)) {
        final pill = find.ancestor(
          of: find.text(label),
          matching: find.byType(Container),
        );
        expect(tester.getSize(pill.first).height, greaterThanOrEqualTo(48.0));
      }
    });

    testWidgets('does not overflow at an accessibility reading size', (
      tester,
    ) async {
      // The row scrolls horizontally and the pill has no fixed height, so a large
      // reading size must widen and heighten it rather than clip it. A
      // `RenderFlex` overflow would surface here as a pumped exception.
      await _pump(tester, textScaler: const TextScaler.linear(3.0));

      expect(tester.takeException(), isNull);
    });

    testWidgets('a selected pill never paints the raw accent as its label in '
        'light theme', (tester) async {
      // The Luminance Rule, second half: a saturated accent over a 13% tint of
      // itself measures under 2:1 in light theme. The same pill passes in dark,
      // so a dark-only check proves nothing — hence this asserts the light case
      // specifically.
      const accent = Color(0xFFF59E0B); // Radarr amber, the worst offender.

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.light),
          home: Scaffold(
            body: SelectionPills<_Segment>(
              values: _Segment.values,
              selected: _Segment.history,
              accent: accent,
              labelBuilder: (value) => value.name,
              onSelected: (_) {},
            ),
          ),
        ),
      );

      final label = tester.widget<Text>(find.text('history'));
      expect(label.style?.color, isNot(accent));
    });
  });
}
