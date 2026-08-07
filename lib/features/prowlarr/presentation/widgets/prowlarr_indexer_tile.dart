import 'package:flutter/material.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/features/prowlarr/domain/models/prowlarr_models.dart';

/// A single indexer row shared by the dashboard preview and the library list.
///
/// Three variants, one layout:
/// - [ProwlarrIndexerTile.preview] is static (dashboard).
/// - [ProwlarrIndexerTile.navigable] opens the detail screen and offers a
///   long-press action menu.
/// - [ProwlarrIndexerTile.selectable] replaces the status dot with a checkbox
///   for the library's bulk-edit mode.
class ProwlarrIndexerTile extends StatelessWidget {
  const ProwlarrIndexerTile.preview({
    super.key,
    required this.indexer,
    required this.failing,
    this.tagLabels = const [],
  }) : onTap = null,
       onLongPress = null,
       selected = null;

  const ProwlarrIndexerTile.navigable({
    super.key,
    required this.indexer,
    required this.failing,
    required this.onTap,
    this.onLongPress,
    this.tagLabels = const [],
  }) : selected = null;

  const ProwlarrIndexerTile.selectable({
    super.key,
    required this.indexer,
    required this.failing,
    required bool this.selected,
    required VoidCallback this.onTap,
    this.tagLabels = const [],
  }) : onLongPress = null;

  final ProwlarrIndexer indexer;
  final bool failing;
  final List<String> tagLabels;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Non-null only in the selectable variant.
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isTorrent = (indexer.protocol ?? '').toLowerCase() == 'torrent';
    final protocolColor = isTorrent ? AppColors.prowlarr : AppColors.sonarr;
    final statusColor = failing
        ? AppColors.error
        : indexer.enable
        ? AppColors.success
        : colorScheme.onSurfaceVariant;
    final subtitleParts = <String>[
      if (indexer.protocol != null) indexer.protocol!,
      if (indexer.privacy != null) indexer.privacy!,
      if (indexer.language != null) indexer.language!,
      if (indexer.priority != null) 'priority ${indexer.priority}',
    ];

    final content = Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(
          color: selected == true
              ? AppColors.prowlarr.withValues(alpha: 0.6)
              : colorScheme.outlineVariant,
        ),
        borderRadius: AppRadius.borderRadiusMd,
      ),
      child: Row(
        children: [
          if (selected == null)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            )
          else
            Icon(
              selected!
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              size: 20,
              color: selected!
                  ? AppColors.prowlarr
                  : colorScheme.onSurfaceVariant,
            ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  indexer.name ?? 'Unknown indexer',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall!.weight(FontWeight.w700),
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
                if (tagLabels.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      tagLabels.join(' · '),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.prowlarr,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          if (!indexer.enable && selected == null)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: Icon(
                Icons.pause_circle_outline_rounded,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: protocolColor.withValues(alpha: 0.12),
              borderRadius: AppRadius.borderRadiusSm,
            ),
            child: Text(
              (indexer.protocol ?? '?').toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall!
                  .weight(FontWeight.w800)
                  .copyWith(color: protocolColor),
            ),
          ),
          if (onTap != null && selected == null) ...[
            const SizedBox(width: AppSpacing.xs),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Material(
        color: selected == true
            ? AppColors.prowlarr.withValues(alpha: 0.08)
            : colorScheme.surface,
        borderRadius: AppRadius.borderRadiusMd,
        child: onTap == null
            ? content
            : InkWell(
                onTap: onTap,
                onLongPress: onLongPress,
                borderRadius: AppRadius.borderRadiusMd,
                child: content,
              ),
      ),
    );
  }
}
