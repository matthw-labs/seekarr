import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/presentation/widgets/manage_media_sheet.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

void main() {
  group('ManageMediaSheet', () {
    testWidgets('remove action is a silent no-op when seerr id is missing', (
      tester,
    ) async {
      var onDataChangedCount = 0;

      await _pumpSheet(
        tester,
        onDataChanged: () => onDataChangedCount += 1,
        settings: const SettingsModel(
          radarrUrl: 'https://radarr.example.com',
          radarrApiKey: 'key',
        ),
      );

      await tester.tap(find.text('Remove from Radarr'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Remove from Radarr'), findsOneWidget);
      expect(onDataChangedCount, 0);
    });

    testWidgets('clear data is a silent no-op when seerr id is missing', (
      tester,
    ) async {
      var onDataChangedCount = 0;

      await _pumpSheet(
        tester,
        onDataChanged: () => onDataChangedCount += 1,
        settings: const SettingsModel(
          radarrUrl: 'https://radarr.example.com',
          radarrApiKey: 'key',
        ),
      );

      await tester.scrollUntilVisible(
        find.text('Clear Data'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Clear Data'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Clear Data'), findsOneWidget);
      expect(onDataChangedCount, 0);
    });

    testWidgets('Media section is hidden when radarr is not configured', (
      tester,
    ) async {
      await _pumpSheet(tester, settings: const SettingsModel());

      expect(find.text('Requests'), findsOneWidget);
      expect(find.text('Open in Radarr'), findsNothing);
      expect(find.text('Remove from Radarr'), findsNothing);
    });

    testWidgets('Media section is hidden when sonarr is not configured', (
      tester,
    ) async {
      await _pumpSheet(
        tester,
        mediaType: 'tv',
        mediaTitle: 'Series',
        tvdbId: 555,
        settings: const SettingsModel(),
      );

      expect(find.text('Requests'), findsOneWidget);
      expect(find.text('Open in Sonarr'), findsNothing);
      expect(find.text('Remove from Sonarr'), findsNothing);
    });

    testWidgets(
      'Media section is shown when movie has externalServiceId and radarr is configured',
      (tester) async {
        await _pumpSheet(
          tester,
          settings: const SettingsModel(
            radarrUrl: 'https://radarr.example.com',
            radarrApiKey: 'key',
          ),
        );

        expect(find.text('Open in Radarr'), findsOneWidget);
        expect(find.text('Remove from Radarr'), findsOneWidget);
      },
    );

    testWidgets(
      'Media section is hidden when externalServiceId is null even with radarr configured',
      (tester) async {
        await _pumpSheet(
          tester,
          mediaInfo: {'requests': const []},
          settings: const SettingsModel(
            radarrUrl: 'https://radarr.example.com',
            radarrApiKey: 'key',
          ),
        );

        expect(find.text('Open in Radarr'), findsNothing);
        expect(find.text('Remove from Radarr'), findsNothing);
      },
    );
  });
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  Map<String, dynamic>? mediaInfo,
  String mediaTitle = 'Movie',
  String mediaType = 'movie',
  int tmdbId = 123,
  int? tvdbId,
  VoidCallback? onDataChanged,
  SettingsModel settings = const SettingsModel(),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [currentSettingsProvider.overrideWith((ref) => settings)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 800,
            child: ManageMediaSheet(
              mediaInfo:
                  mediaInfo ?? {'externalServiceId': 42, 'requests': const []},
              mediaTitle: mediaTitle,
              mediaType: mediaType,
              tmdbId: tmdbId,
              tvdbId: tvdbId,
              onDataChanged: onDataChanged ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
