import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/app_dialog.dart';
import 'package:seekarr/core/widgets/app_error_state.dart';
import 'package:seekarr/core/widgets/app_skeleton.dart';
import 'package:seekarr/core/widgets/section_header.dart';
import 'package:seekarr/features/qbittorrent/domain/models/parse_utils.dart';
import 'package:seekarr/features/truenas/domain/models/pool.dart';
import 'package:seekarr/features/truenas/presentation/storage/truenas_storage_providers.dart';
import 'package:seekarr/features/truenas/presentation/truenas_actions.dart';
import 'package:seekarr/features/truenas/presentation/truenas_provider.dart';
import 'package:seekarr/features/truenas/presentation/widgets/truenas_info_row.dart';
import 'package:seekarr/features/truenas/presentation/widgets/truenas_section_scaffold.dart';

class TrueNasPoolDetailScreen extends ConsumerWidget {
  final String poolName;
  const TrueNasPoolDetailScreen({super.key, required this.poolName});

  Future<void> _runScrub(BuildContext context, WidgetRef ref) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Start scrub?',
      message:
          'A scrub verifies all data in "$poolName". It can take hours and '
          'adds disk load, but is safe to run.',
      confirmLabel: 'Start scrub',
      icon: Icons.cleaning_services_rounded,
    );
    if (!result.confirmed || !context.mounted) return;
    await runTrueNasAction(
      context,
      ref,
      action: () => ref.read(truenasStorageApiProvider).runScrub(poolName),
      successMessage: 'Scrub started on $poolName',
      failureMessage: 'Could not start scrub',
      invalidate: [truenasPoolProvider(poolName)],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pool = ref.watch(truenasPoolProvider(poolName));

    return TrueNasSectionScaffold(
      title: poolName,
      actions: [
        IconButton(
          tooltip: 'Start scrub',
          icon: const Icon(Icons.cleaning_services_outlined),
          onPressed: () => _runScrub(context, ref),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(truenasPoolProvider(poolName)),
        child: pool.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [AppSkeleton.detailBody()],
          ),
          error: (error, _) => ListView(
            children: [
              AppErrorState(
                error: error,
                onRetry: () => ref.invalidate(truenasPoolProvider(poolName)),
              ),
            ],
          ),
          data: (data) => data == null
              ? ListView(
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Text('Pool not found.'),
                    ),
                  ],
                )
              : _PoolDetailBody(pool: data),
        ),
      ),
    );
  }
}

class _PoolDetailBody extends StatelessWidget {
  final TrueNasPool pool;
  const _PoolDetailBody({required this.pool});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final used = pool.usedFraction;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: [
        AppCard.surfaceOutlined(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TrueNasInfoRow(
                label: 'Status',
                value: pool.status,
                valueColor: pool.healthy
                    ? AppColors.success
                    : theme.colorScheme.error,
              ),
              TrueNasInfoRow(
                label: 'Capacity',
                value: pool.sizeBytes != null
                    ? formatSize(pool.sizeBytes!)
                    : null,
              ),
              TrueNasInfoRow(
                label: 'Allocated',
                value: pool.allocatedBytes != null
                    ? formatSize(pool.allocatedBytes!)
                    : null,
              ),
              TrueNasInfoRow(
                label: 'Free',
                value: pool.freeBytes != null
                    ? formatSize(pool.freeBytes!)
                    : null,
              ),
              if (used != null)
                TrueNasInfoRow(
                  label: 'Used',
                  value: '${(used * 100).round()}%',
                ),
              if (pool.scanState != null)
                TrueNasInfoRow(
                  label: 'Last scan',
                  value: pool.scanPercentage != null
                      ? '${pool.scanState} · ${pool.scanPercentage!.toStringAsFixed(0)}%'
                      : pool.scanState,
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const SectionHeader(title: 'Topology', showChevron: false),
        const SizedBox(height: AppSpacing.sm),
        if (!pool.hasTopology)
          AppCard.surfaceOutlined(
            child: Text(
              'Topology unavailable.',
              style: theme.textTheme.bodySmall,
            ),
          )
        else
          for (final entry in pool.topology.entries)
            _TopologyCategory(category: entry.key, vdevs: entry.value),
      ],
    );
  }
}

class _TopologyCategory extends StatelessWidget {
  final String category;
  final List<TrueNasVdev> vdevs;
  const _TopologyCategory({required this.category, required this.vdevs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard.surfaceOutlined(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              category.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final vdev in vdevs) ...[
              Row(
                children: [
                  Text(
                    vdev.type,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _StatusDot(status: vdev.status),
                ],
              ),
              for (final member in vdev.members)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.md, top: 2),
                  child: Row(
                    children: [
                      Icon(
                        Icons.storage_rounded,
                        size: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          member.name,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      _StatusDot(status: member.status),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.xs),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final String status;
  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final healthy = status.toUpperCase() == 'ONLINE';
    final color = healthy ? AppColors.success : AppColors.warning;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          status,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}
