/// Ordering for the single Requests region on `/services`.
///
/// ## Why one region and not two
///
/// The obvious design is two regions — "Needs You" for pending approvals and
/// "Recent Requests" for the rest — or one region with a toggle between them.
/// Both are wrong for the same reason: **pending requests are recent requests.**
/// They are one dataset from one provider, one a subset of the other. Splitting
/// them invents a conflict between a set and its own subset, and then resolves it
/// by hiding one of them.
///
/// A toggle fails for a second reason. On a stack with auto-approvals — a normal
/// configuration — the pending side is permanently empty, so the control exists
/// to be dismissed once and ignored forever. And on a hub where thirteen services
/// each get one matrix cell, spending a control row on a Seerr-only sub-choice
/// over-serves one service out of thirteen.
///
/// So the region never filters. It **sorts**, pending first, and every request
/// stays reachable in every data condition. "Is anything waiting on me" is
/// answered upstream, in the first viewport, by Seerr's matrix cell showing
/// `Pending n`.
library;

import 'package:seekarr/features/discover/domain/models/seerr_request.dart';

/// How many requests the hub shows before deferring to the full list.
///
/// Five rather than the three the old rail showed: pending rows now sort to the
/// top and carry their own actions, so a stack with two approvals waiting would
/// otherwise have room for exactly one line of recent history behind them.
const int servicesRequestsPreviewLimit = 5;

/// The Requests header, spoken, when something is waiting on a decision.
///
/// The header silences its own subtree, so the visible "3 PENDING" badge is not
/// announced unless it is folded in here.
String servicesRequestsHeaderLabel({required int pending}) {
  final noun = pending == 1 ? 'request' : 'requests';
  return 'Requests, $pending $noun awaiting approval';
}

/// Whether this request is waiting on a human decision.
///
/// Reads [SeerrRequest.status] and **not** `displayStatus`. That distinction is
/// load-bearing: `displayStatus` lets media availability override request state,
/// so a request that is still `pendingApproval` reads as "Available" the moment
/// the media exists on disk. Keying the actionable set off it would silently drop
/// exactly the approvals that matter most — the ones for media somebody already
/// has — and no amount of testing against a fresh request would surface it.
bool isAwaitingApproval(SeerrRequest request) =>
    request.status == RequestStatus.pendingApproval;

/// Pending first, then everything else, each group newest first.
///
/// Two keys rather than one: pending is what you can act on, and recency is what
/// makes the rest worth looking at. A single sort on recency would bury a
/// three-day-old approval under today's auto-approved traffic, which is the
/// failure the pending-first rule exists to prevent.
List<SeerrRequest> sortRequestsPendingFirst(
  List<SeerrRequest> requests, {
  required int limit,
}) {
  final sorted = List<SeerrRequest>.of(requests)
    ..sort((a, b) {
      final pendingA = isAwaitingApproval(a);
      final pendingB = isAwaitingApproval(b);
      if (pendingA != pendingB) return pendingA ? -1 : 1;

      // `createdAt` is an ISO 8601 string, or '' when Seerr omitted it. An
      // unparseable date sorts last within its group rather than to the epoch,
      // which would otherwise plant it at the bottom of a "newest first" list
      // and read as genuinely old.
      final createdA = DateTime.tryParse(a.createdAt);
      final createdB = DateTime.tryParse(b.createdAt);
      if (createdA == null && createdB == null) return 0;
      if (createdA == null) return 1;
      if (createdB == null) return -1;
      return createdB.compareTo(createdA);
    });

  return sorted.take(limit).toList(growable: false);
}

/// How many requests are waiting on a decision, across the whole set.
///
/// Counted before [sortRequestsPendingFirst] applies its limit, so the header's
/// count tells the truth even when there are more pending requests than the
/// region has room to show.
int countAwaitingApproval(List<SeerrRequest> requests) =>
    requests.where(isAwaitingApproval).length;
