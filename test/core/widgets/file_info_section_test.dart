import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seekarr/core/widgets/file_info_section.dart';

void main() {
  group('FileInfoSection', () {
    testWidgets('renders nothing when both path and filename are null', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: FileInfoSection())),
      );

      // Should render SizedBox.shrink()
      expect(find.byType(FileInfoSection), findsOneWidget);
      expect(find.text('Library path'), findsNothing);
    });

    testWidgets('renders path when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: FileInfoSection(path: '/movies/Avatar')),
        ),
      );

      expect(find.text('File'), findsNothing);
      expect(find.text('Library path'), findsOneWidget);
      expect(find.text('/movies/Avatar'), findsOneWidget);
      expect(find.byIcon(Icons.storage_rounded), findsOneWidget);
    });

    testWidgets('renders filename when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FileInfoSection(filename: 'Avatar.2009.1080p.mkv'),
          ),
        ),
      );

      expect(find.text('File'), findsNothing);
      expect(find.text('Avatar.2009.1080p.mkv'), findsOneWidget);
      expect(find.byIcon(Icons.storage_rounded), findsOneWidget);
    });

    testWidgets('renders both path and filename when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FileInfoSection(
              path: '/movies/Avatar',
              filename: 'Avatar.2009.1080p.mkv',
            ),
          ),
        ),
      );

      expect(find.text('File'), findsNothing);
      expect(find.text('/movies/Avatar'), findsOneWidget);
      expect(find.text('Avatar.2009.1080p.mkv'), findsOneWidget);
      expect(find.byIcon(Icons.storage_rounded), findsOneWidget);
    });

    testWidgets('tints the storage glyph with the page accent', (tester) async {
      const radarrAmber = Color(0xFFF59E0B);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FileInfoSection(path: '/movies', accent: radarrAmber),
          ),
        ),
      );

      // One accent per screen: the glyph used to be `colorScheme.primary`
      // indigo, which is a second accent on an amber or violet page.
      expect(
        tester.widget<Icon>(find.byIcon(Icons.storage_rounded)).color,
        radarrAmber,
      );
    });

    testWidgets('handles long paths with ellipsis', (tester) async {
      const longPath =
          '/very/long/path/to/movies/that/should/be/truncated/with/ellipsis';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 200, child: FileInfoSection(path: longPath)),
          ),
        ),
      );

      expect(find.text('File'), findsNothing);
      expect(find.text('Library path'), findsOneWidget);
      expect(find.byType(FileInfoSection), findsOneWidget);
    });
  });
}
