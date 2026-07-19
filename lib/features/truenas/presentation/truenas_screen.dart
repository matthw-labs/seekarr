import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/snack_bar_helper.dart';
import 'package:seekarr/core/widgets/ambient_scaffold.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/app_empty_state.dart';
import 'package:seekarr/core/widgets/app_error_state.dart';
import 'package:seekarr/core/widgets/app_skeleton.dart';
import 'package:seekarr/core/widgets/floating_bottom_nav_bar.dart';
import 'package:seekarr/core/widgets/glass_app_bar.dart';
import 'package:seekarr/core/widgets/section_header.dart';
import 'package:seekarr/core/widgets/service_kpi_peek.dart';
import 'package:seekarr/features/qbittorrent/domain/models/parse_utils.dart';
import 'package:seekarr/features/services/presentation/service_kpi_provider.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/truenas/domain/models/truenas_models.dart';
import 'package:seekarr/features/truenas/presentation/truenas_provider.dart';

/// TrueNAS SCALE dashboard: system KPIs, storage pools, alerts and services.
class TrueNasScreen extends ConsumerWidget {
  final bool showAppBar;
  final double topPadding;

  const TrueNasScreen({super.key, this.showAppBar = true, this.topPadding = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configured = ref.watch(
      currentSettingsProvider.select(
        (s) => s.isServiceConfigured(ServiceKey.truenas),
      ),
    );

    return AmbientScaffold(
      accent: ServiceKey.truenas.accent,
      appBar: showAppBar ? const GlassAppBar(title: Text('TrueNAS')) : null,
      body: configured
          ? _TrueNasDashboard(topPadding: topPadding)
          : _NotConfigured(topPadding: topPadding),
    );
  }
}

class _NotConfigured extends StatelessWidget {
  final double topPadding;
  const _NotConfigured({required this.topPadding});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top:
            topPadding +
            (topPadding > 0 ? MediaQuery.paddingOf(context).top : 0),
      ),
      child: AppEmptyState(
        icon: Icons.storage_rounded,
        title: 'TrueNAS not configured',
        message: 'Add your TrueNAS URL and API key to see system status.',
        accentColor: AppColors.truenas,
        action: FilledButton.icon(
          onPressed: () =>
              context.go('/settings/service/${ServiceKey.truenas.routeParam}'),
          icon: const Icon(Icons.settings_outlined, size: 18),
          label: const Text('Set up TrueNAS'),
        ),
      ),
    );
  }
}

class _TrueNasDashboard extends ConsumerWidget {
  final double topPadding;
  const _TrueNasDashboard({required this.topPadding});

  void _refresh(WidgetRef ref) {
    ref.invalidate(truenasDashboardProvider);
    ref.invalidate(serviceKpiProvider(ServiceKey.truenas));
    ref.invalidate(serviceSummaryProvider(ServiceKey.truenas));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(truenasDashboardProvider);
    final bottomPadding = FloatingNavBarMetrics.getScrollViewBottomPadding(
      context,
    );

    return RefreshIndicator(
      onRefresh: () async => _refresh(ref),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          top:
              topPadding +
              (topPadding > 0 ? MediaQuery.paddingOf(context).top : 0) +
              AppSpacing.sm,
        ),
        children: [
          ServiceKpiPeek(
            kpis: ref.watch(serviceKpiProvider(ServiceKey.truenas)),
            accent: AppColors.truenas,
          ),
          dashboard.when(
            loading: () => Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: AppSkeleton.listRows(),
            ),
            error: (error, _) =>
                AppErrorState(error: error, onRetry: () => _refresh(ref)),
            data: (data) =>
                _DashboardBody(data: data, bottomPadding: bottomPadding),
          ),
        ],
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  final TrueNasDashboard data;
  final double bottomPadding;

  const _DashboardBody({required this.data, required this.bottomPadding});

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
    String successMessage,
  ) async {
    try {
      await action();
      ref.invalidate(truenasDashboardProvider);
      ref.invalidate(serviceKpiProvider(ServiceKey.truenas));
      if (context.mounted) SnackBarHelper.success(context, successMessage);
    } catch (e) {
      if (context.mounted) SnackBarHelper.error(context, 'Action failed: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(truenasServiceProvider);
    final alerts = data.activeAlerts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Storage Pools', showChevron: false),
        const SizedBox(height: AppSpacing.sm),
        if (data.pools.isEmpty)
          const _InlineNote(text: 'No pools reported.')
        else
          for (final pool in data.pools)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: _PoolCard(pool: pool),
            ),
        const SizedBox(height: AppSpacing.md),

        const SectionHeader(title: 'Alerts', showChevron: false),
        const SizedBox(height: AppSpacing.sm),
        if (alerts.isEmpty)
          const _InlineNote(text: 'No active alerts. 🎉')
        else
          for (final alert in alerts)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: _AlertCard(
                alert: alert,
                onDismiss: () => _run(
                  context,
                  ref,
                  () => service.dismissAlert(alert.id),
                  'Alert dismissed',
                ),
              ),
            ),
        const SizedBox(height: AppSpacing.md),

        const SectionHeader(title: 'Services', showChevron: false),
        const SizedBox(height: AppSpacing.sm),
        for (final item in data.services)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: _ServiceTile(
              item: item,
              onToggle: (value) => _run(
                context,
                ref,
                () => value
                    ? service.startService(item.name)
                    : service.stopService(item.name),
                value ? 'Started ${item.name}' : 'Stopped ${item.name}',
              ),
            ),
          ),
        SizedBox(height: bottomPadding + AppSpacing.lg),
      ],
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

    return AppCard.surfaceOutlined(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                pool.healthy ? Icons.check_circle_rounded : Icons.error_rounded,
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
    );
  }
}

class _AlertCard extends StatelessWidget {
  final TrueNasAlert alert;
  final VoidCallback onDismiss;

  const _AlertCard({required this.alert, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final level = alert.level.toUpperCase();
    final color = (level == 'CRITICAL' || level == 'ERROR')
        ? colorScheme.error
        : (level == 'WARNING')
        ? AppColors.warning
        : AppColors.truenas;

    return AppCard.surfaceOutlined(
      borderColor: color.withValues(alpha: 0.4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(alert.message, style: theme.textTheme.bodySmall),
          ),
          const SizedBox(width: AppSpacing.sm),
          TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
        ],
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final TrueNasServiceItem item;
  final ValueChanged<bool> onToggle;

  const _ServiceTile({required this.item, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AppCard.surfaceOutlined(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: item.running ? AppColors.success : colorScheme.outline,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              item.name,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Switch(value: item.running, onChanged: onToggle),
        ],
      ),
    );
  }
}

class _InlineNote extends StatelessWidget {
  final String text;
  const _InlineNote({required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: AppRadius.borderRadiusMd,
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
