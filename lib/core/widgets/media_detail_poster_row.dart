import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/media_detail_header_metrics.dart';
import 'package:cupola/core/widgets/media_detail_hero_summary.dart';

/// Prototype-style hero title row for media detail screens.
///
/// This row is the payload of the collapsing hero header, and it is the only
/// widget that renders inside the header's expanded band — so it is also where
/// the header's reading-size contract is honoured: everything here lays out on
/// [MediaDetailHeaderMetrics.heroTextScaler], the same clamp
/// [MediaDetailHeaderMetrics.expandedHeight] grew the band by. The row is
/// bottom-anchored inside a `ClipRect`, so text that outgrows the band is not
/// marked with an overflow stripe — it is cut off the top, taking the status
/// badge with it.
class MediaDetailPosterRow extends StatelessWidget {
  /// The poster widget (typically a [MediaPosterCard]).
  final Widget posterCard;

  /// Optional status badge shown above the actions.
  final Widget? statusBadge;

  /// Title shown in the prototype-style hero copy block.
  final String? title;

  /// Metadata shown below [title], joined by the caller.
  final List<String> metadataItems;

  /// Inline genre/status chips shown below metadata.
  final List<Widget> tags;

  /// Whether the poster should use the circular artist treatment.
  final bool circularPoster;

  const MediaDetailPosterRow({
    super.key,
    required this.posterCard,
    this.statusBadge,
    this.title,
    this.metadataItems = const [],
    this.tags = const [],
    this.circularPoster = false,
  });

  // Poster dimensions at expanded state.
  static const expandedWidth = 82.0;
  static const expandedHeight = 123.0;

  @override
  Widget build(BuildContext context) {
    const posterWidth = expandedWidth;
    const posterHeight = expandedHeight;
    final effectivePosterWidth = circularPoster ? 92.0 : posterWidth;
    final effectivePosterHeight = circularPoster ? 92.0 : posterHeight;
    final showTextContent =
        title != null ||
        statusBadge != null ||
        metadataItems.any((item) => item.trim().isNotEmpty) ||
        tags.isNotEmpty;

    return MediaQuery(
      // The hero band grew on the hero clamp, so its copy must lay out on the
      // same clamp. Applied here rather than around the summary block alone:
      // the status badge lives outside that block, and the badge is precisely
      // what an unclamped stack pushes out of the header.
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: MediaDetailHeaderMetrics.heroTextScaler(context)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            width: effectivePosterWidth,
            height: effectivePosterHeight,
            // Decorative. The poster is the same artwork the hero backdrop is
            // already showing behind it, and the title standing beside it is
            // this region's accessible name — so a poster node would put an
            // extra stop before the title with nothing to say. `MediaPosterCard`
            // wraps a `CachedNetworkImage`, which publishes an `image`-flagged
            // node with an empty label whether or not anyone wanted one; this is
            // where that gets suppressed, because only the host knows the
            // artwork is redundant here.
            child: ExcludeSemantics(child: posterCard),
          ),
          if (showTextContent) ...[
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _HeroSummaryBlock(
                title: title,
                statusBadge: statusBadge,
                metadataItems: metadataItems,
                tags: tags,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroSummaryBlock extends StatelessWidget {
  final String? title;
  final Widget? statusBadge;
  final List<String> metadataItems;
  final List<Widget> tags;

  const _HeroSummaryBlock({
    required this.title,
    required this.statusBadge,
    required this.metadataItems,
    required this.tags,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (statusBadge != null) ...[
          statusBadge!,
          const SizedBox(height: AppSpacing.xs),
        ],
        if (title != null && title!.trim().isNotEmpty)
          MediaDetailHeroSummary(
            title: title!,
            metadataItems: metadataItems,
            tags: tags.take(3).toList(growable: false),
          ),
      ],
    );
  }
}
