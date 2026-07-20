import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/app_dialog.dart';
import 'package:seekarr/core/widgets/app_error_state.dart';
import 'package:seekarr/core/widgets/app_skeleton.dart';
import 'package:seekarr/core/widgets/section_header.dart';
import 'package:seekarr/features/qbittorrent/domain/models/parse_utils.dart';
import 'package:seekarr/features/truenas/domain/models/virt_instance.dart';
import 'package:seekarr/features/truenas/presentation/truenas_actions.dart';
import 'package:seekarr/features/truenas/presentation/truenas_provider.dart';
import 'package:seekarr/features/truenas/presentation/virt/truenas_virt_providers.dart';
import 'package:seekarr/features/truenas/presentation/virt/truenas_virt_screen.dart';
import 'package:seekarr/features/truenas/presentation/widgets/truenas_info_row.dart';
import 'package:seekarr/features/truenas/presentation/widgets/truenas_section_scaffold.dart';

class TrueNasVirtDetailScreen extends ConsumerWidget {
  final String id;
  final String type;
  const TrueNasVirtDetailScreen({
    super.key,
    required this.id,
    required this.type,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instance = ref.watch(truenasVirtInstanceProvider(id));

    return TrueNasSectionScaffold(
      title: id,
      actions: [
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded),
          tooltip: 'Delete',
          onPressed: () async {
            final result = await showAppConfirmDialog(
              context: context,
              title: 'Delete "$id"?',
              message: 'This permanently deletes the instance and its disks.',
              confirmLabel: 'Delete',
              destructive: true,
            );
            if (!result.confirmed || !context.mounted) return;
            final ok = await runTrueNasAction(
              context,
              ref,
              action: () => ref.read(truenasVirtApiProvider).delete(id),
              successMessage: 'Deleted "$id"',
              failureMessage: 'Could not delete',
              invalidate: [truenasVirtInstancesProvider(type)],
            );
            if (ok && context.mounted) context.pop();
          },
        ),
      ],
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(truenasVirtInstanceProvider(id));
          ref.invalidate(truenasVirtDevicesProvider(id));
        },
        child: instance.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [AppSkeleton.detailBody()],
          ),
          error: (e, _) => ListView(
            children: [
              AppErrorState(
                error: e,
                onRetry: () => ref.invalidate(truenasVirtInstanceProvider(id)),
              ),
            ],
          ),
          data: (data) => data == null
              ? ListView(
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Text('Instance not found.'),
                    ),
                  ],
                )
              : _DetailBody(instance: data, type: type),
        ),
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  final TrueNasVirtInstance instance;
  final String type;
  const _DetailBody({required this.instance, required this.type});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(truenasVirtDevicesProvider(instance.id));

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: [
        AppCard.surfaceOutlined(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TrueNasInfoRow(
                      label: 'Status',
                      value: instance.status,
                    ),
                  ),
                  VirtLifecycleButton(instance: instance, type: type),
                ],
              ),
              TrueNasInfoRow(label: 'Type', value: instance.type),
              TrueNasInfoRow(label: 'Image', value: instance.image),
              TrueNasInfoRow(
                label: 'vCPUs',
                value: instance.cpuCount?.toString(),
              ),
              TrueNasInfoRow(
                label: 'Memory',
                value: instance.memoryBytes != null
                    ? formatSize(instance.memoryBytes!)
                    : null,
              ),
              TrueNasInfoRow(
                label: 'Autostart',
                value: instance.autostart ? 'Yes' : 'No',
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const SectionHeader(title: 'Devices', showChevron: false),
        const SizedBox(height: AppSpacing.sm),
        devices.when(
          loading: () => AppSkeleton.listRows(count: 3),
          error: (e, _) => AppCard.surfaceOutlined(
            child: Text('$e', style: Theme.of(context).textTheme.bodySmall),
          ),
          data: (list) => list.isEmpty
              ? AppCard.surfaceOutlined(
                  child: Text(
                    'No devices.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : Column(
                  children: [
                    for (final device in list)
                      AppCard.surfaceOutlined(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                device.name,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            Text(
                              device.type,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
