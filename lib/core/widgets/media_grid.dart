import 'package:flutter/material.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/utils/image_utils.dart';
import 'package:seekarr/core/widgets/app_empty_state.dart';
import 'package:seekarr/core/widgets/content_card.dart';
import 'package:seekarr/core/widgets/floating_bottom_nav_bar.dart';
import 'package:seekarr/core/widgets/pressable_scale.dart';
import 'package:seekarr/core/widgets/staggered_entrance.dart';
import 'package:seekarr/core/widgets/status_badge.dart';

/// Callback signature for when a media item is tapped.
typedef OnMediaItemTap<T> = void Function(T item, String heroTag);

/// Availability details used to build a [StatusBadge].
class MediaAvailabilityInfo {
  final bool hasFile;
  final String status;
  final int? fileCount;
  final int? totalCount;

  const MediaAvailabilityInfo({
    required this.hasFile,
    required this.status,
    this.fileCount,
    this.totalCount,
  });
}

/// Callback signature for extracting status from a media item.
typedef StatusExtractor<T> = MediaAvailabilityInfo? Function(T item);

/// A reusable grid widget for displaying media items (movies, series, music).
///
/// This widget provides a consistent 3-column grid layout with poster images,
/// status badges, and Hero transition support. Following Material Design 3.
class MediaGrid<T> extends StatelessWidget {
  /// The list of media items to display.
  final List<T> items;

  /// Extracts the images list from an item for poster URL resolution.
  final List<dynamic>? Function(T item) imagesExtractor;

  /// Extracts a unique ID from an item for Hero tags.
  final int Function(T item) idExtractor;

  /// Optional: Extracts status info for badge display.
  final StatusExtractor<T>? statusExtractor;

  /// Base URL for authenticated image URLs.
  final String baseUrl;

  /// API key for authenticated image URLs.
  final String apiKey;

  /// Prefix for Hero tags (e.g., 'movie', 'series', 'artist').
  final String heroTagPrefix;

  /// Callback when an item is tapped.
  final OnMediaItemTap<T>? onItemTap;

  /// Cover types to search for in images.
  final List<String> coverTypes;

  /// Scroll physics. Use AlwaysScrollableScrollPhysics for RefreshIndicator.
  final ScrollPhysics? physics;

  /// Number of columns in the grid
  final int crossAxisCount;

  const MediaGrid({
    super.key,
    required this.items,
    required this.imagesExtractor,
    required this.idExtractor,
    this.statusExtractor,
    required this.baseUrl,
    required this.apiKey,
    required this.heroTagPrefix,
    this.onItemTap,
    this.coverTypes = const ['poster', 'cover'],
    this.physics,
    this.crossAxisCount = 3,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const AppEmptyState(
        icon: Icons.movie_filter_outlined,
        title: 'No items found',
      );
    }

    return GridView.builder(
      physics: physics ?? const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom:
            AppSpacing.lg +
            FloatingNavBarMetrics.getScrollViewBottomPadding(context),
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 2 / 3,
        crossAxisSpacing: AppSpacing.gridGap,
        mainAxisSpacing: AppSpacing.gridGap,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final images = imagesExtractor(item);
        final itemId = idExtractor(item);

        final imageSource = ImageUtils.extractPosterUrl(
          images,
          baseUrl: baseUrl,
          apiKey: apiKey,
          coverTypes: coverTypes,
        );

        // Include index to ensure uniqueness for search results where id may be 0
        final heroTag = '${heroTagPrefix}_${itemId}_$index';

        // Extract status for badge
        Widget? badge;
        if (statusExtractor != null) {
          final statusInfo = statusExtractor!(item);
          if (statusInfo != null) {
            badge = StatusBadge.fromMedia(
              hasFile: statusInfo.hasFile,
              fileCount: statusInfo.fileCount,
              totalCount: statusInfo.totalCount,
              status: statusInfo.status,
              compact: true,
            );
          }
        }

        return StaggeredEntrance(
          index: index,
          wrapCount: crossAxisCount * 4,
          child: PressableScale(
            onTap: onItemTap != null ? () => onItemTap!(item, heroTag) : null,
            child: Hero(
              tag: heroTag,
              child: ContentCard(
                imageUrl: imageSource.url,
                httpHeaders: imageSource.headers,
                badge: badge,
              ),
            ),
          ),
        );
      },
    );
  }
}
