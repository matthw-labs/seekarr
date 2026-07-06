import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:seekarr/core/app_elevation.dart';
import 'package:seekarr/core/app_radius.dart';

/// A reusable poster card for media detail screens.
///
/// Consolidates the previously duplicated poster card widgets
/// (`_MoviePosterCard`, `_SeriesPosterCard`, `_MusicPosterCard`,
/// `_DiscoverPosterCard`) into a single shared component.
///
/// The card fills its parent constraints — wrap in a [SizedBox] to
/// control dimensions externally (e.g. from [MediaDetailPosterRow]).
class MediaPosterCard extends StatelessWidget {
  final String heroTag;
  final String? imageUrl;
  final Map<String, String>? imageHeaders;
  final IconData fallbackIcon;
  final bool circular;
  final BorderRadius? borderRadius;

  const MediaPosterCard({
    super.key,
    required this.heroTag,
    this.imageUrl,
    this.imageHeaders,
    this.fallbackIcon = Icons.movie_outlined,
    this.circular = false,
    this.borderRadius,
  });

  static const _fallbackIconSize = 48.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    final effectiveBorderRadius = borderRadius ?? AppRadius.borderRadiusMd;
    Widget fallback() => Container(
      color: colorScheme.surfaceContainer,
      child: Center(
        child: Icon(
          fallbackIcon,
          size: _fallbackIconSize,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );

    final image = hasImage
        ? CachedNetworkImage(
            imageUrl: imageUrl!,
            httpHeaders: imageHeaders,
            fit: BoxFit.cover,
            // No cross-fade: keeps the Hero flight crisp when the poster is
            // already cached from the source grid/carousel.
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            placeholderFadeInDuration: Duration.zero,
            errorWidget: (context, url, error) => fallback(),
          )
        : fallback();
    final clippedImage = circular
        ? ClipOval(child: image)
        : ClipRRect(borderRadius: effectiveBorderRadius, child: image);

    Widget heroChild = DecoratedBox(
      decoration: BoxDecoration(
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular ? null : effectiveBorderRadius,
        // Match ContentCard's resting elevation so the shared-element flight
        // doesn't "pop" a different shadow mid-transition.
        boxShadow: AppElevation.level2(colorScheme),
      ),
      child: clippedImage,
    );

    if (hasImage) {
      heroChild = Stack(
        fit: StackFit.expand,
        children: [
          heroChild,
          Opacity(opacity: 0, child: fallback()),
        ],
      );
    }

    return Hero(
      tag: heroTag,
      child: Material(type: MaterialType.transparency, child: heroChild),
    );
  }
}
