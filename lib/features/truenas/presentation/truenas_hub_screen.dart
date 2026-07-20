import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/service_theme.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/service_routes.dart';
import 'package:seekarr/core/widgets/ambient_scaffold.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/app_empty_state.dart';
import 'package:seekarr/core/widgets/floating_bottom_nav_bar.dart';
import 'package:seekarr/core/widgets/glass_app_bar.dart';
import 'package:seekarr/core/widgets/pressable_scale.dart';
import 'package:seekarr/core/widgets/service_kpi_peek.dart';
import 'package:seekarr/core/widgets/staggered_entrance.dart';
import 'package:seekarr/features/services/presentation/service_kpi_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/truenas/presentation/widgets/truenas_version_banner.dart';

/// A TrueNAS management section reachable from the hub grid.
class _TrueNasSection {
  final String title;
  final String subtitle;
  final IconData icon;
  final String route;
  final bool experimental;

  const _TrueNasSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
    this.experimental = false,
  });
}

const _sections = <_TrueNasSection>[
  _TrueNasSection(
    title: 'Dashboard',
    subtitle: 'CPU, memory & network',
    icon: Icons.speed_rounded,
    route: ServiceRoutes.truenasDashboard,
  ),
  _TrueNasSection(
    title: 'Storage',
    subtitle: 'Pools & topology',
    icon: Icons.dns_rounded,
    route: ServiceRoutes.truenasStorage,
  ),
  _TrueNasSection(
    title: 'Datasets',
    subtitle: 'ZFS datasets & snapshots',
    icon: Icons.account_tree_rounded,
    route: ServiceRoutes.truenasDatasets,
  ),
  _TrueNasSection(
    title: 'Shares',
    subtitle: 'SMB, NFS & iSCSI',
    icon: Icons.folder_shared_rounded,
    route: ServiceRoutes.truenasShares,
  ),
  _TrueNasSection(
    title: 'Data Protection',
    subtitle: 'Snapshots & replication',
    icon: Icons.shield_rounded,
    route: ServiceRoutes.truenasDataProtection,
  ),
  _TrueNasSection(
    title: 'Containers',
    subtitle: 'LXC instances',
    icon: Icons.inventory_2_rounded,
    route: ServiceRoutes.truenasContainers,
    experimental: true,
  ),
  _TrueNasSection(
    title: 'Virtual Machines',
    subtitle: 'Incus VMs',
    icon: Icons.desktop_windows_rounded,
    route: ServiceRoutes.truenasVms,
  ),
  _TrueNasSection(
    title: 'Apps',
    subtitle: 'Installed applications',
    icon: Icons.apps_rounded,
    route: ServiceRoutes.truenasApps,
  ),
  _TrueNasSection(
    title: 'Reporting',
    subtitle: 'Historical graphs',
    icon: Icons.insights_rounded,
    route: ServiceRoutes.truenasReporting,
  ),
  _TrueNasSection(
    title: 'System',
    subtitle: 'Settings & services',
    icon: Icons.settings_rounded,
    route: ServiceRoutes.truenasSystem,
  ),
];

/// TrueNAS root: a grid of management sections, each drilling into its own
/// screen. Replaces the former single-dashboard layout.
class TrueNasHubScreen extends ConsumerWidget {
  final bool showAppBar;
  final double topPadding;

  const TrueNasHubScreen({
    super.key,
    this.showAppBar = true,
    this.topPadding = 0,
  });

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
          ? _HubGrid(topPadding: topPadding)
          : _NotConfigured(topPadding: topPadding),
    );
  }
}

class _HubGrid extends ConsumerWidget {
  final double topPadding;
  const _HubGrid({required this.topPadding});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomPadding = FloatingNavBarMetrics.getScrollViewBottomPadding(
      context,
    );
    final top =
        topPadding +
        (topPadding > 0 ? MediaQuery.paddingOf(context).top : 0) +
        AppSpacing.sm;

    return ListView(
      padding: EdgeInsets.only(top: top),
      children: [
        ServiceKpiPeek(
          kpis: ref.watch(serviceKpiProvider(ServiceKey.truenas)),
          accent: AppColors.truenas,
        ),
        const TrueNasVersionBanner(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            0,
          ),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
            childAspectRatio: 1.35,
            children: [
              for (var i = 0; i < _sections.length; i++)
                StaggeredEntrance(
                  index: i,
                  child: _SectionTile(section: _sections[i]),
                ),
            ],
          ),
        ),
        SizedBox(height: bottomPadding + AppSpacing.lg),
      ],
    );
  }
}

class _SectionTile extends StatelessWidget {
  final _TrueNasSection section;
  const _SectionTile({required this.section});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final serviceTheme = serviceThemeFor(ServiceKey.truenas);

    return PressableScale(
      onTap: () => context.push(section.route),
      child: AppCard.surfaceOutlined(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: serviceTheme.softContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    section.icon,
                    size: 20,
                    color: serviceTheme.accent,
                  ),
                ),
                const Spacer(),
                if (section.experimental)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'BETA',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.warning,
                        fontWeight: FontWeight.w700,
                        fontSize: 9,
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              section.title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              section.subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
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
