import 'package:flutter/material.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/core/widgets/section_header.dart';
import 'package:cupola/features/truenas/domain/models/data_protection.dart';
import 'package:cupola/features/truenas/presentation/truenas_actions.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_section_scaffold.dart';

final truenasProtectionTasksProvider = FutureProvider.autoDispose
    .family<List<TrueNasProtectionTask>, TrueNasTaskKind>((ref, kind) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasDataProtectionApiProvider).getTasks(kind);
    });

class TrueNasDataProtectionScreen extends ConsumerWidget {
  const TrueNasDataProtectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TrueNasSectionScaffold(
      title: 'Data Protection',
      body: RefreshIndicator(
        onRefresh: () async {
          for (final kind in TrueNasTaskKind.values) {
            ref.invalidate(truenasProtectionTasksProvider(kind));
          }
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          children: [
            for (final kind in TrueNasTaskKind.values) _TaskGroup(kind: kind),
          ],
        ),
      ),
    );
  }
}

class _TaskGroup extends ConsumerWidget {
  final TrueNasTaskKind kind;
  const _TaskGroup({required this.kind});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(truenasProtectionTasksProvider(kind));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: kind.label, showChevron: false),
        const SizedBox(height: AppSpacing.sm),
        tasks.when(
          loading: () => AppSkeleton.listRows(count: 2),
          error: (e, _) => AppErrorState(
            error: e,
            onRetry: () => ref.invalidate(truenasProtectionTasksProvider(kind)),
          ),
          data: (list) => list.isEmpty
              ? AppCard.surfaceOutlined(
                  child: Text(
                    'No ${kind.label.toLowerCase()}.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : Column(
                  children: [for (final task in list) _TaskTile(task: task)],
                ),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

class _TaskTile extends ConsumerWidget {
  final TrueNasProtectionTask task;
  const _TaskTile({required this.task});

  /// A scrub is started by pool name, so a task that arrived without one can't
  /// be run; every other kind runs by id.
  bool get _canRun =>
      task.kind != TrueNasTaskKind.scrub ||
      (task.poolName?.isNotEmpty ?? false);

  Future<void> _run(BuildContext context, WidgetRef ref) async {
    // A scrub reads every block in the pool — worth a confirmation, unlike the
    // cheap per-task runs.
    if (task.kind == TrueNasTaskKind.scrub) {
      final result = await showAppConfirmDialog(
        context: context,
        title: 'Start scrub?',
        message:
            'Scrubbing "${task.poolName}" reads the whole pool and can take '
            'hours.',
        confirmLabel: 'Start',
      );
      if (!result.confirmed || !context.mounted) return;
    }
    await runTrueNasAction(
      context,
      ref,
      action: () => ref.read(truenasDataProtectionApiProvider).run(task),
      successMessage: 'Started ${task.title}',
      failureMessage: 'Could not run task',
      invalidate: [truenasProtectionTasksProvider(task.kind)],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final api = ref.read(truenasDataProtectionApiProvider);
    final provider = truenasProtectionTasksProvider(task.kind);

    return AppCard.surfaceOutlined(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: theme.textTheme.bodyMedium!.weight(FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                if (task.subtitle.isNotEmpty)
                  Text(
                    task.subtitle,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                if (task.state != null)
                  Text(
                    task.state!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.truenas,
                    ),
                  ),
              ],
            ),
          ),
          if (_canRun)
            IconButton(
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              tooltip: 'Run now',
              onPressed: () => _run(context, ref),
            ),
          IconButton(
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: theme.colorScheme.error,
            ),
            tooltip: 'Delete',
            onPressed: () async {
              final result = await showAppConfirmDialog(
                context: context,
                title: 'Delete task?',
                message: '"${task.title}" will be removed.',
                confirmLabel: 'Delete',
                destructive: true,
              );
              if (!result.confirmed || !context.mounted) return;
              await runTrueNasAction(
                context,
                ref,
                action: () => api.delete(task.kind, task.id),
                successMessage: 'Task deleted',
                failureMessage: 'Could not delete task',
                invalidate: [provider],
              );
            },
          ),
          Switch(
            value: task.enabled,
            onChanged: (value) => runTrueNasAction(
              context,
              ref,
              action: () => api.setEnabled(task.kind, task.id, value),
              successMessage: value ? 'Enabled' : 'Disabled',
              failureMessage: 'Could not update task',
              invalidate: [provider],
            ),
          ),
        ],
      ),
    );
  }
}
