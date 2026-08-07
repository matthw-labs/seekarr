import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';

void main() {
  const childKey = ValueKey('card-child');

  Widget host({
    required AppCardPressFeedback feedback,
    VoidCallback? onTap,
    String? semanticLabel,
    String? semanticValue,
    String? semanticHint,
  }) => MaterialApp(
    theme: AppTheme.darkTheme(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 120,
          height: 32,
          child: AppCard.surfaceOutlined(
            onTap: onTap,
            pressFeedback: feedback,
            padding: EdgeInsets.zero,
            semanticLabel: semanticLabel,
            semanticValue: semanticValue,
            semanticHint: semanticHint,
            excludeChildSemantics: semanticLabel != null,
            child: const SizedBox.expand(key: childKey),
          ),
        ),
      ),
    ),
  );

  group('press feedback', () {
    testWidgets('ink is the default and paints an InkWell', (tester) async {
      await tester.pumpWidget(
        host(feedback: AppCardPressFeedback.ink, onTap: () {}),
      );

      expect(find.byType(InkWell), findsOneWidget);
      expect(find.byType(PressableScale), findsNothing);
    });

    testWidgets('scale dips instead, and paints no ink', (tester) async {
      // Both halves matter: an `InkWell` left in place would splash *and* dip,
      // and the splash is the half this mode exists to reject.
      await tester.pumpWidget(
        host(feedback: AppCardPressFeedback.scale, onTap: () {}),
      );

      expect(find.byType(PressableScale), findsOneWidget);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('scale still fires the tap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(feedback: AppCardPressFeedback.scale, onTap: () => taps++),
      );

      await tester.tap(find.byType(AppCard));
      expect(taps, 1);
    });

    testWidgets('both modes leave the interior exactly the same height', (
      tester,
    ) async {
      // The regression this locks down. `AppCard` keeps the outline on the
      // `Material`'s `shape` under both feedback modes precisely because a
      // shape's stroke costs no layout, where a `BoxDecoration.border` insets
      // its child 1px per side. When the press-scale was first taken by
      // bypassing `onTap` and wrapping from outside, the card silently moved
      // onto the bordered branch and every card sized to the pixel lost 2.
      await tester.pumpWidget(
        host(feedback: AppCardPressFeedback.ink, onTap: () {}),
      );
      final inkHeight = tester.getSize(find.byKey(childKey)).height;

      await tester.pumpWidget(
        host(feedback: AppCardPressFeedback.scale, onTap: () {}),
      );
      final scaleHeight = tester.getSize(find.byKey(childKey)).height;

      expect(inkHeight, 32);
      expect(scaleHeight, inkHeight);
    });

    testWidgets('scale publishes one labelled button, hint included', (
      tester,
    ) async {
      // `PressableScale` owns the semantics node in this mode, so everything
      // `AppCard` would have published itself has to reach it — the hint was
      // the piece with nowhere to go until `PressableScale` grew one.
      await tester.pumpWidget(
        host(
          feedback: AppCardPressFeedback.scale,
          onTap: () {},
          semanticLabel: 'Radarr',
          semanticValue: 'Online',
          semanticHint: 'opens the Radarr dashboard',
        ),
      );

      expect(
        tester.getSemantics(find.byType(AppCard)),
        containsSemantics(
          label: 'Radarr',
          value: 'Online',
          hint: 'opens the Radarr dashboard',
          isButton: true,
          hasTapAction: true,
        ),
      );

      // Exactly one actionable node, not a nested pair.
      expect(
        find.bySemanticsLabel('Radarr'),
        findsOneWidget,
        reason: 'AppCard must not publish a second node beside PressableScale',
      );
    });

    testWidgets('an untappable card ignores the feedback mode', (tester) async {
      await tester.pumpWidget(host(feedback: AppCardPressFeedback.scale));

      expect(find.byType(PressableScale), findsNothing);
      expect(find.byType(InkWell), findsNothing);
    });
  });
}
