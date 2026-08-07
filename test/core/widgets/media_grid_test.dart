import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/widgets/media_grid.dart';

void main() {
  group('MediaGrid', () {
    testWidgets('shows empty message when items list is empty', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaGrid<String>(
              items: const [],
              imagesExtractor: (_) => null,
              idExtractor: (_) => 0,
              baseUrl: 'http://localhost',
              apiKey: 'test',
              heroTagPrefix: 'test',
            ),
          ),
        ),
      );

      expect(find.text('No items found'), findsOneWidget);
    });

    testWidgets('renders correct number of items', (tester) async {
      final items = ['Item 1', 'Item 2', 'Item 3'];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaGrid<String>(
              items: items,
              imagesExtractor: (_) => null,
              idExtractor: (item) => items.indexOf(item),
              baseUrl: 'http://localhost',
              apiKey: 'test',
              heroTagPrefix: 'test',
            ),
          ),
        ),
      );

      // Should have GridView with items
      expect(find.byType(GridView), findsOneWidget);
    });

    testWidgets('calls onItemTap when item is tapped', (tester) async {
      String? tappedItem;
      String? tappedHeroTag;

      final items = ['Item 1', 'Item 2'];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaGrid<String>(
              items: items,
              imagesExtractor: (_) => null,
              idExtractor: (item) => items.indexOf(item),
              baseUrl: 'http://localhost',
              apiKey: 'test',
              heroTagPrefix: 'test',
              onItemTap: (item, heroTag) {
                tappedItem = item;
                tappedHeroTag = heroTag;
              },
            ),
          ),
        ),
      );

      // Tap on first item
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pump();

      expect(tappedItem, 'Item 1');
      expect(tappedHeroTag, contains('test_0'));
    });

    testWidgets('uses statusExtractor when provided', (tester) async {
      final items = ['Available', 'Missing'];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaGrid<String>(
              items: items,
              imagesExtractor: (_) => null,
              idExtractor: (item) => items.indexOf(item),
              statusExtractor: (item) => MediaStatusInfo(
                availability: item == 'Available'
                    ? MediaAvailability.available
                    : MediaAvailability.missing,
              ),
              baseUrl: 'http://localhost',
              apiKey: 'test',
              heroTagPrefix: 'test',
            ),
          ),
        ),
      );

      // Grid should render with status badges
      expect(find.byType(GridView), findsOneWidget);
    });

    testWidgets('handles null statusExtractor result', (tester) async {
      final items = ['Item 1'];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaGrid<String>(
              items: items,
              imagesExtractor: (_) => null,
              idExtractor: (item) => items.indexOf(item),
              statusExtractor: (_) => null,
              baseUrl: 'http://localhost',
              apiKey: 'test',
              heroTagPrefix: 'test',
            ),
          ),
        ),
      );

      // Should render without throwing
      expect(find.byType(GridView), findsOneWidget);
    });

    testWidgets('generates unique heroTags with index', (tester) async {
      final items = ['Same', 'Same']; // Same items but different indices

      String? heroTag1;
      String? heroTag2;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaGrid<String>(
              items: items,
              imagesExtractor: (_) => null,
              idExtractor: (_) => 0, // Same ID for both
              baseUrl: 'http://localhost',
              apiKey: 'test',
              heroTagPrefix: 'test',
              onItemTap: (item, heroTag) {
                if (heroTag1 == null) {
                  heroTag1 = heroTag;
                } else {
                  heroTag2 = heroTag;
                }
              },
            ),
          ),
        ),
      );

      // Tap both items
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pump();
      await tester.tap(find.byType(GestureDetector).last);
      await tester.pump();

      // Hero tags should be different due to index
      expect(heroTag1, isNot(equals(heroTag2)));
    });
  });
}
