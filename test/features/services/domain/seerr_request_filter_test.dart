import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/services/domain/seerr_request_filter.dart';

/// [mediaStatus] defaults to `unknown`, which is what makes `displayStatus` fall
/// through to the request's own [status] instead of overriding it.
SeerrRequest _request({
  required int id,
  RequestStatus status = RequestStatus.approved,
  SeerrMediaAvailability mediaStatus = SeerrMediaAvailability.unknown,
}) {
  return SeerrRequest(
    id: id,
    status: status,
    media: RequestMedia(title: 'Title $id', status: mediaStatus),
    createdAt: '2026-05-01T10:00:00Z',
    type: 'movie',
  );
}

void main() {
  group('chip labels', () {
    test('reads All, Pending, Approved, Declined in order', () {
      expect(SeerrRequestFilter.values.map((f) => f.label), [
        'All',
        'Pending',
        'Approved',
        'Declined',
      ]);
    });
  });

  group('approved means "got past approval"', () {
    // This is the whole reason the enum exists. `displayStatus` lets media
    // availability override the request's own status, so an approved request
    // that is downloading reports `processing` and a finished one reports
    // `available` — neither reports `approved`. Matching the label literally
    // would leave this bucket almost always empty.
    test('includes requests whose media has moved past approval', () {
      final downloading = _request(
        id: 1,
        mediaStatus: SeerrMediaAvailability.processing,
      );
      final finished = _request(
        id: 2,
        mediaStatus: SeerrMediaAvailability.available,
      );
      final partly = _request(
        id: 3,
        mediaStatus: SeerrMediaAvailability.partiallyAvailable,
      );

      expect(
        downloading.displayStatus.kind,
        SeerrRequestDisplayKind.processing,
      );
      expect(finished.displayStatus.kind, SeerrRequestDisplayKind.available);

      final visible = SeerrRequestFilter.approved.apply([
        downloading,
        finished,
        partly,
      ]);
      expect(visible.map((r) => r.id), [1, 2, 3]);
    });

    test('excludes a request still awaiting approval', () {
      final pending = _request(id: 1, status: RequestStatus.pendingApproval);

      expect(SeerrRequestFilter.approved.apply([pending]), isEmpty);
      expect(SeerrRequestFilter.pending.apply([pending]).map((r) => r.id), [1]);
    });
  });

  group('pending', () {
    test('catches a request whose media is itself still pending', () {
      // Media availability wins here too: this reports `pending` even though the
      // request was approved, and the pill the user sees says Pending.
      final approvedButMediaPending = _request(
        id: 1,
        status: RequestStatus.approved,
        mediaStatus: SeerrMediaAvailability.pending,
      );

      expect(
        approvedButMediaPending.displayStatus.kind,
        SeerrRequestDisplayKind.pending,
      );
      expect(
        SeerrRequestFilter.pending.apply([approvedButMediaPending]).length,
        1,
      );
    });
  });

  group('declined', () {
    test('groups declined, failed and deleted as "will not deliver"', () {
      final declined = _request(id: 1, status: RequestStatus.declined);
      final failed = _request(id: 2, status: RequestStatus.failed);
      final deleted = _request(
        id: 3,
        mediaStatus: SeerrMediaAvailability.deleted,
      );

      expect(
        SeerrRequestFilter.declined.apply([declined, failed, deleted]).length,
        3,
      );
    });

    test('does not swallow an unparsed status', () {
      // `unknown` belongs to no bucket but `all`, so a status the app failed to
      // parse can never hide behind a wrong label.
      final unknown = _request(id: 1, status: RequestStatus.unknown);

      expect(unknown.displayStatus.kind, SeerrRequestDisplayKind.unknown);
      expect(SeerrRequestFilter.declined.apply([unknown]), isEmpty);
      expect(SeerrRequestFilter.pending.apply([unknown]), isEmpty);
      expect(SeerrRequestFilter.approved.apply([unknown]), isEmpty);
      expect(SeerrRequestFilter.all.apply([unknown]).length, 1);
    });
  });

  group('all', () {
    test('passes the list through untouched, order preserved', () {
      final requests = [
        _request(id: 1, status: RequestStatus.pendingApproval),
        _request(id: 2, status: RequestStatus.declined),
      ];

      expect(SeerrRequestFilter.all.apply(requests), same(requests));
    });
  });

  group('emptyLabel', () {
    test('names the bucket so an empty screen explains itself', () {
      expect(SeerrRequestFilter.all.emptyLabel, 'No requests found');
      expect(SeerrRequestFilter.pending.emptyLabel, 'No pending requests');
      expect(SeerrRequestFilter.declined.emptyLabel, 'No declined requests');
    });
  });
}
