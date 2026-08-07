import 'package:flutter/material.dart';
import 'package:seekarr/core/widgets/floating_bottom_nav_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/app_dialog.dart';
import 'package:seekarr/core/widgets/app_error_state.dart';
import 'package:seekarr/core/widgets/app_skeleton.dart';
import 'package:seekarr/core/utils/string_utils.dart';
import 'package:seekarr/core/widgets/section_header.dart';
import 'package:seekarr/features/qbittorrent/domain/models/parse_utils.dart';
import 'package:seekarr/features/truenas/domain/models/dataset.dart';
import 'package:seekarr/features/truenas/presentation/datasets/truenas_dataset_actions.dart';
import 'package:seekarr/features/truenas/presentation/datasets/truenas_dataset_providers.dart';
import 'package:seekarr/features/truenas/presentation/truenas_actions.dart';
import 'package:seekarr/features/truenas/presentation/truenas_provider.dart';
import 'package:seekarr/features/truenas/presentation/widgets/truenas_info_row.dart';
import 'package:seekarr/features/truenas/presentation/widgets/truenas_section_scaffold.dart';

class TrueNasDatasetDetailScreen extends ConsumerWidget {
  final String datasetId;
  const TrueNasDatasetDetailScreen({super.key, required this.datasetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataset = ref.watch(truenasDatasetProvider(datasetId));

    return TrueNasSectionScaffold(
      title: datasetId.split('/').last,
      actions: [
        dataset.maybeWhen(
          data: (d) => d == null
              ? const SizedBox.shrink()
              : PopupMenuButton<String>(
                  onSelected: (value) async {
                    switch (value) {
                      case 'edit':
                        await editDatasetFlow(context, ref, d);
                      case 'child':
                        await createDatasetFlow(context, ref, parentId: d.id);
                      case 'delete':
                        final deleted = await deleteDatasetFlow(
                          context,
                          ref,
                          d,
                        );
                        if (deleted && context.mounted) context.pop();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(
                      value: 'child',
                      child: Text('Create child dataset'),
                    ),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
          orElse: () => const SizedBox.shrink(),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(truenasDatasetProvider(datasetId));
          ref.invalidate(truenasSnapshotsProvider(datasetId));
        },
        child: dataset.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [AppSkeleton.detailBody()],
          ),
          error: (error, _) => ListView(
            children: [
              AppErrorState(
                error: error,
                onRetry: () =>
                    ref.invalidate(truenasDatasetProvider(datasetId)),
              ),
            ],
          ),
          data: (d) => d == null
              ? ListView(
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Text('Dataset not found.'),
                    ),
                  ],
                )
              : _DetailBody(dataset: d),
        ),
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  final TrueNasDataset dataset;
  const _DetailBody({required this.dataset});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshots = ref.watch(truenasSnapshotsProvider(dataset.id));

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        FloatingNavBarMetrics.getScrollViewBottomPadding(context),
      ),
      children: [
        AppCard.surfaceOutlined(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TrueNasInfoRow(label: 'Path', value: dataset.id),
              TrueNasInfoRow(label: 'Type', value: dataset.type),
              TrueNasInfoRow(
                label: 'Used',
                value: dataset.usedBytes != null
                    ? formatSize(dataset.usedBytes!)
                    : null,
              ),
              TrueNasInfoRow(
                label: 'Available',
                value: dataset.availableBytes != null
                    ? formatSize(dataset.availableBytes!)
                    : null,
              ),
              if (dataset.quotaBytes != null && dataset.quotaBytes! > 0)
                TrueNasInfoRow(
                  label: 'Quota',
                  value: formatSize(dataset.quotaBytes!),
                ),
              TrueNasInfoRow(label: 'Compression', value: dataset.compression),
              TrueNasInfoRow(label: 'Ratio', value: dataset.compressionRatio),
              TrueNasInfoRow(label: 'Record size', value: dataset.recordsize),
              TrueNasInfoRow(label: 'Dedup', value: dataset.dedup),
              TrueNasInfoRow(
                label: 'Encrypted',
                value: dataset.encrypted ? 'Yes' : 'No',
              ),
              TrueNasInfoRow(label: 'Comment', value: dataset.comments),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SectionHeader.action(
          title: 'Snapshots',
          trailing: TextButton.icon(
            onPressed: () => createSnapshotFlow(context, ref, dataset.id),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('New'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        snapshots.when(
          loading: () => AppSkeleton.listRows(count: 3),
          error: (e, _) => AppCard.surfaceOutlined(
            child: Text('$e', style: Theme.of(context).textTheme.bodySmall),
          ),
          data: (list) => list.isEmpty
              ? AppCard.surfaceOutlined(
                  child: Text(
                    'No snapshots.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : Column(
                  children: [
                    for (final snap in list)
                      _SnapshotTile(snapshot: snap, dataset: dataset.id),
                  ],
                ),
        ),
      ],
    );
  }
}

class _SnapshotTile extends ConsumerWidget {
  final TrueNasSnapshot snapshot;
  final String dataset;
  const _SnapshotTile({required this.snapshot, required this.dataset});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return AppCard.surfaceOutlined(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snapshot.name,
                  style: theme.textTheme.bodyMedium!.weight(FontWeight.w600),
                ),
                Text(
                  [
                    'used ${snapshot.usedBytes != null ? formatSize(snapshot.usedBytes!) : '—'}',
                    // The dense-row date voice, matching the activity feed.
                    if (snapshot.createdMs != null)
                      formatIsoDate(
                        DateTime.fromMillisecondsSinceEpoch(
                          snapshot.createdMs!,
                        ).toIso8601String(),
                      ),
                  ].join(' · '),
                  style: theme.textTheme.labelSmall!.tabular.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: theme.colorScheme.error,
            ),
            tooltip: 'Delete snapshot',
            onPressed: () async {
              final result = await showAppConfirmDialog(
                context: context,
                title: 'Delete snapshot?',
                message: snapshot.id,
                confirmLabel: 'Delete',
                destructive: true,
              );
              if (!result.confirmed || !context.mounted) return;
              await runTrueNasAction(
                context,
                ref,
                action: () => ref
                    .read(truenasDatasetApiProvider)
                    .deleteSnapshot(snapshot.id),
                successMessage: 'Snapshot deleted',
                failureMessage: 'Could not delete snapshot',
                invalidate: [truenasSnapshotsProvider(dataset)],
              );
            },
          ),
        ],
      ),
    );
  }
}
