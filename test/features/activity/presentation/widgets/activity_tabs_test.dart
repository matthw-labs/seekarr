import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/activity/presentation/activity_screen.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_tab.dart';
import 'package:cupola/features/activity/presentation/widgets/wanted_tab.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';

void main() {
  group('ActivityTab', () {
    testWidgets('switches between queue, history, and blocklist segments', (
      tester,
    ) async {
      final service = _FakeRadarrActivityService(
        queueItems: const [
          {'title': 'Queued.Movie', 'status': 'queued'},
        ],
        historyItems: const [
          {'sourceTitle': 'Grabbed.Release', 'eventType': 'grabbed'},
        ],
        blocklistItems: const [
          {'sourceTitle': 'Blocked.Release', 'message': 'Rejected'},
        ],
      );

      await _pumpWithRadarrService(
        tester,
        service: service,
        child: const ActivityTab(serviceType: ServiceType.movies),
      );

      expect(find.text('Queued.Movie'), findsOneWidget);
      expect(service.queueCalls, 1);

      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();

      expect(find.text('Grabbed.Release'), findsOneWidget);
      expect(find.text('Grabbed'), findsOneWidget);
      expect(service.historyCalls, 1);

      await tester.tap(find.text('Blocklist'));
      await tester.pumpAndSettle();

      expect(find.text('Blocked.Release'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
      expect(service.blocklistCalls, 1);
    });
  });

  group('WantedTab', () {
    testWidgets('shows missing items and cutoff movie quality profile names', (
      tester,
    ) async {
      final service = _FakeRadarrActivityService(
        missingItems: const [
          {'title': 'Missing Movie'},
        ],
        cutoffItems: const [
          {
            'id': 42,
            'title': 'Cutoff Movie',
            'status': 'released',
            'qualityProfileId': 7,
            'sizeOnDisk': 8003897815,
          },
        ],
        qualityProfileResponses: const [
          [
            {'id': 7, 'name': 'HD-1080p'},
          ],
        ],
      );

      await _pumpWithRadarrService(
        tester,
        service: service,
        child: const WantedTab(serviceType: ServiceType.movies),
      );

      expect(find.text('Missing Movie'), findsOneWidget);
      expect(service.missingCalls, 1);

      await tester.tap(find.text('Cutoff Unmet'));
      await tester.pumpAndSettle();

      expect(find.text('Cutoff Movie'), findsOneWidget);
      expect(find.text('HD-1080p'), findsOneWidget);
      expect(service.cutoffCalls, 1);
      expect(service.qualityProfileCalls, 1);
    });

    testWidgets('switching segments clears cached movie quality profiles', (
      tester,
    ) async {
      final service = _FakeRadarrActivityService(
        missingItems: const [
          {'title': 'Missing Movie'},
        ],
        cutoffItems: const [
          {
            'id': 42,
            'title': 'Cutoff Movie',
            'status': 'released',
            'qualityProfileId': 7,
            'sizeOnDisk': 8003897815,
          },
        ],
        qualityProfileResponses: const [
          [
            {'id': 7, 'name': 'HD-1080p'},
          ],
          [
            {'id': 7, 'name': 'Ultra HD'},
          ],
        ],
      );

      await _pumpWithRadarrService(
        tester,
        service: service,
        child: const WantedTab(serviceType: ServiceType.movies),
      );

      await tester.tap(find.text('Cutoff Unmet'));
      await tester.pumpAndSettle();

      expect(find.text('HD-1080p'), findsOneWidget);
      expect(service.cutoffCalls, 1);
      expect(service.qualityProfileCalls, 1);

      await tester.tap(find.text('Missing'));
      await tester.pumpAndSettle();

      expect(find.text('Missing Movie'), findsOneWidget);
      expect(service.missingCalls, 2);

      await tester.tap(find.text('Cutoff Unmet'));
      await tester.pumpAndSettle();

      expect(find.text('Ultra HD'), findsOneWidget);
      expect(find.text('HD-1080p'), findsNothing);
      expect(service.cutoffCalls, 2);
      expect(service.qualityProfileCalls, 2);
    });

    testWidgets('switches wanted segments for series hierarchy', (
      tester,
    ) async {
      final service = _FakeSonarrActivityService(
        missingItems: const [
          {
            'id': 1,
            'title': 'Pilot',
            'series': {'title': 'Missing Show'},
            'seasonNumber': 1,
            'episodeNumber': 1,
          },
        ],
        cutoffItems: const [
          {
            'id': 2,
            'title': 'Finale',
            'series': {'title': 'Cutoff Show'},
            'seasonNumber': 1,
            'episodeNumber': 2,
            'episodeFile': {'size': 5307309140},
          },
        ],
      );

      await _pumpWithSonarrService(
        tester,
        service: service,
        child: const WantedTab(serviceType: ServiceType.series),
      );

      expect(find.text('Missing Show'), findsOneWidget);
      expect(service.missingCalls, 1);

      await tester.tap(find.text('Cutoff Unmet'));
      await tester.pumpAndSettle();

      expect(find.text('Cutoff Show'), findsOneWidget);
      expect(service.cutoffCalls, 1);
    });
  });
}

Future<void> _pumpWithRadarrService(
  WidgetTester tester, {
  required _FakeRadarrActivityService service,
  required Widget child,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [radarrServiceProvider.overrideWith((ref) => service)],
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpWithSonarrService(
  WidgetTester tester, {
  required _FakeSonarrActivityService service,
  required Widget child,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sonarrServiceProvider.overrideWith((ref) => service)],
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeRadarrActivityService extends RadarrService {
  _FakeRadarrActivityService({
    this.queueItems = const [],
    this.historyItems = const [],
    this.blocklistItems = const [],
    this.missingItems = const [],
    this.cutoffItems = const [],
    this.qualityProfileResponses = const [],
  }) : super(ApiClient(baseUrl: 'https://radarr.example.com', apiKey: 'key'));

  final List<dynamic> queueItems;
  final List<dynamic> historyItems;
  final List<dynamic> blocklistItems;
  final List<dynamic> missingItems;
  final List<dynamic> cutoffItems;
  final List<List<Map<String, dynamic>>> qualityProfileResponses;

  int queueCalls = 0;
  int historyCalls = 0;
  int blocklistCalls = 0;
  int missingCalls = 0;
  int cutoffCalls = 0;
  int qualityProfileCalls = 0;

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async {
    queueCalls++;
    return queueItems;
  }

  @override
  Future<List<dynamic>> getAllHistory({
    Map<String, dynamic>? queryParameters,
  }) async {
    historyCalls++;
    return historyItems;
  }

  @override
  Future<List<dynamic>> getBlocklist() async {
    blocklistCalls++;
    return blocklistItems;
  }

  @override
  Future<List<dynamic>> getAllMissing() async {
    missingCalls++;
    return missingItems;
  }

  @override
  Future<List<dynamic>> getAllCutoff() async {
    cutoffCalls++;
    return cutoffItems;
  }

  @override
  Future<List<Map<String, dynamic>>> getQualityProfiles() async {
    qualityProfileCalls++;

    if (qualityProfileResponses.isEmpty) {
      return const [];
    }

    final responseIndex = qualityProfileCalls <= qualityProfileResponses.length
        ? qualityProfileCalls - 1
        : qualityProfileResponses.length - 1;
    return qualityProfileResponses[responseIndex];
  }
}

class _FakeSonarrActivityService extends SonarrService {
  _FakeSonarrActivityService({
    this.missingItems = const [],
    this.cutoffItems = const [],
  }) : super(ApiClient(baseUrl: 'https://sonarr.example.com', apiKey: 'key'));

  final List<dynamic> missingItems;
  final List<dynamic> cutoffItems;

  int missingCalls = 0;
  int cutoffCalls = 0;

  @override
  Future<List<dynamic>> getAllMissing() async {
    missingCalls++;
    return missingItems;
  }

  @override
  Future<List<dynamic>> getAllCutoff() async {
    cutoffCalls++;
    return cutoffItems;
  }
}
