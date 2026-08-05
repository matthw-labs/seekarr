import 'package:flutter/material.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/media_metadata_line.dart';

/// Title + metadata + chip stack of the hero copy block.
///
/// Renders on the ambient text scaler by design: its host `MediaDetailPosterRow`
/// installs `MediaDetailHeaderMetrics.heroTextScaler`, the clamp the hero band
/// was grown by. Do not render this outside that band without installing the
/// same clamp — the band clips from the top, so an unclamped stack loses the
/// status badge above it with no overflow stripe to show for it.
class MediaDetailHeroSummary extends StatelessWidget {
  final String title;
  final List<String> metadataItems;
  final List<Widget> tags;

  const MediaDetailHeroSummary({
    super.key,
    required this.title,
    this.metadataItems = const [],
    this.tags = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasMetadata = metadataItems.any((item) => item.trim().isNotEmpty);

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Marked a heading for the same reason the collapsed bar's title is
          // (`_CollapsedBarContent` in media_detail_view.dart): this string is
          // the page's name, and the two poses hand off to each other on a
          // single `ExcludeSemantics` threshold — so if only one of them carried
          // `header: true` the heading rotor would appear and disappear with the
          // scroll position. Same widget shape as the bar's, deliberately.
          Semantics(
            header: true,
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge!
                  .weight(FontWeight.w800)
                  .copyWith(height: 1.15),
            ),
          ),
          if (hasMetadata) ...[
            const SizedBox(height: AppSpacing.xs),
            MediaMetadataLine(items: metadataItems, maxLines: 1),
          ],
          if (tags.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: tags,
            ),
          ],
        ],
      ),
    );
  }
}
