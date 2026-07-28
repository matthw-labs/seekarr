import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/features/import/domain/manual_import_models.dart';
import 'package:seekarr/features/import/presentation/manual_import_provider.dart';
import 'package:seekarr/features/import/presentation/manual_import_routes.dart';
import 'package:seekarr/features/import/presentation/manual_import_widgets.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

class ManualImportFolderScreen extends ConsumerStatefulWidget {
  final ServiceKey service;
  final int? targetId;

  const ManualImportFolderScreen({
    super.key,
    required this.service,
    this.targetId,
  });

  @override
  ConsumerState<ManualImportFolderScreen> createState() =>
      _ManualImportFolderScreenState();
}

class _ManualImportFolderScreenState
    extends ConsumerState<ManualImportFolderScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final notifier = ref.read(manualImportFlowProvider.notifier);
      final state = ref.read(manualImportFlowProvider);
      if (state.service != widget.service || state.selectedFolder == null) {
        await notifier.start(widget.service, targetId: widget.targetId);
      }
      ref.read(_folderSearchQueryProvider.notifier).state = '';
      await notifier.loadSelectedFolderItems();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(manualImportFlowProvider);
    final selectedCount = state.selectedPaths.length;

    return ManualImportFrame(
      service: widget.service,
      title: 'Select Files',
      subtitle: '${widget.service.title} · Manual Import',
      actions: [
        IconButton(
          tooltip: state.allSelectableSelected
              ? 'Clear selection'
              : 'Select all',
          icon: Icon(
            state.allSelectableSelected
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
          ),
          onPressed: state.selectableItems.isEmpty
              ? null
              : () => ref
                    .read(manualImportFlowProvider.notifier)
                    .toggleAllSelectable(),
        ),
      ],
      bottomBar: ImportPrimaryButton(
        service: widget.service,
        icon: Icons.download_done_rounded,
        label: selectedCount == 1
            ? 'Import 1 selected file'
            : 'Import $selectedCount selected files',
        onPressed: state.hasSelectedItems
            ? () => context.push(
                manualImportLocation(
                  manualImportMatchPath,
                  widget.service,
                  targetId: widget.targetId,
                ),
              )
            : null,
      ),
      child: _FolderBody(service: widget.service, state: state),
    );
  }
}

class _FolderBody extends ConsumerWidget {
  final ServiceKey service;
  final ManualImportFlowState state;

  const _FolderBody({required this.service, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.error != null && state.items.isEmpty) {
      return ImportMessage(
        icon: Icons.cloud_off_rounded,
        message: 'Files unavailable',
        detail: state.error,
      );
    }

    if (state.isLoadingItems) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        ImportBreadcrumb(
          service: service,
          path: state.selectedFolder,
          onSegmentTap: (path) {
            ref.read(manualImportFlowProvider.notifier).selectFolder(path);
            context.pop();
          },
        ),
        _ImportSummaryBanner(service: service, state: state),
        _FolderSearchBar(),
        _FilesCard(service: service, state: state),
      ],
    );
  }
}

class _FolderSearchBar extends ConsumerStatefulWidget {
  @override
  ConsumerState<_FolderSearchBar> createState() => _FolderSearchBarState();
}

class _FolderSearchBarState extends ConsumerState<_FolderSearchBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final query = ref.watch(_folderSearchQueryProvider);
    if (_controller.text != query) {
      _controller.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: SearchBar(
        controller: _controller,
        hintText: 'Filter files...',
        leading: const Icon(Icons.search_rounded, size: 18),
        trailing: [
          if (query.isNotEmpty)
            IconButton(
              tooltip: 'Clear search',
              onPressed: () {
                _controller.clear();
                ref.read(_folderSearchQueryProvider.notifier).state = '';
              },
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
        ],
        onChanged: (value) =>
            ref.read(_folderSearchQueryProvider.notifier).state = value,
        elevation: WidgetStateProperty.all(0),
        backgroundColor: WidgetStateProperty.all(colorScheme.surfaceContainer),
        side: WidgetStateProperty.all(
          BorderSide(color: colorScheme.outlineVariant),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusMd),
        ),
        constraints: const BoxConstraints(minHeight: 40),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        ),
      ),
    );
  }
}

class _ImportSummaryBanner extends StatelessWidget {
  final ServiceKey service;
  final ManualImportFlowState state;

  const _ImportSummaryBanner({required this.service, required this.state});

  @override
  Widget build(BuildContext context) {
    final imported = state.items.where((item) => item.isAlreadyImported).length;
    final eligible = state.items.length - imported;
    final text = imported > 0
        ? '$eligible eligible files · $imported already imported · tap to select'
        : '$eligible eligible files · tap to select';

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: service.accent.withValues(alpha: 0.09),
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: service.accent.withValues(alpha: 0.2)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: service.accent,
        ),
      ),
    );
  }
}

class _FilesCard extends ConsumerWidget {
  final ServiceKey service;
  final ManualImportFlowState state;

  const _FilesCard({required this.service, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final query = ref.watch(_folderSearchQueryProvider).trim().toLowerCase();
    final filteredItems = query.isEmpty
        ? state.items
        : state.items
              .where((item) {
                return item.name.toLowerCase().contains(query) ||
                    item.mediaTitle.toLowerCase().contains(query) ||
                    item.extension.toLowerCase().contains(query);
              })
              .toList(growable: false);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: filteredItems.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: ImportMessage(
                icon: Icons.movie_filter_outlined,
                message: 'No eligible files found',
                detail: 'Choose another folder to continue manual import.',
              ),
            )
          : Column(
              children: [
                for (var index = 0; index < filteredItems.length; index++)
                  _FileRow(
                    service: service,
                    item: filteredItems[index],
                    selected: state.selectedPaths.contains(
                      filteredItems[index].path,
                    ),
                    showDivider: index != filteredItems.length - 1,
                    onChanged: (selected) => ref
                        .read(manualImportFlowProvider.notifier)
                        .toggleItem(filteredItems[index], selected),
                  ),
              ],
            ),
    );
  }
}

class _FileRow extends StatelessWidget {
  final ServiceKey service;
  final ManualImportItem item;
  final bool selected;
  final bool showDivider;
  final ValueChanged<bool> onChanged;

  const _FileRow({
    required this.service,
    required this.item,
    required this.selected,
    required this.showDivider,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = item.isSelectable;

    return InkWell(
      onTap: enabled ? () => onChanged(!selected) : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Container(
          decoration: BoxDecoration(
            color: enabled
                ? colorScheme.surfaceContainer
                : colorScheme.surfaceContainerHigh,
            border: Border(
              bottom: showDivider
                  ? BorderSide(color: colorScheme.outlineVariant)
                  : BorderSide.none,
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              _ImportCheckbox(
                service: service,
                selected: selected,
                enabled: enabled,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${formatImportBytes(item.size)} · ${item.qualityLabel}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _ExtensionBadge(service: service, extension: item.extension),
              if (item.isAlreadyImported) ...[
                const SizedBox(width: AppSpacing.xs),
                const _ImportedBadge(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportCheckbox extends StatelessWidget {
  final ServiceKey service;
  final bool selected;
  final bool enabled;

  const _ImportCheckbox({
    required this.service,
    required this.selected,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected && enabled
            ? service.accent.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          width: 1.5,
          color: enabled ? service.accent : colorScheme.outlineVariant,
        ),
      ),
      child: selected && enabled
          ? Icon(Icons.check_rounded, size: 15, color: service.accent)
          : null,
    );
  }
}

class _ExtensionBadge extends StatelessWidget {
  final ServiceKey service;
  final String extension;

  const _ExtensionBadge({required this.service, required this.extension});

  @override
  Widget build(BuildContext context) {
    final isMkv = extension == 'MKV';
    final colorScheme = Theme.of(context).colorScheme;
    final color = isMkv ? service.accent : colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.borderRadiusXs,
      ),
      child: Text(
        extension,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.36,
          color: color,
        ),
      ),
    );
  }
}

class _ImportedBadge extends StatelessWidget {
  const _ImportedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.15),
        borderRadius: AppRadius.borderRadiusFull,
      ),
      child: const Text(
        'IMPORTED',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: AppColors.success,
        ),
      ),
    );
  }
}

final _folderSearchQueryProvider = StateProvider<String>((ref) => '');
