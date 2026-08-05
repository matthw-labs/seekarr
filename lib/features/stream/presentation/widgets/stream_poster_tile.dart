import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/utils/service_routes.dart';
import 'package:seekarr/core/widgets/content_card.dart';
import 'package:seekarr/core/widgets/media_poster_card.dart';
import 'package:seekarr/core/widgets/pressable_scale.dart';
import 'package:seekarr/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:seekarr/features/plex/presentation/plex_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/stream/domain/models/stream_item.dart';

/// One poster in a Stream library grid.
///
/// Composed from the app's existing tile parts rather than through
/// `MediaBrowseScaffold`, which cannot host a media server: its `idExtractor` is
/// typed `int` and feeds both the Hero tag and the route param, but a Jellyfin id
/// is a GUID and a Plex `ratingKey` is documented as an opaque string that only
/// *often* looks numeric. Its `imagesExtractor` also wants an arr-shaped `images`
/// JSON array, and its filter chips are a closed All/Available/Missing/In-Queue
/// vocabulary in which a null status silently classifies every item as *Missing*.
/// The paged-grid idiom in `discover_see_all_screen.dart` is the seam that fits,
/// and it needed no changes to take string ids — its Hero tags are built by
/// interpolation.
///
/// **The watch state is the point of the tile.** A bare poster wall is the thing
/// the Stream library exists not to be, so an in-progress item carries a resume bar
/// and a partly-watched series carries its unplayed count. Those are the facts only
/// a media server holds.
class StreamPosterTile extends ConsumerWidget {
  const StreamPosterTile({
    super.key,
    required this.service,
    required this.item,
    required this.index,
  });

  final ServiceKey service;
  final StreamItem item;

  /// Position in the full list, included in the Hero tag.
  ///
  /// Two items can carry the same id across a lens change, and a duplicated Hero
  /// tag throws at flight time rather than degrading — the same reason
  /// `MediaGrid` and the discover see-all screen both include it.
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = service == ServiceKey.jellyfin
        ? ref.watch(jellyfinServerProvider)
        : ref.watch(plexServerProvider);

    final poster = item.posterPath == null
        ? null
        : client.imageFor(item.posterPath!, width: 260);
    final heroTag = 'stream_${service.name}_${item.id}_$index';
    final route = service == ServiceKey.jellyfin
        ? ServiceRoutes.jellyfinItem(item.id)
        : ServiceRoutes.plexItem(item.id);

    final progress = item.resumeProgress;
    final unplayed = item.unplayedChildCount;

    return Semantics(
      label: item.title,
      value: _spokenState(item),
      button: true,
      excludeSemantics: true,
      child: PressableScale(
        onTap: () => context.push(route),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: heroTag,
              transitionOnUserGestures: MediaPosterCard.flightOnUserGestures,
              child: ContentCard(
                imageUrl: poster?.url,
                httpHeaders: poster?.headers,
                badge: unplayed != null && unplayed > 0
                    ? _UnplayedBadge(count: unplayed)
                    : null,
              ),
            ),
            if (progress != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _ResumeBar(progress: progress, accent: service.accent),
              ),
          ],
        ),
      ),
    );
  }

  /// What the tile says after its title.
  ///
  /// A resume bar and a count badge are both purely visual, so without this a
  /// screen-reader user gets an unlabelled poster and none of the state that makes
  /// the Stream library different from an arr's.
  static String? _spokenState(StreamItem item) {
    final parts = <String>[];
    final progress = item.resumeProgress;
    if (progress != null) {
      parts.add('${(progress * 100).round()}% watched');
    } else if (item.isPlayed) {
      parts.add('Watched');
    }
    final unplayed = item.unplayedChildCount;
    if (unplayed != null && unplayed > 0) {
      parts.add('$unplayed not played');
    }
    final year = item.year;
    if (year != null) parts.add('$year');
    return parts.isEmpty ? null : parts.join(', ');
  }
}

class _UnplayedBadge extends StatelessWidget {
  const _UnplayedBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: AppRadius.borderRadiusSm,
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The resume position, as a hairline across the poster's foot.
///
/// Deliberately not a `LinearProgressIndicator`: this is a static reading of where
/// someone stopped, not work in flight, and an indeterminate-capable widget invites
/// the animation the state does not have.
class _ResumeBar extends StatelessWidget {
  const _ResumeBar({required this.progress, required this.accent});

  final double progress;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(AppRadius.md),
      ),
      child: SizedBox(
        height: 3,
        child: Row(
          children: [
            Expanded(
              flex: (progress * 1000).round().clamp(1, 1000),
              child: ColoredBox(color: accent),
            ),
            Expanded(
              flex: (1000 - (progress * 1000).round()).clamp(0, 999),
              child: ColoredBox(
                color: Theme.of(
                  context,
                ).colorScheme.scrim.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
