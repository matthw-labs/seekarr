import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';
import 'package:cupola/features/transmission/presentation/transmission_actions.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';

/// Transmission dashboard: the live queue, what is seeding, and the controls
/// that act on both.
class TransmissionScreen extends ConsumerWidget {
  const TransmissionScreen({
    super.key,
    this.showAppBar = true,
    this.topPadding = 0,
  });

  final bool showAppBar;
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final isConfigured = settings.isServiceConfigured(ServiceKey.transmission);

    return AmbientScaffold(
      accent: AppColors.transmission,
      appBar: showAppBar
          ? const GlassAppBar(title: Text('Transmission'))
          : null,
      body: SafeArea(
        child: isConfigured
            ? _TransmissionDashboard(topPadding: topPadding)
            : _TransmissionNotConfigured(
                onOpenSettings: () => context.go(
                  '/settings/service/${ServiceKey.transmission.routeParam}',
                ),
              ),
      ),
    );
  }
}

class _TransmissionNotConfigured extends StatelessWidget {
  const _TransmissionNotConfigured({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.swap_vert_rounded,
              size: 48,
              color: AppColors.transmission,
            ),
            const SizedBox(height: 12),
            const Text(
              'Transmission is not configured yet.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onOpenSettings,
              child: const Text('Open settings'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Providers refreshed after any mutation.
///
/// All three, always. Transmission's write methods return an empty `arguments`
/// with no per-id outcome, so re-reading is the only way to learn what actually
/// happened — see [runTransmissionAction].
final _invalidateAfterAction = <ProviderOrFamily>[
  transmissionTorrentsProvider,
  transmissionStatsProvider,
  transmissionSessionProvider,
];

void _invalidateAll(WidgetRef ref) {
  ref.invalidate(transmissionTorrentsProvider);
  ref.invalidate(transmissionStatsProvider);
  ref.invalidate(transmissionSessionProvider);
  ref.invalidate(serviceKpiProvider(ServiceKey.transmission));
  ref.invalidate(serviceSummaryProvider(ServiceKey.transmission));
}

class _TransmissionDashboard extends ConsumerWidget {
  const _TransmissionDashboard({required this.topPadding});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final torrentsAsync = ref.watch(transmissionTorrentsProvider);
    final summaryAsync = ref.watch(
      serviceSummaryProvider(ServiceKey.transmission),
    );
    final isOffline = summaryAsync.maybeWhen(
      data: (summary) => !summary.isOnline,
      orElse: () => false,
    );

    if (isOffline) {
      return ServiceOfflineState(
        serviceName: ServiceKey.transmission.title,
        accent: AppColors.transmission,
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
            kpis: ref.watch(serviceKpiProvider(ServiceKey.transmission)),
            accent: AppColors.transmission,
          ),
          const SizedBox(height: 8),
          const _TransmissionActionsBar(),
          const SizedBox(height: 8),
          const SectionHeader(title: 'Transferring', showChevron: false),
          const SizedBox(height: 2),
          _TorrentList(
            torrentsAsync: torrentsAsync,
            filter: (t) => t.status.isIncoming,
            emptyLabel: 'Nothing is downloading.',
          ),
          const SizedBox(height: 8),
          const SectionHeader(title: 'Seeding and idle', showChevron: false),
          const SizedBox(height: 2),
          _TorrentList(
            torrentsAsync: torrentsAsync,
            filter: (t) => !t.status.isIncoming,
            emptyLabel: 'Nothing is seeding.',
            limit: 10,
          ),
        ],
      ),
    );
  }
}

/// Global controls: add a torrent, and the turtle toggle.
///
/// Turtle rather than a "pause all": Transmission has no global pause, and
/// faking one by stopping every torrent would be a lie with a bad recovery —
/// "resume all" could not know which ones the user had stopped deliberately.
/// The alternative speed limit is the real control the daemon offers for
/// "quieten down without losing my state", so that is what is here.
class _TransmissionActionsBar extends ConsumerWidget {
  const _TransmissionActionsBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final turtle =
        ref.watch(transmissionSessionProvider).asData?.value.altSpeedEnabled ??
        false;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _showAddTorrentDialog(context, ref),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add torrent'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: () {
                HapticFeedback.selectionClick();
                runTransmissionAction(
                  context,
                  ref,
                  action: (c) => c.setAltSpeedEnabled(!turtle),
                  successMessage: turtle
                      ? 'Speed limits off'
                      : 'Alternative speed limits on',
                  failureMessage: turtle
                      ? 'Failed to turn speed limits off'
                      : 'Failed to turn speed limits on',
                  invalidate: _invalidateAfterAction,
                );
              },
              icon: Icon(
                turtle ? Icons.speed_rounded : Icons.hourglass_bottom_rounded,
                size: 18,
              ),
              label: Text(turtle ? 'Full speed' : 'Slow mode'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Prompts for a magnet link or `.torrent` URL and hands it to the daemon.
Future<void> _showAddTorrentDialog(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final submitted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Add torrent'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          labelText: 'Magnet link or .torrent URL',
          hintText: 'magnet:?xt=urn:btih:…',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Add'),
        ),
      ],
    ),
  );

  if (submitted != true) {
    controller.dispose();
    return;
  }
  final value = controller.text.trim();
  controller.dispose();
  if (value.isEmpty || !context.mounted) return;

  // The duplicate case is reported honestly rather than as a success:
  // Transmission answers `result: "success"` with a `torrent-duplicate` key for
  // a torrent it already had, and telling the user it was added would be wrong.
  var wasDuplicate = false;
  await runTransmissionAction(
    context,
    ref,
    action: (c) async {
      final outcome = await c.addTorrent(value);
      wasDuplicate = outcome.isDuplicate;
    },
    successMessage: null,
    failureMessage: 'Failed to add the torrent',
    invalidate: _invalidateAfterAction,
  );
  if (context.mounted) {
    SnackBarHelper.success(
      context,
      wasDuplicate ? 'Already in Transmission' : 'Torrent added',
    );
  }
}

/// Per-torrent overflow menu.
class _TorrentMenu extends ConsumerWidget {
  const _TorrentMenu({required this.torrent});

  final TransmissionTorrent torrent;

  bool get _stopped => torrent.status == TransmissionStatus.stopped;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = [torrent.rpcId];
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, size: 18),
      tooltip: 'Torrent actions',
      onSelected: (value) {
        switch (value) {
          case 'start':
            runTransmissionAction(
              context,
              ref,
              action: (c) => c.start(ids),
              successMessage: 'Started',
              failureMessage: 'Failed to start the torrent',
              invalidate: _invalidateAfterAction,
            );
          case 'stop':
            runTransmissionAction(
              context,
              ref,
              action: (c) => c.stop(ids),
              successMessage: 'Stopped',
              failureMessage: 'Failed to stop the torrent',
              invalidate: _invalidateAfterAction,
            );
          case 'verify':
            runTransmissionAction(
              context,
              ref,
              action: (c) => c.verify(ids),
              // Deliberately not "Verified": `torrent-verify` returns as soon
              // as the daemon accepts the job, while the re-check itself runs
              // for minutes or hours. Claiming completion here would be false.
              successMessage: 'Verifying — this runs in the background',
              failureMessage: 'Failed to start verification',
              invalidate: _invalidateAfterAction,
            );
          case 'reannounce':
            runTransmissionAction(
              context,
              ref,
              action: (c) => c.reannounce(ids),
              successMessage: 'Asked the trackers for more peers',
              failureMessage: 'Failed to reannounce',
              invalidate: _invalidateAfterAction,
            );
          case 'top':
            runTransmissionAction(
              context,
              ref,
              action: (c) => c.queueMove(ids, TransmissionQueueMove.top),
              successMessage: 'Moved to the top of the queue',
              failureMessage: 'Failed to move the torrent',
              invalidate: _invalidateAfterAction,
            );
          case 'remove':
            _confirmRemove(context, ref, torrent);
        }
      },
      itemBuilder: (context) => [
        if (_stopped)
          const PopupMenuItem(value: 'start', child: Text('Start'))
        else
          const PopupMenuItem(value: 'stop', child: Text('Stop')),
        const PopupMenuItem(value: 'verify', child: Text('Verify local data')),
        const PopupMenuItem(value: 'reannounce', child: Text('Reannounce')),
        const PopupMenuItem(value: 'top', child: Text('Move to top')),
        const PopupMenuItem(value: 'remove', child: Text('Remove…')),
      ],
    );
  }
}

/// Confirms a removal, with deleting the downloaded files as a separate,
/// off-by-default choice.
///
/// Two decisions, not one. Removing a torrent from the daemon is recoverable —
/// re-add it and it re-checks. Deleting its data is not: Transmission unlinks
/// the files and nothing goes to a trash. Folding them into a single "Delete"
/// button is how people lose a library, so the destructive half is a checkbox
/// the user has to reach for, and the dialog escalates to its danger styling
/// only once they do.
Future<void> _confirmRemove(
  BuildContext context,
  WidgetRef ref,
  TransmissionTorrent torrent,
) async {
  final result = await showAppConfirmDialog(
    context: context,
    icon: Icons.delete_outline_rounded,
    title: 'Remove ${torrent.name}?',
    message:
        'It stops downloading and leaves the list. The files it has already '
        'written stay on disk unless you also tick the box below.',
    confirmLabel: 'Remove',
    destructive: true,
    dangerNote: 'Deleting the downloaded files cannot be undone.',
    options: const [
      AppConfirmOption(
        key: 'deleteData',
        label: 'Also delete the downloaded files',
        subtitle: 'Removes the data from the Transmission host permanently.',
        danger: true,
      ),
    ],
  );

  if (!result.confirmed || !context.mounted) return;

  final deleteData = result.option('deleteData');
  await runTransmissionAction(
    context,
    ref,
    action: (c) =>
        c.removeTorrents([torrent.rpcId], deleteLocalData: deleteData),
    successMessage: deleteData ? 'Removed and files deleted' : 'Removed',
    failureMessage: 'Failed to remove the torrent',
    invalidate: _invalidateAfterAction,
  );
}

class _TorrentList extends ConsumerWidget {
  const _TorrentList({
    required this.torrentsAsync,
    required this.filter,
    required this.emptyLabel,
    this.limit = 5,
  });

  final AsyncValue<List<TransmissionTorrent>> torrentsAsync;
  final bool Function(TransmissionTorrent torrent) filter;
  final String emptyLabel;
  final int limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return torrentsAsync.when(
      data: (torrents) {
        final matching = torrents.where(filter).toList(growable: false);
        if (matching.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(emptyLabel),
          );
        }
        return Column(
          children: matching
              .take(limit)
              .map((torrent) => _TorrentTile(torrent: torrent))
              .toList(),
        );
      },
      loading: () => const _TransmissionShimmer(),
      error: (error, _) => _ErrorRetry(
        message: 'Failed to load torrents',
        onRetry: () => ref.invalidate(transmissionTorrentsProvider),
      ),
    );
  }
}

class _TorrentTile extends ConsumerWidget {
  const _TorrentTile({required this.torrent});

  final TransmissionTorrent torrent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final warning = torrent.warning;
    final subtitle = <String>[
      torrent.status.label,
      if (torrent.status.isIncoming) torrent.remainingLabel,
      if (torrent.rateDownload > 0) '↓ ${torrent.downloadSpeedLabel}',
      if (torrent.rateUpload > 0) '↑ ${torrent.uploadSpeedLabel}',
      if (!torrent.status.isIncoming) 'Ratio ${torrent.ratioLabel}',
    ].join(' · ');

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      torrent.name,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium!.weight(FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(torrent.progress * 100).round()}%',
                    style: Theme.of(context).textTheme.labelMedium!
                        .weight(FontWeight.w700)
                        .tabular
                        .copyWith(color: AppColors.transmission),
                  ),
                  _TorrentMenu(torrent: torrent),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: torrent.progress,
                  minHeight: 4,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(
                    warning == null
                        ? AppColors.transmission
                        : AppColors.warning,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                warning == null ? subtitle : '$warning · $subtitle',
                style: Theme.of(context).textTheme.bodySmall!.tabular.copyWith(
                  color: warning == null
                      ? colorScheme.onSurfaceVariant
                      : AppColors.warning,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransmissionShimmer extends StatelessWidget {
  const _TransmissionShimmer();

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
