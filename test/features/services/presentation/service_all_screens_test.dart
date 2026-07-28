import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seekarr/core/widgets/content_card.dart';

import 'package:seekarr/features/discover/domain/models/seerr_request.dart';
import 'package:seekarr/features/services/presentation/service_all_screens.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';

void main() {
  testWidgets('all requests renders filter chips and compact request rows', (
    tester,
  ) async {
    await _pumpAllRequests(tester);
    await _pumpAsyncContent(tester);

    expect(find.text('All Requests'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Declined'), findsOneWidget);
    expect(find.text('A Quiet Place'), findsOneWidget);
    expect(find.text('sarah'), findsOneWidget);
    expect(find.text('Movie'), findsOneWidget);
    expect(find.text('AVAILABLE'), findsOneWidget);
    expect(find.text('PARTIALLY AVAILABLE'), findsOneWidget);
    expect(_contentCardWithImage('/quiet-place.jpg'), findsOneWidget);
  });
}

Future<void> _pumpAllRequests(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _providerOverrides(),
      child: const MaterialApp(home: ServiceAllRequestsScreen()),
    ),
  );
}

_providerOverrides() {
  return [
    currentSettingsProvider.overrideWith(
      (ref) => const SettingsModel(
        seerrUrl: 'http://seerr.local:5055',
        seerrApiKey: 'key',
        radarrUrl: 'http://radarr.local:7878',
        radarrApiKey: 'key',
        sonarrUrl: 'http://sonarr.local:8989',
        sonarrApiKey: 'key',
        lidarrUrl: 'http://lidarr.local:8686',
        lidarrApiKey: 'key',
      ),
    ),
    servicesRequestsProvider.overrideWith(
      (ref) async => const [
        SeerrRequest(
          id: 1,
          status: RequestStatus.pendingApproval,
          media: RequestMedia(
            title: 'A Quiet Place',
            tmdbId: 123,
            posterPath: '/quiet-place.jpg',
            status: SeerrMediaAvailability.available,
          ),
          createdAt: '2026-05-02T10:00:00Z',
          type: 'movie',
          requestedBy: RequestedBy(id: 1, displayName: 'sarah'),
        ),
        SeerrRequest(
          id: 2,
          status: RequestStatus.approved,
          media: RequestMedia(
            title: 'Shogun',
            status: SeerrMediaAvailability.partiallyAvailable,
          ),
          createdAt: '2026-05-01T10:00:00Z',
          type: 'tv',
          requestedBy: RequestedBy(id: 2, displayName: 'james'),
        ),
      ],
    ),
  ];
}

Future<void> _pumpAsyncContent(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Finder _contentCardWithImage(String imagePath) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is ContentCard && widget.imageUrl?.contains(imagePath) == true,
    skipOffstage: false,
  );
}
