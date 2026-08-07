import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/rating_source.dart';
import 'package:cupola/core/widgets/rating_chip.dart';
import 'package:cupola/core/widgets/rating_chips_row.dart';

void main() {
  group('RatingChipsRow', () {
    testWidgets('renders nothing when ratings list is empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: RatingChipsRow(ratings: [])),
        ),
      );

      expect(find.byType(RatingChip), findsNothing);
    });

    testWidgets('renders correct number of RatingChip widgets', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RatingChipsRow(
              ratings: const [
                RatingSource(name: 'IMDb', value: 7.5, votes: 1000, icon: 'IM'),
                RatingSource(name: 'RT', value: 85.0, votes: 500, icon: 'RT'),
                RatingSource(name: 'MC', value: 70.0, votes: 200, icon: 'MC'),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(RatingChip), findsNWidgets(3));
    });

    testWidgets('displays formatted rating values', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RatingChipsRow(
              ratings: const [
                RatingSource(
                  name: 'IMDb',
                  value: 7.567,
                  votes: 1000,
                  icon: 'IM',
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.textContaining('7.6'), findsOneWidget);
    });

    testWidgets('each pill states its own scale, not a bare number', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RatingChipsRow(
              ratings: const [
                RatingSource(name: 'IMDb', value: 6.9, votes: 0, icon: 'IMDb'),
                RatingSource(
                  name: 'Metacritic',
                  value: 53,
                  votes: 0,
                  icon: 'Metacritic',
                ),
                RatingSource(
                  name: 'Rotten Tomatoes',
                  value: 57,
                  votes: 0,
                  icon: 'Rotten Tomatoes',
                ),
              ],
            ),
          ),
        ),
      );

      // Three sources, three scales, stated. The row used to render `6.9`,
      // `53.0` and `57.0` — which reads as one comparable set of numbers.
      expect(find.text('6.9/10'), findsOneWidget);
      expect(find.text('53/100'), findsOneWidget);
      expect(find.text('57%'), findsOneWidget);
      expect(find.textContaining('53.0'), findsNothing);
      expect(find.textContaining('57.0'), findsNothing);
    });

    testWidgets('speaks the scale as words rather than a slash', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RatingChipsRow(
              ratings: const [
                RatingSource(
                  name: 'Metacritic',
                  value: 53,
                  votes: 0,
                  icon: 'Metacritic',
                ),
              ],
            ),
          ),
        ),
      );

      // "53 slash 100" is worse than the ambiguity the denominator fixes.
      expect(
        tester.getSemantics(find.byType(RatingChip)),
        containsSemantics(label: 'Metacritic rating 53 out of 100'),
      );
    });

    testWidgets('a percentage source speaks "percent"', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RatingChipsRow(
              ratings: const [
                RatingSource(
                  name: 'Rotten Tomatoes',
                  value: 57,
                  votes: 1200,
                  icon: 'Rotten Tomatoes',
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(RatingChip)),
        containsSemantics(
          label: 'Rotten Tomatoes rating 57 percent',
          value: '1200 votes',
        ),
      );
    });

    testWidgets('renders ratings in a wrap when non-empty', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RatingChipsRow(
              ratings: const [
                RatingSource(name: 'IMDb', value: 7.5, votes: 1000, icon: 'IM'),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(Wrap), findsOneWidget);
      expect(find.byType(RatingChip), findsOneWidget);
    });
  });
}
