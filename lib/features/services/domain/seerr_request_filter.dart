import 'package:cupola/features/discover/domain/models/seerr_request.dart';

/// The buckets the All Requests screen filters by.
///
/// Grouped by **request lifecycle**, not by the exact pill text, and that
/// distinction is the whole reason this lives here instead of in a build method.
/// [SeerrRequest.displayStatus] lets media availability override the request's
/// own status, so an approved request whose media is still downloading reports
/// `processing` and one that finished reports `available` — neither reports
/// `approved`. Matching the chip label literally would therefore leave
/// "Approved" almost always empty while the requests it should list sit under
/// labels of their own.
///
/// So [approved] means "got past approval", which is what a user picking that
/// chip is asking for.
enum SeerrRequestFilter {
  all('All'),
  pending('Pending'),
  approved('Approved'),
  declined('Declined');

  const SeerrRequestFilter(this.label);

  /// The chip text, and the word used in the empty state.
  final String label;

  bool matches(SeerrRequestDisplayKind kind) {
    return switch (this) {
      SeerrRequestFilter.all => true,
      SeerrRequestFilter.pending => kind == SeerrRequestDisplayKind.pending,
      SeerrRequestFilter.approved =>
        kind == SeerrRequestDisplayKind.approved ||
            kind == SeerrRequestDisplayKind.processing ||
            kind == SeerrRequestDisplayKind.available ||
            kind == SeerrRequestDisplayKind.partiallyAvailable ||
            kind == SeerrRequestDisplayKind.completed,
      // `failed` and `deleted` belong here rather than in their own bucket:
      // both mean the request will not deliver, which is what someone looking
      // for declined requests wants to see. `unknown` is deliberately in no
      // bucket but `all`, so an unparsed status never hides behind a wrong one.
      SeerrRequestFilter.declined =>
        kind == SeerrRequestDisplayKind.declined ||
            kind == SeerrRequestDisplayKind.failed ||
            kind == SeerrRequestDisplayKind.deleted,
    };
  }

  /// The requests in [requests] that belong to this bucket, order preserved.
  List<SeerrRequest> apply(List<SeerrRequest> requests) {
    if (this == SeerrRequestFilter.all) return requests;
    return requests
        .where((request) => matches(request.displayStatus.kind))
        .toList(growable: false);
  }

  /// The empty-state copy for this bucket.
  String get emptyLabel => this == SeerrRequestFilter.all
      ? 'No requests found'
      : 'No ${label.toLowerCase()} requests';
}
