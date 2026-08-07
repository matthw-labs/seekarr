import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/models/service_kpi.dart';
import 'package:seekarr/features/discover/domain/models/seerr_request.dart';
import 'package:seekarr/features/discover/presentation/discover_provider.dart';
import 'package:seekarr/features/services/presentation/service_kpi_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

SeerrRequest _request({
  required int id,
  RequestStatus status = RequestStatus.completed,
  SeerrMediaAvailability mediaStatus = SeerrMediaAvailability.unknown,
}) => SeerrRequest(
  id: id,
  status: status,
  media: RequestMedia(title: 'Title $id', tmdbId: id, status: mediaStatus),
  createdAt: '2024-01-01T00:00:00Z',
  type: 'movie',
);

Future<Map<String, String>> _seerrKpis(List<SeerrRequest> requests) async {
  final container = ProviderContainer(
    overrides: [requestsProvider.overrideWith((ref) async => requests)],
  );
  addTearDown(container.dispose);

  final kpis = await container.read(
    serviceKpiProvider(ServiceKey.seerr).future,
  );
  return {for (final ServiceKpi kpi in kpis) kpi.label: kpi.value};
}

void main() {
  group('Seerr KPIs', () {
    test('counts pending approvals off the request, not the media', () async {
      // The trap: `displayStatus` checks `media.status` first, so a request
      // still awaiting a human reports "Available" the moment Radarr has the
      // file. Counting off it showed "Pending 0" on the dashboard while
      // /activity was offering an Approve button for the same record.
      final pendingButAvailable = _request(
        id: 1,
        status: RequestStatus.pendingApproval,
        mediaStatus: SeerrMediaAvailability.available,
      );
      expect(pendingButAvailable.displayStatus.label, 'Available');

      final kpis = await _seerrKpis([pendingButAvailable]);

      expect(kpis['Pending'], '1');
      // Its media really is available, and that tile is about the media.
      expect(kpis['Available'], '1');
      expect(kpis['Requests'], '1');
    });

    test('counts an ordinary pending request once', () async {
      final kpis = await _seerrKpis([
        _request(id: 1, status: RequestStatus.pendingApproval),
      ]);

      expect(kpis['Pending'], '1');
      expect(kpis['Processing'], '0');
      expect(kpis['Available'], '0');
    });

    test('does not count settled requests as pending', () async {
      final kpis = await _seerrKpis([
        _request(
          id: 1,
          status: RequestStatus.approved,
          mediaStatus: SeerrMediaAvailability.processing,
        ),
        _request(
          id: 2,
          status: RequestStatus.completed,
          mediaStatus: SeerrMediaAvailability.available,
        ),
        _request(id: 3, status: RequestStatus.declined),
      ]);

      expect(kpis['Pending'], '0');
      expect(kpis['Processing'], '1');
      expect(kpis['Available'], '1');
      expect(kpis['Requests'], '3');
    });
  });
}
