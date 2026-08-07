import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';

class TorrentTile extends StatelessWidget {
  final Torrent torrent;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const TorrentTile({
    super.key,
    required this.torrent,
    this.selected = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final state = torrent.parsedState;
    final badge = _stateBadge(context, state);
    final isActive = torrent.dlSpeed > 0 || torrent.upSpeed > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: selected
            ? AppColors.qbittorrent.withValues(alpha: 0.08)
            : colorScheme.surfaceContainer,
        // `shape` already carries the radius; passing `borderRadius` as well
        // trips a Material assertion and blanks the whole list.
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.borderRadiusMd,
          side: BorderSide(
            color: selected
                ? AppColors.qbittorrent.withValues(alpha: 0.4)
                : colorScheme.outline,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: AppRadius.borderRadiusMd,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.download_rounded,
                          size: 16,
                          color: isActive
                              ? AppColors.qbittorrent
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            torrent.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall!.weight(FontWeight.w600),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '${torrent.sizeFormatted}${torrent.etaFormatted.isNotEmpty ? ' • ${torrent.etaFormatted}' : ''}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall!
                                .tabular
                                .copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Flexible so a long state label — or any label at a large
                    // text scale — shrinks instead of overflowing the row.
                    Flexible(child: badge),
                  ],
                ),
                if (torrent.progress < 1 &&
                    state != TorrentState.queuedDl &&
                    state != TorrentState.queuedUp &&
                    state != TorrentState.error) ...[
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: SizedBox(
                      height: 3,
                      width: double.infinity,
                      child: LinearProgressIndicator(
                        value: torrent.progress,
                        backgroundColor: colorScheme.outline,
                        color: state == TorrentState.seeding
                            ? AppColors.success
                            : AppColors.qbittorrent,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    // The speed labels give way to the progress figure when
                    // space is tight (narrow screen, large text scale).
                    Expanded(
                      child: Row(
                        children: [
                          if (isActive && torrent.dlSpeed > 0) ...[
                            Flexible(
                              child: _SpeedLabel(
                                speed: torrent.dlSpeedFormatted,
                                color: AppColors.qbittorrent,
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          if (isActive && torrent.upSpeed > 0)
                            Flexible(
                              child: _SpeedLabel(
                                speed: torrent.upSpeedFormatted,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      torrent.progressFormatted,
                      style: Theme.of(context).textTheme.labelSmall!.tabular
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stateBadge(BuildContext context, TorrentState state) {
    final colorScheme = Theme.of(context).colorScheme;
    final badgeDef = _badgeStyleForState(state, colorScheme);
    final foreground = _foregroundForState(state, colorScheme);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: badgeDef.$1,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        state.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall!
            .weight(FontWeight.w800)
            .copyWith(color: foreground),
      ),
    );
  }
}

(Color background, String _) _badgeStyleForState(
  TorrentState state,
  ColorScheme colorScheme,
) {
  final muted = colorScheme.onSurfaceVariant;
  switch (state) {
    case TorrentState.downloading:
    case TorrentState.metaDownloading:
    case TorrentState.checking:
      return (AppColors.qbittorrent.withValues(alpha: 0.09), '');
    case TorrentState.seeding:
      return (AppColors.success.withValues(alpha: 0.09), '');
    case TorrentState.stalled:
      return (AppColors.warning.withValues(alpha: 0.12), '');
    case TorrentState.paused:
      return (muted.withValues(alpha: 0.18), '');
    case TorrentState.queuedDl:
    case TorrentState.queuedUp:
      return (muted.withValues(alpha: 0.12), '');
    case TorrentState.error:
      return (colorScheme.error.withValues(alpha: 0.12), '');
    case TorrentState.unknown:
      return (muted.withValues(alpha: 0.12), '');
  }
}

Color _foregroundForState(TorrentState state, ColorScheme colorScheme) {
  switch (state) {
    case TorrentState.downloading:
    case TorrentState.metaDownloading:
    case TorrentState.checking:
      return AppColors.qbittorrent;
    case TorrentState.seeding:
      return AppColors.success;
    case TorrentState.stalled:
      return AppColors.warning;
    case TorrentState.paused:
    case TorrentState.queuedDl:
    case TorrentState.queuedUp:
    case TorrentState.unknown:
      return colorScheme.onSurfaceVariant;
    case TorrentState.error:
      return colorScheme.error;
  }
}

class _SpeedLabel extends StatelessWidget {
  final String speed;
  final Color color;

  const _SpeedLabel({required this.speed, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            speed,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelSmall!.tabular.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
