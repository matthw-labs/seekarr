import 'package:flutter/material.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/features/prowlarr/domain/models/prowlarr_models.dart';

/// A single indexer row shared by the dashboard preview and the library list.
///
/// When [onTap] is provided the tile becomes tappable (InkWell) and shows a
/// trailing chevron; when it is null the tile is a static preview.
class ProwlarrIndexerTile extends StatelessWidget {
  const ProwlarrIndexerTile({
    super.key,
    required this.indexer,
    required this.failing,
    this.onTap,
  });

  final ProwlarrIndexer indexer;
  final bool failing;
  final VoidCallback? onTap;

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
    ];

    final content = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: AppRadius.borderRadiusMd,
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
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
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
          if (onTap != null) ...[
            const SizedBox(width: 4),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: colorScheme.surface,
        borderRadius: AppRadius.borderRadiusMd,
        child: onTap == null
            ? content
            : InkWell(
                onTap: onTap,
                borderRadius: AppRadius.borderRadiusMd,
                child: content,
              ),
      ),
    );
  }
}
