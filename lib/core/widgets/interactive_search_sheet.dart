import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/utils/grab_error_utils.dart';
import 'package:seekarr/core/utils/release_utils.dart';
import 'package:seekarr/core/widgets/app_bottom_sheet.dart';
import 'package:seekarr/core/widgets/app_dialog.dart';
import 'package:seekarr/core/widgets/release_list_widgets.dart';

// Re-export ReleaseSortType for backwards compatibility
export 'package:seekarr/core/utils/release_utils.dart' show ReleaseSortType;

/// A reusable bottom sheet for displaying and selecting releases (Interactive Search).
class InteractiveSearchSheet extends StatefulWidget {
  final List<dynamic> releases;
  final String title;
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
  }) {
    return AppBottomSheet.showScrollable(
      context: context,
      title: 'Releases',
      subtitle: title,
      icon: Icons.search_rounded,
      initialSize: 0.7,
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
  /// Closes the sheet and shows a SnackBar on fetch error (unless cancelled by user).
  static Future<void> showAsync({
    required BuildContext context,
    required String title,
    required Future<List<dynamic>> Function(CancelToken token) fetchReleases,
    required Future<void> Function(String guid, int indexerId) onGrabRelease,
  }) {
    return AppBottomSheet.showScrollable(
      context: context,
      title: 'Releases',
      subtitle: title,
      icon: Icons.search_rounded,
      initialSize: 0.7,
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
  ReleaseSortType _sortType = ReleaseSortType.score;
  bool _sortAscending = false;
  bool _hideRejected = false;
  String? _selectedIndexer;

  /// Returns filtered and sorted releases using the pure function.
  List<dynamic> get _filteredAndSortedReleases {
    return filterAndSortReleases(
      widget.releases,
      sortType: _sortType,
      sortAscending: _sortAscending,
      hideRejected: _hideRejected,
      selectedIndexer: _selectedIndexer,
    );
  }

  /// Returns unique indexer names from all releases.
  Set<String> get _availableIndexers {
    return extractAvailableIndexers(widget.releases);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final filteredReleases = _filteredAndSortedReleases;

    return Column(
      children: [
        // Result count
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: [
              const Spacer(),
              Text(
                '${filteredReleases.length}/${widget.releases.length}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),

        // Sort & Filter controls
        _buildSortFilterBar(context, colorScheme),

        // Releases list
        Expanded(
          child: filteredReleases.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 48,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        _hideRejected || _selectedIndexer != null
                            ? 'No releases match filters'
                            : 'No releases found',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (_hideRejected || _selectedIndexer != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        TextButton(
                          onPressed: () => setState(() {
                            _hideRejected = false;
                            _selectedIndexer = null;
                          }),
                          child: const Text('Clear Filters'),
                        ),
                      ],
                    ],
                  ),
                )
              : ListView.builder(
                  controller: widget.scrollController,
                  itemCount: filteredReleases.length,
                  itemBuilder: (context, index) {
                    final release = filteredReleases[index];
                    return ReleaseListItem(
                      release: release,
                      onGrab: () => _handleGrab(context, release),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSortFilterBar(BuildContext context, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Sort dropdown
            PopupMenuButton<ReleaseSortType>(
              initialValue: _sortType,
              onSelected: (type) => setState(() => _sortType = type),
              child: Chip(
                avatar: Icon(_sortType.icon, size: 18),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_sortType.label),
                    const SizedBox(width: 4),
                    Icon(
                      _sortAscending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 16,
                    ),
                  ],
                ),
              ),
              itemBuilder: (context) => ReleaseSortType.values.map((type) {
                return PopupMenuItem(
                  value: type,
                  child: Row(
                    children: [
                      Icon(type.icon, size: 20),
                      const SizedBox(width: AppSpacing.sm),
                      Text(type.label),
                      if (type == _sortType) ...[
                        const Spacer(),
                        Icon(
                          Icons.check_rounded,
                          size: 20,
                          color: colorScheme.primary,
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(width: AppSpacing.sm),

            // Sort direction toggle
            IconButton(
              icon: Icon(
                _sortAscending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 20,
              ),
              onPressed: () => setState(() => _sortAscending = !_sortAscending),
              tooltip: _sortAscending ? 'Ascending' : 'Descending',
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(width: AppSpacing.md),

            // Hide rejected filter
            FilterChip(
              label: const Text('Hide Rejected'),
              selected: _hideRejected,
              onSelected: (selected) =>
                  setState(() => _hideRejected = selected),
              avatar: _hideRejected
                  ? const Icon(Icons.check_rounded, size: 18)
                  : const Icon(Icons.block_rounded, size: 18),
            ),
            const SizedBox(width: AppSpacing.sm),

            // Indexer filter
            if (_availableIndexers.length > 1)
              PopupMenuButton<String?>(
                initialValue: _selectedIndexer,
                onSelected: (indexer) =>
                    setState(() => _selectedIndexer = indexer),
                child: Chip(
                  avatar: const Icon(Icons.dns_rounded, size: 18),
                  label: Text(_selectedIndexer ?? 'All Indexers'),
                  deleteIcon: _selectedIndexer != null
                      ? const Icon(Icons.close_rounded, size: 18)
                      : null,
                  onDeleted: _selectedIndexer != null
                      ? () => setState(() => _selectedIndexer = null)
                      : null,
                ),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: null,
                    child: Row(
                      children: [
                        const Icon(Icons.all_inclusive_rounded, size: 20),
                        const SizedBox(width: AppSpacing.sm),
                        const Text('All Indexers'),
                        if (_selectedIndexer == null) ...[
                          const Spacer(),
                          Icon(
                            Icons.check_rounded,
                            size: 20,
                            color: colorScheme.primary,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  ..._availableIndexers.map((indexer) {
                    return PopupMenuItem(
                      value: indexer,
                      child: Row(
                        children: [
                          const Icon(Icons.dns_outlined, size: 20),
                          const SizedBox(width: AppSpacing.sm),
                          Text(indexer),
                          if (indexer == _selectedIndexer) ...[
                            const Spacer(),
                            Icon(
                              Icons.check_rounded,
                              size: 20,
                              color: colorScheme.primary,
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleGrab(BuildContext context, dynamic release) async {
    final guid = release['guid'] as String?;
    final indexerId = release['indexerId'] as int?;
    final releaseTitle = release['title'] as String? ?? 'Release';

    if (guid == null || indexerId == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invalid release data')));
      }
      return;
    }

    // Show confirmation dialog
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Grab Release',
      message: 'Download "$releaseTitle"?',
      confirmLabel: 'Download',
      cancelLabel: 'Cancel',
    );

    if (!result.confirmed || !context.mounted) return;

    try {
      await widget.onGrabRelease(guid, indexerId);
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Download started'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        final message = translateGrabError(e);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }
}

/// Wrapper widget that fetches releases asynchronously and displays InteractiveSearchSheet.
/// Shows loading state, handles errors by closing sheet and showing SnackBar,
/// and cancels fetch on widget dispose.
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
  late final CancelToken _cancelToken;
  List<dynamic>? _releases;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _cancelToken = CancelToken();
    _loadReleases();
  }

  @override
  void dispose() {
    _cancelToken.cancel();
    super.dispose();
  }

  Future<void> _loadReleases() async {
    try {
      final releases = await widget.fetchReleases(_cancelToken);
      if (mounted && !_cancelToken.isCancelled) {
        setState(() {
          _releases = releases;
        });
      }
    } catch (e) {
      if (_cancelToken.isCancelled) {
        return;
      }
      if (mounted) {
        setState(() {
          _hasError = true;
        });
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load releases: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return const SizedBox.shrink();
    }

    if (_releases == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Searching for releases...',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return InteractiveSearchSheet(
      releases: _releases!,
      title: widget.title,
      onGrabRelease: widget.onGrabRelease,
      scrollController: widget.scrollController,
    );
  }
}
