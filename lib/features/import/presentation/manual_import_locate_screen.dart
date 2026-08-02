import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_animation.dart';
import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/service_theme.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/import/domain/manual_import_models.dart';
import 'package:seekarr/features/import/presentation/manual_import_provider.dart';
import 'package:seekarr/features/import/presentation/manual_import_routes.dart';
import 'package:seekarr/features/import/presentation/manual_import_widgets.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// Station 1 — Locate: walk the server's filesystem to the folder that holds
/// the files, then hand it to Review for the scan.
class ManualImportLocateScreen extends ConsumerStatefulWidget {
  final ServiceKey service;
  final int? targetId;

  /// Pre-seeded folder, e.g. a failed download's output path from Activity.
  final String? initialPath;

  const ManualImportLocateScreen({
    super.key,
    required this.service,
    this.targetId,
    this.initialPath,
  });

  @override
  ConsumerState<ManualImportLocateScreen> createState() =>
      _ManualImportLocateScreenState();
}

class _ManualImportLocateScreenState
    extends ConsumerState<ManualImportLocateScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(_start);
  }

  @override
  void didUpdateWidget(covariant ManualImportLocateScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service ||
        oldWidget.targetId != widget.targetId ||
        oldWidget.initialPath != widget.initialPath) {
      Future.microtask(() => _start(force: true));
    }
  }

  void _start({bool force = false}) {
    ref
        .read(manualImportFlowProvider.notifier)
        .start(
          widget.service,
          targetId: widget.targetId,
          force: force,
          initialPath: widget.initialPath,
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(manualImportFlowProvider);
    final selectedFolder = state.selectedFolder;

    return ManualImportFrame(
      service: widget.service,
      title: 'Manual Import',
      subtitle: '${widget.service.title} · Choose a folder to scan',
      bottomBar: ImportPrimaryButton(
        service: widget.service,
        icon: Icons.radar_rounded,
        label: selectedFolder == null
            ? 'Choose a folder'
            : 'Scan "${manualImportPathName(selectedFolder)}"',
        onPressed: selectedFolder == null
            ? null
            : () => context.push(
                manualImportLocation(
                  manualImportReviewPath,
                  widget.service,
                  targetId: widget.targetId,
                ),
              ),
      ),
      child: _LocateBody(
        service: widget.service,
        state: state,
        onRetry: () => _start(force: true),
      ),
    );
  }
}

class _LocateBody extends ConsumerWidget {
  final ServiceKey service;
  final ManualImportFlowState state;
  final VoidCallback onRetry;

  const _LocateBody({
    required this.service,
    required this.state,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.error != null && state.rootFolders.isEmpty) {
      return AppEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Manual import unavailable',
        message: state.error,
        accentColor: service.accent,
        action: FilledButton.tonalIcon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Try again'),
        ),
      );
    }

    final lastFolder = ref.watch(manualImportLastFolderProvider(service));
    final showLastFolder =
        lastFolder != null &&
        lastFolder.isNotEmpty &&
        lastFolder != state.selectedFolder;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        ImportStationBar(service: service, activeIndex: 0),
        if (state.rootFolders.isNotEmpty)
          _RootFolderRail(service: service, state: state),
        if (showLastFolder)
          _LastFolderShortcut(service: service, path: lastFolder),
        ImportBreadcrumb(
          service: service,
          path: state.currentPath,
          onSegmentTap: (path) =>
              ref.read(manualImportFlowProvider.notifier).selectFolder(path),
        ),
        if (state.isLoadingBrowse && state.fileSystem == null)
          const _DirectorySkeleton()
        else
          _DirectoryCard(service: service, state: state),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

/// The service's root folders as one horizontal rail of jump points.
class _RootFolderRail extends ConsumerWidget {
  final ServiceKey service;
  final ManualImportFlowState state;

  const _RootFolderRail({required this.service, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          for (final folder in state.rootFolders) ...[
            _RootFolderChip(
              service: service,
              folder: folder,
              selected: _isWithin(state.currentPath, folder.path),
              onTap: () => ref
                  .read(manualImportFlowProvider.notifier)
                  .selectFolder(folder.path),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }

  bool _isWithin(String? currentPath, String rootPath) {
    if (currentPath == null) return false;
    return currentPath == rootPath || currentPath.startsWith(rootPath);
  }
}

class _RootFolderChip extends StatelessWidget {
  final ServiceKey service;
  final ManualImportRootFolder folder;
  final bool selected;
  final VoidCallback onTap;

  const _RootFolderChip({
    required this.service,
    required this.folder,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = service.accent;
    final freeSpace = folder.freeSpace;
    final subtitle = !folder.accessible
        ? 'Unreachable'
        : freeSpace == null
        ? null
        : '${formatImportBytes(freeSpace)} free';
    final labelColor = selected
        ? ServiceTheme.onTint(
            accent,
            surface: colorScheme.surface,
            tintAlpha: 0.14,
          )
        : colorScheme.onSurface;

    return PressableScale(
      onTap: onTap,
      semanticLabel: 'Root folder ${folder.displayName}',
      semanticValue: [
        if (subtitle != null) subtitle,
        if (selected) 'selected',
      ].join(', '),
      excludeChildSemantics: true,
      child: AnimatedContainer(
        duration: AppAnimation.durationSm,
        curve: AppAnimation.emphasizedCurve,
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.14)
              : colorScheme.surfaceContainer,
          borderRadius: AppRadius.borderRadiusMd,
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.28)
                : colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              folder.accessible
                  ? Icons.folder_rounded
                  : Icons.folder_off_rounded,
              size: 18,
              color: folder.accessible ? accent : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  folder.displayName,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: labelColor,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One-tap return to the folder this service last scanned — the rescue scene
/// almost always comes back to the same completed-downloads folder.
class _LastFolderShortcut extends ConsumerWidget {
  final ServiceKey service;
  final String path;

  const _LastFolderShortcut({required this.service, required this.path});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
        onTap: () =>
            ref.read(manualImportFlowProvider.notifier).selectFolder(path),
        semanticLabel: 'Return to last scanned folder',
        semanticValue: path,
        semanticHint: 'selects the folder',
        excludeChildSemantics: true,
        child: Row(
          children: [
            Icon(Icons.history_rounded, size: 18, color: service.accent),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Last scanned',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _DirectorySkeleton extends StatelessWidget {
  const _DirectorySkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        children: [
          for (var index = 0; index < 5; index++) ...[
            ShimmerPlaceholder.card(height: 56),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _DirectoryCard extends ConsumerWidget {
  final ServiceKey service;
  final ManualImportFlowState state;

  const _DirectoryCard({required this.service, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final directories = state.fileSystem?.directories ?? const [];

    if (directories.isEmpty) {
      return AppEmptyState.compact(
        icon: Icons.folder_off_rounded,
        title: 'No subfolders here',
        message: 'You can still scan this folder as the import source.',
        accentColor: service.accent,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: AppCard.surfaceOutlined(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: AppRadius.borderRadiusMd,
          child: Column(
            children: [
              for (var index = 0; index < directories.length; index++) ...[
                if (index > 0) const Divider(height: 1),
                _DirectoryRow(
                  service: service,
                  entry: directories[index],
                  selected: directories[index].path == state.selectedFolder,
                  onTap: () => ref
                      .read(manualImportFlowProvider.notifier)
                      .selectFolder(directories[index].path),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectoryRow extends StatelessWidget {
  final ServiceKey service;
  final ManualImportFileSystemEntry entry;
  final bool selected;
  final VoidCallback onTap;

  const _DirectoryRow({
    required this.service,
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = service.accent;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      button: true,
      selected: selected,
      label: entry.name,
      hint: 'opens the folder',
      onTap: onTap,
      child: Material(
        color: selected ? accent.withValues(alpha: 0.08) : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          excludeFromSemantics: true,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: ExcludeSemantics(
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: serviceThemeFor(service).softContainer,
                      borderRadius: AppRadius.borderRadiusSm,
                    ),
                    child: Icon(Icons.folder_rounded, size: 18, color: accent),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                        Text(
                          entry.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Icon(Icons.check_rounded, size: 18, color: accent),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
