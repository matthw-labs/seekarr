import 'package:flutter/material.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';

/// One row of a download client's queue: name, percentage, progress bar and a
/// counting-down secondary line.
///
/// The SABnzbd and NZBGet dashboards each carried a line-for-line copy of this,
/// differing only in field names and accent colour — and the copies had already
/// started to drift (one of them showed an ETA the other did not). Both now
/// render through this, so a fix to the row's density, radius or semantics
/// lands on both dashboards at once.
///
/// Deliberately given no knowledge of either client: it takes the four rendered
/// values and an [accent], and the caller supplies whatever [actions] widget the
/// row can offer. That is what keeps one tile serving two APIs whose queue
/// records share no field names at all.
class DownloadQueueTile extends StatelessWidget {
  const DownloadQueueTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.percentage,
    required this.accent,
    this.actions,
  });

  final String title;

  /// The counting-down line — status, category/ETA and remaining size.
  final String subtitle;

  /// 0..1, for the bar.
  final double progress;

  /// The same value as a whole number, for the label. Taken separately because
  /// SABnzbd reports it directly while NZBGet derives it from sizes, and
  /// re-deriving one from the other would round twice.
  final int percentage;

  final Color accent;

  /// The row's overflow menu, when the client supports per-job commands.
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Material(
        color: colorScheme.surface,
        borderRadius: AppRadius.borderRadiusMd,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
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
                      title,
                      style: theme.textTheme.bodyMedium!.weight(
                        FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '$percentage%',
                    style: theme.textTheme.labelMedium!
                        .weight(FontWeight.w700)
                        .tabular
                        .copyWith(color: accent),
                  ),
                  if (actions != null) actions!,
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              ClipRRect(
                borderRadius: AppRadius.borderRadiusXs,
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(accent),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                subtitle,
                // Carries the ETA and the remaining size, both counting down,
                // so the figures are tabular and do not jitter as they tick.
                style: theme.textTheme.bodySmall!.tabular.copyWith(
                  color: colorScheme.onSurfaceVariant,
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

/// The three commands a Usenet download client offers on a single job.
enum DownloadQueueCommand { pause, resume, delete }

/// The per-job overflow menu shared by the Usenet dashboards.
///
/// [paused] chooses which half of the toggle is offered, exactly as the two
/// private copies did — the difference being that there is now one of them.
class DownloadQueueActionsMenu extends StatelessWidget {
  const DownloadQueueActionsMenu({
    super.key,
    required this.paused,
    required this.onCommand,
    this.tooltip = 'Job actions',
  });

  final bool paused;
  final ValueChanged<DownloadQueueCommand> onCommand;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<DownloadQueueCommand>(
      icon: const Icon(Icons.more_vert_rounded, size: 18),
      tooltip: tooltip,
      onSelected: onCommand,
      itemBuilder: (context) => [
        if (paused)
          const PopupMenuItem(
            value: DownloadQueueCommand.resume,
            child: Text('Resume'),
          )
        else
          const PopupMenuItem(
            value: DownloadQueueCommand.pause,
            child: Text('Pause'),
          ),
        const PopupMenuItem(
          value: DownloadQueueCommand.delete,
          child: Text('Delete'),
        ),
      ],
    );
  }
}
