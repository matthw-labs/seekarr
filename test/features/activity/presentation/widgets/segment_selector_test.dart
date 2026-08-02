import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/widgets/selection_pills.dart';
import 'package:seekarr/features/activity/presentation/widgets/segment_selector.dart';

/// Pumps the selector inside a scroll view and returns the height it occupies.
Future<double> _pumpAndMeasure(
  WidgetTester tester,
  TextScaler textScaler,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: Scaffold(
            body: CustomScrollView(
              slivers: [
                ActivitySegmentSelector<ActivitySegment>(
                  segments: ActivitySegment.values,
                  selected: ActivitySegment.queue,
                  onChanged: (_) {},
                  labelBuilder: (segment) => segment.label,
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 2000)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return tester.getSize(find.byType(SelectionPills<ActivitySegment>)).height;
}

void main() {
  group('ActivitySegmentSelector', () {
    testWidgets('the pinned header extent follows the reading size', (
      tester,
    ) async {
      final atDefault = await _pumpAndMeasure(tester, TextScaler.noScaling);
      final atLarge = await _pumpAndMeasure(
        tester,
        const TextScaler.linear(2.0),
      );

      // Both extents used to be a flat `56.0` around a control made of text, so
      // the selector could not grow and Flutter painted its overflow stripe
      // across a pinned header the user cannot scroll away from.
      expect(atDefault, closeTo(56.0, 0.5));
      expect(atLarge, greaterThan(atDefault));
    });

    testWidgets('does not overflow at an accessibility reading size', (
      tester,
    ) async {
      await _pumpAndMeasure(tester, const TextScaler.linear(3.0));

      expect(tester.takeException(), isNull);
    });

    testWidgets('the selected segment is announced as selected', (
      tester,
    ) async {
      await _pumpAndMeasure(tester, TextScaler.noScaling);

      // The `SegmentedButton` this replaced carried its own semantics; the global
      // screen's hand-rolled equivalent did not. Both now route through one
      // control, so neither can drift again.
      expect(
        find.semantics.byLabel('Queue'),
        containsSemantics(isButton: true, isSelected: true),
      );
      expect(
        find.semantics.byLabel('Blocklist'),
        containsSemantics(isButton: true, isSelected: false),
      );
    });
  });
}
