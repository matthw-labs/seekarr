import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/media_detail_header_metrics.dart';

void main() {
  group('MediaDetailHeaderMetrics', () {
    Future<(double minExtent, double maxExtent)> resolve(
      WidgetTester tester, {
      required double textScale,
      double topPadding = 59,
    }) async {
      late double minExtent;
      late double maxExtent;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(textScale),
            padding: EdgeInsets.only(top: topPadding),
          ),
          child: Builder(
            builder: (context) {
              minExtent = MediaDetailHeaderMetrics.minExtent(context);
              maxExtent = MediaDetailHeaderMetrics.maxExtent(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return (minExtent, maxExtent);
    }

    testWidgets('minExtent never exceeds maxExtent across reading sizes', (
      tester,
    ) async {
      for (final scale in const [1.0, 1.3, 1.6, 2.0, 3.0]) {
        final (minExtent, maxExtent) = await resolve(tester, textScale: scale);
        expect(
          minExtent,
          lessThan(maxExtent),
          reason: 'clamps crossed at scale $scale',
        );
      }
    });

    testWidgets('default scale matches the prototype hero geometry', (
      tester,
    ) async {
      final (minExtent, maxExtent) = await resolve(tester, textScale: 1.0);
      expect(minExtent, 59 + MediaDetailHeaderMetrics.baseCollapsedHeight);
      expect(maxExtent, 59 + MediaDetailHeaderMetrics.baseExpandedHeight);
    });

    testWidgets('both extents grow with the reading size', (tester) async {
      final (min1, max1) = await resolve(tester, textScale: 1.0);
      final (min2, max2) = await resolve(tester, textScale: 2.0);
      expect(min2, greaterThan(min1));
      expect(max2, greaterThan(max1));
    });

    Future<(double height, double scaledTen)> resolveHero(
      WidgetTester tester, {
      required double textScale,
    }) async {
      late double height;
      late double scaledTen;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Builder(
            builder: (context) {
              height = MediaDetailHeaderMetrics.expandedHeight(context);
              scaledTen = MediaDetailHeaderMetrics.heroTextScaler(
                context,
              ).scale(10);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return (height, scaledTen);
    }

    testWidgets('the hero grows by, and paints on, the same one clamp', (
      tester,
    ) async {
      const ceiling = MediaDetailHeaderMetrics.heroMaxScaleFactor;

      final (baseHeight, baseTen) = await resolveHero(tester, textScale: 1.0);
      final (justBelow, _) = await resolveHero(
        tester,
        textScale: ceiling - 0.1,
      );
      final (atCeiling, ceilingTen) = await resolveHero(
        tester,
        textScale: ceiling,
      );
      final (atTriple, tripleTen) = await resolveHero(tester, textScale: 3.0);

      // Below the ceiling, height and scaler move together.
      expect(baseTen, 10);
      expect(justBelow, greaterThan(baseHeight));
      expect(atCeiling, greaterThan(justBelow));
      expect(ceilingTen, closeTo(10 * ceiling, 0.001));

      // At and past it, both stop — which is the whole invariant: a hero grown
      // on one clamp and painted on another clips its status badge off the top.
      expect(atTriple, atCeiling);
      expect(tripleTen, ceilingTen);
    });
  });

  group('MediaDetailHeroPhase', () {
    test('all getters stay within [0, 1]-derived ranges across t', () {
      for (var i = 0; i <= 100; i++) {
        final t = i / 100;
        for (final reduceMotion in const [false, true]) {
          final phase = MediaDetailHeroPhase(t: t, reduceMotion: reduceMotion);
          expect(phase.summaryFade, inInclusiveRange(0, 1));
          expect(phase.scrimDepth, inInclusiveRange(0, 1));
          expect(phase.barReveal, inInclusiveRange(0, 1));
          expect(phase.posterScale, inInclusiveRange(0.86, 1));
          expect(phase.posterLift, inInclusiveRange(0, 1));
          expect(phase.glowAlpha, inInclusiveRange(0.12, 0.22));
        }
      }
    });

    test('t = 0 renders identity — byte-identical to the static hero', () {
      const phase = MediaDetailHeroPhase(t: 0);
      expect(phase.summaryFade, 1);
      expect(phase.scrimDepth, 0);
      expect(phase.barReveal, 0);
      expect(phase.posterScale, 1);
      expect(phase.posterLift, 0);
      expect(phase.glowAlpha, 0.22);
    });

    test('t = 1 reaches the fully collapsed pose', () {
      const phase = MediaDetailHeroPhase(t: 1);
      expect(phase.summaryFade, 0);
      expect(phase.scrimDepth, 1);
      expect(phase.barReveal, 1);
      expect(phase.posterScale, closeTo(0.86, 0.001));
      expect(phase.glowAlpha, closeTo(0.12, 0.001));
    });

    test('reduce motion flattens only the decorative getters', () {
      const phase = MediaDetailHeroPhase(t: 0.7, reduceMotion: true);
      expect(phase.posterScale, 1);
      expect(phase.posterLift, 0);
      expect(phase.parallaxFactor, 0);
      // Functional layers keep tracking the finger.
      expect(phase.scrimDepth, greaterThan(0));
      expect(phase.barReveal, greaterThan(0));
    });
  });
}
