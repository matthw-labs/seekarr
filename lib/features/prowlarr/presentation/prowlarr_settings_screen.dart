import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/route_utils.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_indexer_actions.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';

/// Hub for everything Prowlarr keeps under Settings: the four field-driven
/// resources, sync profiles and tags.
///
/// Each row carries a live count so the screen says what is configured without
/// being opened — a Prowlarr with no app connected is the single most common
/// reason indexers never reach Radarr/Sonarr.
class ProwlarrSettingsScreen extends ConsumerWidget {
  const ProwlarrSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.prowlarr.withValues(alpha: 0.12),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          tooltip: 'Back',
          onPressed: () => RouteUtils.popOrGo(context, ServiceRoutes.prowlarr),
        ),
        title: const Text('Prowlarr settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: [
          for (final kind in ProwlarrProviderKind.values)
            _SettingsRow(
              icon: kind.icon,
              title: kind.title,
              subtitle: _providerSubtitle(kind),
              count: ref
                  .watch(prowlarrProvidersProvider(kind))
                  .asData
                  ?.value
                  .length,
              onTap: () =>
                  context.push(ServiceRoutes.prowlarrSettingsSection(kind)),
            ),
          _SettingsRow(
            icon: Icons.tune_rounded,
            title: 'Sync profiles',
            subtitle: 'Search and RSS settings pushed to the apps',
            count: ref.watch(prowlarrAppProfilesProvider).asData?.value.length,
            onTap: () => context.push(ServiceRoutes.prowlarrSyncProfiles),
          ),
          _SettingsRow(
            icon: Icons.sell_outlined,
            title: 'Tags',
            subtitle: 'Decide which apps receive which indexers',
            count: ref.watch(prowlarrTagsProvider).asData?.value.length,
            onTap: () => context.push(ServiceRoutes.prowlarrTags),
          ),
          const Divider(height: AppSpacing.xl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: OutlinedButton.icon(
              onPressed: () => syncAppIndexersFlow(context, ref),
              icon: const Icon(Icons.sync_rounded, size: 18),
              label: const Text('Sync app indexers'),
            ),
          ),
        ],
      ),
    );
  }

  static String _providerSubtitle(ProwlarrProviderKind kind) => switch (kind) {
    ProwlarrProviderKind.application =>
      'Radarr, Sonarr, Lidarr… that receive your indexers',
    ProwlarrProviderKind.downloadClient =>
      'Used when a grab is redirected through Prowlarr',
    ProwlarrProviderKind.notification => 'Where Prowlarr reports events',
    ProwlarrProviderKind.indexerProxy =>
      'FlareSolverr, HTTP or SOCKS proxies for indexers',
  };
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// Null while the count is still loading (or failed), which renders no badge
  /// rather than a misleading zero.
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Material(
        color: colorScheme.surface,
        borderRadius: AppRadius.borderRadiusMd,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.borderRadiusMd,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: AppRadius.borderRadiusMd,
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.prowlarr.withValues(alpha: 0.12),
                    borderRadius: AppRadius.borderRadiusSm,
                  ),
                  child: Icon(icon, size: 18, color: AppColors.prowlarr),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(
                          context,
                        ).textTheme.titleSmall!.weight(FontWeight.w700),
                      ),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
                if (count != null)
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.sm),
                    child: Text(
                      '$count',
                      style: Theme.of(context).textTheme.titleSmall!
                          .weight(FontWeight.w800)
                          .tabular
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
