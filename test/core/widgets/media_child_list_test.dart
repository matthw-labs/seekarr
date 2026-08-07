import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/status/media_status.dart';
import 'package:seekarr/core/widgets/media_child_list.dart';

void main() {
  group('MediaChildGroupSliver selection', () {
    testWidgets('re-tapping the selected container keeps it expanded', (
      tester,
    ) async {
      await _pumpGroups(tester, groupCount: 2, childCount: 25);

      await tester.tap(find.text('Show all 25 episodes'));
      await tester.pump();
      expect(find.text('Show fewer'), findsOneWidget);
      expect(find.text('S1E25'), findsOneWidget);

      // The rail highlights the first container before any tap has happened,
      // and `SelectionPills` fires `onSelected` unconditionally — so a guard
      // comparing against the *stored* id (still null) let this fall through
      // and silently collapsed 25 rows back to eight.
      await tester.tap(find.text('S1'));
      await tester.pump();

      expect(find.text('Show fewer'), findsOneWidget);
      expect(find.text('S1E25'), findsOneWidget);
    });

    testWidgets('re-tapping a container chosen earlier keeps it expanded', (
      tester,
    ) async {
      await _pumpGroups(tester, groupCount: 2, childCount: 25);

      await tester.tap(find.text('S2'));
      await tester.pump();
      await tester.tap(find.text('Show all 25 episodes'));
      await tester.pump();
      expect(find.text('S2E25'), findsOneWidget);

      await tester.tap(find.text('S2'));
      await tester.pump();

      expect(find.text('Show fewer'), findsOneWidget);
      expect(find.text('S2E25'), findsOneWidget);
    });

    testWidgets('switching container still returns to collapsed', (
      tester,
    ) async {
      await _pumpGroups(tester, groupCount: 2, childCount: 25);

      await tester.tap(find.text('Show all 25 episodes'));
      await tester.pump();
      expect(find.text('Show fewer'), findsOneWidget);

      await tester.tap(find.text('S2'));
      await tester.pump();

      // Expanding season 1 must not drop the user into 25 rows of season 2.
      expect(find.text('Show all 25 episodes'), findsOneWidget);
      expect(find.text('Show fewer'), findsNothing);
      expect(find.text('S2E9'), findsNothing);
    });
  });
}

Future<void> _pumpGroups(
  WidgetTester tester, {
  required int groupCount,
  required int childCount,
}) async {
  // Tall enough that the expanded run is genuinely built rather than merely
  // off-screen, so the assertions are about the collapse and not about laziness.
  tester.view.physicalSize = const Size(600, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            MediaChildGroupSliver(
              groups: [
                for (var number = 1; number <= groupCount; number++)
                  MediaChildGroup(
                    id: number,
                    shortLabel: 'S$number',
                    label: 'Season $number',
                    status: const MediaStatusInfo(
                      availability: MediaAvailability.available,
                    ),
                  ),
              ],
              accent: Colors.amber,
              childCount: (_) => childCount,
              childBuilder: (context, group, index) =>
                  Text('S${group.id}E${index + 1}'),
              emptyState: const Text('No seasons'),
              pickerLabel: 'All $groupCount seasons',
              pickerTitle: 'Seasons',
              childNoun: 'episodes',
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
