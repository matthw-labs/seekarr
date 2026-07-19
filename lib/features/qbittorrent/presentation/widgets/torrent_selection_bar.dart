import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/theme.dart';
import 'package:seekarr/features/qbittorrent/presentation/qbittorrent_actions.dart';
import 'package:seekarr/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:seekarr/features/qbittorrent/presentation/widgets/torrent_delete_dialog.dart';

class TorrentSelectionBar extends ConsumerWidget {
  final VoidCallback onConfirmDelete;

  const TorrentSelectionBar({super.key, required this.onConfirmDelete});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedHashes = ref.watch(selectedTorrentHashesProvider);
    final colorScheme = Theme.of(context).colorScheme;

    if (selectedHashes.isEmpty) return const SizedBox.shrink();

    return Material(
      elevation: 8,
      color: colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              TextButton(
                onPressed: () {
                  ref.read(selectedTorrentHashesProvider.notifier).state = {};
                },
                child: const Text('Cancel'),
              ),
              const Spacer(),
              Text(
                '${selectedHashes.length} selected',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => runTorrentAction(
                  context,
                  ref,
                  action: (service) =>
                      service.resumeTorrents(selectedHashes.toList()),
                  successMessage: 'Resumed',
                  failureMessage: 'Failed to resume',
                  invalidate: [torrentsProvider],
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Resume'),
              ),
              IconButton(
                icon: Icon(
                  Icons.flash_on_rounded,
                  color: AppColors.qbittorrent,
                ),
                tooltip: 'Force Resume',
                onPressed: () => runTorrentAction(
                  context,
                  ref,
                  action: (service) =>
                      service.setForceStart(selectedHashes.toList(), true),
                  successMessage: 'Force started',
                  failureMessage: 'Failed',
                  invalidate: [torrentsProvider],
                ),
              ),
              IconButton(
                icon: Icon(Icons.pause_rounded, color: AppColors.warning),
                tooltip: 'Pause',
                onPressed: () => runTorrentAction(
                  context,
                  ref,
                  action: (service) =>
                      service.pauseTorrents(selectedHashes.toList()),
                  failureMessage: 'Failed to pause',
                  invalidate: [torrentsProvider],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: colorScheme.error,
                ),
                tooltip: 'Delete',
                onPressed: onConfirmDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> confirmDeleteTorrents(
  BuildContext context,
  WidgetRef ref,
  Set<String> hashes,
) async {
  final count = hashes.length;
  final result = await showTorrentDeleteDialog(
    context: context,
    title: 'Delete torrents',
    message:
        'Delete $count torrent${count > 1 ? 's' : ''}? This action cannot be undone.',
    multi: count > 1,
  );
  if (!result.confirmed) return false;
  if (!context.mounted) return false;

  final plural = count > 1 ? 's' : '';
  final ok = await runTorrentAction(
    context,
    ref,
    action: (service) =>
        service.deleteTorrents(hashes.toList(), deleteFiles: result.deleteFiles),
    successMessage: result.deleteFiles
        ? 'Deleted $count torrent$plural and files'
        : 'Deleted $count torrent$plural',
    failureMessage: 'Failed to delete',
    invalidate: [torrentsProvider],
  );
  if (ok) {
    ref.read(selectedTorrentHashesProvider.notifier).state = {};
  }
  return ok;
}
