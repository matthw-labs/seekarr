import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/service_routes.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/dockge/data/dockge_client.dart';
import 'package:seekarr/features/dockge/domain/models/dockge_stack.dart';
import 'package:seekarr/features/dockge/presentation/dockge_actions.dart';
import 'package:seekarr/features/dockge/presentation/dockge_provider.dart';
import 'package:seekarr/features/services/presentation/service_kpi_provider.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

class DockgeScreen extends ConsumerWidget {
  const DockgeScreen({super.key, this.showAppBar = true, this.topPadding = 0});

  final bool showAppBar;
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final isConfigured = settings.isServiceConfigured(ServiceKey.dockge);

    return AmbientScaffold(
      accent: AppColors.dockge,
      appBar: showAppBar ? const GlassAppBar(title: Text('Dockge')) : null,
      body: SafeArea(
        child: isConfigured
            ? _DockgeDashboard(topPadding: topPadding)
            : const NotConfiguredPlaceholder(serviceName: 'Dockge'),
      ),
    );
  }
}

class _DockgeDashboard extends ConsumerWidget {
  const _DockgeDashboard({required this.topPadding});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stacksAsync = ref.watch(dockgeStackListProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(dockgeStackListProvider);
        ref.invalidate(serviceKpiProvider(ServiceKey.dockge));
        ref.invalidate(serviceSummaryProvider(ServiceKey.dockge));
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
            kpis: ref.watch(serviceKpiProvider(ServiceKey.dockge)),
            accent: AppColors.dockge,
          ),
          const SizedBox(height: 4),
          SectionHeader.action(
            title: 'Stacks',
            trailing: TextButton.icon(
              onPressed: () => context.push(ServiceRoutes.dockgeNewStack),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New'),
              style: TextButton.styleFrom(foregroundColor: AppColors.dockge),
            ),
          ),
          const SizedBox(height: 2),
          stacksAsync.when(
            data: (stacks) => _StackList(stacks: stacks),
            loading: () => const _ListShimmer(),
            error: (error, _) => AppErrorState(
              error: error,
              onRetry: () => ref.invalidate(dockgeStackListProvider),
            ),
          ),
        ],
      ),
    );
  }
}

class _StackList extends StatelessWidget {
  const _StackList({required this.stacks});

  final List<DockgeStack> stacks;

  @override
  Widget build(BuildContext context) {
    if (stacks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: AppEmptyState(
          icon: Icons.layers_clear_rounded,
          title: 'No stacks yet',
          message: 'Compose stacks managed by Dockge will appear here.',
        ),
      );
    }
    return Column(children: stacks.map((s) => _StackTile(stack: s)).toList());
  }
}

class _StackTile extends ConsumerWidget {
  const _StackTile({required this.stack});

  final DockgeStack stack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = stack.status.color;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: colorScheme.surface,
        borderRadius: AppRadius.borderRadiusMd,
        child: InkWell(
          borderRadius: AppRadius.borderRadiusMd,
          onTap: () => context.push(ServiceRoutes.dockgeStack(stack.name)),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: AppRadius.borderRadiusMd,
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stack.name,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium!.weight(FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        stack.status.label,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: statusColor),
                      ),
                    ],
                  ),
                ),
                _StackQuickActions(stack: stack),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline start/stop/restart controls on a stack row.
class _StackQuickActions extends ConsumerWidget {
  const _StackQuickActions({required this.stack});

  final DockgeStack stack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRunning = stack.status == DockgeStackStatus.running;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isRunning)
          IconButton(
            tooltip: 'Stop',
            icon: const Icon(Icons.stop_rounded),
            color: AppColors.error,
            // Confirmed first: these buttons sit on a scrolling list of live
            // production stacks, and a mis-tap took one down with no warning —
            // while deleting a movie, a far smaller consequence, already asked.
            onPressed: () => _confirmThenRun(
              context,
              ref,
              title: 'Stop ${stack.name}?',
              message:
                  'The stack and its containers will be stopped until you '
                  'start them again.',
              confirmLabel: 'Stop',
              destructive: true,
              action: (c) => c.stopStack(stack.name),
              success: 'Stopped ${stack.name}',
              failure: 'Failed to stop ${stack.name}',
            ),
          )
        else
          IconButton(
            tooltip: 'Start',
            icon: const Icon(Icons.play_arrow_rounded),
            color: AppColors.success,
            onPressed: () => runDockgeStackAction(
              context,
              ref,
              (c) => c.startStack(stack.name),
              'Started ${stack.name}',
              'Failed to start ${stack.name}',
              invalidate: [dockgeStackListProvider],
            ),
          ),
        IconButton(
          tooltip: 'Restart',
          icon: const Icon(Icons.restart_alt_rounded),
          color: AppColors.dockge,
          onPressed: () => _confirmThenRun(
            context,
            ref,
            title: 'Restart ${stack.name}?',
            message: 'The stack will be briefly unavailable while it restarts.',
            confirmLabel: 'Restart',
            action: (c) => c.restartStack(stack.name),
            success: 'Restarted ${stack.name}',
            failure: 'Failed to restart ${stack.name}',
          ),
        ),
      ],
    );
  }

  /// Asks before running a lifecycle action, then runs it.
  ///
  /// Starting a stack is additive and stays a single tap; stopping and
  /// restarting interrupt something the user is running, so they confirm.
  Future<void> _confirmThenRun(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String message,
    required String confirmLabel,
    required Future<void> Function(DockgeClient client) action,
    required String success,
    required String failure,
    bool destructive = false,
  }) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      destructive: destructive,
      dangerNote: '',
    );
    if (!result.confirmed || !context.mounted) return;

    await runDockgeStackAction(
      context,
      ref,
      action,
      success,
      failure,
      invalidate: [dockgeStackListProvider],
    );
  }
}

class _ListShimmer extends StatelessWidget {
  const _ListShimmer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: List.generate(
          4,
          (_) => const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: ShimmerPlaceholder(height: 60),
          ),
        ),
      ),
    );
  }
}
