import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_gradients.dart';
import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/text_scale.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/image_utils.dart';
import 'package:seekarr/core/utils/service_routes.dart';
import 'package:seekarr/core/widgets/pressable_scale.dart';
import 'package:seekarr/features/discover/domain/models/discover_detail_model.dart';

/// The `COLLECTION` banner: artwork, a caption, and a tap into the collection.
///
/// Headless and accent-less, for the reason given on `DiscoverCastList`: the
/// enclosing `MediaDetailSlot` supplies the heading so every page's label is
/// drawn once, by the spine, in that page's accent.
class DiscoverCollectionBanner extends StatelessWidget {
  final CollectionInfo collection;

  const DiscoverCollectionBanner({super.key, required this.collection});

  /// Banner height at the default reading size: the artwork band, with the
  /// caption overlaid on its lower third.
  static const double _bannerBaseHeight = 82;

  /// The growing half of [_bannerBaseHeight]: two lines of `titleSmall` (14pt at
  /// 1.34 leading), which is what a long collection name needs.
  static const double _captionBlockHeight = 40;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final backdropUrl = ImageUtils.buildTmdbPosterUrl(
      collection.backdropPath,
      size: 'w780',
    );

    return PressableScale(
      onTap: () => context.push(
        ServiceRoutes.seerrCollection(
          collection.id,
          heroTag: 'collection_${collection.id}',
        ),
      ),
      child: ClipRRect(
        borderRadius: AppRadius.borderRadiusMd,
        child: SizedBox(
          // The artwork is the fixed half, the caption the growing half.
          height: TextScaleMetrics.boxHeight(
            context,
            base: _bannerBaseHeight,
            textHeight: _captionBlockHeight,
          ),
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (backdropUrl.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: backdropUrl,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) =>
                      Container(color: colorScheme.surfaceContainerHigh),
                )
              else
                Container(color: colorScheme.surfaceContainerHigh),
              // The caption sits on arbitrary photographic artwork, so it
              // needs a scrim — the same bottom-up one the detail hero uses,
              // in the banner's own container tone rather than a flat black
              // wash. Fading to the tone the artwork already falls back to
              // means the caption always lands on `onSurface`-legible
              // ground, in both themes, with no literal in sight.
              //
              // `depth: 1` on purpose: this band is a fifth of the hero's
              // height, so a two-line caption reaches well past the 35% stop
              // and the resting scrim would leave its top line at roughly
              // half alpha over unknown artwork. The collapsed strength is
              // the one that covers the whole caption; the artwork still
              // reads through the 35% wash above it.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppGradients.heroScrim(
                    colorScheme.surfaceContainerHigh,
                    depth: 1,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  // Grown box, clamped scaler: one mechanism. Two lines is
                  // the budget the height above reserves.
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaleMetrics.clampedScalerOf(context),
                    ),
                    child: Text(
                      'Part of ${collection.name}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.weight(FontWeight.w700)
                          .copyWith(color: colorScheme.onSurface),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
