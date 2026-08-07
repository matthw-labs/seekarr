import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/media_info_card.dart';

void main() {
  group('MediaInfoCard', () {
    testWidgets('renders nothing when groups is empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: MediaInfoCard(groups: [])),
        ),
      );

      expect(find.text('Genre'), findsNothing);
      expect(find.text('Studio'), findsNothing);
    });

    testWidgets('renders group titles and content', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaInfoCard(
              groups: const [
                MediaInfoGroup(title: 'Genre', child: Text('Action')),
                MediaInfoGroup(title: 'Studio', child: Text('Warner')),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Genre'), findsOneWidget);
      expect(find.text('Action'), findsOneWidget);
      expect(find.text('Studio'), findsOneWidget);
      expect(find.text('Warner'), findsOneWidget);
    });
  });

  group('MediaFactsList', () {
    testWidgets('renders nothing when facts is empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: MediaFactsList(facts: [])),
        ),
      );

      expect(find.text('In Cinemas'), findsNothing);
      expect(find.text('2023-06-15'), findsNothing);
    });

    testWidgets('renders label-value pairs', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaFactsList(
              facts: const [
                MediaFact('In Cinemas', '2023-06-15'),
                MediaFact('Digital', '2023-09-01'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('In Cinemas'), findsOneWidget);
      expect(find.text('2023-06-15'), findsOneWidget);
      expect(find.text('Digital'), findsOneWidget);
      expect(find.text('2023-09-01'), findsOneWidget);
    });
  });
}
