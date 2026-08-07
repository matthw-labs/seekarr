import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/network/pinned_image_cache.dart';
import 'package:seekarr/core/text_scale.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/service_routes.dart';
import 'package:seekarr/core/widgets/media_detail_section_label.dart';
import 'package:seekarr/core/widgets/media_poster_card.dart';
import 'package:seekarr/core/widgets/pressable_scale.dart';
import 'package:seekarr/features/discover/presentation/discover_detail_view_model.dart';

/// The horizontal `CAST` rail: a face, a name and a character per tile.
///
/// Headless, and carries no accent: the enclosing `MediaDetailSlot` supplies the
/// heading, so the spine draws every page's label with that page's accent and
/// `Semantics(header: true)`. This widget used to build its own
/// [MediaDetailSectionLabel] because the Radarr/Sonarr hosts reached it through
/// one undifferentiated extras section and had no slot to hang a label on; those
/// hosts now emit a `CAST` slot of their own.
class DiscoverCastList extends StatelessWidget {
  final List<DiscoverCastMember> cast;

  /// Horizontal inset for the rail's first and last tile.
  ///
  /// `MediaDetailSlot.rail` hands the resolved content-column gutter to its
  /// builder for exactly this: the first face aligns to the column while the
  /// rail keeps bleeding off the trailing edge.
  final EdgeInsetsGeometry padding;

  const DiscoverCastList({
    super.key,
    required this.cast,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
  });

  /// Rail height at the default reading size: a 64pt avatar, a 4pt gap and two
  /// lines of `labelSmall`, with a little slack.
  static const double _railBaseHeight = 108;

  /// The growing half of [_railBaseHeight]: two lines of `labelSmall` (11pt at
  /// 1.22 leading) — the actor's name and their character.
  static const double _labelBlockHeight = 27;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // The avatar is the fixed half of the tile, the two labels the growing
      // half, so the rail gains exactly what the labels gain.
      height: TextScaleMetrics.boxHeight(
        context,
        base: _railBaseHeight,
        textHeight: _labelBlockHeight,
      ),
      // …and the labels have to lay out on the same clamp the rail grew by, or
      // a 2x reader gets an overflow stripe instead of the ellipsis the clamp
      // promises. Grown box and clamped scaler are one mechanism.
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaleMetrics.clampedScalerOf(context)),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: padding,
          itemCount: cast.length,
          itemBuilder: (context, index) => _CastTile(member: cast[index]),
        ),
      ),
    );
  }
}

class _CastTile extends StatelessWidget {
  final DiscoverCastMember member;

  const _CastTile({required this.member});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final profilePath = member.profilePath;
    final imageUrl = profilePath != null && profilePath.isNotEmpty
        ? 'https://image.tmdb.org/t/p/w185$profilePath'
        : null;
    final tappable = member.id > 0;
    // One tile per person is an invariant of the list this widget is given —
    // `DiscoverDetailViewModel` dedupes the credits by person id precisely so
    // this tag stays unique. TMDB bills one entry per *role*, so a dual-role
    // actor arrives twice and two Heroes with one tag assert on the next push.
    final heroTag = 'person_${member.id}';

    Widget avatar = CircleAvatar(
      radius: 32,
      backgroundColor: colorScheme.surfaceContainer,
      backgroundImage: imageUrl != null
          ? CachedNetworkImageProvider(
              imageUrl,
              cacheManager: pinnedImageCacheFor(imageUrl),
            )
          : null,
      child: imageUrl == null
          ? Icon(Icons.person, size: 28, color: colorScheme.onSurfaceVariant)
          : null,
    );
    if (tappable) {
      avatar = Hero(
        tag: heroTag,
        transitionOnUserGestures: MediaPosterCard.flightOnUserGestures,
        child: avatar,
      );
    }

    final tile = SizedBox(
      width: 64,
      child: Column(
        children: [
          avatar,
          const SizedBox(height: AppSpacing.xs),
          Text(
            member.name,
            maxLines: 1,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.weight(FontWeight.w700),
          ),
          Text(
            member.character,
            maxLines: 1,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            // Same role as the name above; the character reads as secondary
            // through weight and colour, not through a hard-coded size.
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: tappable
          ? PressableScale(
              onTap: () => context.push(
                ServiceRoutes.seerrPerson(
                  member.id,
                  heroTag: heroTag,
                  posterUrl: imageUrl,
                ),
              ),
              child: tile,
            )
          : tile,
    );
  }
}
