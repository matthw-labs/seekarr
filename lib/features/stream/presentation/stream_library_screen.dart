import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:seekarr/features/plex/presentation/plex_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/stream/domain/models/stream_item.dart';
import 'package:seekarr/features/stream/domain/stream_semantics.dart';
import 'package:seekarr/features/stream/domain/stream_server_client.dart';
import 'package:seekarr/features/stream/presentation/widgets/stream_poster_tile.dart';

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

  @override
  void initState() {
    super.initState();
    _paging = _buildController();
  }

  @override
  void dispose() {
    _paging.dispose();
    super.dispose();
  }

  PagingController<int, StreamItem> _buildController() {
    return PagingController<int, StreamItem>(
      getNextPageKey: (state) =>
          state.lastPageIsEmpty ? null : state.nextIntPageKey,
      fetchPage: _fetchPage,
    );
  }

  /// Changing lens is a new list, not a filter over the old one.
  ///
  /// Each lens is a different server query with its own ordering, so the paging
  /// controller is rebuilt rather than refreshed — reusing it would append page 1
  /// of "Unplayed" onto page 3 of "Continue" and produce a list that is neither.
  void _selectLens(StreamLibraryLens lens) {
    if (lens == _lens) return;
    final previous = _paging;
    setState(() {
      _lens = lens;
      _paging = _buildController();
    });
    previous.dispose();
  }

  Future<List<StreamItem>> _fetchPage(int pageKey) {
    final client = _client;
    return client.getLibraryItems(
      libraryId: widget.libraryId,
      lens: _lens,
      startIndex: pageKey * _pageSize,
      limit: _pageSize,
    );
  }

  static const int _pageSize = 50;

  StreamServerClient get _client => widget.service == ServiceKey.jellyfin
      ? ref.read(jellyfinServerProvider)
      : ref.read(plexServerProvider);

  @override
  Widget build(BuildContext context) {
    final accent = widget.service.accent;

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
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
  });

  final ServiceKey service;
  final StreamLibraryLens lens;
  final PagingState<int, StreamItem> state;
  final VoidCallback fetchNextPage;
  final VoidCallback onBrowseRecent;

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
