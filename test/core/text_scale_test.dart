import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/text_scale.dart';

/// Builds a context carrying [scale] as the reading size.
Future<BuildContext> _contextAt(WidgetTester tester, double scale) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return captured;
}

void main() {
  group('TextScaleMetrics.boxHeight', () {
    testWidgets('is unchanged at the default reading size', (tester) async {
      final context = await _contextAt(tester, 1.0);

      expect(
        TextScaleMetrics.boxHeight(context, base: 176, textHeight: 34),
        176,
      );
    });

    testWidgets('grows by exactly what the text grew', (tester) async {
      final context = await _contextAt(tester, 1.5);

      // 34pt of text at 1.5x needs 17pt more room, and only the text part grows
      // — the 138pt poster above it keeps its size.
      expect(
        TextScaleMetrics.boxHeight(context, base: 176, textHeight: 34),
        closeTo(176 + 17, 0.01),
      );
    });

    testWidgets('stops growing past the clamp', (tester) async {
      final atCap = await _contextAt(
        tester,
        TextScaleMetrics.defaultMaxScaleFactor,
      );
      final capped = TextScaleMetrics.boxHeight(
        atCap,
        base: 176,
        textHeight: 34,
      );

      final beyond = await _contextAt(tester, 4.0);
      expect(
        TextScaleMetrics.boxHeight(beyond, base: 176, textHeight: 34),
        closeTo(capped, 0.01),
      );
    });

    testWidgets('never shrinks below the base', (tester) async {
      final context = await _contextAt(tester, 0.5);

      expect(
        TextScaleMetrics.boxHeight(context, base: 176, textHeight: 34),
        176,
      );
    });
  });

  group('TextScaleMetrics.aspectRatio', () {
    testWidgets('is unchanged at the default reading size', (tester) async {
      final context = await _contextAt(tester, 1.0);

      expect(TextScaleMetrics.aspectRatio(context, base: 1.4), 1.4);
    });

    testWidgets('drops as text grows, making cells taller', (tester) async {
      final context = await _contextAt(tester, 1.5);

      // A lower ratio means a taller cell for the same width, which is what
      // keeps a grid tile's label from being clipped.
      expect(TextScaleMetrics.aspectRatio(context, base: 1.4), lessThan(1.4));
    });

    testWidgets('stops dropping past the clamp', (tester) async {
      final atCap = await _contextAt(
        tester,
        TextScaleMetrics.defaultMaxScaleFactor,
      );
      final capped = TextScaleMetrics.aspectRatio(atCap, base: 1.4);

      final beyond = await _contextAt(tester, 4.0);
      expect(
        TextScaleMetrics.aspectRatio(beyond, base: 1.4),
        closeTo(capped, 0.0001),
      );
      // Still a wide-ish tile, not a column.
      expect(capped, greaterThan(0.8));
    });

    testWidgets('never grows above the base', (tester) async {
      final context = await _contextAt(tester, 0.5);

      expect(TextScaleMetrics.aspectRatio(context, base: 1.4), 1.4);
    });
  });
}
