import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/activity/presentation/widgets/sonarr_wanted_hierarchy.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';

void main() {
  group('SonarrWantedHierarchy', () {
    final service = SonarrService(
      ApiClient(baseUrl: 'http://localhost', apiKey: 'test'),
    );

    testWidgets('groups episodes by series title', (tester) async {
      final items = [
        {
          'series': {'title': 'Show B'},
          'seasonNumber': 1,
          'episodeNumber': 2,
          'title': 'Ep2',
        },
        {
          'series': {'title': 'Show A'},
          'seasonNumber': 1,
          'episodeNumber': 1,
          'title': 'Pilot',
        },
        {
          'series': {'title': 'Show B'},
          'seasonNumber': 1,
          'episodeNumber': 1,
          'title': 'Ep1',
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SonarrWantedHierarchy(items: items, service: service),
            ),
          ),
        ),
      );

      expect(find.text('Show A'), findsOneWidget);
      expect(find.text('Show B'), findsOneWidget);
      expect(find.text('1 episode'), findsOneWidget);
      expect(find.text('2 episodes'), findsOneWidget);
    });

    testWidgets('renders season groups', (tester) async {
      final items = [
        {
          'series': {'title': 'Show'},
          'seasonNumber': 2,
          'episodeNumber': 1,
          'title': 'S2E1',
        },
        {
          'series': {'title': 'Show'},
          'seasonNumber': 1,
          'episodeNumber': 3,
          'title': 'S1E3',
        },
        {
          'series': {'title': 'Show'},
          'seasonNumber': 1,
          'episodeNumber': 1,
          'title': 'S1E1',
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SonarrWantedHierarchy(items: items, service: service),
            ),
          ),
        ),
      );

      expect(find.text('Show'), findsOneWidget);
      expect(find.text('Season 1'), findsOneWidget);
      expect(find.text('Season 2'), findsOneWidget);
      expect(find.text('3 episodes'), findsOneWidget);
    });

    testWidgets('handles seriesTitle fallback field', (tester) async {
      final items = [
        {
          'seriesTitle': 'Fallback Show',
          'seasonNumber': 1,
          'episodeNumber': 1,
          'title': 'Ep1',
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SonarrWantedHierarchy(items: items, service: service),
            ),
          ),
        ),
      );

      expect(find.text('Fallback Show'), findsOneWidget);
    });

    testWidgets('uses Unknown Series when no series info', (tester) async {
      final items = [
        {'seasonNumber': 1, 'episodeNumber': 1, 'title': 'Orphan Episode'},
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SonarrWantedHierarchy(items: items, service: service),
            ),
          ),
        ),
      );

      expect(find.text('Unknown Series'), findsOneWidget);
    });

    testWidgets('renders no expansion tiles for empty items', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SonarrWantedHierarchy(items: [], service: service),
            ),
          ),
        ),
      );

      expect(find.byType(ExpansionTile), findsNothing);
    });

    testWidgets('cutoff episodes show episode file size in subtitle', (
      tester,
    ) async {
      final items = [
        {
          'series': {'title': 'Show'},
          'seasonNumber': 2,
          'episodeNumber': 3,
          'title': 'Big Episode',
          'airDateUtc': '2026-04-01T01:48:00Z',
          'episodeFile': {'size': 5307309140},
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SonarrWantedHierarchy(
                items: items,
                service: service,
                isCutoff: true,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('4.94 GB'), findsOneWidget);
    });
  });
}
