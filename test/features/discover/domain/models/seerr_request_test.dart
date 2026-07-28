import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/features/discover/domain/models/seerr_request.dart';

void main() {
  group('RequestStatus.fromCode', () {
    test('maps known Overseerr request codes', () {
      expect(RequestStatus.fromCode(1), RequestStatus.pendingApproval);
      expect(RequestStatus.fromCode(2), RequestStatus.approved);
      expect(RequestStatus.fromCode(3), RequestStatus.declined);
      expect(RequestStatus.fromCode(4), RequestStatus.failed);
      expect(RequestStatus.fromCode(5), RequestStatus.completed);
      expect(RequestStatus.fromCode(99), RequestStatus.unknown);
    });
  });

  group('SeerrRequest.displayStatus', () {
    test('prefers media availability over request workflow when available', () {
      final request = SeerrRequest(
        id: 1,
        status: RequestStatus.unknown,
        media: const RequestMedia(status: SeerrMediaAvailability.available),
        createdAt: '2026-05-01T10:00:00Z',
        type: 'movie',
      );

      expect(request.displayStatus.label, 'Available');
      expect(request.displayStatus.kind, SeerrRequestDisplayKind.available);
    });

    test('returns partially available from media status', () {
      final request = SeerrRequest(
        id: 2,
        status: RequestStatus.approved,
        media: const RequestMedia(
          status: SeerrMediaAvailability.partiallyAvailable,
        ),
        createdAt: '2026-05-01T10:00:00Z',
        type: 'tv',
      );

      expect(request.displayStatus.label, 'Partially Available');
      expect(
        request.displayStatus.kind,
        SeerrRequestDisplayKind.partiallyAvailable,
      );
    });

    test(
      'falls back to approved when request is approved without media state',
      () {
        final request = SeerrRequest(
          id: 3,
          status: RequestStatus.approved,
          createdAt: '2026-05-01T10:00:00Z',
          type: 'movie',
        );

        expect(request.displayStatus.label, 'Approved');
        expect(request.displayStatus.kind, SeerrRequestDisplayKind.approved);
      },
    );
  });
}
