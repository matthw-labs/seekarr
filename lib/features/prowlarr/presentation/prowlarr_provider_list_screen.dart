import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/route_utils.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider_actions.dart';
import 'package:cupola/features/prowlarr/presentation/widgets/prowlarr_list_shimmer.dart';

/// One screen for all four field-driven resources: apps, download clients,
/// notifications and indexer proxies.
///
/// They differ only in what a row summarises, so the list, the add button, the
/// row menu and "test all" are written once and parameterised by [kind].
class ProwlarrProviderListScreen extends ConsumerWidget {
  const ProwlarrProviderListScreen({super.key, required this.kind});

  final ProwlarrProviderKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providersAsync = ref.watch(prowlarrProvidersProvider(kind));
    final tagLabels = ref.watch(prowlarrTagLabelsProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.prowlarr.withValues(alpha: 0.12),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          tooltip: 'Back',
          onPressed: () =>
              RouteUtils.popOrGo(context, ServiceRoutes.prowlarrSettings),
        ),
        title: Text(kind.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add ${kind.singular}',
            onPressed: () => addProviderFlow(context, ref, kind),
          ),
          IconButton(
            icon: const Icon(Icons.network_check_rounded),
            tooltip: 'Test all',
            onPressed: () => testAllProvidersFlow(context, ref, kind),
          ),
        ],
      ),
      body: providersAsync.when(
        data: (providers) {
          if (providers.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(kind.icon, size: 40, color: AppColors.prowlarr),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'No ${kind.title.toLowerCase()} configured.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.icon(
                      onPressed: () => addProviderFlow(context, ref, kind),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text('Add ${kind.singular}'),
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(prowlarrProvidersProvider(kind));
              await Future<void>.delayed(const Duration(milliseconds: 300));
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              itemCount: providers.length,
              itemBuilder: (context, index) {
                final provider = providers[index];
                return _ProviderRow(
                  kind: kind,
                  resource: provider,
                  tagLabels: provider.tags
                      .map((id) => tagLabels[id])
                      .whereType<String>()
                      .toList(growable: false),
                  onTap: () => editProviderFlow(context, ref, kind, provider),
                  onLongPress: () =>
                      _showRowActions(context, ref, kind, provider),
                );
              },
            ),
          );
        },
        loading: () =>
            const ProwlarrListShimmer(count: 4, verticalPadding: AppSpacing.sm),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Failed to load the ${kind.title.toLowerCase()}'),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: () =>
                      ref.invalidate(prowlarrProvidersProvider(kind)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showRowActions(
    BuildContext context,
    WidgetRef ref,
    ProwlarrProviderKind kind,
    ProwlarrProviderResource resource,
  ) async {
    await AppBottomSheet.show<void>(
      context: context,
      title: resource.name ?? kind.singular,
      subtitle: resource.displayImplementation.isEmpty
          ? null
          : resource.displayImplementation,
      icon: kind.icon,
      accent: AppColors.prowlarr,
      builder: (sheetContext) => Column(
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              editProviderFlow(context, ref, kind, resource);
            },
          ),
          ListTile(
            leading: const Icon(Icons.network_check_rounded),
            title: const Text('Test'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              testProviderFlow(context, ref, kind, resource);
            },
          ),
          ListTile(
            leading: Icon(
              Icons.delete_outline_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () {
              Navigator.of(sheetContext).pop();
              deleteProviderFlow(context, ref, kind, resource);
            },
          ),
        ],
      ),
    );
  }
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    required this.kind,
    required this.resource,
    required this.tagLabels,
    required this.onTap,
    required this.onLongPress,
  });

  final ProwlarrProviderKind kind;
  final ProwlarrProviderResource resource;
  final List<String> tagLabels;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subtitleParts = <String>[
      resource.displayImplementation,
      if (kind == ProwlarrProviderKind.application &&
          resource.syncLevel != null)
        prowlarrSyncLevelLabel(resource.syncLevel!),
      if (kind == ProwlarrProviderKind.downloadClient) ...[
        if (resource.protocol != null) resource.protocol!,
        if (resource.priority != null) 'priority ${resource.priority}',
      ],
      if (kind == ProwlarrProviderKind.notification)
        _notificationEvents(resource),
      ...tagLabels,
    ].where((part) => part.isNotEmpty).toList(growable: false);

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
          onLongPress: onLongPress,
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
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: resource.isActive
                        ? AppColors.success
                        : colorScheme.onSurfaceVariant,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        resource.name ?? resource.displayImplementation,
                        style: Theme.of(
                          context,
                        ).textTheme.titleSmall!.weight(FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitleParts.isNotEmpty)
                        Text(
                          subtitleParts.join(' · '),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
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

  /// Which events a notification is subscribed to, so a row says what it will
  /// actually do rather than just naming its implementation.
  static String _notificationEvents(ProwlarrProviderResource resource) {
    final events = <String>[
      if (resource.flag('onGrab')) 'grabs',
      if (resource.flag('onHealthIssue')) 'health',
      if (resource.flag('onHealthRestored')) 'health restored',
      if (resource.flag('onApplicationUpdate')) 'updates',
    ];
    return events.isEmpty ? 'no events' : events.join(', ');
  }
}

/// Human label for an application's `syncLevel`.
String prowlarrSyncLevelLabel(String raw) => switch (raw) {
  'fullSync' => 'Full sync',
  'addOnly' => 'Add only',
  'disabled' => 'No sync',
  _ => raw,
};
