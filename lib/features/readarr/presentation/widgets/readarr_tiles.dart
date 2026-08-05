import 'package:flutter/material.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/features/readarr/domain/models/readarr_models.dart';

/// Visual style (icon + colour + label) for a Readarr history event type.
({IconData icon, Color color, String label}) readarrEventStyle(
  String eventType,
  ColorScheme colorScheme,
) {
  switch (eventType) {
    case 'grabbed':
      return (
        icon: Icons.download_rounded,
        color: AppColors.info,
        label: 'GRABBED',
      );
    case 'bookFileImported':
    case 'downloadFolderImported':
      return (
        icon: Icons.check_circle_rounded,
        color: AppColors.success,
        label: 'IMPORTED',
      );
    case 'bookFileDeleted':
      return (
        icon: Icons.delete_outline_rounded,
        color: AppColors.warning,
        label: 'DELETED',
      );
    case 'downloadFailed':
      return (
        icon: Icons.error_outline_rounded,
        color: AppColors.error,
        label: 'FAILED',
      );
    default:
      return (
        icon: Icons.history_rounded,
        color: colorScheme.onSurfaceVariant,
        label: eventType.toUpperCase(),
      );
  }
}

/// A bordered list row for a Readarr author, matching the app's service-row
/// anatomy (accent icon square, title, dot-joined subtitle, trailing marker).
class ReadarrAuthorTile extends StatelessWidget {
  const ReadarrAuthorTile({super.key, required this.author, this.onTap});

  final ReadarrAuthor author;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subtitle = <String>[
      '${author.bookFileCount}/${author.bookCount} books',
      if (author.missingBookCount > 0) '${author.missingBookCount} missing',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: colorScheme.surface,
        borderRadius: AppRadius.borderRadiusMd,
        child: InkWell(
          onTap: onTap,
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
                    color: AppColors.readarr.withValues(alpha: 0.12),
                    borderRadius: AppRadius.borderRadiusSm,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.person_rounded,
                    size: 16,
                    color: AppColors.readarr,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        author.authorName,
                        style: Theme.of(
                          context,
                        ).textTheme.titleSmall!.weight(FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        subtitle,
                        // "3/12 books · 4 missing" — counts that move as the
                        // library is scanned.
                        style: Theme.of(context).textTheme.bodySmall!.tabular
                            .copyWith(color: colorScheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (!author.monitored) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Not monitored',
                    child: Icon(
                      Icons.visibility_off_rounded,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A bordered list row for a Readarr history event.
class ReadarrHistoryTile extends StatelessWidget {
  const ReadarrHistoryTile({super.key, required this.item});

  final ReadarrHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final event = readarrEventStyle(item.eventType, colorScheme);
    final title = item.sourceTitle?.trim().isNotEmpty == true
        ? item.sourceTitle!
        : (item.authorName ?? 'Readarr activity');
    final subtitleParts = <String>[
      if (item.authorName != null && item.authorName!.isNotEmpty)
        item.authorName!,
      if (item.date != null) _relativeTime(item.date!),
    ];

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
                  color: event.color.withValues(alpha: 0.12),
                  borderRadius: AppRadius.borderRadiusSm,
                ),
                alignment: Alignment.center,
                child: Icon(event.icon, size: 16, color: event.color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall!.weight(FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitleParts.isNotEmpty)
                      Text(
                        subtitleParts.join(' · '),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: event.color.withValues(alpha: 0.12),
                  borderRadius: AppRadius.borderRadiusSm,
                ),
                child: Text(
                  event.label,
                  style: Theme.of(context).textTheme.labelSmall!
                      .weight(FontWeight.w800)
                      .copyWith(color: event.color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _relativeTime(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return '${(diff.inDays / 30).floor()}mo ago';
}
