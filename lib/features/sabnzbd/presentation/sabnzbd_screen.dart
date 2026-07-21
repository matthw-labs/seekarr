import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/sabnzbd/domain/models/sabnzbd_models.dart';
import 'package:seekarr/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:seekarr/features/services/presentation/service_kpi_provider.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// SABnzbd dashboard: live queue and recent history. Read-only for the first
/// release.
class SabnzbdScreen extends ConsumerWidget {
  const SabnzbdScreen({super.key, this.showAppBar = true, this.topPadding = 0});

  final bool showAppBar;
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final isConfigured = settings.isServiceConfigured(ServiceKey.sabnzbd);

    return AmbientScaffold(
      accent: AppColors.sabnzbd,
      appBar: showAppBar ? const GlassAppBar(title: Text('SABnzbd')) : null,
      body: SafeArea(
        child: isConfigured
            ? _SabnzbdDashboard(topPadding: topPadding)
            : _SabnzbdNotConfigured(
                onOpenSettings: () => context.go(
                  '/settings/service/${ServiceKey.sabnzbd.routeParam}',
                ),
              ),
      ),
    );
  }
}

class _SabnzbdNotConfigured extends StatelessWidget {
  const _SabnzbdNotConfigured({required this.onOpenSettings});

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
              Icons.cloud_download_rounded,
              size: 48,
              color: AppColors.sabnzbd,
            ),
            const SizedBox(height: 12),
            const Text(
              'SABnzbd is not configured yet.',
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

class _SabnzbdDashboard extends ConsumerWidget {
  const _SabnzbdDashboard({required this.topPadding});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(sabnzbdQueueProvider);
    final historyAsync = ref.watch(sabnzbdHistoryProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(sabnzbdQueueProvider);
        ref.invalidate(sabnzbdHistoryProvider);
        ref.invalidate(serviceKpiProvider(ServiceKey.sabnzbd));
        ref.invalidate(serviceSummaryProvider(ServiceKey.sabnzbd));
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
            kpis: ref.watch(serviceKpiProvider(ServiceKey.sabnzbd)),
            accent: AppColors.sabnzbd,
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

  final AsyncValue<SabnzbdQueue> queueAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return queueAsync.when(
      data: (queue) {
        if (queue.slots.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text('Queue is empty.'),
          );
        }
        return Column(
          children: queue.slots
              .take(5)
              .map((slot) => _QueueTile(slot: slot))
              .toList(),
        );
      },
      loading: () => const _SabnzbdShimmer(),
      error: (error, _) => _ErrorRetry(
        message: 'Failed to load the queue',
        onRetry: () => ref.invalidate(sabnzbdQueueProvider),
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({required this.slot});

  final SabnzbdQueueSlot slot;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subtitle = <String>[
      if (slot.status.isNotEmpty) slot.status,
      if (slot.timeLeft.isNotEmpty) slot.timeLeft,
      slot.sizeLeftLabel,
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
                      slot.filename,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${slot.percentage}%',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.sabnzbd,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: slot.progress,
                  minHeight: 4,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: const AlwaysStoppedAnimation(AppColors.sabnzbd),
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

  final AsyncValue<List<SabnzbdHistorySlot>> historyAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return historyAsync.when(
      data: (slots) {
        if (slots.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text('No history yet.'),
          );
        }
        return Column(
          children: slots
              .take(10)
              .map((slot) => _HistoryTile(slot: slot))
              .toList(),
        );
      },
      loading: () => const _SabnzbdShimmer(),
      error: (error, _) => _ErrorRetry(
        message: 'Failed to load history',
        onRetry: () => ref.invalidate(sabnzbdHistoryProvider),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.slot});

  final SabnzbdHistorySlot slot;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = slot.failed ? AppColors.error : AppColors.success;
    final icon = slot.failed
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
                      slot.name,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      slot.failMessage ??
                          [
                            if (slot.category.isNotEmpty) slot.category,
                            slot.status,
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

class _SabnzbdShimmer extends StatelessWidget {
  const _SabnzbdShimmer();

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
