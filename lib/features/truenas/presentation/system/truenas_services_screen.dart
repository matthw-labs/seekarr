import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/app_error_state.dart';
import 'package:seekarr/core/widgets/app_skeleton.dart';
import 'package:seekarr/features/truenas/domain/models/service_item.dart';
import 'package:seekarr/features/truenas/presentation/shares/truenas_shares_providers.dart';
import 'package:seekarr/features/truenas/presentation/truenas_actions.dart';
import 'package:seekarr/features/truenas/presentation/truenas_provider.dart';
import 'package:seekarr/features/truenas/presentation/widgets/truenas_section_scaffold.dart';

class TrueNasServicesScreen extends ConsumerWidget {
  const TrueNasServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(truenasServicesProvider);

    return TrueNasSectionScaffold(
      title: 'Services',
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(truenasServicesProvider),
        child: services.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [AppSkeleton.listRows()],
          ),
          error: (e, _) => ListView(
            children: [
              AppErrorState(
                error: e,
                onRetry: () => ref.invalidate(truenasServicesProvider),
              ),
            ],
          ),
          data: (list) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            children: [
              for (final item in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _ServiceTile(item: item),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceTile extends ConsumerWidget {
  final TrueNasServiceItem item;
  const _ServiceTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final api = ref.read(truenasSystemApiProvider);

    return AppCard.surfaceOutlined(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: item.running
                  ? AppColors.success
                  : theme.colorScheme.outline,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (item.enabled)
                  Text(
                    'Starts on boot',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (item.id != null)
            IconButton(
              tooltip: item.enabled ? 'Disable autostart' : 'Enable autostart',
              icon: Icon(
                item.enabled ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                size: 18,
                color: item.enabled
                    ? AppColors.warning
                    : theme.colorScheme.outline,
              ),
              onPressed: () => runTrueNasAction(
                context,
                ref,
                action: () => api.setServiceAutostart(item.id!, !item.enabled),
                successMessage: item.enabled
                    ? 'Autostart disabled'
                    : 'Autostart enabled',
                failureMessage: 'Could not update service',
                invalidate: [truenasServicesProvider],
              ),
            ),
          Switch(
            value: item.running,
            onChanged: (value) => runTrueNasAction(
              context,
              ref,
              action: () => value
                  ? api.startService(item.name)
                  : api.stopService(item.name),
              successMessage: value
                  ? 'Started ${item.name}'
                  : 'Stopped ${item.name}',
              failureMessage: 'Action failed',
              invalidate: [truenasServicesProvider],
            ),
          ),
        ],
      ),
    );
  }
}
