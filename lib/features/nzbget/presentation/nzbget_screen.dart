import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/nzbget/domain/models/nzbget_models.dart';
import 'package:seekarr/features/nzbget/presentation/nzbget_provider.dart';
import 'package:seekarr/features/services/presentation/service_kpi_provider.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// NZBGet dashboard: live queue and recent history. Read-only for the first
/// release.
class NzbgetScreen extends ConsumerWidget {
  const NzbgetScreen({super.key, this.showAppBar = true, this.topPadding = 0});

  final bool showAppBar;
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final isConfigured = settings.isServiceConfigured(ServiceKey.nzbget);

    return AmbientScaffold(
      accent: AppColors.nzbget,
      appBar: showAppBar ? const GlassAppBar(title: Text('NZBGet')) : null,
      body: SafeArea(
        child: isConfigured
            ? _NzbgetDashboard(topPadding: topPadding)
            : _NzbgetNotConfigured(
                onOpenSettings: () => context.go(
                  '/settings/service/${ServiceKey.nzbget.routeParam}',
                ),
              ),
      ),
    );
  }
}

class _NzbgetNotConfigured extends StatelessWidget {
  const _NzbgetNotConfigured({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_sync_rounded,
              size: 48,
              color: AppColors.nzbget,
            ),
            const SizedBox(height: 12),
            const Text(
              'NZBGet is not configured yet.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onOpenSettings,
              child: const Text('Open settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NzbgetDashboard extends ConsumerWidget {
  const _NzbgetDashboard({required this.topPadding});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(nzbgetQueueProvider);
    final historyAsync = ref.watch(nzbgetHistoryProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(nzbgetStatusProvider);
        ref.invalidate(nzbgetQueueProvider);
        ref.invalidate(nzbgetHistoryProvider);
        ref.invalidate(serviceKpiProvider(ServiceKey.nzbget));
        ref.invalidate(serviceSummaryProvider(ServiceKey.nzbget));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: [
          if (topPadding > 0) SizedBox(height: topPadding),
          ServiceKpiPeek(
            kpis: ref.watch(serviceKpiProvider(ServiceKey.nzbget)),
            accent: AppColors.nzbget,
          ),
          const SizedBox(height: 8),
          const SectionHeader(title: 'Downloading', showChevron: false),
          const SizedBox(height: 2),
          _QueueList(queueAsync: queueAsync),
          const SizedBox(height: 8),
          const SectionHeader(title: 'History', showChevron: false),
          const SizedBox(height: 2),
          _HistoryList(historyAsync: historyAsync),
        ],
      ),
    );
  }
}

class _QueueList extends ConsumerWidget {
  const _QueueList({required this.queueAsync});

  final AsyncValue<List<NzbgetGroup>> queueAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return queueAsync.when(
      data: (groups) {
        if (groups.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text('Queue is empty.'),
          );
        }
        return Column(
          children: groups
              .take(5)
              .map((group) => _QueueTile(group: group))
              .toList(),
        );
      },
      loading: () => const _NzbgetShimmer(),
      error: (error, _) => _ErrorRetry(
        message: 'Failed to load the queue',
        onRetry: () => ref.invalidate(nzbgetQueueProvider),
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({required this.group});

  final NzbgetGroup group;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subtitle = <String>[
      if (group.status.isNotEmpty) group.status,
      if (group.category.isNotEmpty) group.category,
      group.remainingLabel,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: colorScheme.surface,
        borderRadius: AppRadius.borderRadiusMd,
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: AppRadius.borderRadiusMd,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      group.name,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${group.percentage}%',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.nzbget,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: group.progress,
                  minHeight: 4,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: const AlwaysStoppedAnimation(AppColors.nzbget),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryList extends ConsumerWidget {
  const _HistoryList({required this.historyAsync});

  final AsyncValue<List<NzbgetHistoryItem>> historyAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return historyAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text('No history yet.'),
          );
        }
        return Column(
          children: items
              .take(10)
              .map((item) => _HistoryTile(item: item))
              .toList(),
        );
      },
      loading: () => const _NzbgetShimmer(),
      error: (error, _) => _ErrorRetry(
        message: 'Failed to load history',
        onRetry: () => ref.invalidate(nzbgetHistoryProvider),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.item});

  final NzbgetHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = item.failed ? AppColors.error : AppColors.success;
    final icon = item.failed
        ? Icons.error_outline_rounded
        : Icons.check_circle_rounded;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: colorScheme.surface,
        borderRadius: AppRadius.borderRadiusMd,
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: AppRadius.borderRadiusMd,
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: AppRadius.borderRadiusSm,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      [
                        if (item.category.isNotEmpty) item.category,
                        item.status,
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NzbgetShimmer extends StatelessWidget {
  const _NzbgetShimmer();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: List.generate(
        4,
        (_) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: AppRadius.borderRadiusMd,
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
