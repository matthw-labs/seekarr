import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/models/media_preview.dart';
import 'package:seekarr/core/utils/image_utils.dart';
import 'package:seekarr/core/utils/service_routes.dart';
import 'package:seekarr/core/widgets/app_skeleton.dart';
import 'package:seekarr/core/widgets/content_card.dart';
import 'package:seekarr/core/widgets/pressable_scale.dart';
import 'package:seekarr/core/widgets/section_header.dart';
import 'package:seekarr/core/widgets/staggered_entrance.dart';

/// A single premium discover row: a section header + horizontal poster
/// carousel. Collapses to nothing while it has no data (so unsupported Seerr
/// endpoints or empty genres simply don't render).
class DiscoverCarousel extends StatelessWidget {
  final String title;

  /// Unique id used for Hero tags in this row (e.g. 'trending', 'genre_28').
  final String sectionId;

  final AsyncValue<List<MediaPreview>> items;

  /// Forces the media type for detail navigation (movie rows vs tv rows).
  final String? forcedMediaType;

  final VoidCallback? onSeeAll;

  static const double _posterWidth = 104;
  static const double _posterHeight = 156;

  const DiscoverCarousel({
    super.key,
    required this.title,
    required this.sectionId,
    required this.items,
    this.forcedMediaType,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    // While loading, show a header + skeleton rail so layout doesn't jump.
    return items.when(
      loading: () =>
          _shell(child: AppSkeleton.posterRow(height: _posterHeight)),
      error: (_, __) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return _shell(
          child: SizedBox(
            height: _posterHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              itemCount: list.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: AppSpacing.carouselGap),
              itemBuilder: (context, index) =>
                  _tile(context, list[index], index),
            ),
          ),
        );
      },
    );
  }

  Widget _shell({required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          showChevron: onSeeAll != null,
          onTap: onSeeAll,
        ),
        const SizedBox(height: AppSpacing.md),
        child,
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  Widget _tile(BuildContext context, MediaPreview item, int index) {
    final mediaType = forcedMediaType ?? item.mediaType;
    final imageUrl = ImageUtils.buildTmdbPosterUrl(item.posterPath);
    final heroTag = 'discover_${sectionId}_${item.id}';

    return StaggeredEntrance(
      index: index,
      child: SizedBox(
        width: _posterWidth,
        child: PressableScale(
          onTap: () => context.push(
            ServiceRoutes.seerrDetail(
              mediaType: mediaType,
              id: item.id,
              heroTag: heroTag,
              posterUrl: imageUrl,
            ),
          ),
          child: Hero(
            tag: heroTag,
            child: ContentCard(imageUrl: imageUrl),
          ),
        ),
      ),
    );
  }
}
