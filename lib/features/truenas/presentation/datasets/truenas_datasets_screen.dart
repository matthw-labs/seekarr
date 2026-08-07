import 'package:flutter/material.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/features/qbittorrent/domain/models/parse_utils.dart';
import 'package:cupola/features/truenas/domain/models/dataset.dart';
import 'package:cupola/features/truenas/presentation/datasets/truenas_dataset_actions.dart';
import 'package:cupola/features/truenas/presentation/datasets/truenas_dataset_providers.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_section_scaffold.dart';

class TrueNasDatasetsScreen extends ConsumerWidget {
  const TrueNasDatasetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(truenasDatasetTreeProvider);

    return TrueNasSectionScaffold(
      title: 'Datasets',
      floatingActionButton: const DatasetCreateButton(),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(truenasDatasetTreeProvider),
        child: tree.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [AppSkeleton.listRows()],
          ),
          error: (error, _) => ListView(
            children: [
              AppErrorState(
                error: error,
                onRetry: () => ref.invalidate(truenasDatasetTreeProvider),
              ),
            ],
          ),
          data: (roots) => roots.isEmpty
              ? const AppEmptyState(
                  icon: Icons.account_tree_rounded,
                  title: 'No datasets',
                  accentColor: AppColors.truenas,
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    FloatingNavBarMetrics.getScrollViewBottomPadding(context),
                  ),
                  children: [
                    for (final root in roots)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: AppCard.surfaceOutlined(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          child: _DatasetNode(dataset: root, depth: 0),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _DatasetNode extends StatelessWidget {
  final TrueNasDataset dataset;
  final int depth;
  const _DatasetNode({required this.dataset, required this.depth});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = dataset.isVolume
        ? 'zvol · ${dataset.volsizeBytes != null ? formatSize(dataset.volsizeBytes!) : '—'}'
        : 'used ${dataset.usedBytes != null ? formatSize(dataset.usedBytes!) : '—'}';

    final tileTitle = Row(
      children: [
        Icon(
          dataset.isVolume ? Icons.storage_rounded : Icons.folder_rounded,
          size: 16,
          color: AppColors.truenas,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            depth == 0 ? dataset.id : dataset.shortName,
            style: theme.textTheme.bodyMedium!.weight(FontWeight.w600),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.info_outline_rounded, size: 16),
          tooltip: 'Details',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          // 44pt hit area even though the glyph is 16pt: the visual stays
          // compact in a dense tree while the target meets the HIG minimum.
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          onPressed: () =>
              context.push(ServiceRoutes.truenasDataset(dataset.id)),
        ),
      ],
    );

    if (dataset.children.isEmpty) {
      return ListTile(
        contentPadding: EdgeInsets.only(left: depth * 10.0),
        dense: true,
        visualDensity: VisualDensity.compact,
        minVerticalPadding: 2,
        title: tileTitle,
        subtitle: Text(subtitle, style: theme.textTheme.labelSmall!.tabular),
        onTap: () => context.push(ServiceRoutes.truenasDataset(dataset.id)),
      );
    }

    return Padding(
      padding: EdgeInsets.only(left: depth * 10.0),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        minTileHeight: 40,
        shape: const Border(),
        collapsedShape: const Border(),
        initiallyExpanded: depth == 0,
        title: tileTitle,
        subtitle: Text(subtitle, style: theme.textTheme.labelSmall!.tabular),
        children: [
          for (final child in dataset.children)
            _DatasetNode(dataset: child, depth: depth + 1),
        ],
      ),
    );
  }
}

/// A floating action to create a top-level dataset, shared with the section
/// scaffold via [DatasetCreateButton].
class DatasetCreateButton extends ConsumerWidget {
  const DatasetCreateButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FloatingActionButton.extended(
      onPressed: () => createDatasetFlow(context, ref, parentId: null),
      backgroundColor: AppColors.truenas,
      icon: const Icon(Icons.add_rounded),
      label: const Text('New dataset'),
    );
  }
}
