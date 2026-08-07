/// One page of a library browse, with the three facts a pager cannot recover
/// from the rows it received.
///
/// **This type exists because a bare `List<StreamItem>` is ambiguous in two ways
/// that both produce an affirmative false claim on screen.**
///
///  * *Empty because it failed.* Both clients degrade a remote failure to an
///    empty list, which is the project's read-path convention and is right — a
///    timed-out dashboard section should not take the page down. But a browse
///    that only saw `[]` told the user "This library is empty · The server
///    reports no items here" about a server that had not answered at all.
///  * *Empty because the page was filtered.* Plex has no separate continue and
///    next-up endpoints, so `PlexClient` splits one `onDeck` response after
///    mapping. A page whose rows all fall on the wrong side of that predicate
///    comes back with nothing in it while the *next* page holds real items, so a
///    pager that stopped at "the page I received was empty" ended the list
///    before it started.
///
/// So a page carries the server's own accounting ([nextStartIndex], [hasMore])
/// and says explicitly why it is empty when it is ([outcome]).
library;

import 'package:flutter/foundation.dart';

import 'package:cupola/features/stream/domain/models/stream_item.dart';

/// Why a page has the contents it has.
enum StreamPageOutcome {
  /// The server answered. [StreamLibraryPage.items] is what it holds.
  ok,

  /// The request failed. Says nothing at all about what the library contains,
  /// and the UI must offer a retry rather than report an absence.
  failed,

  /// The lens is per-viewer and no viewer is selected, so the server was never
  /// asked. Also not a claim about the library — the user has a setting to
  /// change, not an empty shelf to look at.
  viewerRequired,
}

@immutable
class StreamLibraryPage {
  final List<StreamItem> items;

  /// Where the next request must start.
  ///
  /// The **server's** accounting, not `startIndex + items.length`: both clients
  /// drop rows after the response is counted (Plex's on-deck split, a malformed
  /// entry either side), and a pager that advanced by what survived would
  /// re-request rows it had already seen.
  final int nextStartIndex;

  /// Whether another request would return anything.
  final bool hasMore;

  final StreamPageOutcome outcome;

  const StreamLibraryPage({
    required this.items,
    required this.nextStartIndex,
    required this.hasMore,
    this.outcome = StreamPageOutcome.ok,
  });

  /// The request did not complete. [startIndex] is echoed back so a retry can
  /// resume from the same place.
  const StreamLibraryPage.failed({required int startIndex})
    : items = const [],
      nextStartIndex = startIndex,
      hasMore = false,
      outcome = StreamPageOutcome.failed;

  /// The lens needs a viewer and none is selected.
  const StreamLibraryPage.viewerRequired()
    : items = const [],
      nextStartIndex = 0,
      hasMore = false,
      outcome = StreamPageOutcome.viewerRequired;

  /// The server answered and had nothing to send.
  const StreamLibraryPage.empty({int startIndex = 0})
    : items = const [],
      nextStartIndex = startIndex,
      hasMore = false,
      outcome = StreamPageOutcome.ok;

  bool get failed => outcome == StreamPageOutcome.failed;

  bool get needsViewer => outcome == StreamPageOutcome.viewerRequired;
}
