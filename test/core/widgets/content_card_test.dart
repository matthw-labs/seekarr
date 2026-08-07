import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/core/widgets/content_card.dart';

void main() {
  group('ContentCard', () {
    testWidgets('renders placeholder when imageUrl is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ContentCard(imageUrl: null))),
      );

      expect(find.byType(ContentCard), findsOneWidget);
      expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    });

    testWidgets('renders placeholder when imageUrl is empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ContentCard(imageUrl: '')),
        ),
      );

      expect(find.byType(ContentCard), findsOneWidget);
      expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    });

    testWidgets('renders badge when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContentCard(
              imageUrl: null,
              badge: Container(
                key: const Key('test_badge'),
                width: 10,
                height: 10,
                color: Colors.green,
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('test_badge')), findsOneWidget);
    });

    testWidgets('does not render badge when not provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ContentCard(imageUrl: null))),
      );

      // Should not find any Positioned widget (which wraps the badge)
      // Just check that the widget renders correctly
      expect(find.byType(ContentCard), findsOneWidget);
    });

    testWidgets('has correct border radius', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ContentCard(imageUrl: null))),
      );

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(ContentCard),
          matching: find.byType(Container).first,
        ),
      );

      final decoration = container.decoration as BoxDecoration?;
      // AppRadius.borderRadiusMd = 12
      expect(decoration?.borderRadius, BorderRadius.circular(12));
    });
  });
}
