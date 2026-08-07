import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/duration_format.dart';
import 'package:seekarr/core/utils/grab_error_utils.dart';
import 'package:seekarr/core/utils/release_utils.dart';
import 'package:seekarr/core/widgets/app_bottom_sheet.dart';
import 'package:seekarr/core/widgets/app_dialog.dart';
import 'package:seekarr/core/widgets/app_empty_state.dart';
import 'package:seekarr/core/widgets/app_error_state.dart';
import 'package:seekarr/core/widgets/release_list_widgets.dart';
import 'package:seekarr/core/widgets/shimmer_placeholder.dart';

// Re-export ReleaseSortType for backwards compatibility
export 'package:seekarr/core/utils/release_utils.dart' show ReleaseSortType;

/// Signals that a grab callback deliberately did **not** grab.
///
/// The sheet infers "the release was grabbed" from "the callback returned
/// without throwing", and closes under a green *Download started* on that
/// inference. It is right for a callback that only ever grabs, and wrong for one
/// that may decide not to: the release-search sheet asks *"Search again for this
/// release?"* once the service has dropped the release list, and both of that
/// prompt's non-grab outcomes — cancelling it, or accepting and starting a fresh
/// search — return normally. Cancelling used to close the sheet and claim a
/// download had started.
///
/// It rides the error channel because that is where "no grab happened" already
/// lives: the callback's return type is `Future<void>`, so a throw is the only
/// thing it can say. Unlike a real failure it is silent — the row stops
/// spinning, the sheet stays open, and no snackbar is shown, because a caller
/// that abandons a grab has just shown the user why.
class ReleaseGrabAbandoned implements Exception {
  const ReleaseGrabAbandoned();

  @override
  String toString() => 'ReleaseGrabAbandoned';
}

/// A reusable bottom sheet for displaying and selecting releases (Interactive Search).
class InteractiveSearchSheet extends StatefulWidget {
  final List<dynamic> releases;
  final String title;

  /// Grabs the release. Returning normally means it was grabbed — the sheet
  /// closes and reports a started download on exactly that. A callback that can
  /// decide *not* to grab must say so by throwing [ReleaseGrabAbandoned];
  /// anything else it throws is reported as a failure.
  final Future<void> Function(String guid, int indexerId) onGrabRelease;

  final ScrollController scrollController;

  const InteractiveSearchSheet({
    super.key,
    required this.releases,
    required this.title,
    required this.onGrabRelease,
    required this.scrollController,
  });

  /// Shows the interactive search sheet as a modal bottom sheet.
  static Future<void> show({
    required BuildContext context,
    required List<dynamic> releases,
    required String title,
    required Future<void> Function(String guid, int indexerId) onGrabRelease,
    Color? accent,
  }) {
    return AppBottomSheet.showScrollable(
      context: context,
      title: 'Releases',
      subtitle: title,
      icon: Icons.travel_explore_rounded,
      accent: accent,
      showClose: true,
      initialSize: 0.75,
      minSize: 0.5,
      maxSize: 0.95,
      builder: (context, scrollController) => InteractiveSearchSheet(
        releases: releases,
        title: title,
        onGrabRelease: onGrabRelease,
        scrollController: scrollController,
      ),
    );
  }

  /// Shows interactive search sheet with loading state, fetching releases asynchronously.
  /// Fetch failures render inline with a retry action instead of closing the sheet.
  static Future<void> showAsync({
    required BuildContext context,
    required String title,
    required Future<List<dynamic>> Function(CancelToken token) fetchReleases,
    required Future<void> Function(String guid, int indexerId) onGrabRelease,
    Color? accent,
  }) {
    return AppBottomSheet.showScrollable(
      context: context,
      title: 'Releases',
      subtitle: title,
      icon: Icons.travel_explore_rounded,
      accent: accent,
      showClose: true,
      initialSize: 0.75,
      minSize: 0.5,
      maxSize: 0.95,
      builder: (context, scrollController) => _AsyncInteractiveSearchSheet(
        title: title,
        fetchReleases: fetchReleases,
        onGrabRelease: onGrabRelease,
        scrollController: scrollController,
      ),
    );
  }

  @override
  State<InteractiveSearchSheet> createState() => _InteractiveSearchSheetState();
}

class _InteractiveSearchSheetState extends State<InteractiveSearchSheet> {
  final TextEditingController _searchController = TextEditingController();

  ReleaseSortType _sortType = ReleaseSortType.score;
  bool _sortAscending = false;
  bool _approvedOnly = false;
  String? _selectedIndexer;
  ReleaseProtocol? _selectedProtocol;
  String _query = '';

  /// GUID of the release currently being grabbed, if any.
  String? _grabbingGuid;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _hasActiveFilters =>
      _approvedOnly ||
      _selectedIndexer != null ||
      _selectedProtocol != null ||
      _query.trim().isNotEmpty;

  /// Returns filtered and sorted releases using the pure function.
  List<dynamic> get _filteredAndSortedReleases {
    return filterAndSortReleases(
      widget.releases,
      sortType: _sortType,
      sortAscending: _sortAscending,
      hideRejected: _approvedOnly,
      selectedIndexer: _selectedIndexer,
      selectedProtocol: _selectedProtocol,
      query: _query,
    );
  }

  /// Returns unique indexer names from all releases.
  Set<String> get _availableIndexers =>
      extractAvailableIndexers(widget.releases);

  void _clearFilters() {
    HapticFeedback.selectionClick();
    _searchController.clear();
    setState(() {
      _approvedOnly = false;
      _selectedIndexer = null;
      _selectedProtocol = null;
      _query = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredAndSortedReleases;
    final protocols = extractAvailableProtocols(widget.releases);

    return Column(
      children: [
        _ReleaseToolbar(
          searchController: _searchController,
          onQueryChanged: (value) => setState(() => _query = value),
          sortType: _sortType,
          sortAscending: _sortAscending,
          onSortChanged: (type) => setState(() {
            // Re-selecting the active sort flips its direction — one gesture
            // for both "sort by" and "which way".
            if (type == _sortType) {
              _sortAscending = !_sortAscending;
            } else {
              _sortType = type;
              _sortAscending = false;
            }
          }),
          onDirectionToggled: () =>
              setState(() => _sortAscending = !_sortAscending),
          approvedOnly: _approvedOnly,
          onApprovedOnlyChanged: (value) =>
              setState(() => _approvedOnly = value),
          protocols: protocols,
          selectedProtocol: _selectedProtocol,
          onProtocolChanged: (protocol) =>
              setState(() => _selectedProtocol = protocol),
          indexers: _availableIndexers,
          selectedIndexer: _selectedIndexer,
          onIndexerChanged: (indexer) =>
              setState(() => _selectedIndexer = indexer),
          shownCount: filtered.length,
          totalCount: widget.releases.length,
          approvedCount: countApprovedReleases(widget.releases),
          hasActiveFilters: _hasActiveFilters,
          onClearFilters: _clearFilters,
        ),
        Expanded(
          child: filtered.isEmpty
              ? _EmptyReleases(
                  hasActiveFilters: _hasActiveFilters,
                  onClearFilters: _clearFilters,
                  scrollController: widget.scrollController,
                )
              : ListView.builder(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.only(
                    top: AppSpacing.sm,
                    bottom: AppSpacing.xl,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final release = filtered[index];
                    final isGrabbing =
                        _grabbingGuid != null &&
                        _grabbingGuid == release['guid'];
                    return ReleaseListItem(
                      // guid is indexer-supplied and not guaranteed unique;
                      // two identical ones threw "Duplicate keys found" and
                      // blanked the list. Pairing it with the index keeps keys
                      // unique and stops a guid-less row inheriting another's
                      // expanded state when a filter shifts the indices.
                      key: ValueKey('${release['guid'] ?? ''}#$index'),
                      release: release,
                      isGrabbing: isGrabbing,
                      // One grab at a time: only the busy row used to show a
                      // spinner, so a second tap elsewhere overwrote
                      // `_grabbingGuid`, the first row's spinner vanished while
                      // its request was still in flight, and whichever finished
                      // first popped the sheet.
                      onGrab: _grabbingGuid != null
                          ? null
                          : () => _handleGrab(context, release),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Grabs one release.
  ///
  /// [rowContext] is the list row's element, and it is deliberately *not* what
  /// the outcome is reported through. The toolbar stays live during a grab, so
  /// a filter or query that empties the list mid-flight swaps the `ListView`
  /// for `_EmptyReleases` and deactivates that row — while the request, and the
  /// sheet, carry on. Reporting through it meant a **successful** grab silently
  /// skipped both the pop and the confirmation and simply re-armed every button:
  /// the download had started, nothing on screen said so, and tapping the same
  /// row again grabbed it twice. So the row's context is used only for the
  /// confirmation dialog it belongs to; everything after the await goes through
  /// the sheet's own, which is alive exactly while [mounted] is true.
  Future<void> _handleGrab(BuildContext rowContext, dynamic release) async {
    final guid = release['guid'] as String?;
    final indexerId = release['indexerId'] as int?;
    final releaseTitle = release['title'] as String? ?? 'Release';

    if (guid == null || indexerId == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invalid release data')));
      }
      return;
    }

    final rejections = releaseRejectionReasons(release);
    final result = await showAppConfirmDialog(
      context: rowContext,
      title: rejections.isEmpty ? 'Grab Release' : 'Grab Rejected Release',
      message: rejections.isEmpty
          ? 'Download "$releaseTitle"?'
          : 'This release was rejected:\n\n'
                '${rejections.map((r) => '• $r').join('\n')}\n\n'
                'Download "$releaseTitle" anyway?',
      confirmLabel: 'Download',
      cancelLabel: 'Cancel',
    );

    if (!result.confirmed || !mounted) return;

    HapticFeedback.mediumImpact();
    setState(() => _grabbingGuid = guid);

    try {
      await widget.onGrabRelease(guid, indexerId);
      if (!mounted) return;
      // Both resolved before the pop, which takes this element out of the tree.
      final messenger = ScaffoldMessenger.of(context);
      final accent = Theme.of(context).colorScheme.primary;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Download started'),
          backgroundColor: accent,
        ),
      );
    } on ReleaseGrabAbandoned {
      // No grab, and the caller has already said why. Re-arm the list and stay.
      if (mounted) setState(() => _grabbingGuid = null);
    } catch (e) {
      if (!mounted) return;
      // Re-armed rather than popped: the sheet is where the user retries, and
      // the failure has to be reported even when the row it started from is
      // gone — the busy state is the State's, not the row's.
      setState(() => _grabbingGuid = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(translateGrabError(e)),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
}

/// Pinned search + sort + filter controls above the release list.
class _ReleaseToolbar extends StatelessWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final ReleaseSortType sortType;
  final bool sortAscending;
  final ValueChanged<ReleaseSortType> onSortChanged;
  final VoidCallback onDirectionToggled;
  final bool approvedOnly;
  final ValueChanged<bool> onApprovedOnlyChanged;
  final List<ReleaseProtocol> protocols;
  final ReleaseProtocol? selectedProtocol;
  final ValueChanged<ReleaseProtocol?> onProtocolChanged;
  final Set<String> indexers;
  final String? selectedIndexer;
  final ValueChanged<String?> onIndexerChanged;
  final int shownCount;
  final int totalCount;
  final int approvedCount;
  final bool hasActiveFilters;
  final VoidCallback onClearFilters;

  const _ReleaseToolbar({
    required this.searchController,
    required this.onQueryChanged,
    required this.sortType,
    required this.sortAscending,
    required this.onSortChanged,
    required this.onDirectionToggled,
    required this.approvedOnly,
    required this.onApprovedOnlyChanged,
    required this.protocols,
    required this.selectedProtocol,
    required this.onProtocolChanged,
    required this.indexers,
    required this.selectedIndexer,
    required this.onIndexerChanged,
    required this.shownCount,
    required this.totalCount,
    required this.approvedCount,
    required this.hasActiveFilters,
    required this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: TextField(
            controller: searchController,
            onChanged: onQueryChanged,
            textInputAction: TextInputAction.search,
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Filter releases',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 40,
                minHeight: 40,
              ),
              suffixIcon: searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      tooltip: 'Clear filter',
                      onPressed: () {
                        searchController.clear();
                        onQueryChanged('');
                      },
                    ),
              filled: true,
              fillColor: colorScheme.surfaceContainerHigh,
              contentPadding: const EdgeInsets.symmetric(
                vertical: AppSpacing.md,
              ),
              border: OutlineInputBorder(
                borderRadius: AppRadius.borderRadiusFull,
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadius.borderRadiusFull,
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppRadius.borderRadiusFull,
                borderSide: BorderSide(color: colorScheme.primary),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            children: [
              _SortChip(
                sortType: sortType,
                ascending: sortAscending,
                onSelected: onSortChanged,
                onDirectionToggled: onDirectionToggled,
              ),
              const SizedBox(width: AppSpacing.sm),
              FilterChip(
                label: const Text('Approved only'),
                selected: approvedOnly,
                showCheckmark: false,
                avatar: Icon(
                  approvedOnly
                      ? Icons.verified_rounded
                      : Icons.filter_alt_outlined,
                  size: 18,
                ),
                onSelected: (value) {
                  HapticFeedback.selectionClick();
                  onApprovedOnlyChanged(value);
                },
              ),
              if (protocols.length > 1)
                for (final protocol in protocols) ...[
                  const SizedBox(width: AppSpacing.sm),
                  FilterChip(
                    label: Text(protocol.label),
                    selected: selectedProtocol == protocol,
                    showCheckmark: false,
                    avatar: Icon(protocol.icon, size: 18),
                    onSelected: (selected) {
                      HapticFeedback.selectionClick();
                      onProtocolChanged(selected ? protocol : null);
                    },
                  ),
                ],
              if (indexers.length > 1) ...[
                const SizedBox(width: AppSpacing.sm),
                _IndexerChip(
                  indexers: indexers,
                  selected: selectedIndexer,
                  onChanged: onIndexerChanged,
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _summary(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (hasActiveFilters)
                TextButton.icon(
                  onPressed: onClearFilters,
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                  label: const Text('Clear'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _summary() {
    final buffer = StringBuffer();
    if (shownCount == totalCount) {
      buffer.write('$totalCount release${totalCount == 1 ? '' : 's'}');
    } else {
      buffer.write('$shownCount of $totalCount releases');
    }
    buffer.write(' · $approvedCount approved');
    return buffer.toString();
  }
}

/// Sort selector: the chip opens the field menu, the trailing arrow flips
/// the direction without leaving the sheet.
class _SortChip extends StatelessWidget {
  final ReleaseSortType sortType;
  final bool ascending;
  final ValueChanged<ReleaseSortType> onSelected;
  final VoidCallback onDirectionToggled;

  const _SortChip({
    required this.sortType,
    required this.ascending,
    required this.onSelected,
    required this.onDirectionToggled,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final directionIcon = ascending
        ? Icons.arrow_upward_rounded
        : Icons.arrow_downward_rounded;

    return PopupMenuButton<ReleaseSortType>(
      initialValue: sortType,
      tooltip: 'Sort releases',
      onSelected: (type) {
        HapticFeedback.selectionClick();
        onSelected(type);
      },
      itemBuilder: (context) => ReleaseSortType.values.map((type) {
        final isActive = type == sortType;
        return PopupMenuItem(
          value: type,
          child: Row(
            children: [
              Icon(type.icon, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Text(type.label),
              if (isActive) ...[
                const Spacer(),
                Icon(directionIcon, size: 18, color: colorScheme.primary),
              ],
            ],
          ),
        );
      }).toList(),
      // The chip body is the popup anchor; the trailing arrow is its own tap
      // target so flipping the direction never opens the menu.
      child: _ChipShell(
        icon: sortType.icon,
        label: sortType.label,
        trailing: _ChipTrailing(
          icon: directionIcon,
          tooltip: ascending ? 'Ascending' : 'Descending',
          onTap: () {
            HapticFeedback.selectionClick();
            onDirectionToggled();
          },
        ),
      ),
    );
  }
}

/// Pill used as the anchor for the sort and indexer popup menus.
///
/// Mirrors [FilterChip]'s metrics so the toolbar reads as one row of chips,
/// while allowing an independently tappable trailing affordance.
class _ChipShell extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  final bool selected;

  const _ChipShell({
    required this.icon,
    required this.label,
    this.trailing,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final foreground = selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.secondaryContainer
            : colorScheme.surfaceContainerHigh,
        borderRadius: AppRadius.borderRadiusSm,
        border: Border.all(
          color: selected
              ? Colors.transparent
              : colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(color: foreground),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.xs),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Independently tappable icon at the end of a [_ChipShell].
class _ChipTrailing extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ChipTrailing({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 16,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Icon(
            icon,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Popup chip listing every indexer that returned results.
class _IndexerChip extends StatelessWidget {
  final Set<String> indexers;
  final String? selected;
  final ValueChanged<String?> onChanged;

  const _IndexerChip({
    required this.indexers,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuButton<String?>(
      initialValue: selected,
      tooltip: 'Filter by indexer',
      onSelected: (indexer) {
        HapticFeedback.selectionClick();
        onChanged(indexer);
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: null,
          child: Row(
            children: [
              const Icon(Icons.all_inclusive_rounded, size: 20),
              const SizedBox(width: AppSpacing.sm),
              const Text('All Indexers'),
              if (selected == null) ...[
                const Spacer(),
                Icon(Icons.check_rounded, size: 20, color: colorScheme.primary),
              ],
            ],
          ),
        ),
        const PopupMenuDivider(),
        ...indexers.map(
          (indexer) => PopupMenuItem(
            value: indexer,
            child: Row(
              children: [
                const Icon(Icons.dns_outlined, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Flexible(child: Text(indexer)),
                if (indexer == selected) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Icon(
                    Icons.check_rounded,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
      child: _ChipShell(
        icon: Icons.dns_rounded,
        label: selected ?? 'All Indexers',
        selected: selected != null,
        trailing: selected == null
            ? null
            : _ChipTrailing(
                icon: Icons.close_rounded,
                tooltip: 'Clear indexer filter',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(null);
                },
              ),
      ),
    );
  }
}

/// Empty state for "no results" and "filtered everything out".
///
/// A scrollable, not a `Center`: every branch of a sheet body has to be attached
/// to the controller [AppBottomSheet.showScrollable] hands in, or the sheet
/// stops answering drag-to-resize and flick-to-close the moment a filter empties
/// the list — the same rule `music_albums_list.dart` states for its own loading
/// and error branches.
class _EmptyReleases extends StatelessWidget {
  final bool hasActiveFilters;
  final VoidCallback onClearFilters;
  final ScrollController scrollController;

  const _EmptyReleases({
    required this.hasActiveFilters,
    required this.onClearFilters,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        hasActiveFilters
            ? AppEmptyState.compact(
                icon: Icons.filter_alt_off_rounded,
                title: 'No releases match filters',
                message: 'Loosen the filters to see the rest of the results.',
                action: TextButton(
                  onPressed: onClearFilters,
                  child: const Text('Clear Filters'),
                ),
              )
            : const AppEmptyState.compact(
                icon: Icons.search_off_rounded,
                title: 'No releases found',
                message:
                    'No indexer returned a result for this search. Try again '
                    'later or check your indexer settings.',
              ),
      ],
    );
  }
}

/// Skeleton list shown while indexers are queried.
///
/// A release search is the one arr call that legitimately runs for minutes, so
/// this is an instrument rather than a spinner. The elapsed readout appears only
/// once the search crosses [readoutAfter] — a clock on a search that answers in
/// two seconds is noise — and Cancel makes the exit explicit rather than leaving
/// it to be discovered by dismissing the sheet.
///
/// There is deliberately no percentage: the server reports no per-indexer
/// progress, so any bar would be invented. Elapsed is the only honest readout.
class _ReleaseSearchLoading extends StatelessWidget {
  const _ReleaseSearchLoading({required this.elapsed, required this.onCancel});

  final Duration elapsed;
  final VoidCallback onCancel;

  /// Below this the search is about to answer anyway; a clock only adds noise.
  static const readoutAfter = Duration(seconds: 3);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showElapsed = elapsed >= readoutAfter;
    const label = 'Searching for releases…';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              // The status summary is one node; Cancel stays a sibling so it
              // keeps its own, rather than being swallowed by the summary's.
              Expanded(
                child: Semantics(
                  container: true,
                  // Not a live region: announcing a clock every second is
                  // hostile, so this is read on focus, not pushed at the user.
                  label: showElapsed
                      ? '$label ${formatElapsedForSpeech(elapsed)} elapsed.'
                      : label,
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (showElapsed)
                          Padding(
                            padding: const EdgeInsets.only(left: AppSpacing.sm),
                            child: Text(
                              formatElapsed(elapsed),
                              style: theme.textTheme.bodySmall?.tabular
                                  .copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              TextButton(onPressed: onCancel, child: const Text('Cancel')),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            itemCount: 6,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ShimmerPlaceholder(
                height: 104,
                borderRadius: AppRadius.borderRadiusMd,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Wrapper widget that fetches releases asynchronously and displays InteractiveSearchSheet.
/// Shows a skeleton while loading, renders failures inline with a retry action,
/// and cancels the fetch on dispose.
class _AsyncInteractiveSearchSheet extends StatefulWidget {
  final String title;
  final Future<List<dynamic>> Function(CancelToken token) fetchReleases;
  final Future<void> Function(String guid, int indexerId) onGrabRelease;
  final ScrollController scrollController;

  const _AsyncInteractiveSearchSheet({
    required this.title,
    required this.fetchReleases,
    required this.onGrabRelease,
    required this.scrollController,
  });

  @override
  State<_AsyncInteractiveSearchSheet> createState() =>
      _AsyncInteractiveSearchSheetState();
}

class _AsyncInteractiveSearchSheetState
    extends State<_AsyncInteractiveSearchSheet> {
  late CancelToken _cancelToken;
  List<dynamic>? _releases;
  Object? _error;

  /// Drives the elapsed readout. A release search can run for minutes, so how
  /// long it has been waiting is the only progress the server lets us report.
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _cancelToken = CancelToken();
    _startSearch();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _cancelToken.cancel();
    super.dispose();
  }

  void _startSearch() {
    _elapsed = Duration.zero;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
    });
    _loadReleases();
  }

  /// Stops the clock as soon as the search resolves, so a settled sheet is not
  /// rebuilding once a second behind the release list.
  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> _loadReleases() async {
    try {
      final releases = await widget.fetchReleases(_cancelToken);
      if (mounted && !_cancelToken.isCancelled) {
        _stopTicker();
        setState(() {
          _releases = releases;
          _error = null;
        });
      }
    } catch (e) {
      if (_cancelToken.isCancelled || !mounted) return;
      _stopTicker();
      setState(() => _error = e);
    }
  }

  void _retry() {
    _cancelToken = CancelToken();
    setState(() {
      _error = null;
      _releases = null;
    });
    _startSearch();
  }

  /// Dismissing the sheet already cancels the fetch in [dispose]; this only
  /// makes that exit visible, because a search that may run for minutes needs a
  /// way out the user can see.
  void _cancel() {
    HapticFeedback.selectionClick();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: AppErrorState.compact(error: _error!, onRetry: _retry),
        ),
      );
    }

    if (_releases == null) {
      return _ReleaseSearchLoading(elapsed: _elapsed, onCancel: _cancel);
    }

    return InteractiveSearchSheet(
      releases: _releases!,
      title: widget.title,
      onGrabRelease: widget.onGrabRelease,
      scrollController: widget.scrollController,
    );
  }
}
