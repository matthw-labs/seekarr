import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/route_utils.dart';
import 'package:cupola/core/utils/service_action.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';

/// Tag manager, built on `tag/detail` so every row can say what still uses the
/// tag — deleting one silently drops it from those indexers and apps.
class ProwlarrTagsScreen extends ConsumerWidget {
  const ProwlarrTagsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailsAsync = ref.watch(prowlarrTagDetailsProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.prowlarr.withValues(alpha: 0.12),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          tooltip: 'Back',
          onPressed: () =>
              RouteUtils.popOrGo(context, ServiceRoutes.prowlarrSettings),
        ),
        title: const Text('Tags'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add tag',
            onPressed: () => _create(context, ref),
          ),
        ],
      ),
      body: detailsAsync.when(
        data: (tags) {
          if (tags.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'No tags yet. Tags decide which apps receive which '
                      'indexers.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.icon(
                      onPressed: () => _create(context, ref),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add tag'),
                    ),
                  ],
                ),
              ),
            );
          }
          final sorted = [...tags]
            ..sort(
              (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
            );
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(prowlarrTagDetailsProvider);
              ref.invalidate(prowlarrTagsProvider);
              await Future<void>.delayed(const Duration(milliseconds: 300));
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              itemCount: sorted.length,
              itemBuilder: (context, index) => _TagRow(
                tag: sorted[index],
                onRename: () => _rename(context, ref, sorted[index]),
                onDelete: () => _delete(context, ref, sorted[index]),
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Failed to load the tags'),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: () => ref.invalidate(prowlarrTagDetailsProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final label = await _askLabel(context, title: 'New tag');
    if (label == null || !context.mounted) return;

    await runServiceAction(
      context,
      ref,
      action: () => ref.read(prowlarrServiceProvider).createTag(label),
      successMessage: 'Tag "$label" created',
      failureMessage: 'Could not create the tag',
      invalidate: [prowlarrTagDetailsProvider, prowlarrTagsProvider],
    );
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    ProwlarrTagDetail tag,
  ) async {
    final label = await _askLabel(
      context,
      title: 'Rename tag',
      initial: tag.label,
    );
    if (label == null || label == tag.label || !context.mounted) return;

    await runServiceAction(
      context,
      ref,
      action: () => ref.read(prowlarrServiceProvider).renameTag(tag.id, label),
      successMessage: 'Tag renamed to "$label"',
      failureMessage: 'Could not rename the tag',
      invalidate: [
        prowlarrTagDetailsProvider,
        prowlarrTagsProvider,
        prowlarrIndexersProvider,
      ],
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ProwlarrTagDetail tag,
  ) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Delete "${tag.label}"?',
      message: tag.isUnused
          ? 'Nothing uses this tag.'
          : 'It is removed from ${_usageSentence(tag)}, which changes what '
                'those apps receive.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!result.confirmed || !context.mounted) return;

    await runServiceAction(
      context,
      ref,
      action: () => ref.read(prowlarrServiceProvider).deleteTag(tag.id),
      successMessage: 'Tag deleted',
      failureMessage: 'Could not delete the tag',
      invalidate: [
        prowlarrTagDetailsProvider,
        prowlarrTagsProvider,
        prowlarrIndexersProvider,
        prowlarrProvidersProvider(ProwlarrProviderKind.application),
      ],
    );
  }

  static Future<String?> _askLabel(
    BuildContext context, {
    required String title,
    String? initial,
  }) {
    final controller = TextEditingController(text: initial ?? '');
    return AppBottomSheet.show<String>(
      context: context,
      title: title,
      icon: Icons.sell_outlined,
      accent: AppColors.prowlarr,
      showClose: true,
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Label',
              hintText: 'e.g. italian',
              isDense: true,
            ),
            onSubmitted: (value) {
              final label = value.trim();
              if (label.isNotEmpty) Navigator.of(context).pop(label);
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: () {
              final label = controller.text.trim();
              if (label.isNotEmpty) Navigator.of(context).pop(label);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

String _usageSentence(ProwlarrTagDetail tag) {
  final parts = <String>[
    if (tag.indexerIds.isNotEmpty) '${tag.indexerIds.length} indexers',
    if (tag.applicationIds.isNotEmpty) '${tag.applicationIds.length} apps',
    if (tag.notificationIds.isNotEmpty)
      '${tag.notificationIds.length} notifications',
    if (tag.indexerProxyIds.isNotEmpty) '${tag.indexerProxyIds.length} proxies',
  ];
  return parts.join(', ');
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.tag,
    required this.onRename,
    required this.onDelete,
  });

  final ProwlarrTagDetail tag;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Material(
        color: colorScheme.surface,
        borderRadius: AppRadius.borderRadiusMd,
        child: InkWell(
          onTap: onRename,
          borderRadius: AppRadius.borderRadiusMd,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: AppRadius.borderRadiusMd,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tag.label,
                        style: Theme.of(
                          context,
                        ).textTheme.titleSmall!.weight(FontWeight.w700),
                      ),
                      Text(
                        tag.isUnused
                            ? 'Unused'
                            : 'Used by ${_usageSentence(tag)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  tooltip: 'Delete tag',
                  color: colorScheme.error,
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
