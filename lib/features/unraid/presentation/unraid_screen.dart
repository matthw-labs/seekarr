import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/services/presentation/service_kpi_provider.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/unraid/domain/models/unraid_models.dart';
import 'package:seekarr/features/unraid/presentation/unraid_provider.dart';

/// Unraid dashboard: array status, disks and Docker containers. Read-only for
/// the first release (isFullConsole = false).
class UnraidScreen extends ConsumerWidget {
  const UnraidScreen({super.key, this.showAppBar = true, this.topPadding = 0});

  final bool showAppBar;
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final isConfigured = settings.isServiceConfigured(ServiceKey.unraid);

    return AmbientScaffold(
      accent: AppColors.unraid,
      appBar: showAppBar ? const GlassAppBar(title: Text('Unraid')) : null,
      body: SafeArea(
        // The shared placeholder, not a private copy: four dashboards had each
        // grown their own "this service isn't set up" card, which is the state
        // `NotConfiguredPlaceholder` exists to unify.
        child: isConfigured
            ? _UnraidDashboard(topPadding: topPadding)
            : NotConfiguredPlaceholder.forService(ServiceKey.unraid),
      ),
    );
  }
}

class _UnraidDashboard extends ConsumerWidget {
  const _UnraidDashboard({required this.topPadding});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arrayAsync = ref.watch(unraidArrayProvider);
    final dockerAsync = ref.watch(unraidDockerProvider);
    final summaryAsync = ref.watch(serviceSummaryProvider(ServiceKey.unraid));
    final isOffline = summaryAsync.maybeWhen(
      data: (summary) => !summary.isOnline,
      orElse: () => false,
    );

    if (isOffline) {
      return ServiceOfflineState(
        serviceName: ServiceKey.unraid.title,
        accent: AppColors.unraid,
        onRetry: () => _invalidateAll(ref),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        _invalidateAll(ref);
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
            kpis: ref.watch(serviceKpiProvider(ServiceKey.unraid)),
            accent: AppColors.unraid,
          ),
          const SizedBox(height: 8),
          const SectionHeader(title: 'Array disks', showChevron: false),
          const SizedBox(height: 2),
          _DiskList(arrayAsync: arrayAsync),
          const SizedBox(height: 8),
          const SectionHeader(title: 'Docker', showChevron: false),
          const SizedBox(height: 2),
          _DockerList(dockerAsync: dockerAsync),
        ],
      ),
    );
  }
}

void _invalidateAll(WidgetRef ref) {
  ref.invalidate(unraidArrayProvider);
  ref.invalidate(unraidDockerProvider);
  ref.invalidate(serviceKpiProvider(ServiceKey.unraid));
  ref.invalidate(serviceSummaryProvider(ServiceKey.unraid));
}

class _DiskList extends ConsumerWidget {
  const _DiskList({required this.arrayAsync});

  final AsyncValue<UnraidArray> arrayAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return arrayAsync.when(
      data: (array) {
        if (array.disks.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text('No array disks reported.'),
          );
        }
        return Column(
          children: array.disks.map((disk) => _DiskTile(disk: disk)).toList(),
        );
      },
      loading: () => const _UnraidShimmer(),
      error: (error, _) => _ErrorRetry(
        message: 'Failed to load the array',
        onRetry: () => ref.invalidate(unraidArrayProvider),
      ),
    );
  }
}

class _DiskTile extends StatelessWidget {
  const _DiskTile({required this.disk});

  final UnraidDisk disk;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tempLabel = disk.temp != null ? '${disk.temp}°C' : null;
    final hot = (disk.temp ?? 0) >= 45;

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
                  color: AppColors.unraid.withValues(alpha: 0.12),
                  borderRadius: AppRadius.borderRadiusSm,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.storage_rounded,
                  size: 16,
                  color: AppColors.unraid,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      disk.name,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium!.weight(FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (disk.status.isNotEmpty)
                      Text(
                        disk.status,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (tempLabel != null) ...[
                const SizedBox(width: 8),
                Text(
                  tempLabel,
                  style: Theme.of(context).textTheme.labelMedium!
                      .weight(FontWeight.w700)
                      .tabular
                      .copyWith(
                        color: hot
                            ? AppColors.warning
                            : colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DockerList extends ConsumerWidget {
  const _DockerList({required this.dockerAsync});

  final AsyncValue<List<UnraidDockerContainer>> dockerAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return dockerAsync.when(
      data: (containers) {
        if (containers.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text('No containers reported.'),
          );
        }
        final sorted = [
          ...containers,
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return Column(
          children: sorted
              .map((container) => _ContainerTile(container: container))
              .toList(),
        );
      },
      loading: () => const _UnraidShimmer(),
      error: (error, _) => _ErrorRetry(
        message: 'Failed to load containers',
        onRetry: () => ref.invalidate(unraidDockerProvider),
      ),
    );
  }
}

class _ContainerTile extends StatelessWidget {
  const _ContainerTile({required this.container});

  final UnraidDockerContainer container;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = container.running
        ? AppColors.success
        : colorScheme.onSurfaceVariant;

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
                child: Icon(
                  container.running
                      ? Icons.play_circle_rounded
                      : Icons.stop_circle_rounded,
                  size: 16,
                  color: color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      container.name,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium!.weight(FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (container.status.isNotEmpty)
                      Text(
                        container.status,
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

class _UnraidShimmer extends StatelessWidget {
  const _UnraidShimmer();

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
