import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_actions.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/qbittorrent/presentation/widgets/add_torrent_button.dart';

class QbittorrentActionsBar extends ConsumerWidget {
  const QbittorrentActionsBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: const [AddTorrentButton(), QbittorrentOverflowMenu()],
    );
  }
}

class QbittorrentOverflowMenu extends ConsumerWidget {
  const QbittorrentOverflowMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_QbOverflowAction>(
      icon: Icon(Icons.more_vert_rounded, color: AppColors.qbittorrent),
      tooltip: 'More',
      onSelected: (action) => _handle(context, ref, action),
      itemBuilder: (ctx) => const [
        PopupMenuItem(
          value: _QbOverflowAction.pauseAll,
          child: ListTile(
            leading: Icon(Icons.pause_rounded),
            title: Text('Pause all'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: _QbOverflowAction.resumeAll,
          child: ListTile(
            leading: Icon(Icons.play_arrow_rounded),
            title: Text('Resume all'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: _QbOverflowAction.toggleAltSpeed,
          child: ListTile(
            leading: Icon(Icons.shield_moon_outlined),
            title: Text('Toggle alternative speeds'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Future<void> _handle(
    BuildContext context,
    WidgetRef ref,
    _QbOverflowAction action,
  ) {
    switch (action) {
      case _QbOverflowAction.pauseAll:
        return runTorrentAction(
          context,
          ref,
          action: (service) => service.pauseTorrents(const ['all']),
          successMessage: 'All torrents paused',
          failureMessage: 'Failed',
          invalidate: [torrentsProvider, allTorrentsProvider],
        );
      case _QbOverflowAction.resumeAll:
        return runTorrentAction(
          context,
          ref,
          action: (service) => service.resumeTorrents(const ['all']),
          successMessage: 'All torrents resumed',
          failureMessage: 'Failed',
          invalidate: [torrentsProvider, allTorrentsProvider],
        );
      case _QbOverflowAction.toggleAltSpeed:
        return runTorrentAction(
          context,
          ref,
          action: (service) => service.toggleAlternativeSpeedLimits(),
          successMessage: 'Alternative speed limits toggled',
          failureMessage: 'Failed',
          invalidate: [transferInfoProvider],
        );
    }
  }
}

enum _QbOverflowAction { pauseAll, resumeAll, toggleAltSpeed }
