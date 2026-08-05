import 'package:flutter/material.dart';
import 'package:seekarr/core/widgets/floating_bottom_nav_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/service_routes.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/app_empty_state.dart';
import 'package:seekarr/core/widgets/app_error_state.dart';
import 'package:seekarr/core/widgets/app_skeleton.dart';
import 'package:seekarr/core/widgets/pressable_scale.dart';
import 'package:seekarr/features/qbittorrent/domain/models/parse_utils.dart';
import 'package:seekarr/features/truenas/domain/models/virt_instance.dart';
import 'package:seekarr/features/truenas/presentation/truenas_actions.dart';
import 'package:seekarr/features/truenas/presentation/truenas_provider.dart';
import 'package:seekarr/features/truenas/presentation/virt/truenas_virt_actions.dart';
import 'package:seekarr/features/truenas/presentation/virt/truenas_virt_providers.dart';
import 'package:seekarr/features/truenas/presentation/widgets/truenas_section_scaffold.dart';

/// A list of Incus instances of a given [type] (`CONTAINER` or `VM`).
class TrueNasVirtScreen extends ConsumerWidget {
  final String type;
  final String title;
  final bool experimental;

  const TrueNasVirtScreen({
    super.key,
    required this.type,
    required this.title,
    this.experimental = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final global = ref.watch(truenasVirtGlobalProvider);
    final instances = ref.watch(truenasVirtInstancesProvider(type));

    return TrueNasSectionScaffold(
      title: title,
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.truenas,
        onPressed: () => createInstanceFlow(context, ref, type: type),
        child: const Icon(Icons.add_rounded),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(truenasVirtGlobalProvider);
          ref.invalidate(truenasVirtInstancesProvider(type));
        },
        child: global.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [AppSkeleton.listRows()],
          ),
          error: (e, _) => ListView(
            children: [
              AppErrorState(
                error: e,
                onRetry: () => ref.invalidate(truenasVirtGlobalProvider),
              ),
            ],
          ),
          // Legacy KVM VMs don't need Incus to be configured, so only gate
          // containers (and Incus VMs) on the virtualization pool being ready.
          data: (cfg) => (type.toUpperCase() != 'VM' && !cfg.isReady)
              ? ListView(
                  children: const [
                    Padding(
                      padding: EdgeInsets.only(top: AppSpacing.xxl),
                      child: AppEmptyState(
                        icon: Icons.settings_suggest_rounded,
                        title: 'Virtualization not configured',
                        message:
                            'Choose a storage pool for instances in the '
                            'TrueNAS web UI (Virtualization) to get started.',
                        accentColor: AppColors.truenas,
                      ),
                    ),
                  ],
                )
              : _InstanceList(
                  type: type,
                  instances: instances,
                  experimental: experimental,
                ),
        ),
      ),
    );
  }
}

class _InstanceList extends ConsumerWidget {
  final String type;
  final AsyncValue<List<TrueNasVirtInstance>> instances;
  final bool experimental;

  const _InstanceList({
    required this.type,
    required this.instances,
    required this.experimental,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return instances.when(
      loading: () => ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [AppSkeleton.listRows()],
      ),
      error: (e, _) => ListView(
        children: [
          AppErrorState(
            error: e,
            onRetry: () => ref.invalidate(truenasVirtInstancesProvider(type)),
          ),
        ],
      ),
      data: (list) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: [
          if (experimental)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _ExperimentalNote(),
            ),
          if (list.isEmpty)
            AppCard.surfaceOutlined(
              child: Text(
                'No instances yet.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            for (final instance in list)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _InstanceCard(instance: instance, type: type),
              ),
        ],
      ),
    );
  }
}

class _ExperimentalNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.md),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.science_rounded, size: 16, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'LXC containers are experimental in TrueNAS SCALE.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _InstanceCard extends ConsumerWidget {
  final TrueNasVirtInstance instance;
  final String type;
  const _InstanceCard({required this.instance, required this.type});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final route = type.toUpperCase() == 'VM'
        ? ServiceRoutes.truenasVm(instance.id)
        : ServiceRoutes.truenasContainer(instance.id);
    final specs = <String>[
      if (instance.cpuCount != null) '${instance.cpuCount} vCPU',
      if (instance.memoryBytes != null) formatSize(instance.memoryBytes!),
      if (instance.image != null) instance.image!,
    ];

    return PressableScale(
      onTap: () => context.push(route),
      child: AppCard.surfaceOutlined(
        child: Row(
          children: [
            _StatusDot(running: instance.isRunning),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          instance.name,
                          style: theme.textTheme.titleSmall!.weight(
                            FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (instance.autostart) ...[
                        const SizedBox(width: AppSpacing.sm),
                        const _AutostartBadge(),
                      ],
                    ],
                  ),
                  if (specs.isNotEmpty)
                    Text(
                      specs.join(' · '),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            VirtLifecycleButton(instance: instance, type: type),
          ],
        ),
      ),
    );
  }
}

/// Small pill indicating the instance is set to auto-start on boot.
class _AutostartBadge extends StatelessWidget {
  const _AutostartBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.truenas.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.power_settings_new_rounded,
            size: 11,
            color: AppColors.truenas,
          ),
          const SizedBox(width: 3),
          Text(
            'AUTOSTART',
            style: theme.textTheme.labelSmall!
                .weight(FontWeight.w800)
                .copyWith(color: AppColors.truenas),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final bool running;
  const _StatusDot({required this.running});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: running
            ? AppColors.success
            : Theme.of(context).colorScheme.outline,
      ),
    );
  }
}

/// Start/stop/restart control shared by list cards and the detail screen.
class VirtLifecycleButton extends ConsumerWidget {
  final TrueNasVirtInstance instance;
  final String type;
  const VirtLifecycleButton({
    super.key,
    required this.instance,
    required this.type,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(truenasVirtApiProvider);
    final legacyId = instance.legacyVmId;
    void invalidate() {
      ref.invalidate(truenasVirtInstancesProvider(type));
      ref.invalidate(truenasVirtInstanceProvider(instance.id));
    }

    // Route lifecycle calls to the legacy `vm.*` API for KVM VMs, or to Incus
    // (`virt.instance.*`) otherwise.
    Future<dynamic> doStop() =>
        legacyId != null ? api.vmStop(legacyId) : api.stop(instance.id);
    Future<dynamic> doRestart() =>
        legacyId != null ? api.vmRestart(legacyId) : api.restart(instance.id);
    Future<dynamic> doStart() =>
        legacyId != null ? api.vmStart(legacyId) : api.start(instance.id);

    if (instance.isRunning) {
      return PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert_rounded),
        onSelected: (value) => runTrueNasAction(
          context,
          ref,
          action: () => value == 'restart' ? doRestart() : doStop(),
          successMessage: value == 'restart' ? 'Restarting' : 'Stopping',
          failureMessage: 'Action failed',
        ).then((_) => invalidate()),
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'stop', child: Text('Stop')),
          PopupMenuItem(value: 'restart', child: Text('Restart')),
        ],
      );
    }
    return IconButton(
      icon: const Icon(Icons.play_arrow_rounded),
      color: AppColors.success,
      tooltip: 'Start',
      onPressed: () => runTrueNasAction(
        context,
        ref,
        action: () => doStart(),
        successMessage: 'Starting ${instance.name}',
        failureMessage: 'Could not start',
      ).then((_) => invalidate()),
    );
  }
}
