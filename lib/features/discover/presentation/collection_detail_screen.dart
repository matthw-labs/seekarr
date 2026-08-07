import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_carousel.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Premium collection page: backdrop hero, overview and a rail of the
/// collection's movies. Reached by tapping the collection banner on a movie.
class CollectionDetailScreen extends ConsumerWidget {
  final int collectionId;
  final String? heroTag;

  const CollectionDetailScreen({
    super.key,
    required this.collectionId,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collectionAsync = ref.watch(collectionDetailProvider(collectionId));

    return collectionAsync.when(
      loading: () => MediaDetailLoadingView(
        accent: ServiceKey.seerr.accent,
        heroFallbackIcon: Icons.collections_bookmark_rounded,
      ),
      // A lookup that failed and a collection that is genuinely empty are two
      // different facts, and they used to share one sentence
      // ("Collection is unavailable.") under one empty-title bar — so a blinking
      // reverse proxy read as "this collection does not exist", with no retry
      // either way. The failure now names Seerr, keeps the diagnostics and
      // offers a way back; the empty case keeps the empty-state voice.
      error: (error, _) => MediaDetailPlaceholderView.error(
        error: error,
        serviceName: 'Seerr',
        accent: ServiceKey.seerr.accent,
        onRetry: () => ref.invalidate(collectionDetailProvider(collectionId)),
      ),
      data: (collection) {
        if (collection.isEmpty) {
          return MediaDetailPlaceholderView.notFound(
            icon: Icons.collections_bookmark_outlined,
            title: 'No collection here',
            message:
                'Seerr answered, but it has nothing filed under this '
                'collection.',
            serviceName: 'Seerr',
            accent: ServiceKey.seerr.accent,
          );
        }

        final poster = ImageUtils.buildTmdbPosterUrl(collection.posterPath);
        final backdrop = ImageUtils.buildTmdbPosterUrl(
          collection.backdropPath,
          size: 'w1280',
        );

        return MediaDetailView(
          accent: ServiceKey.seerr.accent,
          posterUrl: poster,
          backdropUrl: backdrop.isNotEmpty ? backdrop : null,
          title: collection.name,
          heroFallbackIcon: Icons.collections_bookmark_rounded,
          posterRow: MediaDetailPosterRow(
            title: collection.name,
            // The chip slot carries the manifest counter here too, so the
            // metadata line is free for anything a collection later gains.
            metadataItems: const [],
            tags: [
              TagChip(
                text:
                    '${collection.parts.length} '
                    '${collection.parts.length == 1 ? 'movie' : 'movies'}',
                color: ServiceKey.seerr.accent,
              ),
            ],
            posterCard: MediaPosterCard(
              heroTag: heroTag ?? 'collection_$collectionId',
              imageUrl: poster,
              fallbackIcon: Icons.collections_bookmark_rounded,
            ),
          ),
          onRefresh: () async =>
              ref.invalidate(collectionDetailProvider(collectionId)),
          body: MediaDetailBody(
            // Region 1 is a reference page's state — 'three of seven in your
            // library'. That needs a resolved collection status and a
            // status-only deck, neither of which exists yet, so the region
            // collapses rather than inventing a state out of the parts list.
            // Region 3 — the members. On a page *about* a collection they are
            // the content, not a teaser, so they sit above the overview.
            //
            // `.rail` rather than `.box`: the carousel owns its own gutter and
            // its own heading internally, so the spine hands it the resolved
            // padding and it is free to ignore both.
            operate: [
              if (collection.parts.isEmpty)
                const MediaDetailSlot.box(
                  label: 'Movies',
                  child: AppEmptyState.compact(
                    icon: Icons.movie_filter_outlined,
                    title: 'No movies listed',
                    message:
                        'Seerr knows this collection but has no titles filed '
                        'under it yet.',
                  ),
                )
              else
                MediaDetailSlot.rail(
                  builder: (_) => DiscoverCarousel(
                    title: 'Movies',
                    sectionId: 'collection_$collectionId',
                    items: AsyncData(collection.parts),
                    forcedMediaType: 'movie',
                  ),
                ),
            ],
            synopsis: [
              if ((collection.overview ?? '').isNotEmpty)
                MediaDetailSlot.box(
                  label: 'Overview',
                  child: MediaProseSection(text: collection.overview!),
                ),
            ],
          ),
        );
      },
    );
  }
}
