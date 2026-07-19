import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/features/activity/presentation/activity_screen.dart';
import 'package:seekarr/features/activity/presentation/widgets/activity_tab.dart';
import 'package:seekarr/features/activity/presentation/widgets/wanted_tab.dart';
import 'package:seekarr/features/discover/data/seerr_service.dart';
import 'package:seekarr/features/discover/domain/models/seerr_request.dart';
import 'package:seekarr/features/discover/presentation/discover_provider.dart';
import 'package:seekarr/features/movies/data/radarr_service.dart';
import 'package:seekarr/features/music/data/lidarr_service.dart';
import 'package:seekarr/features/series/data/sonarr_service.dart';

import '../../../test_helpers/fake_services.dart';

void main() {
  testWidgets('renders requests screen for discover', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          requestsProvider.overrideWith((ref) async => <SeerrRequest>[]),
        ],
        child: const MaterialApp(
          home: ActivityScreen(serviceType: ServiceType.discover),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Requests'), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(ActivityTab), findsNothing);
    expect(find.byType(WantedTab), findsNothing);
    expect(find.text('No requests found'), findsOneWidget);
  });

  testWidgets('renders tabbed activity screen for movies', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          radarrServiceProvider.overrideWith((ref) => FakeRadarrService()),
        ],
        child: const MaterialApp(
          home: ActivityScreen(serviceType: ServiceType.movies),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Movies Activity'), findsOneWidget);
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Wanted'), findsOneWidget);
    expect(find.byType(ActivityTab), findsOneWidget);

    await tester.tap(find.text('Wanted'));
    await tester.pumpAndSettle();

    expect(find.byType(WantedTab), findsOneWidget);
  });

  testWidgets('renders global activity with sections, grouping and filter', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          requestsProvider.overrideWith(
            (ref) async => const [
              SeerrRequest(
                id: 1,
                status: RequestStatus.approved,
                media: RequestMedia(title: 'Shogun'),
                createdAt: '2026-04-03T09:05:00Z',
                type: 'tv',
                requestedBy: RequestedBy(id: 1, displayName: 'sarah'),
              ),
            ],
          ),
          seerrServiceProvider.overrideWith((ref) => FakeSeerrService()),
          radarrServiceProvider.overrideWith(
            (ref) => _ActivityRadarrService(
              queue: const [
                {
                  'title': 'Furiosa.2024.2160p.WEB-DL-GROUP',
                  'status': 'downloading',
                  'size': 100,
                  'sizeleft': 25,
                  'movie': {'title': 'Furiosa', 'year': 2024},
                },
              ],
              history: const [
                {
                  'sourceTitle': 'Dune.Part.Two.2024',
                  'eventType': 'downloadImported',
                  'date': '2026-04-02T11:18:00Z',
                  'movie': {'title': 'Dune: Part Two', 'year': 2024},
                },
              ],
              missing: const [
                {'title': 'Kingdom of the Planet of the Apes'},
              ],
            ),
          ),
          sonarrServiceProvider.overrideWith((ref) => FakeSonarrService()),
          lidarrServiceProvider.overrideWith((ref) => FakeLidarrService()),
        ],
        child: const MaterialApp(home: GlobalActivityScreen()),
      ),
    );

    await tester.pumpAndSettle();

    // Three clear top-level sections replace the old seven tabs.
    expect(find.text('Activity'), findsWidgets);
    for (final label in ['Now', 'History', 'Wanted']) {
      expect(find.text(label), findsOneWidget);
    }

    // "Now" merges active downloads (queue) with current requests, grouped by
    // service.
    expect(find.text('Furiosa'), findsOneWidget);
    expect(find.text('Shogun'), findsOneWidget);
    expect(
      find.textContaining('Furiosa.2024.2160p.WEB-DL-GROUP'),
      findsOneWidget,
    );

    // Switch to the Wanted section.
    await tester.tap(find.text('Wanted'));
    await tester.pumpAndSettle();

    expect(find.text('Kingdom of the Planet of the Apes'), findsOneWidget);
    expect(find.text('Furiosa'), findsNothing);
  });
}

class _ActivityRadarrService extends FakeRadarrService {
  _ActivityRadarrService({
    this.queue = const [],
    this.history = const [],
    this.missing = const [],
  });

  final List<dynamic> queue;
  final List<dynamic> history;
  final List<dynamic> missing;

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => queue;

  @override
  Future<List<dynamic>> getHistory({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async => history;

  @override
  Future<List<dynamic>> getAllHistory({
    Map<String, dynamic>? queryParameters,
  }) async => history;

  @override
  Future<List<dynamic>> getMissing({int page = 1, int pageSize = 20}) async =>
      missing;

  @override
  Future<List<dynamic>> getAllMissing() async => missing;
}
