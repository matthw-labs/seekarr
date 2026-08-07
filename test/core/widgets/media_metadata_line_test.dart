import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/media_metadata_line.dart';

void main() {
  group('MediaMetadataLine', () {
    testWidgets('renders dot-separated items', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: MediaMetadataLine(items: ['2023', '120 min'])),
        ),
      );

      expect(find.text('2023 • 120 min'), findsOneWidget);
    });

    testWidgets('filters out empty items', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MediaMetadataLine(items: ['2023', '', '120 min']),
          ),
        ),
      );

      expect(find.text('2023 • 120 min'), findsOneWidget);
    });

    testWidgets('renders nothing when all items are empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: MediaMetadataLine(items: ['', '  '])),
        ),
      );

      expect(find.text('2023'), findsNothing);
      expect(find.text('•'), findsNothing);
    });

    testWidgets('renders single item without dot', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: MediaMetadataLine(items: ['2023'])),
        ),
      );

      expect(find.text('2023'), findsOneWidget);
    });

    testWidgets('respects textAlign parameter', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MediaMetadataLine(
              items: ['2023'],
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );

      final textWidget = tester.widget<Text>(find.text('2023'));
      expect(textWidget.textAlign, TextAlign.center);
    });
  });
}
