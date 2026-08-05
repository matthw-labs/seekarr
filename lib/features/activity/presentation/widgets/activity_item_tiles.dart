import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/service_theme.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/arr_activity_display.dart';
import 'package:seekarr/core/utils/dynamic_map_utils.dart' as dynamic_utils;
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/media_search_popup_menu.dart';
import 'package:seekarr/core/widgets/status_badge.dart';
import 'package:seekarr/core/widgets/tag_chip.dart';
import 'package:seekarr/features/activity/presentation/activity_provider.dart';
import 'package:seekarr/features/activity/presentation/activity_screen.dart';
import 'package:seekarr/features/activity/presentation/widgets/activity_actions.dart';
import 'package:seekarr/features/activity/presentation/widgets/activity_formatters.dart';
import 'package:seekarr/features/activity/presentation/widgets/activity_tab_helpers.dart';
import 'package:seekarr/features/activity/presentation/widgets/detail_sheets.dart';
import 'package:seekarr/features/discover/domain/models/seerr_request.dart';
import 'package:seekarr/features/import/presentation/manual_import_routes.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

class QueueItemTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final ServiceType serviceType;

  const QueueItemTile({
    super.key,
    required this.item,
    required this.serviceType,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final resolvedStatus = resolveQueueDisplayStatus(item);
    final title = _queueTitle(item, serviceType);
    final subtitle = _queueSubtitle(item, serviceType);
    final progress = dynamic_utils.queueProgress(
      item,
      parseStrings: false,
      includeSizeLeftAlias: false,
    );
    final chips = _buildQueueChips(item, colorScheme);
    // Gated on the status vocabulary rather than on `downloading` alone, so a
    // stalled transfer keeps its bar: "stuck at 43%" is how the user decides
    // between waiting and blocklisting, and the bar is tinted by tone, so it
    // reads as a frozen amber rather than as healthy progress.
    final showInlineProgress = progress != null && resolvedStatus.showsProgress;
    final toneColor = statusToneColor(colorScheme, resolvedStatus.tone);

    return _TileShell(
      onTap: () => DetailSheets.showQueueDetail(context, item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.weight(
                        FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) _SubtitleText(text: subtitle),
                    const SizedBox(height: AppSpacing.sm),
                    // The badge carries the label, the state icon and the
                    // percentage in tabular figures — the percentage used to be
                    // concatenated into a subtitle string, so it re-flowed the
                    // line every time it ticked.
                    StatusBadge(info: resolvedStatus),
                    if (resolvedStatus.detail != null)
                      _SubtitleText(
                        text: resolvedStatus.detail!,
                        color: toneColor,
                      ),
                    if (showInlineProgress)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: SizedBox(
                          width: 96,
                          child: ClipRRect(
                            borderRadius: AppRadius.borderRadiusFull,
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 6,
                              color: toneColor,
                              backgroundColor:
                                  colorScheme.surfaceContainerHighest,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          _ChipRow(chips: chips),
        ],
      ),
    );
  }
}

class HistoryItemTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final ServiceType serviceType;

  const HistoryItemTile({
    super.key,
    required this.item,
    required this.serviceType,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title = _historyTitle(item, serviceType);
    final subtitle = _historySubtitle(item, serviceType);
    final metadata = joinActivityParts([
      formatDateOnly(stringOrNull(item['date'])),
      _historySizeLabel(item),
    ]);
    final episodeCode = serviceType == ServiceType.series
        ? _historyEpisodeCode(item)
        : null;
    final chips = _buildHistoryChips(item, colorScheme);

    return _TileShell(
      onTap: () => DetailSheets.showHistoryDetail(context, item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (episodeCode != null)
                      TagChip(
                        text: episodeCode,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.weight(
                        FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Same resolver and same renderer as the global feed. These were
              // two independent switches before, and they disagreed: a
              // `downloadFailed` event was red here and green there.
              StatusBadge(info: resolveHistoryStatus(item)),
            ],
          ),
          if (subtitle != null) _SubtitleText(text: subtitle),
          if (metadata.isNotEmpty)
            _SubtitleText(text: metadata, topSpacing: AppSpacing.sm),
          _ChipRow(chips: chips),
        ],
      ),
    );
  }
}

class BlocklistItemTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final ServiceType serviceType;

  const BlocklistItemTile({
    super.key,
    required this.item,
    required this.serviceType,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final subtitle = _blocklistSubtitle(item, serviceType);
    final chips = _buildBlocklistChips(item, colorScheme);
    final status = resolveBlocklistStatus(item);
    final reason = status.detail;

    return _TileShell(
      onTap: () => DetailSheets.showBlocklistDetail(context, item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TitleRow(
            title: _blocklistTitle(item, serviceType),
            titleStyle: theme.textTheme.titleSmall?.weight(FontWeight.w700),
            trailing: StatusBadge(info: status),
          ),
          if (subtitle != null) _SubtitleText(text: subtitle),
          _ChipRow(chips: chips),
          if (reason != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              reason,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            formatRelativeActivityDate(stringOrNull(item['date'])),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class WantedItemTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final ServiceType serviceType;
  final VoidCallback? onAutoSearch;
  final VoidCallback? onInteractiveSearch;
  final bool isCutoff;
  final String? qualityProfileName;

  const WantedItemTile({
    super.key,
    required this.item,
    required this.serviceType,
    this.onAutoSearch,
    this.onInteractiveSearch,
    this.isCutoff = false,
    this.qualityProfileName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title = _wantedTitle(item, serviceType);
    final subtitle = isCutoff && serviceType == ServiceType.movies
        ? null
        : _wantedSubtitle(item, serviceType);
    final statusText = isCutoff
        ? formatCutoffSize(item, serviceType)
        : wantedStatusText(item, serviceType);
    final chips = _buildWantedChips(
      item,
      serviceType,
      colorScheme,
      isCutoff: isCutoff,
      qualityProfileName: qualityProfileName,
    );
    final canSearch = onAutoSearch != null && onInteractiveSearch != null;

    return _TileShell(
      onTap: () => DetailSheets.showWantedDetail(context, item, serviceType),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TitleRow(
            title: title,
            titleStyle: theme.textTheme.titleSmall?.weight(FontWeight.w700),
            maxLines: isCutoff ? 1 : null,
            trailing: canSearch
                ? MediaSearchPopupMenu(
                    onAutoSearch: onAutoSearch!,
                    onInteractiveSearch: onInteractiveSearch!,
                    iconSize: 18,
                  )
                : null,
          ),
          if (subtitle != null) _SubtitleText(text: subtitle),
          if (statusText != null)
            _SubtitleText(text: statusText, color: colorScheme.error),
          _ChipRow(chips: chips),
        ],
      ),
    );
  }
}

class GlobalActivityItemTile extends ConsumerWidget {
  final GlobalActivityItem item;

  const GlobalActivityItemTile({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = item.service.accent;
    final raw = item.raw;
    // One colour for the whole row's state — badge, warning text and progress
    // bar all read from the resolved tone rather than from the row's category.
    final toneColor = statusToneColor(colorScheme, item.status.tone);
    final canSearch =
        raw != null &&
        (item.kind == GlobalActivityKind.missing ||
            item.kind == GlobalActivityKind.cutoff) &&
        extractWantedItemId(item.serviceType, raw) != null;
    final icon = switch (item.kind) {
      GlobalActivityKind.request => Icons.person_add_alt_1_rounded,
      GlobalActivityKind.queue => Icons.downloading_rounded,
      GlobalActivityKind.history => Icons.history_rounded,
      GlobalActivityKind.blocklist => Icons.block_rounded,
      GlobalActivityKind.missing => Icons.warning_amber_rounded,
      GlobalActivityKind.cutoff => Icons.trending_up_rounded,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: AppCard.outlined(
        // Request rows used to be styled exactly like every other card and then
        // swallow the tap — `raw` is never set for them, so `onTap` resolved to
        // null while the affordance stayed. They now go where requests are
        // actually managed instead of promising a detail that does not exist.
        //
        // `push`, emphatically not `go`. `/activity/:type` is a root-navigator
        // route *outside* the ShellRoute, so it carries no bottom nav bar of its
        // own — and `go` replaces the stack rather than pushing onto it, so
        // `Navigator.canPop()` was false and the app bar had no back entry to
        // imply a leading button from. The result was a dead end: no nav bar, no
        // back, nothing but the requests list. `push` keeps the return path.
        onTap: switch (item.kind) {
          GlobalActivityKind.request => () => context.push(
            '/activity/${ServiceType.discover.name}',
          ),
          _ => item.raw == null ? null : () => _showDetails(context, ref),
        },
        backgroundColor: colorScheme.surfaceContainer,
        borderColor: colorScheme.outlineVariant,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 56,
              decoration: BoxDecoration(
                color: ServiceTheme.fromAccent(accent).softContainer,
                borderRadius: AppRadius.borderRadiusSm,
              ),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.weight(FontWeight.w700),
                  ),
                  if (item.subtitle.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      item.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // The resolved status, rendered by the shared badge. The
                      // service is deliberately no longer a chip here: when the
                      // feed is grouped its section header already names the
                      // service, and when it is filtered the user chose it — so
                      // the chip was restating known information on every row,
                      // in the same 11pt weight as the status it competed with.
                      // The accent-tinted icon well still carries the identity.
                      StatusBadge(info: item.status),
                      // When each event happened. `sortDate` was already being
                      // parsed to order the feed but never shown, which left the
                      // History list unable to answer its own question — several
                      // rows for one title, no way to tell which came first.
                      // Plain text rather than a pill: it is context, not
                      // another label to scan.
                      if (item.sortDate != null)
                        Text(
                          formatRelativeDateTime(item.sortDate!),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                  // The service's own explanation of a problem. It was already
                  // being fetched and then thrown away behind a bare "Warning"
                  // chip, so the row announced that something was wrong while
                  // withholding what.
                  if (item.detail != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      item.detail!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: toneColor),
                    ),
                  ],
                  if (item.progress != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    ClipRRect(
                      borderRadius: AppRadius.borderRadiusFull,
                      child: LinearProgressIndicator(
                        value: item.progress,
                        minHeight: 4,
                        // Tone, not the service accent: a failed transfer's bar
                        // has to read red. Colouring it by service meant a
                        // stalled download and a healthy one were chromatically
                        // identical.
                        color: toneColor,
                        backgroundColor: colorScheme.outlineVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // No trailing percentage: StatusBadge already prints it, with
            // tabular figures, right next to the label it belongs to. Two
            // copies of one number on one row is how the old layout ended up
            // with four things at 11pt competing for the same glance.
            if (raw != null && canSearch) ...[
              const SizedBox(width: AppSpacing.xs),
              MediaSearchPopupMenu(
                onAutoSearch: () => _runAutoSearch(context, ref, raw),
                onInteractiveSearch: () =>
                    _showInteractiveSearch(context, ref, raw),
                iconSize: 18,
              ),
            ] else if (_writeActions.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.xs),
              _RowActionsMenu(item: item, actions: _writeActions),
            ],
          ],
        ),
      ),
    );
  }

  /// The write actions this row supports.
  ///
  /// Empty for history (nothing to change about something that happened) and
  /// whenever the record has no id to act on.
  List<_RowAction> get _writeActions {
    // Requests are checked before the `recordId` guard, not after: they are the
    // one kind that carries no \*arr record at all, so that guard would drop them
    // before they were ever considered.
    if (item.kind == GlobalActivityKind.request) {
      final request = item.request;
      // Gate on the request's **own** status, never on `displayStatus`. That
      // getter is overridden by media availability, so a request that is still
      // waiting for approval reports "Available" the moment the media exists
      // anywhere — and would silently lose the only action it needs.
      if (request == null || request.status != RequestStatus.pendingApproval) {
        return const [];
      }
      return const [_RowAction.approveRequest, _RowAction.declineRequest];
    }

    if (item.recordId == null) return const [];
    if (!item.serviceType.supportsArrActivity) return const [];
    return switch (item.kind) {
      GlobalActivityKind.queue => [
        // The rescue fast-path: a stuck download's row can jump straight into
        // manual import with the download's own output folder pre-seeded.
        if (item.service.supportsManualImport && _manualImportFolder != null)
          _RowAction.manualImport,
        _RowAction.blocklistAndRetry,
        _RowAction.removeFromQueue,
      ],
      GlobalActivityKind.blocklist => const [_RowAction.removeFromBlocklist],
      _ => const [],
    };
  }

  String? get _manualImportFolder => manualImportFolderFromOutputPath(
    dynamic_utils.stringOrNull(item.raw?['outputPath']),
  );

  void _showDetails(BuildContext context, WidgetRef ref) {
    final raw = item.raw;
    if (raw == null) return;
    switch (item.kind) {
      case GlobalActivityKind.queue:
        DetailSheets.showQueueDetail(
          context,
          raw,
          actions: _writeActions.isEmpty
              ? null
              : _SheetActions(item: item, actions: _writeActions),
        );
        break;
      case GlobalActivityKind.history:
        DetailSheets.showHistoryDetail(context, raw);
        break;
      case GlobalActivityKind.blocklist:
        DetailSheets.showBlocklistDetail(context, raw);
        break;
      case GlobalActivityKind.missing:
      case GlobalActivityKind.cutoff:
        DetailSheets.showWantedDetail(context, raw, item.serviceType);
        break;
      case GlobalActivityKind.request:
        break;
    }
  }

  void _runAutoSearch(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> raw,
  ) {
    runWantedAutoSearch(
      context,
      ref.read(resolvedArrServiceProvider(item.serviceType)),
      item.serviceType,
      raw,
    );
  }

  void _showInteractiveSearch(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> raw,
  ) {
    showWantedInteractiveSearch(
      context,
      ref.read(resolvedArrServiceProvider(item.serviceType)),
      item.serviceType,
      raw,
      // The subject alone: the sheet's own heading already says "Releases", and
      // `showWantedInteractiveSearch` caps whatever it is handed.
      title: item.title,
    );
  }
}

/// A write action available on an Activity row.
enum _RowAction {
  approveRequest(
    'Approve request',
    Icons.check_circle_outline_rounded,
    destructive: false,
  ),
  declineRequest('Decline request', Icons.cancel_outlined, destructive: true),
  manualImport(
    'Manual import',
    Icons.drive_file_move_rounded,
    destructive: false,
  ),
  blocklistAndRetry(
    'Blocklist and retry',
    Icons.refresh_rounded,
    destructive: false,
  ),
  removeFromQueue(
    'Remove from queue',
    Icons.delete_outline_rounded,
    destructive: true,
  ),
  removeFromBlocklist(
    'Remove from blocklist',
    Icons.playlist_add_check_rounded,
    destructive: false,
  );

  const _RowAction(this.label, this.icon, {required this.destructive});

  final String label;
  final IconData icon;
  final bool destructive;
}

/// The same actions as buttons, for the detail sheet.
///
/// A row can only afford an overflow glyph; a sheet the user deliberately opened
/// on a stalled download can afford to name the actions outright.
class _SheetActions extends ConsumerWidget {
  final GlobalActivityItem item;
  final List<_RowAction> actions;

  const _SheetActions({required this.item, required this.actions});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final menu = _RowActionsMenu(item: item, actions: actions);

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final action in actions)
          action.destructive
              ? OutlinedButton.icon(
                  onPressed: () {
                    // Close the sheet first: the confirmation dialog is the
                    // thing that should hold focus, and leaving the sheet up
                    // behind it stacks two modals over the row being removed.
                    Navigator.of(context).pop();
                    menu._run(context, ref, action);
                  },
                  icon: Icon(action.icon, size: 18),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.error,
                    side: BorderSide(
                      color: colorScheme.error.withValues(alpha: 0.5),
                    ),
                  ),
                  label: Text(action.label),
                )
              : FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    menu._run(context, ref, action);
                  },
                  icon: Icon(action.icon, size: 18),
                  label: Text(action.label),
                ),
      ],
    );
  }
}

/// The per-row action menu — the thing that turns Activity from a feed into
/// something you can operate.
class _RowActionsMenu extends ConsumerWidget {
  final GlobalActivityItem item;
  final List<_RowAction> actions;

  const _RowActionsMenu({required this.item, required this.actions});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuButton<_RowAction>(
      tooltip: 'Actions for ${item.title}',
      icon: Icon(
        Icons.more_vert_rounded,
        size: 18,
        color: colorScheme.onSurfaceVariant,
      ),
      onSelected: (action) => _run(context, ref, action),
      itemBuilder: (context) => [
        for (final action in actions)
          PopupMenuItem<_RowAction>(
            value: action,
            child: Row(
              children: [
                Icon(
                  action.icon,
                  size: 18,
                  color: action.destructive
                      ? colorScheme.error
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  action.label,
                  // Recoloured from the ambient row style, not built from
                  // scratch: a bare `TextStyle(color:)` only happened to keep
                  // the family and size because `Text` merges an inheriting
                  // style, which makes the base invisible at the call site.
                  style: action.destructive
                      ? DefaultTextStyle.of(
                          context,
                        ).style.copyWith(color: colorScheme.error)
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Each case reads the key it actually needs.
  ///
  /// There used to be one `recordId == null` guard covering the whole method,
  /// which quietly made every action \*arr-shaped: a Seerr request is keyed by its
  /// own id and has no \*arr record, so it could never have reached the switch.
  void _run(BuildContext context, WidgetRef ref, _RowAction action) {
    switch (action) {
      case _RowAction.approveRequest:
        final requestId = item.request?.id;
        if (requestId == null) return;
        ActivityActions.approveRequest(
          context,
          ref,
          requestId: requestId,
          title: item.title,
        );
      case _RowAction.declineRequest:
        final requestId = item.request?.id;
        if (requestId == null) return;
        ActivityActions.declineRequest(
          context,
          ref,
          requestId: requestId,
          title: item.title,
        );
      case _RowAction.manualImport:
        final folder = manualImportFolderFromOutputPath(
          dynamic_utils.stringOrNull(item.raw?['outputPath']),
        );
        if (folder == null || !item.service.supportsManualImport) return;
        context.push(
          manualImportLocation(
            manualImportBrowsePath,
            item.service,
            folderPath: folder,
          ),
        );
      case _RowAction.blocklistAndRetry:
        final recordId = item.recordId;
        if (recordId == null) return;
        ActivityActions.blocklistAndRetry(
          context,
          ref,
          serviceType: item.serviceType,
          recordId: recordId,
          title: item.title,
        );
      case _RowAction.removeFromQueue:
        final recordId = item.recordId;
        if (recordId == null) return;
        ActivityActions.removeFromQueue(
          context,
          ref,
          serviceType: item.serviceType,
          recordId: recordId,
          title: item.title,
        );
      case _RowAction.removeFromBlocklist:
        final recordId = item.recordId;
        if (recordId == null) return;
        ActivityActions.removeFromBlocklist(
          context,
          ref,
          serviceType: item.serviceType,
          recordId: recordId,
          title: item.title,
        );
    }
  }
}

class _TileShell extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;

  const _TileShell({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // One card rhythm for the whole feature. This used to be `sm` top *and*
      // bottom — 16pt between cards — while `GlobalActivityItemTile` used 0/`sm`
      // for 8pt, so the same conceptual row had two different densities
      // depending on which screen you opened. 8pt is the denser of the two,
      // which is the right call for an operational list.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: AppCard.outlined(
        onTap: onTap,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        borderColor: Theme.of(context).colorScheme.outlineVariant,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: child,
      ),
    );
  }
}

class _SubtitleText extends StatelessWidget {
  final String text;
  final Color? color;
  final double topSpacing;

  const _SubtitleText({
    required this.text,
    this.color,
    this.topSpacing = AppSpacing.xs,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: topSpacing),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: color ?? colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ChipRow extends StatelessWidget {
  final List<Widget> chips;

  const _ChipRow({required this.chips});

  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: chips,
        ),
      ],
    );
  }
}

class _TitleRow extends StatelessWidget {
  final String title;
  final TextStyle? titleStyle;
  final Widget? trailing;
  final int? maxLines;

  const _TitleRow({
    required this.title,
    this.titleStyle,
    this.trailing,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            title,
            style: titleStyle,
            maxLines: maxLines,
            overflow: maxLines == null ? null : TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.sm),
          trailing!,
        ],
      ],
    );
  }
}

List<Widget> _buildQueueChips(
  Map<String, dynamic> item,
  ColorScheme colorScheme,
) {
  final quality = extractQualityName(item);
  final protocol = stringOrNull(item['protocol']);
  final downloadClient = stringOrNull(item['downloadClient']);
  final hasWarning = arrQueueHasWarning(item);

  return [
    if (hasWarning)
      TagChip(
        text: 'Warning',
        color: colorScheme.error,
        icon: Icons.warning_amber_rounded,
      ),
    if (quality != null) TagChip(text: quality),
    if (protocol != null) TagChip(text: protocol, color: AppColors.info),
    if (downloadClient != null)
      TagChip(text: downloadClient, color: colorScheme.tertiary),
  ];
}

List<Widget> _buildHistoryChips(
  Map<String, dynamic> item,
  ColorScheme colorScheme,
) {
  final quality = extractQualityName(item);
  final indexer = stringOrNull(asActivityMap(item['data'])?['indexer']);

  return [
    if (quality != null) TagChip(text: quality),
    if (indexer != null) TagChip(text: indexer, color: colorScheme.tertiary),
  ];
}

List<Widget> _buildBlocklistChips(
  Map<String, dynamic> item,
  ColorScheme colorScheme,
) {
  final protocol = stringOrNull(item['protocol']);
  final indexer = stringOrNull(item['indexer']);

  return [
    if (protocol != null) TagChip(text: protocol, color: AppColors.info),
    if (indexer != null) TagChip(text: indexer, color: colorScheme.tertiary),
  ];
}

List<Widget> _buildWantedChips(
  Map<String, dynamic> item,
  ServiceType serviceType,
  ColorScheme colorScheme, {
  bool isCutoff = false,
  String? qualityProfileName,
}) {
  final monitored = item['monitored'] == false
      ? TagChip(text: 'Unmonitored', color: colorScheme.error)
      : null;
  final quality = switch (serviceType) {
    ServiceType.movies =>
      qualityProfileName ??
          extractQualityName(item, fileKey: 'movieFile') ??
          extractQualityName(item),
    ServiceType.music =>
      extractQualityName(item, fileKey: 'albumFile') ??
          extractQualityName(item),
    _ => extractQualityName(item),
  };
  final date = switch (serviceType) {
    ServiceType.movies => stringOrNull(
      item['airDateUtc'] ?? item['digitalRelease'] ?? item['inCinemas'],
    ),
    ServiceType.music => stringOrNull(item['releaseDate']),
    _ => stringOrNull(item['airDateUtc']),
  };
  final showDateChip = !(isCutoff && serviceType == ServiceType.movies);

  return [
    if (monitored != null) monitored,
    if (quality != null) TagChip(text: quality),
    if (showDateChip && date != null)
      TagChip(text: formatIsoDate(date), color: AppColors.info),
  ];
}

String _historyTitle(Map<String, dynamic> item, ServiceType serviceType) {
  return arrPrimaryMediaTitle(item, includeMovieYear: true) ??
      stringOrNull(item['sourceTitle']) ??
      'Unknown release';
}

String? _historyEpisodeCode(Map<String, dynamic> item) {
  final episode = asActivityMap(item['episode']);
  return formatEpisodeCode(
    intOrNull(episode?['seasonNumber'] ?? item['seasonNumber']),
    intOrNull(episode?['episodeNumber'] ?? item['episodeNumber']),
  );
}

String? _historySizeLabel(Map<String, dynamic> item) {
  final size = formatSizeInGb(
    asActivityMap(item['data'])?['size'] ?? item['size'],
  );
  return size == '—' ? null : size;
}

String _queueTitle(Map<String, dynamic> item, ServiceType serviceType) {
  return switch (serviceType) {
    ServiceType.movies =>
      arrPrimaryMediaTitle(item, includeMovieYear: true) ??
          arrReleaseTitle(item) ??
          'Unknown release',
    ServiceType.series || ServiceType.music =>
      arrPrimaryMediaTitle(item) ?? arrReleaseTitle(item) ?? 'Unknown release',
    ServiceType.discover => arrReleaseTitle(item) ?? 'Unknown release',
  };
}

String? _queueSubtitle(Map<String, dynamic> item, ServiceType serviceType) {
  final release = arrReleaseTitle(item);
  final title = _queueTitle(item, serviceType);
  final uniqueRelease = release == title ? null : release;

  return switch (serviceType) {
    ServiceType.series => _joinSecondaryParts([
      arrEpisodeCode(item),
      arrEpisodeTitle(item),
      uniqueRelease,
    ]),
    ServiceType.movies => _joinSecondaryParts([uniqueRelease]),
    ServiceType.music => _joinSecondaryParts([
      arrArtistName(item),
      uniqueRelease,
    ]),
    ServiceType.discover => null,
  };
}

String? _historySubtitle(Map<String, dynamic> item, ServiceType serviceType) {
  final release = stringOrNull(item['sourceTitle']);
  final title = _historyTitle(item, serviceType);
  final uniqueRelease = release == title ? null : release;

  return switch (serviceType) {
    ServiceType.series => _joinSecondaryParts([
      arrEpisodeCode(item),
      arrEpisodeTitle(item),
      uniqueRelease,
    ]),
    ServiceType.movies => _joinSecondaryParts([uniqueRelease]),
    ServiceType.music => _joinSecondaryParts([
      arrArtistName(item),
      uniqueRelease,
    ]),
    ServiceType.discover => null,
  };
}

String _blocklistTitle(Map<String, dynamic> item, ServiceType serviceType) {
  return switch (serviceType) {
    ServiceType.movies =>
      arrPrimaryMediaTitle(item, includeMovieYear: true) ??
          stringOrNull(item['sourceTitle']) ??
          'Unknown release',
    ServiceType.series || ServiceType.music =>
      arrPrimaryMediaTitle(item) ??
          stringOrNull(item['sourceTitle']) ??
          'Unknown release',
    ServiceType.discover =>
      stringOrNull(item['sourceTitle']) ?? 'Unknown release',
  };
}

String? _blocklistSubtitle(Map<String, dynamic> item, ServiceType serviceType) {
  final release = stringOrNull(item['sourceTitle']);
  final title = _blocklistTitle(item, serviceType);
  final uniqueRelease = release == title ? null : release;

  return switch (serviceType) {
    ServiceType.series => _joinSecondaryParts([
      arrEpisodeCode(item),
      arrEpisodeTitle(item),
      uniqueRelease,
    ]),
    ServiceType.movies => _joinSecondaryParts([uniqueRelease]),
    ServiceType.music => _joinSecondaryParts([
      arrArtistName(item),
      uniqueRelease,
    ]),
    ServiceType.discover => null,
  };
}

String? _joinSecondaryParts(List<String?> parts) {
  final line = joinDisplayParts(parts);
  return line.isEmpty ? null : line;
}

String _wantedTitle(Map<String, dynamic> item, ServiceType serviceType) {
  switch (serviceType) {
    case ServiceType.movies:
      final title = stringOrNull(item['title']) ?? 'Unknown movie';
      final year = intOrNull(item['year']);
      return year == null ? title : '$title ($year)';
    case ServiceType.music:
      return stringOrNull(item['title']) ?? 'Unknown release';
    case ServiceType.series:
      final episodeCode = formatEpisodeCode(
        intOrNull(item['seasonNumber']),
        intOrNull(item['episodeNumber']),
      );
      final title = joinActivityParts([
        episodeCode,
        stringOrNull(item['title']),
      ]);
      return title.isEmpty ? 'Unknown Episode' : title;
    case ServiceType.discover:
      return stringOrNull(item['title']) ?? 'Unknown';
  }
}

String? _wantedSubtitle(Map<String, dynamic> item, ServiceType serviceType) {
  switch (serviceType) {
    case ServiceType.movies:
      final date = stringOrNull(
        item['airDateUtc'] ?? item['digitalRelease'] ?? item['inCinemas'],
      );
      return date == null ? null : 'Release ${formatIsoDate(date)}';
    case ServiceType.music:
      return stringOrNull(asActivityMap(item['artist'])?['artistName']);
    case ServiceType.series:
      return stringOrNull(asActivityMap(item['series'])?['title']) ??
          'Unknown Series';
    case ServiceType.discover:
      return null;
  }
}
