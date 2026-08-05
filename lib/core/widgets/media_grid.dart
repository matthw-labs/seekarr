import 'package:flutter/material.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/utils/image_utils.dart';
import 'package:seekarr/core/widgets/app_empty_state.dart';
import 'package:seekarr/core/widgets/content_card.dart';
import 'package:seekarr/core/widgets/floating_bottom_nav_bar.dart';
import 'package:seekarr/core/widgets/media_poster_card.dart';
import 'package:seekarr/core/widgets/pressable_scale.dart';
import 'package:seekarr/core/widgets/staggered_entrance.dart';
import 'package:seekarr/core/widgets/status_badge.dart';

/// Callback signature for when a media item is tapped.
typedef OnMediaItemTap<T> = void Function(T item, String heroTag);

/// Callback signature for extracting a resolved status from a media item.
///
/// The caller resolves the status — including the download queue — so the grid
/// and the item's detail page cannot show different badges for the same item.
typedef StatusExtractor<T> = MediaStatusInfo? Function(T item);

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

  /// Optional: Extracts the item's title, used as the accessible name.
  ///
  /// Without it each cell is an unlabelled poster image and a screen reader has
  /// nothing to announce.
  final String Function(T item)? titleExtractor;

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

  /// Minimum number of columns; more are used when the window is wide enough.
  ///
  /// This is a floor rather than a fixed count so an iPad or a resized macOS
  /// window fills with more posters instead of stretching three of them to
  /// several hundred points each.
  final int crossAxisCount;

  const MediaGrid({
    super.key,
    required this.items,
    required this.imagesExtractor,
    required this.idExtractor,
    this.statusExtractor,
    this.titleExtractor,
    required this.baseUrl,
    required this.apiKey,
    required this.heroTagPrefix,
    this.onItemTap,
    this.coverTypes = const ['poster', 'cover'],
    this.physics,
    this.crossAxisCount = 3,
  });

  /// Width a poster wants before another column is worth adding. Chosen so a
  /// 390pt-wide phone keeps exactly three columns.
  static const double _preferredTileWidth = 130.0;

  /// Columns that fit [availableWidth], never fewer than [minColumns].
  static int columnsFor(double availableWidth, int minColumns) {
    final fits = (availableWidth / _preferredTileWidth).floor();
    return fits > minColumns ? fits : minColumns;
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const AppEmptyState(
        icon: Icons.movie_filter_outlined,
        title: 'No items found',
      );
    }

    final columns = columnsFor(
      MediaQuery.sizeOf(context).width - (AppSpacing.lg * 2),
      crossAxisCount,
    );

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
        crossAxisCount: columns,
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
        final statusInfo = statusExtractor?.call(item);
        final title = titleExtractor?.call(item);
        if (statusInfo != null) {
          badge = StatusBadge(
            info: statusInfo,
            compact: true,
            // With a title the cell publishes one node and drops the child
            // subtree, so the badge's own node would be discarded anyway and
            // the status rides on `semanticValue` instead. Without a title
            // there is nothing to exclude, so the badge speaks for itself.
            excludeFromSemantics: title != null,
          );
        }

        return StaggeredEntrance(
          index: index,
          wrapCount: columns * 4,
          child: PressableScale(
            onTap: onItemTap != null ? () => onItemTap!(item, heroTag) : null,
            semanticLabel: title,
            // Only alongside a label: a node carrying a value and no name
            // announces "Downloading" with nothing to attach it to.
            semanticValue: title == null ? null : statusInfo?.semanticLabel,
            excludeChildSemantics: title != null,
            child: Hero(
              tag: heroTag,
              transitionOnUserGestures: MediaPosterCard.flightOnUserGestures,
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
