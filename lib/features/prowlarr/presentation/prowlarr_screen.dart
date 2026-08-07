import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_history_format.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_indexer_actions.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider_list_screen.dart'
    show prowlarrSyncLevelLabel;
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/prowlarr/presentation/widgets/prowlarr_indexer_tile.dart';
import 'package:cupola/features/prowlarr/presentation/widgets/prowlarr_list_shimmer.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Prowlarr service dashboard: indexer overview, usage stats, recent activity
/// and the write actions the web UI puts on its indexer page — add an indexer,
/// test them all, push them to the connected apps. Per-indexer editing lives in
/// the library and detail screens.
class ProwlarrScreen extends ConsumerWidget {
  const ProwlarrScreen({
    super.key,
    this.showAppBar = true,
    this.topPadding = 0,
  });

  final bool showAppBar;
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final isConfigured = settings.isServiceConfigured(ServiceKey.prowlarr);

    return AmbientScaffold(
      accent: AppColors.prowlarr,
      appBar: showAppBar ? const GlassAppBar(title: Text('Prowlarr')) : null,
      body: SafeArea(
        child: isConfigured
            ? _ProwlarrDashboard(topPadding: topPadding)
            : _ProwlarrNotConfigured(
                onOpenSettings: () => _openSettings(context),
              ),
      ),
    );
  }

  void _openSettings(BuildContext context) {
    context.go('/settings/service/${ServiceKey.prowlarr.routeParam}');
  }
}

class _ProwlarrNotConfigured extends StatelessWidget {
  const _ProwlarrNotConfigured({required this.onOpenSettings});

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
              Icons.travel_explore_rounded,
              size: 48,
              color: AppColors.prowlarr,
            ),
            const SizedBox(height: 12),
            const Text(
              'Prowlarr is not configured yet.',
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

class _ProwlarrDashboard extends ConsumerWidget {
  const _ProwlarrDashboard({required this.topPadding});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final indexersAsync = ref.watch(prowlarrIndexersProvider);
    final historyAsync = ref.watch(prowlarrRecentHistoryProvider);
    final healthAsync = ref.watch(prowlarrHealthProvider);
    final statusAsync = ref.watch(prowlarrIndexerStatusProvider);
    final disabledIds = statusAsync.maybeWhen(
      data: (statuses) => statuses.map((s) => s.indexerId).toSet(),
      orElse: () => const <int>{},
    );

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(prowlarrIndexersProvider);
        ref.invalidate(prowlarrIndexerStatsProvider);
        ref.invalidate(prowlarrIndexerStatusProvider);
        ref.invalidate(prowlarrRecentHistoryProvider);
        ref.invalidate(prowlarrHealthProvider);
        ref.invalidate(serviceKpiProvider(ServiceKey.prowlarr));
        ref.invalidate(serviceSummaryProvider(ServiceKey.prowlarr));
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
            kpis: ref.watch(serviceKpiProvider(ServiceKey.prowlarr)),
            accent: AppColors.prowlarr,
          ),
          const SizedBox(height: 8),
          _HealthBanner(healthAsync: healthAsync),
          const _QuickActions(),
          SectionHeader(
            title: 'Indexers',
            showChevron: true,
            onTap: () => context.push(ServiceRoutes.prowlarrLibrary),
          ),
          const SizedBox(height: 2),
          _IndexerList(indexersAsync: indexersAsync, disabledIds: disabledIds),
          const SizedBox(height: 8),
          SectionHeader(
            title: 'Apps',
            showChevron: true,
            onTap: () => context.push(
              ServiceRoutes.prowlarrSettingsSection(
                ProwlarrProviderKind.application,
              ),
            ),
          ),
          const SizedBox(height: 2),
          const _AppsList(),
          const SizedBox(height: 8),
          const SectionHeader(title: 'Recent Activity', showChevron: false),
          const SizedBox(height: 2),
          _HistoryList(historyAsync: historyAsync),
        ],
      ),
    );
  }
}

/// Compact health summary shown only when Prowlarr reports issues.
class _HealthBanner extends StatelessWidget {
  const _HealthBanner({required this.healthAsync});

  final AsyncValue<List<ProwlarrHealthIssue>> healthAsync;

  @override
  Widget build(BuildContext context) {
    return healthAsync.maybeWhen(
      data: (issues) {
        if (issues.isEmpty) return const SizedBox.shrink();
        final errors = issues.where((i) => i.isError).length;
        final colorScheme = Theme.of(context).colorScheme;
        final accent = errors > 0 ? AppColors.error : AppColors.warning;
        final label = errors > 0
            ? '$errors error${errors == 1 ? '' : 's'}, ${issues.length} issue${issues.length == 1 ? '' : 's'}'
            : '${issues.length} warning${issues.length == 1 ? '' : 's'}';
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: AppRadius.borderRadiusMd,
              border: Border.all(color: accent.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    issues.first.message ?? 'Health issues detected',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: AppRadius.borderRadiusSm,
                  ),
                  child: Text(
                    label,
                    // Error/issue tallies move as health changes — tabular so
                    // the badge does not reflow as the digits update.
                    style: Theme.of(context).textTheme.labelSmall!
                        .weight(FontWeight.w800)
                        .tabular
                        .copyWith(color: accent),
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

/// The three actions the web UI keeps one click away on its indexer page.
class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              onPressed: () => addIndexerFlow(context, ref),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => syncAppIndexersFlow(context, ref),
              icon: const Icon(Icons.sync_rounded, size: 18),
              label: const Text('Sync apps'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => testAllIndexersFlow(context, ref),
              icon: const Icon(Icons.network_check_rounded, size: 18),
              label: const Text('Test all'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Applications Prowlarr pushes its indexers to, with their sync level.
class _AppsList extends ConsumerWidget {
  const _AppsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return ref
        .watch(prowlarrApplicationsProvider)
        .when(
          data: (apps) {
            if (apps.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text('No applications connected to Prowlarr.'),
              );
            }
            return Column(
              children: [
                for (final app in apps)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.xs,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        border: Border.all(color: colorScheme.outlineVariant),
                        borderRadius: AppRadius.borderRadiusMd,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              // Applications carry no `enable` flag of their
                              // own — a sync level of `disabled` is "off".
                              color: app.isActive
                                  ? AppColors.success
                                  : colorScheme.onSurfaceVariant,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Text(
                              app.name ?? app.implementation ?? 'Application',
                              style: Theme.of(
                                context,
                              ).textTheme.titleSmall!.weight(FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (app.syncLevel != null)
                            Text(
                              prowlarrSyncLevelLabel(app.syncLevel!),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
          loading: () => const ProwlarrListShimmer(count: 2),
          error: (error, _) => _ErrorRetry(
            message: 'Failed to load applications',
            onRetry: () => ref.invalidate(prowlarrApplicationsProvider),
          ),
        );
  }
}

class _IndexerList extends ConsumerWidget {
  const _IndexerList({required this.indexersAsync, required this.disabledIds});

  final AsyncValue<List<ProwlarrIndexer>> indexersAsync;
  final Set<int> disabledIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return indexersAsync.when(
      data: (indexers) {
        if (indexers.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text('No indexers configured.'),
          );
        }
        final sorted = [...indexers]
          ..sort(
            (a, b) => (a.name ?? '').toLowerCase().compareTo(
              (b.name ?? '').toLowerCase(),
            ),
          );
        // Dashboard shows a preview; the full list lives in the library screen.
        return Column(
          children: sorted
              .take(5)
              .map(
                (indexer) => ProwlarrIndexerTile.preview(
                  indexer: indexer,
                  failing: disabledIds.contains(indexer.id),
                ),
              )
              .toList(),
        );
      },
      loading: () => const ProwlarrListShimmer(),
      error: (error, _) => _ErrorRetry(
        message: 'Failed to load indexers',
        onRetry: () => ref.invalidate(prowlarrIndexersProvider),
      ),
    );
  }
}

class _HistoryList extends ConsumerWidget {
  const _HistoryList({required this.historyAsync});

  final AsyncValue<ProwlarrHistoryPage> historyAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return historyAsync.when(
      data: (page) {
        if (page.records.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text('No recent activity yet.'),
          );
        }
        return Column(
          children: page.records
              .take(10)
              .map((item) => _HistoryTile(item: item))
              .toList(),
        );
      },
      loading: () => const ProwlarrListShimmer(),
      error: (error, _) => _ErrorRetry(
        message: 'Failed to load recent activity',
        onRetry: () => ref.invalidate(prowlarrRecentHistoryProvider),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.item});

  final ProwlarrHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final event = prowlarrEventStyle(item);
    final source = prowlarrHistorySource(item);
    final title = prowlarrHistoryTitle(item);
    final subtitleParts = <String>[
      if (source != null) source,
      if (item.date != null) prowlarrRelativeTime(item.date!),
    ];

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
                  color: event.color.withValues(alpha: 0.12),
                  borderRadius: AppRadius.borderRadiusSm,
                ),
                alignment: Alignment.center,
                child: Icon(event.icon, size: 16, color: event.color),
              ),
              const SizedBox(width: 10),
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
                    if (subtitleParts.isNotEmpty)
                      Text(
                        subtitleParts.join(' · '),
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
      ),
    );
  }
}

/// Inline error placeholder with a retry action so failures are
/// distinguishable from the loading shimmer state.
class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      height: 120,
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
