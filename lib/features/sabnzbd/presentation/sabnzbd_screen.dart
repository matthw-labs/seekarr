import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/sabnzbd/domain/models/sabnzbd_models.dart';
import 'package:seekarr/features/sabnzbd/presentation/sabnzbd_actions.dart';
import 'package:seekarr/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:seekarr/features/services/presentation/service_kpi_provider.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// SABnzbd dashboard: live queue and recent history. Read-only for the first
/// release.
class SabnzbdScreen extends ConsumerWidget {
  const SabnzbdScreen({super.key, this.showAppBar = true, this.topPadding = 0});

  final bool showAppBar;
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final isConfigured = settings.isServiceConfigured(ServiceKey.sabnzbd);

    return AmbientScaffold(
      accent: AppColors.sabnzbd,
      appBar: showAppBar ? const GlassAppBar(title: Text('SABnzbd')) : null,
      body: SafeArea(
        // The shared placeholder, not a private copy. Four dashboards had grown
        // their own version of "this service isn't set up" — same shape, four
        // different icons, paddings and sentences — while
        // `NotConfiguredPlaceholder` exists precisely to unify that state.
        child: isConfigured
            ? _SabnzbdDashboard(topPadding: topPadding)
            : NotConfiguredPlaceholder.forService(ServiceKey.sabnzbd),
      ),
    );
  }
}

class _SabnzbdDashboard extends ConsumerWidget {
  const _SabnzbdDashboard({required this.topPadding});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(sabnzbdQueueProvider);
    final historyAsync = ref.watch(sabnzbdHistoryProvider);
    final summaryAsync = ref.watch(serviceSummaryProvider(ServiceKey.sabnzbd));
    final isOffline = summaryAsync.maybeWhen(
      data: (summary) => !summary.isOnline,
      orElse: () => false,
    );

    if (isOffline) {
      return ServiceOfflineState(
        serviceName: ServiceKey.sabnzbd.title,
        accent: AppColors.sabnzbd,
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
            kpis: ref.watch(serviceKpiProvider(ServiceKey.sabnzbd)),
            accent: AppColors.sabnzbd,
          ),
          const SizedBox(height: 8),
          _SabnzbdActionsBar(queueAsync: queueAsync),
          const SizedBox(height: 8),
          const SectionHeader(title: 'Downloading', showChevron: false),
          const SizedBox(height: 2),
          _QueueList(queueAsync: queueAsync),
          const SizedBox(height: 8),
          const SectionHeader(title: 'History', showChevron: false),
          const SizedBox(height: 2),
          _HistoryList(historyAsync: historyAsync),
        ],
      ),
    );
  }
}

/// Providers refreshed after any SABnzbd mutation.
final _sabnzbdInvalidateAfterAction = <ProviderOrFamily>[
  sabnzbdQueueProvider,
  sabnzbdHistoryProvider,
];

/// Global controls: add an NZB by URL and pause/resume the whole queue.
void _invalidateAll(WidgetRef ref) {
  ref.invalidate(sabnzbdQueueProvider);
  ref.invalidate(sabnzbdHistoryProvider);
  ref.invalidate(serviceKpiProvider(ServiceKey.sabnzbd));
  ref.invalidate(serviceSummaryProvider(ServiceKey.sabnzbd));
}

class _SabnzbdActionsBar extends ConsumerWidget {
  const _SabnzbdActionsBar({required this.queueAsync});

  final AsyncValue<SabnzbdQueue> queueAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Null until the first queue load lands. Defaulting that to `false` meant
    // an already-paused queue rendered "Pause all" for the duration of the
    // first fetch, and a tap in that window sent `pause()` to a queue that was
    // already paused. The toggle is inert until its own state is known.
    final paused = queueAsync.value?.paused;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _showAddNzbDialog(context, ref),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add NZB'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: paused == null
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      runSabnzbdAction(
                        context,
                        ref,
                        action: (c) => paused ? c.resume() : c.pause(),
                        successMessage: paused
                            ? 'Queue resumed'
                            : 'Queue paused',
                        failureMessage: paused
                            ? 'Failed to resume the queue'
                            : 'Failed to pause the queue',
                        invalidate: _sabnzbdInvalidateAfterAction,
                      );
                    },
              icon: Icon(
                paused ?? false
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
                size: 18,
              ),
              label: Text(paused ?? false ? 'Resume all' : 'Pause all'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Prompts for an NZB URL (and optional category) and enqueues it.
Future<void> _showAddNzbDialog(BuildContext context, WidgetRef ref) async {
  final result = await showDialog<_AddNzbRequest>(
    context: context,
    builder: (context) => const _AddNzbDialog(),
  );

  if (result == null || !context.mounted) return;

  await runSabnzbdAction(
    context,
    ref,
    action: (c) => c.addUrl(result.url, category: result.category),
    successMessage: 'NZB added',
    failureMessage: 'Failed to add the NZB',
    invalidate: _sabnzbdInvalidateAfterAction,
  );
}

/// What the add dialog hands back once the user commits.
class _AddNzbRequest {
  const _AddNzbRequest({required this.url, this.category});

  final String url;
  final String? category;
}

/// The add-NZB form.
///
/// A `ConsumerStatefulWidget` that **watches** the categories rather than
/// reading them once. `ref.read(sabnzbdCategoriesProvider).asData?.value` was
/// the previous shape, and nothing else in the app watches that provider — so
/// on first open it was cold, the read returned `AsyncLoading` with no value,
/// the dropdown was hidden entirely and the NZB went in with no category at
/// all. The captured local was never re-read either, so the dropdown stayed
/// hidden even after the fetch landed while the dialog was still open.
class _AddNzbDialog extends ConsumerStatefulWidget {
  const _AddNzbDialog();

  @override
  ConsumerState<_AddNzbDialog> createState() => _AddNzbDialogState();
}

class _AddNzbDialogState extends ConsumerState<_AddNzbDialog> {
  final _urlController = TextEditingController();
  String? _category;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    Navigator.of(context).pop(_AddNzbRequest(url: url, category: _category));
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(sabnzbdCategoriesProvider);

    return AlertDialog(
      title: const Text('Add NZB by URL'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _urlController,
            autofocus: true,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'NZB URL',
              hintText: 'https://…/download.nzb',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          categoriesAsync.when(
            data: (categories) => categories.isEmpty
                ? const SizedBox.shrink()
                : DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: categories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => _category = v),
                  ),
            // Plain text rather than a spinner: it says the same thing, and an
            // indeterminate indicator inside a dialog is a frame the eye has to
            // keep discarding.
            loading: () => const Align(
              alignment: Alignment.centerLeft,
              child: Text('Loading categories…'),
            ),
            // A category is optional; SABnzbd applies its default. Failing to
            // list them is not a reason to block adding the NZB.
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}

class _QueueList extends ConsumerWidget {
  const _QueueList({required this.queueAsync});

  final AsyncValue<SabnzbdQueue> queueAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return queueAsync.when(
      data: (queue) {
        if (queue.slots.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Text('Queue is empty.'),
          );
        }
        return Column(
          children: queue.slots
              .take(5)
              .map((slot) => _QueueTile(slot: slot))
              .toList(),
        );
      },
      loading: () => const _SabnzbdShimmer(),
      error: (error, _) => _ErrorRetry(
        message: 'Failed to load the queue',
        onRetry: () => ref.invalidate(sabnzbdQueueProvider),
      ),
    );
  }
}

class _QueueTile extends ConsumerWidget {
  const _QueueTile({required this.slot});

  final SabnzbdQueueSlot slot;

  bool get _paused => slot.status.toLowerCase() == 'paused';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DownloadQueueTile(
      title: slot.filename,
      subtitle: <String>[
        if (slot.status.isNotEmpty) slot.status,
        if (slot.timeLeft.isNotEmpty) slot.timeLeft,
        slot.sizeLeftLabel,
      ].join(' · '),
      progress: slot.progress,
      percentage: slot.percentage,
      accent: AppColors.sabnzbd,
      actions: DownloadQueueActionsMenu(
        paused: _paused,
        onCommand: (command) => _run(context, ref, command),
      ),
    );
  }

  void _run(BuildContext context, WidgetRef ref, DownloadQueueCommand command) {
    switch (command) {
      case DownloadQueueCommand.pause:
        runSabnzbdAction(
          context,
          ref,
          action: (c) => c.pauseJob(slot.nzoId),
          successMessage: 'Job paused',
          failureMessage: 'Failed to pause the job',
          invalidate: _sabnzbdInvalidateAfterAction,
        );
      case DownloadQueueCommand.resume:
        runSabnzbdAction(
          context,
          ref,
          action: (c) => c.resumeJob(slot.nzoId),
          successMessage: 'Job resumed',
          failureMessage: 'Failed to resume the job',
          invalidate: _sabnzbdInvalidateAfterAction,
        );
      case DownloadQueueCommand.delete:
        runSabnzbdAction(
          context,
          ref,
          action: (c) => c.deleteJob(slot.nzoId),
          successMessage: 'Job removed',
          failureMessage: 'Failed to remove the job',
          invalidate: _sabnzbdInvalidateAfterAction,
        );
    }
  }
}

class _HistoryList extends ConsumerWidget {
  const _HistoryList({required this.historyAsync});

  final AsyncValue<List<SabnzbdHistorySlot>> historyAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return historyAsync.when(
      data: (slots) {
        if (slots.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Text('No history yet.'),
          );
        }
        return Column(
          children: slots
              .take(10)
              .map((slot) => _HistoryTile(slot: slot))
              .toList(),
        );
      },
      loading: () => const _SabnzbdShimmer(),
      error: (error, _) => _ErrorRetry(
        message: 'Failed to load history',
        onRetry: () => ref.invalidate(sabnzbdHistoryProvider),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.slot});

  final SabnzbdHistorySlot slot;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = slot.failed ? AppColors.error : AppColors.success;
    final icon = slot.failed
        ? Icons.error_outline_rounded
        : Icons.check_circle_rounded;

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
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      slot.name,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium!.weight(FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      slot.failMessage ??
                          [
                            if (slot.category.isNotEmpty) slot.category,
                            slot.status,
                          ].join(' · '),
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

class _SabnzbdShimmer extends StatelessWidget {
  const _SabnzbdShimmer();

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
