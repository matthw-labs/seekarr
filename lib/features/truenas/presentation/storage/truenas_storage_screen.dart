import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/service_routes.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/app_empty_state.dart';
import 'package:seekarr/core/widgets/app_error_state.dart';
import 'package:seekarr/core/widgets/app_skeleton.dart';
import 'package:seekarr/core/widgets/pressable_scale.dart';
import 'package:seekarr/features/qbittorrent/domain/models/parse_utils.dart';
import 'package:seekarr/features/truenas/domain/models/pool.dart';
import 'package:seekarr/features/truenas/presentation/storage/truenas_storage_providers.dart';
import 'package:seekarr/features/truenas/presentation/widgets/truenas_section_scaffold.dart';

class TrueNasStorageScreen extends ConsumerWidget {
  const TrueNasStorageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pools = ref.watch(truenasPoolsProvider);

    return TrueNasSectionScaffold(
      title: 'Storage',
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(truenasPoolsProvider),
        child: pools.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [AppSkeleton.listRows()],
          ),
          error: (error, _) => ListView(
            children: [
              AppErrorState(
                error: error,
                onRetry: () => ref.invalidate(truenasPoolsProvider),
              ),
            ],
          ),
          data: (data) => data.isEmpty
              ? const AppEmptyState(
                  icon: Icons.dns_rounded,
                  title: 'No pools',
                  message: 'This system has no storage pools.',
                  accentColor: AppColors.truenas,
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.xxl,
                  ),
                  children: [
                    for (final pool in data)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _PoolCard(pool: pool),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _PoolCard extends StatelessWidget {
  final TrueNasPool pool;
  const _PoolCard({required this.pool});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final used = pool.usedFraction;
    final barColor = !pool.healthy
        ? colorScheme.error
        : (used != null && used >= 0.9)
        ? AppColors.warning
        : AppColors.truenas;

    return PressableScale(
      onTap: () => context.push(ServiceRoutes.truenasPool(pool.name)),
      child: AppCard.surfaceOutlined(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  pool.healthy
                      ? Icons.check_circle_rounded
                      : Icons.error_rounded,
                  size: 16,
                  color: pool.healthy ? AppColors.success : colorScheme.error,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    pool.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  pool.status,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            if (used != null) ...[
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: used,
                  minHeight: 6,
                  color: barColor,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${(used * 100).round()}% used'
                '${pool.sizeBytes != null ? ' · ${formatSize(pool.allocatedBytes ?? 0)} / ${formatSize(pool.sizeBytes!)}' : ''}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
