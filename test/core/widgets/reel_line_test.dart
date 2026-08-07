import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reel_text/reel_text.dart';

import 'package:cupola/core/widgets/reel_line.dart';

/// The gate [ReelLine] applies is a real paragraph shaping, and it runs inside a
/// [LayoutBuilder] — so without memoisation it is paid again on every build of
/// every rolling line, including every frame of any ancestor animation. These
/// tests pin both halves: the work is not redone when nothing that can change
/// the answer changed, and it *is* redone when something did.
void main() {
  setUp(ReelLine.debugResetMeasurements);

  const style = TextStyle(fontSize: 14);

  testWidgets('shapes the line once and reuses it across rebuilds', (
    tester,
  ) async {
    final rebuild = ValueNotifier<int>(0);
    addTearDown(rebuild.dispose);

    await _pump(tester, width: 1000, rebuild: rebuild, style: style);

    expect(ReelLine.debugMeasurements, 1);
    expect(find.byType(ReelText), findsOneWidget);

    rebuild.value++;
    await tester.pump();
    rebuild.value++;
    await tester.pump();

    expect(
      ReelLine.debugMeasurements,
      1,
      reason: 'nothing that can change the answer changed',
    );
  });

  testWidgets('two lines with the same text and style share one shaping', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            child: Column(
              children: [
                ReelLine('Downloading', style: style),
                ReelLine('Downloading', style: style),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ReelText), findsNWidgets(2));
    expect(ReelLine.debugMeasurements, 1);
  });

  testWidgets('a width change re-answers the question without re-shaping', (
    tester,
  ) async {
    // The painter is laid out unconstrained, so what it reports is the line's
    // intrinsic width and the box only enters as a comparison. A resize — a
    // rotation, a split view, a collapsing header — must not re-shape anything.
    final rebuild = ValueNotifier<int>(0);
    addTearDown(rebuild.dispose);

    await _pump(tester, width: 1000, rebuild: rebuild, style: style);
    expect(find.byType(ReelText), findsOneWidget);
    expect(ReelLine.debugMeasurements, 1);

    await _pump(tester, width: 20, rebuild: rebuild, style: style);

    expect(
      find.byType(ReelText),
      findsNothing,
      reason: 'it no longer fits, so it must fall back',
    );
    expect(find.text('Downloading'), findsOneWidget);
    expect(ReelLine.debugMeasurements, 1);
  });

  testWidgets('a text scale change re-shapes and can flip the answer', (
    tester,
  ) async {
    await _pump(tester, width: 300, style: style);
    expect(find.byType(ReelText), findsOneWidget);
    expect(ReelLine.debugMeasurements, 1);

    await _pump(
      tester,
      width: 300,
      style: style,
      textScaler: const TextScaler.linear(4),
    );

    expect(ReelLine.debugMeasurements, 2);
    expect(
      find.byType(ReelText),
      findsNothing,
      reason: 'at an accessibility reading size the roll is impossible',
    );
    expect(find.text('Downloading'), findsOneWidget);
  });

  testWidgets('a style change re-shapes', (tester) async {
    await _pump(tester, width: 1000, style: style);
    expect(ReelLine.debugMeasurements, 1);

    await _pump(
      tester,
      width: 1000,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    );

    expect(ReelLine.debugMeasurements, 2);
  });

  testWidgets('an unbounded parent rolls without measuring anything', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(children: [ReelLine('Downloading', style: style)]),
        ),
      ),
    );

    expect(find.byType(ReelText), findsOneWidget);
    expect(ReelLine.debugMeasurements, 0);
  });

  testWidgets('Reduce Motion renders a plain Text and measures nothing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: SizedBox(
              width: 1000,
              child: ReelLine('Downloading', style: style),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ReelText), findsNothing);
    expect(find.text('Downloading'), findsOneWidget);
    expect(ReelLine.debugMeasurements, 0);
  });

  testWidgets('a system font change invalidates every cached shaping', (
    tester,
  ) async {
    // A cached width outlives the font it was measured with. Swapping a
    // fallback face in, or the user changing the system font, moves every one
    // of them — and a stale cache would keep answering with the old metrics
    // forever, so a line that no longer fits would keep rolling off the edge.
    await _pump(tester, width: 1000, style: style);
    expect(ReelLine.debugMeasurements, 1);

    await _notifyFontsChanged(tester);
    await _pump(tester, width: 1000, style: style);

    expect(ReelLine.debugMeasurements, 2);
  });

  testWidgets('the rich variant measures its flattened span once', (
    tester,
  ) async {
    final rebuild = ValueNotifier<int>(0);
    addTearDown(rebuild.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            child: ValueListenableBuilder<int>(
              valueListenable: rebuild,
              builder: (context, _, _) => ReelLine.rich(
                const TextSpan(
                  children: [
                    TextSpan(text: '12'),
                    TextSpan(text: ' MB/s'),
                  ],
                ),
                plain: '12 MB/s',
                style: style,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ReelText), findsOneWidget);
    expect(ReelLine.debugMeasurements, 1);

    rebuild.value++;
    await tester.pump();

    expect(ReelLine.debugMeasurements, 1);
  });
}

/// Pumps one [ReelLine] inside a box of [width], optionally under a listenable
/// that can force a rebuild with every input unchanged.
Future<void> _pump(
  WidgetTester tester, {
  required double width,
  required TextStyle style,
  ValueNotifier<int>? rebuild,
  TextScaler textScaler = TextScaler.noScaling,
  String text = 'Downloading',
}) async {
  final line = ReelLine(text, style: style);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: Scaffold(
          body: SizedBox(
            width: width,
            child: rebuild == null
                ? line
                : ValueListenableBuilder<int>(
                    valueListenable: rebuild,
                    builder: (context, _, _) => ReelLine(text, style: style),
                  ),
          ),
        ),
      ),
    ),
  );
}

/// Delivers the platform's `fontsChange` notification, which is what
/// `PaintingBinding.systemFonts` fans out to its listeners.
Future<void> _notifyFontsChanged(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.system.name,
    SystemChannels.system.codec.encodeMessage(<String, dynamic>{
      'type': 'fontsChange',
    }),
    null,
  );
  await tester.pump();
}
