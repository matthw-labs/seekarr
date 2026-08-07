import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:seekarr/core/app_elevation.dart';
import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/network/pinned_image_cache.dart';

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

  /// Whether poster Heroes also fly during the interactive swipe-back
  /// gesture (iOS Photos behaviour). Shared by every Hero source that flies
  /// into a detail page, so the whole flight family toggles in one place —
  /// flip to false if the interactive flight proves flaky on device.
  static const bool flightOnUserGestures = true;

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
            cacheManager: pinnedImageCacheFor(imageUrl),
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

    Widget content(List<BoxShadow> shadow) {
      Widget child = DecoratedBox(
        decoration: BoxDecoration(
          shape: circular ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: circular ? null : effectiveBorderRadius,
          boxShadow: shadow,
        ),
        child: clippedImage,
      );
      if (hasImage) {
        child = Stack(
          fit: StackFit.expand,
          children: [
            child,
            Opacity(opacity: 0, child: fallback()),
          ],
        );
      }
      return child;
    }

    // Match ContentCard's resting elevation so the shared-element flight
    // doesn't "pop" a different shadow mid-transition.
    final heroChild = content(AppElevation.level2(colorScheme));

    return Hero(
      tag: heroTag,
      transitionOnUserGestures: flightOnUserGestures,
      flightShuttleBuilder:
          (flightContext, animation, direction, fromContext, toContext) {
            if (MediaQuery.disableAnimationsOf(flightContext)) {
              return Material(
                type: MaterialType.transparency,
                child: heroChild,
              );
            }
            // "Pick up / set down": the shadow deepens to level3 mid-flight
            // and settles back to level2, so the poster reads as physically
            // lifted off one surface and placed on the other. Symmetric, so
            // push and pop flights both work.
            return AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                final lift = 1 - (2 * animation.value - 1).abs();
                final scheme = Theme.of(flightContext).colorScheme;
                final shadow = BoxShadow.lerpList(
                  AppElevation.level2(scheme),
                  AppElevation.level3(scheme),
                  Curves.easeOut.transform(lift),
                )!;
                return Material(
                  type: MaterialType.transparency,
                  child: content(shadow),
                );
              },
            );
          },
      child: Material(type: MaterialType.transparency, child: heroChild),
    );
  }
}
