import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/route_utils.dart';
import 'package:seekarr/core/utils/service_routes.dart';
import 'package:seekarr/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:seekarr/features/prowlarr/presentation/prowlarr_history_format.dart';
import 'package:seekarr/features/prowlarr/presentation/prowlarr_indexer_actions.dart';
import 'package:seekarr/features/prowlarr/presentation/prowlarr_provider.dart';

class ProwlarrIndexerDetailScreen extends ConsumerWidget {
  const ProwlarrIndexerDetailScreen({super.key, required this.indexerId});

  final int indexerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final indexerAsync = ref.watch(prowlarrIndexerByIdProvider(indexerId));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.prowlarr.withValues(alpha: 0.12),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () =>
              RouteUtils.popOrGo(context, ServiceRoutes.prowlarrLibrary),
          tooltip: 'Back',
        ),
        title: Text(
          indexerAsync.maybeWhen(
            data: (indexer) => indexer?.name ?? 'Indexer',
            orElse: () => 'Indexer',
          ),
        ),
        actions: [
          indexerAsync.maybeWhen(
            data: (indexer) => indexer == null
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit indexer',
                    onPressed: () => _edit(context, ref, indexer),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: indexerAsync.when(
        data: (indexer) {
          if (indexer == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Indexer not found.'),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(prowlarrIndexersProvider);
              ref.invalidate(prowlarrIndexerStatsProvider);
              ref.invalidate(prowlarrIndexerStatusProvider);
              ref.invalidate(prowlarrIndexerHistoryProvider(indexerId));
              await Future<void>.delayed(const Duration(milliseconds: 300));
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _StatusBanner(indexerId: indexerId),
                _ActionRow(indexer: indexer),
                _InfoCard(indexer: indexer),
                const SizedBox(height: 8),
                _StatsSection(indexerId: indexerId),
                const SizedBox(height: 8),
                _SectionLabel(text: 'Recent Activity'),
                _IndexerHistory(indexerId: indexerId),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Failed to load indexer'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () =>
                      ref.invalidate(prowlarrIndexerByIdProvider(indexerId)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the edit form; leaves the screen when the indexer ends up deleted.
Future<void> _edit(
  BuildContext context,
  WidgetRef ref,
  ProwlarrIndexer indexer,
) async {
  final deleted = await editIndexerFlow(context, ref, indexer);
  if (deleted && context.mounted) {
    RouteUtils.popOrGo(context, ServiceRoutes.prowlarrLibrary);
  }
}

/// Per-indexer write actions, matching what the web UI offers on an indexer.
class _ActionRow extends ConsumerWidget {
  const _ActionRow({required this.indexer});

  final ProwlarrIndexer indexer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () => testIndexerFlow(context, ref, indexer),
              icon: const Icon(Icons.network_check_rounded, size: 18),
              label: const Text('Test'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => toggleIndexerFlow(context, ref, indexer),
              icon: Icon(
                indexer.enable
                    ? Icons.pause_circle_outline_rounded
                    : Icons.play_circle_outline_rounded,
                size: 18,
              ),
              label: Text(indexer.enable ? 'Disable' : 'Enable'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton.filled(
            onPressed: () async {
              final deleted = await deleteIndexerFlow(context, ref, indexer);
              if (deleted && context.mounted) {
                RouteUtils.popOrGo(context, ServiceRoutes.prowlarrLibrary);
              }
            },
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            tooltip: 'Delete indexer',
            style: IconButton.styleFrom(
              backgroundColor: colorScheme.errorContainer,
              foregroundColor: colorScheme.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends ConsumerWidget {
  const _StatusBanner({required this.indexerId});

  final int indexerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(prowlarrIndexerStatusByIdProvider(indexerId));
    return statusAsync.maybeWhen(
      data: (status) {
        if (status == null) return const SizedBox.shrink();
        final until = status.disabledTill;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: AppRadius.borderRadiusMd,
              border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 18,
                  color: AppColors.error,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    until != null
                        ? 'Disabled due to failures until $until'
                        : 'Indexer is currently failing',
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _InfoCard extends ConsumerWidget {
  const _InfoCard({required this.indexer});

  final ProwlarrIndexer indexer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final tagLabels = ref.watch(prowlarrTagLabelsProvider);
    final profiles = ref.watch(prowlarrAppProfilesProvider).asData?.value;
    final profileName = profiles
        ?.where((profile) => profile.id == indexer.appProfileId)
        .map((profile) => profile.name)
        .whereType<String>()
        .firstOrNull;
    final tags = indexer.tags
        .map((id) => tagLabels[id] ?? '#$id')
        .toList(growable: false);

    final rows = <(String, String)>[
      ('Status', indexer.enable ? 'Enabled' : 'Disabled'),
      if (indexer.protocol != null) ('Protocol', indexer.protocol!),
      if (indexer.privacy != null) ('Privacy', indexer.privacy!),
      if (indexer.language != null) ('Language', indexer.language!),
      if (indexer.priority != null) ('Priority', '${indexer.priority}'),
      if (profileName != null) ('Sync profile', profileName),
      ('RSS', indexer.supportsRss ? 'Yes' : 'No'),
      ('Search', indexer.supportsSearch ? 'Yes' : 'No'),
      if (indexer.supportsRedirect)
        ('Redirect', indexer.redirect ? 'On' : 'Off'),
      if (tags.isNotEmpty) ('Tags', tags.join(', ')),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: AppRadius.borderRadiusMd,
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (indexer.description != null) ...[
              Text(
                indexer.description!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Divider(height: 20),
            ],
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      row.$1,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      row.$2,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium!.weight(FontWeight.w700),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatsSection extends ConsumerWidget {
  const _StatsSection({required this.indexerId});

  final int indexerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statAsync = ref.watch(prowlarrIndexerStatByIdProvider(indexerId));
    return statAsync.maybeWhen(
      data: (stat) {
        if (stat == null) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text('No usage statistics yet.'),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _StatTile(
                label: 'Queries',
                value: '${stat.numberOfQueries}',
                icon: Icons.search_rounded,
              ),
              const SizedBox(width: 8),
              _StatTile(
                label: 'Grabs',
                value: '${stat.numberOfGrabs}',
                icon: Icons.download_rounded,
              ),
              const SizedBox(width: 8),
              _StatTile(
                label: 'Fails',
                value: '${stat.numberOfFailures}',
                icon: Icons.error_outline_rounded,
                accent: stat.numberOfFailures > 0 ? AppColors.warning : null,
              ),
              const SizedBox(width: 8),
              _StatTile(
                label: 'Resp',
                value: '${stat.averageResponseTime}ms',
                icon: Icons.timer_outlined,
              ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = accent ?? AppColors.prowlarr;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: AppRadius.borderRadiusMd,
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 6),
            Text(
              value,
              // Query/grab/failure counts and the response time all refresh in
              // place, so the digits get a fixed advance.
              style: Theme.of(
                context,
              ).textTheme.titleSmall!.weight(FontWeight.w800).tabular,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall!.weight(FontWeight.w800),
      ),
    );
  }
}

class _IndexerHistory extends ConsumerWidget {
  const _IndexerHistory({required this.indexerId});

  final int indexerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(prowlarrIndexerHistoryProvider(indexerId));
    return historyAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('No recent activity for this indexer.'),
          );
        }
        return Column(
          children: items
              .take(15)
              .map((item) => _HistoryRow(item: item))
              .toList(),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Expanded(child: Text('Failed to load activity')),
            TextButton(
              onPressed: () =>
                  ref.invalidate(prowlarrIndexerHistoryProvider(indexerId)),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.item});

  final ProwlarrHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final event = prowlarrEventStyle(item);
    final title = prowlarrHistoryTitle(item);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: AppRadius.borderRadiusMd,
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall!.weight(FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.date != null)
                    Text(
                      prowlarrRelativeTime(item.date!),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: event.color.withValues(alpha: 0.12),
                borderRadius: AppRadius.borderRadiusSm,
              ),
              child: Text(
                event.label,
                style: Theme.of(context).textTheme.labelSmall!
                    .weight(FontWeight.w800)
                    .copyWith(color: event.color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
