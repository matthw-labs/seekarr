import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/features/import/domain/manual_import_models.dart';
import 'package:seekarr/features/import/presentation/manual_import_fix_sheet.dart';
import 'package:seekarr/features/import/presentation/manual_import_provider.dart';
import 'package:seekarr/features/import/presentation/manual_import_routes.dart';
import 'package:seekarr/features/import/presentation/manual_import_widgets.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

class ManualImportMatchScreen extends ConsumerWidget {
  final ServiceKey service;
  final int? targetId;

  const ManualImportMatchScreen({
    super.key,
    required this.service,
    this.targetId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(manualImportFlowProvider);
    final selectedItems = state.selectedItems;

    return ManualImportFrame(
      service: service,
      title: 'Match & Assign',
      subtitle: '${service.title} · ${selectedItems.length} files selected',
      bottomBar: _ImportFooter(service: service, targetId: targetId),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          ImportStepPills(service: service, activeStep: 2),
          if (state.error != null)
            _InlineError(service: service, error: state.error!),
          if (_canBulkFix(service, state))
            _BulkFixBar(service: service, items: state.bulkFixItems),
          if (selectedItems.isEmpty)
            const ImportMessage(
              icon: Icons.check_box_outline_blank_rounded,
              message: 'No selected files',
              detail: 'Go back and select files before matching.',
            )
          else
            for (final item in selectedItems)
              _MatchCard(service: service, item: item),
        ],
      ),
    );
  }

  bool _canBulkFix(ServiceKey service, ManualImportFlowState state) {
    return (service == ServiceKey.sonarr || service == ServiceKey.lidarr) &&
        state.bulkFixItems.length >= 2;
  }
}

class _MatchCard extends ConsumerStatefulWidget {
  final ServiceKey service;
  final ManualImportItem item;

  const _MatchCard({required this.service, required this.item});

  @override
  ConsumerState<_MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends ConsumerState<_MatchCard> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final state = ref.watch(manualImportFlowProvider);
    final item = widget.item;
    final matched = item.isMatchedFor(widget.service);
    final warning = item.hasWarningFor(widget.service);

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusLg,
        border: Border.all(
          color: warning
              ? AppColors.error.withValues(alpha: 0.35)
              : colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _FileHeader(
            service: widget.service,
            item: item,
            showBulkToggle:
                !matched &&
                (widget.service == ServiceKey.sonarr ||
                    widget.service == ServiceKey.lidarr),
            bulkSelected: state.bulkFixPaths.contains(item.path),
            onBulkChanged: (value) => ref
                .read(manualImportFlowProvider.notifier)
                .toggleBulkFixItem(item, value),
            onRemove: () => ref
                .read(manualImportFlowProvider.notifier)
                .toggleItem(item, false),
          ),
          _MediaMatchRow(
            service: widget.service,
            item: item,
            matched: matched,
            warning: warning,
            onFix: () => showManualImportFixSheet(
              context: context,
              service: widget.service,
              item: item,
            ),
          ),
          _QualityLanguageRow(service: widget.service, item: item),
        ],
      ),
    );
  }
}

class _FileHeader extends StatelessWidget {
  final ServiceKey service;
  final ManualImportItem item;
  final bool showBulkToggle;
  final bool bulkSelected;
  final ValueChanged<bool> onBulkChanged;
  final VoidCallback onRemove;

  const _FileHeader({
    required this.service,
    required this.item,
    required this.showBulkToggle,
    required this.bulkSelected,
    required this.onBulkChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: service.accent.withValues(alpha: 0.12),
              borderRadius: AppRadius.borderRadiusSm,
            ),
            child: Icon(
              Icons.description_rounded,
              size: 16,
              color: service.accent,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  formatImportBytes(item.size),
                  style: TextStyle(
                    fontSize: 10,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (showBulkToggle) ...[
            const SizedBox(width: AppSpacing.xs),
            Checkbox(
              value: bulkSelected,
              activeColor: service.accent,
              visualDensity: VisualDensity.compact,
              onChanged: (value) => onBulkChanged(value == true),
            ),
          ],
          IconButton.filledTonal(
            tooltip: 'Remove from import',
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 16),
            color: AppColors.error,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.error.withValues(alpha: 0.1),
              minimumSize: const Size(26, 26),
              fixedSize: const Size(26, 26),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaMatchRow extends StatelessWidget {
  final ServiceKey service;
  final ManualImportItem item;
  final bool matched;
  final bool warning;
  final VoidCallback onFix;

  const _MediaMatchRow({
    required this.service,
    required this.item,
    required this.matched,
    required this.warning,
    required this.onFix,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = matched ? AppColors.success : AppColors.error;
    final title = matched ? item.mediaTitle : item.firstRejectionReason;
    final subtitle = matched
        ? item.mediaSubtitle
        : item.hasMatchFor(service)
        ? 'Identity assigned, but metadata still needs attention'
        : null;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'MEDIA MATCH',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.45,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              _StatusPill(
                label: matched ? 'Matched' : 'Unmatched',
                color: statusColor,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Container(
                width: 30,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: AppRadius.borderRadiusSm,
                ),
                child: Icon(
                  matched ? service.icon : Icons.warning_amber_rounded,
                  size: 18,
                  color: matched ? service.accent : AppColors.error,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: matched ? 13 : 12,
                        fontWeight: matched ? FontWeight.w700 : FontWeight.w600,
                        color: matched
                            ? colorScheme.onSurface
                            : AppColors.error,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: onFix,
                icon: const Icon(Icons.search_rounded, size: 14),
                label: const Text('Fix'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: service.accent,
                  side: BorderSide(color: service.accent),
                  textStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BulkFixBar extends ConsumerWidget {
  final ServiceKey service;
  final List<ManualImportItem> items;

  const _BulkFixBar({required this.service, required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: service.accent.withValues(alpha: 0.12),
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: service.accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(Icons.checklist_rtl_rounded, color: service.accent, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '${items.length} unmatched files selected',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: service.accent,
              ),
            ),
          ),
          FilledButton.tonal(
            onPressed: () => showManualImportBulkFixSheet(
              context: context,
              service: service,
              items: items,
            ),
            child: const Text('Fix files'),
          ),
          IconButton(
            tooltip: 'Clear selection',
            onPressed: () => ref
                .read(manualImportFlowProvider.notifier)
                .clearBulkFixSelection(),
            icon: const Icon(Icons.close_rounded, size: 18),
            color: service.accent,
          ),
        ],
      ),
    );
  }
}

class _QualityLanguageRow extends StatelessWidget {
  final ServiceKey service;
  final ManualImportItem item;

  const _QualityLanguageRow({required this.service, required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: _MetaBox(
              label: 'QUALITY',
              value: item.qualityLabel,
              enabled: item.hasMatchFor(service),
              onTap: item.hasMatchFor(service)
                  ? () => _showQualityPicker(context, service, item)
                  : null,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _MetaBox(
              label: 'LANGUAGE',
              value: item.languageLabel,
              enabled: item.hasMatchFor(service),
              onTap: item.hasMatchFor(service)
                  ? () => _showLanguagePicker(context, service, item)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaBox extends StatelessWidget {
  final String label;
  final String value;
  final bool enabled;
  final VoidCallback? onTap;

  const _MetaBox({
    required this.label,
    required this.value,
    this.enabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.45,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: AppRadius.borderRadiusSm,
            onTap: enabled ? onTap : null,
            child: Ink(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: AppRadius.borderRadiusSm,
                border: Border.all(
                  color: enabled
                      ? colorScheme.outlineVariant
                      : colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: enabled
                            ? colorScheme.onSurface
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ImportFooter extends ConsumerWidget {
  final ServiceKey service;
  final int? targetId;

  const _ImportFooter({required this.service, this.targetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(manualImportFlowProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          _ImportModeMenu(service: service),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: SizedBox(
              height: 46,
              child: FilledButton.icon(
                onPressed: state.isSubmitting || !state.canImportSelected
                    ? null
                    : () async {
                        final command = await ref
                            .read(manualImportFlowProvider.notifier)
                            .confirmImport();
                        if (command != null && context.mounted) {
                          context.push(
                            manualImportLocation(
                              manualImportProgressPath,
                              service,
                              targetId: targetId,
                            ),
                          );
                        }
                      },
                icon: state.isSubmitting
                    ? SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: const Text('Confirm Import'),
                style: FilledButton.styleFrom(
                  backgroundColor: service.accent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  disabledForegroundColor: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant,
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: const StadiumBorder(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportModeMenu extends ConsumerWidget {
  final ServiceKey service;

  const _ImportModeMenu({required this.service});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(manualImportFlowProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 38,
      child: MenuAnchor(
        builder: (context, controller, _) {
          return OutlinedButton(
            onPressed: controller.isOpen ? controller.close : controller.open,
            style: OutlinedButton.styleFrom(
              shape: const StadiumBorder(),
              side: BorderSide(color: colorScheme.outlineVariant),
              minimumSize: const Size(0, 38),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              visualDensity: VisualDensity.compact,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  state.importMode.label,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.expand_more_rounded,
                  size: 15,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          );
        },
        menuChildren: [
          for (final mode in ManualImportMode.values)
            MenuItemButton(
              onPressed: () => ref
                  .read(manualImportFlowProvider.notifier)
                  .setImportMode(mode),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(mode.label),
                  Text(
                    mode.subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _showQualityPicker(
  BuildContext context,
  ServiceKey service,
  ManualImportItem item,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => _QualityPickerSheet(service: service, item: item),
  );
}

Future<void> _showLanguagePicker(
  BuildContext context,
  ServiceKey service,
  ManualImportItem item,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _LanguagePickerSheet(service: service, item: item),
  );
}

class _QualityPickerSheet extends ConsumerWidget {
  final ServiceKey service;
  final ManualImportItem item;

  const _QualityPickerSheet({required this.service, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<ManualImportQualityOption>>(
      future: ref.read(manualImportFlowProvider.notifier).getQualityOptions(),
      builder: (context, snapshot) {
        final options = snapshot.data ?? const <ManualImportQualityOption>[];
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.72,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select Quality',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (options.isEmpty)
                    const ImportMessage(
                      icon: Icons.high_quality_rounded,
                      message: 'No quality options available',
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (context, index) {
                          final option = options[index];
                          final selected = option.id == item.qualityId;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              option.name,
                              style: TextStyle(
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            leading: Icon(
                              selected
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_off_rounded,
                              color: selected
                                  ? service.accent
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                            onTap: () async {
                              if (selected) {
                                if (context.mounted)
                                  Navigator.of(context).pop();
                                return;
                              }

                              await ref
                                  .read(manualImportFlowProvider.notifier)
                                  .updateItemMetadata(item, quality: option);
                              if (context.mounted) {
                                Navigator.of(context).pop();
                              }
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LanguagePickerSheet extends ConsumerStatefulWidget {
  final ServiceKey service;
  final ManualImportItem item;

  const _LanguagePickerSheet({required this.service, required this.item});

  @override
  ConsumerState<_LanguagePickerSheet> createState() =>
      _LanguagePickerSheetState();
}

class _LanguagePickerSheetState extends ConsumerState<_LanguagePickerSheet> {
  late Set<int> _selectedIds;
  late final Future<List<ManualImportLanguageOption>> _optionsFuture;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.item.languageIds.toSet();
    _optionsFuture = ref
        .read(manualImportFlowProvider.notifier)
        .getLanguageOptions();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ManualImportLanguageOption>>(
      future: _optionsFuture,
      builder: (context, snapshot) {
        final options = snapshot.data ?? const <ManualImportLanguageOption>[];
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select Languages',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AppSpacing.md),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Center(child: CircularProgressIndicator())
                else
                  Flexible(
                    child: ListView(
                      controller: _scrollController,
                      shrinkWrap: true,
                      children: [
                        for (final option in options)
                          CheckboxListTile(
                            value: _selectedIds.contains(option.id),
                            activeColor: widget.service.accent,
                            contentPadding: EdgeInsets.zero,
                            title: Text(option.name),
                            onChanged: (selected) {
                              setState(() {
                                if (selected == true) {
                                  _selectedIds.add(option.id);
                                } else {
                                  _selectedIds.remove(option.id);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      final selected = options
                          .where((option) => _selectedIds.contains(option.id))
                          .toList(growable: false);
                      await ref
                          .read(manualImportFlowProvider.notifier)
                          .updateItemMetadata(widget.item, languages: selected);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.service.accent,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Apply Languages'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.borderRadiusFull,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final ServiceKey service;
  final String error;

  const _InlineError({required this.service, required this.error});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AppColors.error,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
