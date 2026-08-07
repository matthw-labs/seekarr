import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/stream_semantics.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_poster_tile.dart';

/// One library on a media server, browsed by watch state.
///
/// **The landing lens is never A–Z, and that is the whole design.** Radarr already
/// holds an alphabetical wall of the same films; a Stream library that opened on one
/// would be Radarr rendered twice under a different accent. What only a media server
/// knows is *subject and time* — who watched, where they stopped, what is next, what
/// nobody has played — so those lenses lead and `StreamLibraryLens.all` is an
/// explicit sort you have to ask for.
///
/// The falsifiable form of that rule lives on `StreamLibraryLens`: **if this screen
/// would look identical after nobody watched anything for a month, it is the wrong
/// screen.** Landing on Continue satisfies it by construction.
///
/// **The viewer chip is absent on Plex rather than showing one entry.** A Jellyfin
/// API key authenticates as an administrator with no user attached, so it can read
/// any household member's state once told which; a Plex token *is* its user and
/// `/library/*` accepts no impersonation parameter. That asymmetry is a property of
/// the two APIs, so the control appears where it can do something and disappears
/// where it cannot.
class StreamLibraryScreen extends ConsumerStatefulWidget {
  const StreamLibraryScreen({
    super.key,
    required this.service,
    required this.libraryId,
    this.libraryTitle,
  });

  final ServiceKey service;
  final String libraryId;

  /// Carried as a query parameter so a deep link still resolves from the path
  /// alone; when present it spares the destination a fetch before its first frame.
  final String? libraryTitle;

  @override
  ConsumerState<StreamLibraryScreen> createState() =>
      _StreamLibraryScreenState();
}

class _StreamLibraryScreenState extends ConsumerState<StreamLibraryScreen> {
  late PagingController<int, StreamItem> _paging;
  StreamLibraryLens _lens = StreamLibraryLens.continueWatching;

  /// Where the next request starts, or null once the server says there is no
  /// more. **The server's number, never `pagesFetched * _pageSize`.**
  ///
  /// Both facts a pager needs are things only the server knows, and the previous
  /// controller inferred both from the rows it happened to receive:
  /// `lastPageIsEmpty ? null : nextIntPageKey` ended the list on any empty page,
  /// which on Plex's on-deck lenses is a page whose rows simply all fell on the
  /// wrong side of the continue/next-up split — real items sat in the page after
  /// it. Reset with the controller, because the offset belongs to the lens.
  int? _nextStartIndex;

  /// Whether the *first* fetch of the current lens has been made.
  ///
  /// `getNextPageKey` cannot ask the state — a first call and a call after a
  /// completed page look the same through `PagingState` once the key stops being
  /// derivable from the page count.
  bool _started = false;

  /// Which controller [_nextStartIndex] and [_started] currently belong to.
  ///
  /// Those two live on the State rather than in `PagingState`, which means they
  /// are *shared* across a rebuild in a way per-controller state never was. A
  /// `PagingController.dispose` only detaches its result — the fetch it was
  /// awaiting keeps running — so without this fence a stale fetch resolved
  /// after a lens change and wrote its offset over the new lens's: tap A–Z while
  /// Continue's first page is in flight, and A–Z's list truncates at fifty rows
  /// because Continue finished with `hasMore == false`.
  int _fetchGeneration = 0;

  /// The in-flight fetch's token, so a lens change stops the request rather than
  /// only ignoring its answer.
  CancelToken? _fetchCancel;

  @override
  void initState() {
    super.initState();
    _paging = _buildController();
  }

  @override
  void dispose() {
    _fetchCancel?.cancel();
    _paging.dispose();
    super.dispose();
  }

  PagingController<int, StreamItem> _buildController() {
    _fetchGeneration++;
    _nextStartIndex = 0;
    _started = false;
    return PagingController<int, StreamItem>(
      getNextPageKey: (_) => _started ? _nextStartIndex : 0,
      fetchPage: _fetchPage,
    );
  }

  /// Rebuilds the list from its first page, abandoning whatever is in flight.
  void _restart() {
    final previous = _paging;
    _fetchCancel?.cancel();
    _fetchCancel = null;
    setState(() => _paging = _buildController());
    previous.dispose();
  }

  /// Changing lens is a new list, not a filter over the old one.
  ///
  /// Each lens is a different server query with its own ordering, so the paging
  /// controller is rebuilt rather than refreshed — reusing it would append page 1
  /// of "Unplayed" onto page 3 of "Continue" and produce a list that is neither.
  void _selectLens(StreamLibraryLens lens) {
    if (lens == _lens) return;
    setState(() => _lens = lens);
    _restart();
  }

  /// One screenful of rows, which is not the same thing as one server page.
  ///
  /// The loop is the fix for the on-deck split. `PagedLayoutBuilder` reports
  /// `noItemsFound` the moment the accumulated item count is zero — regardless
  /// of `hasNextPage` — and then never builds an item, so nothing ever triggers
  /// the next fetch. A server page that filtered down to nothing therefore has
  /// to be walked past *here*, before the controller is told about it, or the
  /// grid shows "Nothing in progress" over a library that has plenty.
  ///
  /// Only while nothing has been collected: once there is a row to show, the
  /// grid takes over and asks for the rest as the user scrolls.
  Future<List<StreamItem>> _fetchPage(int startIndex) async {
    final generation = _fetchGeneration;
    // Read once: the loop below awaits, and the lens can change under it.
    final lens = _lens;
    final client = _client;
    final cancelToken = CancelToken();
    _fetchCancel = cancelToken;

    final collected = <StreamItem>[];
    var offset = startIndex;
    var hasMore = true;

    for (var attempt = 0; attempt < _maxPagesPerFetch; attempt++) {
      final page = await client.getLibraryPage(
        libraryId: widget.libraryId,
        lens: lens,
        startIndex: offset,
        limit: _pageSize,
        cancelToken: cancelToken,
      );

      // Checked before anything is thrown or written: a fetch whose controller
      // has been replaced must not raise the *old* lens's failure into the new
      // one's state, must not ask for another page, and must not touch the
      // shared offset. A disposed controller drops the returned list.
      if (generation != _fetchGeneration) return const [];

      // Thrown rather than returned empty: `PagingController` catches it into
      // `state.error`, which is what puts a retry on screen instead of the
      // affirmative "the server reports no items here". The clients keep their
      // degrade-to-`[]` convention; the *envelope* is what carries the failure.
      if (page.failed) throw const StreamLibraryPageFailure();
      if (page.needsViewer) throw const StreamLibraryViewerRequired();

      collected.addAll(page.items);
      // "There is more" is only usable if the place to ask for it has moved.
      // Jellyfin computes `nextStartIndex` from the rows it *sent* while
      // `hasMore` compares it against `TotalRecordCount`, so an endpoint that
      // filters rows away server-side (`/UserItems/Resume` with
      // `excludeActiveSessions`, `/Shows/NextUp` with `enableRewatching: false`)
      // answers with zero rows, an unmoved offset and `hasMore: true`. Trusting
      // that pair re-requested the same offset forever: the loop burns its five
      // attempts, the controller appends an empty page, `PagingStatus` stays
      // `ongoing`, and `PagedLayoutBuilder` fires the next fetch straight back.
      final advanced = page.nextStartIndex > offset;
      offset = page.nextStartIndex;
      hasMore = page.hasMore && advanced;
      _started = true;
      if (collected.isNotEmpty || !hasMore) break;
    }

    _nextStartIndex = hasMore ? offset : null;
    return collected;
  }

  static const int _pageSize = 50;

  /// How many server pages one fetch may walk while it has nothing to show.
  ///
  /// A bound rather than "until something turns up": the loop above only runs
  /// while the fetch is empty-handed, and on the lenses that can filter a page
  /// away (Plex's on-deck split) the underlying list is small, so five pages —
  /// 250 rows — is far past any real case. Unbounded, one pathological library
  /// could walk itself end to end inside a single fetch.
  static const int _maxPagesPerFetch = 5;

  StreamServerClient get _client => widget.service == ServiceKey.jellyfin
      ? ref.read(jellyfinServerProvider)
      : ref.read(plexServerProvider);

  @override
  Widget build(BuildContext context) {
    final accent = widget.service.accent;

    // Choosing a household member is the one action [_NeedsViewer] offers, and
    // it happens on another route. Nothing here reads settings otherwise — the
    // client is fetched with `ref.read` inside the fetch — so coming back landed
    // on a controller still parked in `firstPageError`, which
    // `PagedLayoutBuilder` never retries: the panel kept telling the user to
    // choose a viewer they had just chosen. Plex has no viewer to pick.
    if (widget.service == ServiceKey.jellyfin) {
      ref.listen<String>(
        currentSettingsProvider.select((s) => s.jellyfinUserId),
        (_, _) => _restart(),
      );
    }

    return AmbientScaffold(
      accent: accent,
      appBar: GlassAppBar(title: Text(widget.libraryTitle ?? 'Library')),
      body: SafeArea(
        child: Column(
          children: [
            _LensChips(
              selected: _lens,
              accent: accent,
              onSelected: _selectLens,
            ),
            Expanded(
              child: PagingListener<int, StreamItem>(
                controller: _paging,
                builder: (context, state, fetchNextPage) => _LibraryGrid(
                  service: widget.service,
                  lens: _lens,
                  state: state,
                  fetchNextPage: fetchNextPage,
                  onBrowseRecent: () =>
                      _selectLens(StreamLibraryLens.recentlyAdded),
                  onChooseViewer: () => context.push(
                    '/settings/service/${widget.service.routeParam}',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The page did not load. Deliberately an `Exception` rather than an `Error`:
/// `PagingController` rethrows anything that is not one, on the reasoning that a
/// non-exception is a bug rather than a remote failure.
class StreamLibraryPageFailure implements Exception {
  const StreamLibraryPageFailure();

  @override
  String toString() => 'The server did not answer.';
}

/// The lens is per-viewer and no household member has been chosen.
class StreamLibraryViewerRequired implements Exception {
  const StreamLibraryViewerRequired();

  @override
  String toString() => 'No viewer selected.';
}

/// The lens row.
///
/// `ChoiceChip` rather than a `SegmentedButton`: five options do not fit a phone's
/// width as segments, and the row has to be able to scroll. Labels stay short for
/// the eye and are expanded for the ear through [streamLensLabel] — "Continue" on
/// its own does not say what it continues, and both screen readers spell "A–Z" out
/// character by character.
class _LensChips extends StatelessWidget {
  const _LensChips({
    required this.selected,
    required this.accent,
    required this.onSelected,
  });

  final StreamLibraryLens selected;
  final Color accent;
  final ValueChanged<StreamLibraryLens> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          for (final lens in StreamLibraryLens.values)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: Semantics(
                label: streamLensLabel(lens.label),
                selected: lens == selected,
                button: true,
                excludeSemantics: true,
                child: ChoiceChip(
                  label: Text(lens.label),
                  selected: lens == selected,
                  onSelected: (_) => onSelected(lens),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LibraryGrid extends StatelessWidget {
  const _LibraryGrid({
    required this.service,
    required this.lens,
    required this.state,
    required this.fetchNextPage,
    required this.onBrowseRecent,
    required this.onChooseViewer,
  });

  final ServiceKey service;
  final StreamLibraryLens lens;
  final PagingState<int, StreamItem> state;
  final VoidCallback fetchNextPage;
  final VoidCallback onBrowseRecent;
  final VoidCallback onChooseViewer;

  @override
  Widget build(BuildContext context) {
    return PagedGridView<int, StreamItem>(
      state: state,
      fetchNextPage: fetchNextPage,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        FloatingNavBarMetrics.getScrollViewBottomPadding(context),
      ),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        // A floor rather than a fixed count, per the Column Floor Rule: a wide
        // macOS window fills with more posters instead of stretching three.
        maxCrossAxisExtent: 130 + AppSpacing.gridGap,
        childAspectRatio: 2 / 3,
        crossAxisSpacing: AppSpacing.gridGap,
        mainAxisSpacing: AppSpacing.gridGap,
      ),
      builderDelegate: PagedChildBuilderDelegate<StreamItem>(
        itemBuilder: (context, item, index) =>
            StreamPosterTile(service: service, item: item, index: index),
        noItemsFoundIndicatorBuilder: (context) =>
            _EmptyLens(lens: lens, onBrowseRecent: onBrowseRecent),
        // Nothing arrived *and* something went wrong. The default here is the
        // package's generic tile; this has to be the state that never says the
        // library is empty, because at this point we do not know that.
        firstPageErrorIndicatorBuilder: (context) =>
            state.error is StreamLibraryViewerRequired
            ? _NeedsViewer(service: service, onChooseViewer: onChooseViewer)
            : AppErrorState(
                error: state.error ?? const StreamLibraryPageFailure(),
                serviceName: service.title,
                onRetry: fetchNextPage,
              ),
        // A failure partway down used to truncate the grid silently — no
        // spinner, no message, no way to ask again. The rows already fetched
        // stay; this is the footer under them.
        newPageErrorIndicatorBuilder: (context) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Center(
            child: TextButton.icon(
              onPressed: fetchNextPage,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Couldn’t load more · Try again'),
            ),
          ),
        ),
      ),
    );
  }
}

/// The per-viewer lenses on a Jellyfin server with no household member chosen.
///
/// **Not an empty state, because the library is not empty** — nothing has been
/// asked of the server at all. An API key authenticates as an administrator with
/// no user attached, so "continue watching" has no subject until one is named,
/// and the control that names it lives in settings. Saying "This library is
/// empty" here was a false claim with no way out of it: the browse offers no
/// picker, so the user had nothing to act on.
class _NeedsViewer extends StatelessWidget {
  const _NeedsViewer({required this.service, required this.onChooseViewer});

  final ServiceKey service;
  final VoidCallback onChooseViewer;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.person_outline_rounded,
      accentColor: service.accent,
      title: 'Choose whose watch state to show',
      message:
          'Continue watching, next up and unplayed are per person, and '
          '${service.title} needs to be told which one. A–Z works either way.',
      action: FilledButton(
        onPressed: onChooseViewer,
        child: const Text('Pick a viewer'),
      ),
    );
  }
}

/// A lens with nothing in it.
///
/// The per-viewer lenses are legitimately empty on a server nobody has watched
/// yet, and that is not a failure — so this offers the way out rather than just
/// reporting the absence. It deliberately does **not** silently fall back to A–Z:
/// that would quietly undo the reason the landing lens is what it is, and the user
/// would never learn the other lenses exist.
class _EmptyLens extends StatelessWidget {
  const _EmptyLens({required this.lens, required this.onBrowseRecent});

  final StreamLibraryLens lens;
  final VoidCallback onBrowseRecent;

  @override
  Widget build(BuildContext context) {
    final showRecent = lens != StreamLibraryLens.recentlyAdded;

    return AppEmptyState(
      icon: switch (lens) {
        StreamLibraryLens.continueWatching => Icons.play_circle_outline_rounded,
        StreamLibraryLens.nextUp => Icons.skip_next_rounded,
        StreamLibraryLens.recentlyAdded => Icons.new_releases_outlined,
        StreamLibraryLens.unplayed => Icons.visibility_off_outlined,
        StreamLibraryLens.all => Icons.sort_by_alpha_rounded,
      },
      title: switch (lens) {
        StreamLibraryLens.continueWatching => 'Nothing in progress',
        StreamLibraryLens.nextUp => 'Nothing queued up',
        StreamLibraryLens.recentlyAdded => 'Nothing added yet',
        StreamLibraryLens.unplayed => 'Everything has been played',
        StreamLibraryLens.all => 'This library is empty',
      },
      message: switch (lens) {
        StreamLibraryLens.continueWatching =>
          'Start something and it will pick up here.',
        StreamLibraryLens.nextUp =>
          'Next episodes appear once a series is under way.',
        StreamLibraryLens.recentlyAdded =>
          'New files show up here after a library scan.',
        StreamLibraryLens.unplayed => 'Nothing left unwatched in this library.',
        StreamLibraryLens.all => 'The server reports no items here.',
      },
      action: showRecent
          ? FilledButton(
              onPressed: onBrowseRecent,
              child: const Text('See what’s new'),
            )
          : null,
    );
  }
}
