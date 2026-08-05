import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/service_theme.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/import/domain/manual_import_display.dart';
import 'package:seekarr/features/import/domain/manual_import_models.dart';
import 'package:seekarr/features/import/domain/manual_import_status.dart';
import 'package:seekarr/features/import/presentation/manual_import_fix_sheet.dart';
import 'package:seekarr/features/import/presentation/manual_import_provider.dart';
import 'package:seekarr/features/import/presentation/manual_import_review_facets.dart';
import 'package:seekarr/features/import/presentation/manual_import_review_rows.dart';
import 'package:seekarr/features/import/presentation/manual_import_routes.dart';
import 'package:seekarr/features/import/presentation/manual_import_widgets.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// Above this many ready files, groups arrive collapsed.
///
/// A three-file rescue should show its contents immediately; a four-hundred
/// file backlog should show its *shape* — the list of shows — and let the user
/// open the one they came for.
const _autoCollapseThreshold = 20;

/// Above this many scanned files, the filter field appears.
///
/// A three-file rescue does not need a search box above it; anything that runs
/// past a screenful does, and by the time a real downloads folder is involved
/// the filter is the primary way in.
const _filterThreshold = 6;

/// Station 2 — Review: the scanned files, grouped by what they need and by what
/// they matched to.
///
/// Selection and matching live on one list. A file is either matched (checkbox,
/// included in the import), already in the library (checkbox too — ticking it
/// asks for a replacement), in need of a match (tap to fix), or of a kind this
/// service does not import. The old flow split selection and matching across two
/// screens, so you selected blind and discovered the match problems a screen
/// later.
///
/// The counts across the top are the screen's one control for *what is on it*.
/// Show/hide used to be spread over three places — an app-bar toggle for the
/// imported files, a collapsing header for the unmatched ones, a second one for
/// the unimportable ones — and none of them said what they were hiding. Now the
/// four counts are four filters, and the row beneath them says how much of the
/// scan is currently on screen.
class ManualImportReviewScreen extends ConsumerStatefulWidget {
  final ServiceKey service;
  final int? targetId;

  const ManualImportReviewScreen({
    super.key,
    required this.service,
    this.targetId,
  });

  @override
  ConsumerState<ManualImportReviewScreen> createState() =>
      _ManualImportReviewScreenState();
}

class _ManualImportReviewScreenState
    extends ConsumerState<ManualImportReviewScreen> {
  final _filterController = TextEditingController();

  /// Group titles the user has explicitly opened or closed, overriding the
  /// density default.
  final _expanded = <String>{};
  final _collapsed = <String>{};

  String _query = '';

  /// Facets the user has switched off in the count row.
  ///
  /// "Other" starts hidden: files this service cannot import are the one class
  /// that is never actionable, and a real downloads folder holds dozens of them.
  /// Everything else starts visible — including the files already in the
  /// library, because the whole job of the Review step is to show what the scan
  /// found, and a file silently missing from the list is how "I already imported
  /// that" became an unanswerable question.
  final _hidden = <ManualImportFacet>{ManualImportFacet.other};

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final notifier = ref.read(manualImportFlowProvider.notifier);
      final state = ref.read(manualImportFlowProvider);
      if (state.service != widget.service || state.selectedFolder == null) {
        await notifier.start(widget.service, targetId: widget.targetId);
      }
      await notifier.loadSelectedFolderItems();
    });
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  bool _isGroupExpanded(String title, {required bool defaultExpanded}) {
    // A filter narrows the list to what the user asked for, so hiding it behind
    // a closed group would defeat the search.
    if (_query.trim().isNotEmpty) return true;
    if (_expanded.contains(title)) return true;
    if (_collapsed.contains(title)) return false;
    return defaultExpanded;
  }

  void _toggleGroup(String title, {required bool nowExpanded}) {
    setState(() {
      if (nowExpanded) {
        _expanded.add(title);
        _collapsed.remove(title);
      } else {
        _collapsed.add(title);
        _expanded.remove(title);
      }
    });
  }

  bool _shows(ManualImportFacet facet) => !_hidden.contains(facet);

  void _toggleFacet(ManualImportFacet facet) {
    setState(() {
      if (!_hidden.remove(facet)) _hidden.add(facet);
    });
  }

  void _setAllGroups(List<String> titles, {required bool expanded}) {
    setState(() {
      _expanded.clear();
      _collapsed.clear();
      if (expanded) {
        _expanded.addAll(titles);
      } else {
        _collapsed.addAll(titles);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(manualImportFlowProvider);
    final folder = state.selectedFolder;
    final folderName = folder == null ? '…' : manualImportPathName(folder);

    return ManualImportFrame(
      service: widget.service,
      title: 'Review Files',
      subtitle: '${widget.service.title} · $folderName',
      actions: [
        IconButton(
          tooltip: state.allReadySelected
              ? 'Clear selection'
              : 'Select all ready files',
          icon: Icon(
            state.allReadySelected
                ? Icons.deselect_rounded
                : Icons.select_all_rounded,
          ),
          onPressed: state.readyItems.isEmpty || state.isLoadingItems
              ? null
              : () => ref
                    .read(manualImportFlowProvider.notifier)
                    .toggleAllReady(),
        ),
        // No "show what I already imported" toggle here any more: the scan
        // always reports those files and the count row filters them, so the one
        // control that changes what is on the list lives next to the list.
        IconButton(
          tooltip: 'Rescan folder',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: state.isLoadingItems
              ? null
              : () => ref
                    .read(manualImportFlowProvider.notifier)
                    .loadSelectedFolderItems(),
        ),
      ],
      bottomBar: _ReviewFooter(
        service: widget.service,
        targetId: widget.targetId,
      ),
      child: _buildBody(state),
    );
  }

  Widget _buildBody(ManualImportFlowState state) {
    final service = widget.service;

    if (state.isLoadingItems) {
      return _ScanningState(service: service, state: state);
    }

    if (state.error != null && state.items.isEmpty) {
      return AppEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Scan failed',
        message: state.error,
        accentColor: service.accent,
        action: FilledButton.tonalIcon(
          onPressed: () => ref
              .read(manualImportFlowProvider.notifier)
              .loadSelectedFolderItems(),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Scan again'),
        ),
      );
    }

    if (state.items.isEmpty) {
      return AppEmptyState(
        icon: Icons.movie_filter_outlined,
        title: 'No importable files',
        message:
            '${service.title} found nothing to import in this folder. '
            'Try another folder.',
        accentColor: service.accent,
        action: FilledButton.tonalIcon(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.folder_open_rounded, size: 18),
          label: const Text('Choose another folder'),
        ),
      );
    }

    final rows = _buildRows(state);

    return ListView.builder(
      // Lazy: a real downloads folder is hundreds of files, and building every
      // row up front is what made this list feel heavy to scroll.
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index].build(context),
    );
  }

  /// Flattens the whole screen into row descriptors so the list can stay lazy
  /// while still carrying headers, group headers and per-file rows.
  List<_ReviewRow> _buildRows(ManualImportFlowState state) {
    final service = widget.service;
    final query = _query;

    bool matches(ManualImportItem item) =>
        manualImportMatchesQuery(service, item, query);

    /// Everything of one facet that survives both filters — the chip row and
    /// the text field. A hidden facet contributes nothing at all, which is what
    /// keeps its section header from appearing above no rows.
    List<ManualImportItem> visible(
      List<ManualImportItem> items,
      ManualImportFacet facet,
    ) => _shows(facet)
        ? items.where(matches).toList(growable: false)
        : const <ManualImportItem>[];

    final attention = visible(
      state.attentionItems,
      ManualImportFacet.attention,
    );
    final ready = visible(state.readyItems, ManualImportFacet.ready);
    final other = visible(state.otherItems, ManualImportFacet.other);
    final imported = visible(state.importedItems, ManualImportFacet.imported);

    final rows = <_ReviewRow>[
      _WidgetRow(
        key: 'station',
        child: ImportStationBar(service: service, activeIndex: 1),
      ),
      _WidgetRow(
        key: 'facets',
        child: ManualImportFacetBar(
          counts: {
            ManualImportFacet.ready: state.readyItems.length,
            ManualImportFacet.attention: state.attentionItems.length,
            ManualImportFacet.imported: state.importedItems.length,
            ManualImportFacet.other: state.otherItems.length,
          },
          hidden: _hidden,
          onToggle: _toggleFacet,
        ),
      ),
    ];

    if (state.items.length > _filterThreshold) {
      rows.add(
        _WidgetRow(
          key: 'filter',
          child: _FilterField(
            controller: _filterController,
            service: service,
            total: state.items.length,
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
      );
    }

    if (state.error != null) {
      rows.add(
        _WidgetRow(
          key: 'error',
          child: _InlineError(error: state.error!),
        ),
      );
    }

    final visibleCount =
        attention.length + ready.length + other.length + imported.length;
    // The classified total, not `state.items.length`: files already handed to a
    // command are neither filterable nor countable by facet, and they get their
    // own section below, so counting them here would make the fraction lie.
    final totalCount =
        state.readyItems.length +
        state.attentionItems.length +
        state.otherItems.length +
        state.importedItems.length;

    if (visibleCount > 0 && visibleCount < totalCount) {
      rows.add(
        _WidgetRow(
          key: 'filter-status',
          child: _FilterStatus(
            visibleCount: visibleCount,
            totalCount: totalCount,
            // Offered only when it would actually change the selection, so it
            // never reads as a no-op button.
            onSelectOnly:
                ready.isEmpty ||
                    (state.selectedPaths.length == ready.length &&
                        ready.every(
                          (item) => state.selectedPaths.contains(item.path),
                        ))
                ? null
                : () => ref
                      .read(manualImportFlowProvider.notifier)
                      .selectOnly(ready),
            readyCount: ready.length,
          ),
        ),
      );
    }

    // Where the last batch went. Shown above everything else because it is the
    // answer to "did my import happen?", and because these rows are the reason
    // the files are missing from the lists below. Deliberately outside the
    // filter: a batch in flight is not a facet the user can switch off.
    final inFlight = state.inFlightItems.where(matches).toList(growable: false);
    final command = state.command;
    if (inFlight.isNotEmpty && command != null) {
      rows.addAll(_inFlightRows(command, inFlight));
    } else if (command != null && state.submittedItems.isNotEmpty) {
      // A finished import has moved its files out of the folder, so there are
      // no rows left to show — but the batch still happened, and the only way
      // back to its result would otherwise be gone with them.
      rows.add(
        _WidgetRow(
          key: 'last-import',
          child: _LastImportBanner(
            service: service,
            command: command,
            fileCount: state.submittedItems.length,
            onView: () => _openTrack(),
          ),
        ),
      );
    }

    // Nothing left to show, for one of two different reasons — and the recovery
    // differs, so the two are never collapsed into one "no results".
    if (visibleCount == 0 && totalCount > 0) {
      final searching = query.trim().isNotEmpty;
      rows.add(
        _WidgetRow(
          key: 'no-results',
          child: AppEmptyState.compact(
            icon: searching
                ? Icons.search_off_rounded
                : Icons.filter_alt_off_rounded,
            title: searching
                ? 'No files match "${query.trim()}"'
                : 'Every file is filtered out',
            message: searching
                ? 'Clear the filter to see all $totalCount files.'
                : 'The counts above are switched off. Tap one to bring those '
                      'files back.',
            accentColor: service.accent,
            action: searching
                ? null
                : FilledButton.tonalIcon(
                    onPressed: () => setState(_hidden.clear),
                    icon: const Icon(Icons.visibility_rounded, size: 18),
                    label: Text('Show all $totalCount files'),
                  ),
          ),
        ),
      );
      return rows;
    }

    if (attention.isNotEmpty) {
      rows.addAll(_attentionRows(state, attention));
    }
    if (ready.isNotEmpty || imported.isNotEmpty) {
      rows.addAll(_matchedRows(state, ready: ready, imported: imported));
    }
    if (other.isNotEmpty) {
      rows.add(
        _WidgetRow(
          key: 'other-header',
          child: SectionHeader(
            title: 'Other files',
            subtitle: _fileCount(
              other.length,
              'is not a kind ${service.title} imports',
              'are not a kind ${service.title} imports',
            ),
            showChevron: false,
          ),
        ),
      );
      for (final item in other) {
        rows.add(
          _WidgetRow(
            key: 'other-${item.path}',
            child: OtherFileRow(service: service, item: item),
          ),
        );
      }
    }

    return rows;
  }

  List<_ReviewRow> _attentionRows(
    ManualImportFlowState state,
    List<ManualImportItem> attention,
  ) {
    final service = widget.service;
    final picked = state.fixSelectionItems
        .where((item) => attention.contains(item))
        .toList(growable: false);
    // Radarr needs only a movie id, so one identity legitimately covers several
    // files. Sonarr and Lidarr need per-file episodes and tracks, which is what
    // the bulk sheet maps — and what makes assigning "everything at once"
    // meaningless there unless the user picked the files.
    final canAssignTogether = picked.length >= 2;

    // No collapse of its own any more. A folder can hold hundreds of unmatched
    // files and scrolling past all of them is not a review — but that is exactly
    // what the "need a match" chip does now, with the count still on screen.
    // Two controls for one job is how a section came to be hideable in a place
    // that never said what it was hiding.
    return [
      _WidgetRow(
        key: 'attention-header',
        child: SectionHeader.action(
          title: 'Needs attention',
          subtitle: _fileCount(
            attention.length,
            'needs a match',
            'need a match',
          ),
          trailing: canAssignTogether
              ? TextButton.icon(
                  onPressed: () => showManualImportBulkFixSheet(
                    context: context,
                    service: service,
                    items: picked,
                  ),
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                  label: Text('Assign ${picked.length}'),
                )
              : const SizedBox.shrink(),
        ),
      ),
      if (picked.length == 1)
        _WidgetRow(
          key: 'attention-hint',
          child: _AssignHint(
            onClear: () =>
                ref.read(manualImportFlowProvider.notifier).clearFixSelection(),
          ),
        ),
      for (final item in attention)
        _WidgetRow(
          key: 'attention-${item.path}',
          child: AttentionFileRow(
            service: service,
            item: item,
            picked: state.fixSelectionPaths.contains(item.path),
            onPickedChanged: (value) => ref
                .read(manualImportFlowProvider.notifier)
                .toggleFixSelection(item, value),
            onFix: () => showManualImportFixSheet(
              context: context,
              service: service,
              item: item,
            ),
          ),
        ),
    ];
  }

  /// Opens Track, then re-reads the folder on the way back.
  Future<void> _openTrack() async {
    await context.push(
      manualImportLocation(
        manualImportProgressPath,
        widget.service,
        targetId: widget.targetId,
      ),
    );
    if (!mounted) return;
    await ref.read(manualImportFlowProvider.notifier).refreshAfterImport();
  }

  /// The batch already handed to the service, and where to watch it.
  List<_ReviewRow> _inFlightRows(
    ManualImportCommandStatus command,
    List<ManualImportItem> inFlight,
  ) {
    final running = command.isActive;
    return [
      _WidgetRow(
        key: 'inflight-header',
        child: SectionHeader.action(
          title: running ? 'Importing now' : 'Sent to import',
          subtitle: _fileCount(
            inFlight.length,
            running
                ? 'is with ${widget.service.title}'
                : 'was sent to ${widget.service.title}',
            running
                ? 'are with ${widget.service.title}'
                : 'were sent to ${widget.service.title}',
          ),
          trailing: TextButton(
            // Same contract as the import button: coming back re-reads the
            // folder, so what the service did lands in the list.
            onPressed: _openTrack,
            child: const Text('View progress'),
          ),
        ),
      ),
      for (final item in inFlight)
        _WidgetRow(
          key: 'inflight-${item.path}',
          child: InFlightFileRow(
            service: widget.service,
            item: item,
            command: command,
          ),
        ),
    ];
  }

  /// Every file the service recognised, grouped by what it matched to.
  ///
  /// Ready files and already-imported ones share these groups on purpose. The
  /// imported ones used to sit in a collapsed section at the bottom of the
  /// screen, which answered "is it in the library?" only for someone who already
  /// suspected it was: the useful place for "S01E05 is already imported" is
  /// between S01E04 and S01E06, in the same group, in broadcast order — where
  /// the gap it explains actually is.
  List<_ReviewRow> _matchedRows(
    ManualImportFlowState state, {
    required List<ManualImportItem> ready,
    required List<ManualImportItem> imported,
  }) {
    final service = widget.service;

    // Group by matched media, alphabetically, each group in broadcast order.
    final groups = <String, List<ManualImportItem>>{};
    for (final item in [...ready, ...imported]) {
      groups
          .putIfAbsent(manualImportGroupTitle(service, item), () => [])
          .add(item);
    }
    final titles = groups.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    for (final title in titles) {
      groups[title]!.sort((a, b) {
        final aCode = manualImportIdentityFor(service, a).code ?? '';
        final bCode = manualImportIdentityFor(service, b).code ?? '';
        final byCode = aCode.compareTo(bCode);
        return byCode != 0 ? byCode : a.name.compareTo(b.name);
      });
    }

    final total = ready.length + imported.length;
    final defaultExpanded =
        total <= _autoCollapseThreshold || titles.length == 1;
    final anyCollapsed = titles.any(
      (title) => !_isGroupExpanded(title, defaultExpanded: defaultExpanded),
    );

    final readyTotal = state.readyItems.length;
    final importedTotal = state.importedItems.length;
    final reimportCount = state.selectedReimportItems.length;
    final selectedReady = state.selectedItems.length - reimportCount;

    final rows = <_ReviewRow>[
      _WidgetRow(
        key: 'matched-header',
        child: SectionHeader.action(
          title: 'Matched files',
          subtitle: [
            if (readyTotal > 0) '$selectedReady of $readyTotal selected',
            if (importedTotal > 0)
              reimportCount == 0
                  ? '$importedTotal already in the library'
                  : '$reimportCount of $importedTotal being re-imported',
          ].join(' · '),
          trailing: titles.length > 1
              ? TextButton(
                  onPressed: () =>
                      _setAllGroups(titles, expanded: anyCollapsed),
                  child: Text(anyCollapsed ? 'Expand all' : 'Collapse all'),
                )
              : const SizedBox.shrink(),
        ),
      ),
    ];

    for (final title in titles) {
      final group = groups[title]!;
      // A single file needs no header: its own checkbox already is the group's,
      // and a header per row would double the chrome of a movie library where
      // every group is one file.
      final hasHeader = group.length > 1;
      // The group's select-all reaches its importable files only; an imported
      // file joins the batch by its own tick, never by a sweep.
      final groupReady = group
          .where((item) => !item.isAlreadyImported)
          .toList(growable: false);
      final selectedCount = groupReady
          .where((item) => state.selectedPaths.contains(item.path))
          .length;
      final expanded =
          !hasHeader ||
          _isGroupExpanded(title, defaultExpanded: defaultExpanded);

      if (hasHeader) {
        rows.add(
          _WidgetRow(
            key: 'group-$title',
            child: ReadyGroupHeader(
              service: service,
              title: title,
              total: groupReady.length,
              importedCount: group.length - groupReady.length,
              selectedCount: selectedCount,
              expanded: expanded,
              onToggleExpanded: () =>
                  _toggleGroup(title, nowExpanded: !expanded),
              onSelectionChanged: (selected) => ref
                  .read(manualImportFlowProvider.notifier)
                  .setGroupSelected(groupReady, selected),
            ),
          ),
        );
      }

      if (!expanded) continue;

      for (final item in group) {
        final selected = state.selectedPaths.contains(item.path);
        void toggle(bool value) =>
            ref.read(manualImportFlowProvider.notifier).toggleItem(item, value);
        void openOptions() => _showAdjustSheet(context, ref, service, item);

        rows.add(
          _WidgetRow(
            key:
                '${item.isAlreadyImported ? 'imported' : 'ready'}-${item.path}',
            child: item.isAlreadyImported
                ? MatchedFileRow.imported(
                    service: service,
                    item: item,
                    groupTitle: title,
                    underGroupHeader: hasHeader,
                    selected: selected,
                    // An imported file whose payload no longer carries a usable
                    // identity cannot be sent anywhere, so it keeps the row and
                    // loses the tick rather than offering an import that would
                    // fail at the service.
                    onSelectedChanged: item.isReimportableFor(service)
                        ? toggle
                        : null,
                    onOpenOptions: openOptions,
                  )
                : MatchedFileRow.ready(
                    service: service,
                    item: item,
                    groupTitle: title,
                    underGroupHeader: hasHeader,
                    selected: selected,
                    onSelectedChanged: toggle,
                    onOpenOptions: openOptions,
                  ),
          ),
        );
      }
    }

    return rows;
  }

  String _fileCount(int count, String singular, String plural) =>
      count == 1 ? '$count file $singular' : '$count files $plural';
}

/// One built row in the flattened list.
abstract class _ReviewRow {
  String get key;
  Widget build(BuildContext context);
}

class _WidgetRow implements _ReviewRow {
  @override
  final String key;
  final Widget child;

  const _WidgetRow({required this.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}

/// Narrows a large scan to the files the user came for.
class _FilterField extends StatelessWidget {
  final TextEditingController controller;
  final ServiceKey service;
  final int total;
  final ValueChanged<String> onChanged;

  const _FilterField({
    required this.controller,
    required this.service,
    required this.total,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Filter $total files',
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Clear filter',
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

/// The outcome of the last batch, once its files have left the folder.
class _LastImportBanner extends StatelessWidget {
  final ServiceKey service;
  final ManualImportCommandStatus command;
  final int fileCount;
  final VoidCallback onView;

  const _LastImportBanner({
    required this.service,
    required this.command,
    required this.fileCount,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = manualImportCommandStatus(command);
    final tone = statusToneColor(theme.colorScheme, info.tone);
    final files = fileCount == 1 ? '1 file' : '$fileCount files';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: AppCard.filled(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        backgroundColor: tone.withValues(alpha: 0.08),
        onTap: onView,
        semanticLabel: 'Last import: ${info.label}, $files',
        semanticHint: 'opens the import progress',
        excludeChildSemantics: true,
        child: Row(
          children: [
            Icon(
              command.isActive
                  ? Icons.drive_file_move_rounded
                  : command.isFailure
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              size: 18,
              color: tone,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                command.isActive
                    ? '$files handed to ${service.title}'
                    : command.isFailure
                    ? 'Last import failed · $files'
                    : 'Imported $files',
                // Carries the handed-off file count, which climbs while the
                // command runs.
                style: theme.textTheme.bodySmall!
                    .weight(FontWeight.w600)
                    .tabular,
              ),
            ),
            Text(
              'View progress',
              style: theme.textTheme.labelMedium!
                  .weight(FontWeight.w700)
                  .copyWith(color: theme.colorScheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}

/// What a filter is hiding, and the shortcut to act on only what is left.
///
/// Without this the counts and the import button above and below a filtered
/// list describe the whole scan while the list describes a slice of it — true,
/// but easy to misread as "these are the files I am importing".
class _FilterStatus extends StatelessWidget {
  final int visibleCount;
  final int totalCount;
  final int readyCount;
  final VoidCallback? onSelectOnly;

  const _FilterStatus({
    required this.visibleCount,
    required this.totalCount,
    required this.readyCount,
    required this.onSelectOnly,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Showing $visibleCount of $totalCount files',
              // Both counts move as facet chips are toggled.
              style: theme.textTheme.bodySmall!.tabular.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (onSelectOnly != null && readyCount > 0)
            TextButton(
              onPressed: onSelectOnly,
              child: Text(
                readyCount == 1
                    ? 'Import only this'
                    : 'Import only these $readyCount',
              ),
            ),
        ],
      ),
    );
  }
}

/// Explains what a single tick is waiting for.
class _AssignHint extends StatelessWidget {
  final VoidCallback onClear;

  const _AssignHint({required this.onClear});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Tick another file of the same title to assign them together.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(onPressed: onClear, child: const Text('Clear')),
        ],
      ),
    );
  }
}

/// The scan is server-side and genuinely slow — minutes on big folders — so
/// the wait gets a legible shape: the message up front, skeleton rows below.
class _ScanningState extends StatelessWidget {
  final ServiceKey service;
  final ManualImportFlowState state;

  const _ScanningState({required this.service, required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final folder = state.selectedFolder;
    final folderName = folder == null
        ? 'this folder'
        : '"${manualImportPathName(folder)}"';

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        ImportStationBar(service: service, activeIndex: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: AppCard.filled(
            accentColor: service.accent,
            child: Semantics(
              container: true,
              liveRegion: true,
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: serviceThemeFor(service).softContainer,
                      borderRadius: AppRadius.borderRadiusSm,
                    ),
                    child: Icon(
                      Icons.radar_rounded,
                      size: 18,
                      color: service.accent,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${service.title} is scanning $folderName',
                          style: theme.textTheme.titleSmall!.weight(
                            FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Every file gets parsed and probed on the server — '
                          'large folders can take a few minutes.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: ExcludeSemantics(
            child: Column(
              children: [
                for (var index = 0; index < 6; index++) ...[
                  ShimmerPlaceholder.card(height: 72),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InlineError extends StatelessWidget {
  final String error;

  const _InlineError({required this.error});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = statusToneColor(theme.colorScheme, StatusTone.error);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: AppCard.filled(
        backgroundColor: tone.withValues(alpha: 0.1),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Semantics(
          container: true,
          liveRegion: true,
          child: Row(
            children: [
              Icon(Icons.error_outline_rounded, size: 18, color: tone),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  error,
                  style: theme.textTheme.bodySmall!.weight(FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewFooter extends ConsumerWidget {
  final ServiceKey service;
  final int? targetId;

  const _ReviewFooter({required this.service, this.targetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(manualImportFlowProvider);
    final count = state.selectedItems.length;
    final label = count == 0
        ? 'Nothing selected to import'
        : count == 1
        ? 'Import 1 file'
        : 'Import $count files';

    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.lg),
      child: Row(
        children: [
          _ImportModeMenu(service: service),
          Expanded(
            child: ImportPrimaryButton(
              service: service,
              icon: Icons.check_circle_outline_rounded,
              label: label,
              loading: state.isSubmitting,
              onPressed: !state.canImportSelected
                  ? null
                  : () async {
                      final notifier = ref.read(
                        manualImportFlowProvider.notifier,
                      );
                      final command = await notifier.confirmImport();
                      if (command == null || !context.mounted) return;
                      // Await the pop: coming back from Track re-reads the
                      // folder, so the list reflects what the service actually
                      // did with the files instead of the state we left behind.
                      await context.push(
                        manualImportLocation(
                          manualImportProgressPath,
                          service,
                          targetId: targetId,
                        ),
                      );
                      if (!context.mounted) return;
                      await notifier.refreshAfterImport();
                    },
            ),
          ),
        ],
      ),
    );
  }
}

/// Auto / Move / Copy — how the service should take the files.
class _ImportModeMenu extends ConsumerWidget {
  final ServiceKey service;

  const _ImportModeMenu({required this.service});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(manualImportFlowProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return MenuAnchor(
      builder: (context, controller, _) {
        return Semantics(
          button: true,
          label: 'Import mode',
          value: state.importMode.label,
          child: OutlinedButton.icon(
            onPressed: controller.isOpen ? controller.close : controller.open,
            style: OutlinedButton.styleFrom(
              foregroundColor: colorScheme.onSurface,
              side: BorderSide(color: colorScheme.outlineVariant),
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            ),
            icon: Icon(
              Icons.expand_more_rounded,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
            iconAlignment: IconAlignment.end,
            label: Text(state.importMode.label),
          ),
        );
      },
      menuChildren: [
        for (final mode in ManualImportMode.values)
          MenuItemButton(
            onPressed: () =>
                ref.read(manualImportFlowProvider.notifier).setImportMode(mode),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mode.label, style: theme.textTheme.labelLarge),
                Text(
                  mode.subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Per-file options for a matched file: quality, languages, or a new match.
Future<void> _showAdjustSheet(
  BuildContext context,
  WidgetRef ref,
  ServiceKey service,
  ManualImportItem item,
) {
  final identity = manualImportIdentityFor(service, item);
  return AppBottomSheet.show<void>(
    context: context,
    // Title is the matched identity — the series (or movie, or artist) plus the
    // positional code. Subtitle is the raw file, nothing else. Folding the
    // episode name and the filename into one subtitle line made the sheet's two
    // jobs — "what did this match" and "which file is this" — indistinguishable.
    title: [
      manualImportGroupTitle(service, item),
      if (identity.code != null) identity.code!,
    ].join(' · '),
    subtitle: item.fileName,
    icon: service.icon,
    accent: service.accent,
    bodyPadding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      0,
      AppSpacing.lg,
      AppSpacing.lg,
    ),
    builder: (sheetContext) => SettingsGroupCard(
      children: [
        SettingsCard.grouped(
          leading: const Icon(Icons.high_quality_rounded),
          title: 'Quality',
          subtitle: item.qualityLabel,
          accentColor: service.accent,
          semanticHint: 'opens the quality picker',
          onTap: () {
            Navigator.of(sheetContext).pop();
            _showQualityPicker(context, ref, service, item);
          },
        ),
        SettingsCard.grouped(
          leading: const Icon(Icons.translate_rounded),
          title: 'Languages',
          subtitle: item.languageLabel,
          accentColor: service.accent,
          semanticHint: 'opens the language picker',
          onTap: () {
            Navigator.of(sheetContext).pop();
            _showLanguagePicker(context, ref, service, item);
          },
        ),
        SettingsCard.grouped(
          leading: const Icon(Icons.swap_horiz_rounded),
          title: 'Change match',
          subtitle:
              'Assign a different '
              '${service.manualImportSubLabel.toLowerCase()} identity',
          accentColor: service.accent,
          semanticHint: 'opens match assignment',
          onTap: () {
            Navigator.of(sheetContext).pop();
            showManualImportFixSheet(
              context: context,
              service: service,
              item: item,
            );
          },
        ),
      ],
    ),
  );
}

Future<void> _showQualityPicker(
  BuildContext context,
  WidgetRef ref,
  ServiceKey service,
  ManualImportItem item,
) async {
  final options = await ref
      .read(manualImportFlowProvider.notifier)
      .getQualityOptions();
  if (!context.mounted) return;

  await AppBottomSheet.show<void>(
    context: context,
    title: 'Select quality',
    icon: Icons.high_quality_rounded,
    accent: service.accent,
    builder: (sheetContext) {
      if (options.isEmpty) {
        return const AppEmptyState.compact(
          icon: Icons.high_quality_rounded,
          title: 'No quality options available',
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in options)
            ImportChoiceRow(
              label: option.name,
              selected: option.id == item.qualityId,
              accent: service.accent,
              onSelected: () async {
                Navigator.of(sheetContext).pop();
                await ref
                    .read(manualImportFlowProvider.notifier)
                    .updateItemMetadata(item, quality: option);
              },
            ),
        ],
      );
    },
  );
}

Future<void> _showLanguagePicker(
  BuildContext context,
  WidgetRef ref,
  ServiceKey service,
  ManualImportItem item,
) async {
  final options = await ref
      .read(manualImportFlowProvider.notifier)
      .getLanguageOptions();
  if (!context.mounted) return;

  final selectedIds = item.languageIds.toSet();

  await AppBottomSheet.show<void>(
    context: context,
    title: 'Select languages',
    icon: Icons.translate_rounded,
    accent: service.accent,
    builder: (sheetContext) {
      if (options.isEmpty) {
        return const AppEmptyState.compact(
          icon: Icons.translate_rounded,
          title: 'No language options available',
        );
      }
      return StatefulBuilder(
        builder: (context, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in options)
              CheckboxListTile(
                value: selectedIds.contains(option.id),
                activeColor: service.accent,
                checkColor: ServiceTheme.foregroundOn(service.accent),
                title: Text(option.name),
                onChanged: (selected) {
                  setState(() {
                    if (selected == true) {
                      selectedIds.add(option.id);
                    } else {
                      selectedIds.remove(option.id);
                    }
                  });
                },
              ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () async {
                final selected = options
                    .where((option) => selectedIds.contains(option.id))
                    .toList(growable: false);
                Navigator.of(sheetContext).pop();
                await ref
                    .read(manualImportFlowProvider.notifier)
                    .updateItemMetadata(item, languages: selected);
              },
              style: FilledButton.styleFrom(
                backgroundColor: service.accent,
                foregroundColor: ServiceTheme.foregroundOn(service.accent),
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Apply languages'),
            ),
          ],
        ),
      );
    },
  );
}
