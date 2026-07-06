import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/utils/image_utils.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/discover/presentation/discover_details_provider.dart';
import 'package:seekarr/features/discover/presentation/widgets/discover_carousel.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

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
      loading: () => const MediaDetailLoadingView(),
      error: (error, _) =>
          const _CollectionMessage(message: 'Collection is unavailable.'),
      data: (collection) {
        if (collection.isEmpty) {
          return const _CollectionMessage(
            message: 'Collection is unavailable.',
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
          posterRow: (collapseFactor) => MediaDetailPosterRow(
            collapseFactor: collapseFactor,
            title: collection.name,
            metadataItems: ['${collection.parts.length} movies'],
            posterCard: MediaPosterCard(
              heroTag: heroTag ?? 'collection_$collectionId',
              imageUrl: poster,
              fallbackIcon: Icons.collections_bookmark_rounded,
            ),
          ),
          contentSections: [
            if ((collection.overview ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: MediaDetailOverviewSection(
                  overview: collection.overview!,
                ),
              ),
            DiscoverCarousel(
              title: 'Movies',
              sectionId: 'collection_$collectionId',
              items: AsyncData(collection.parts),
              forcedMediaType: 'movie',
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        );
      },
    );
  }
}

class _CollectionMessage extends StatelessWidget {
  final String message;

  const _CollectionMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    return AmbientScaffold(
      appBar: const GlassAppBar(title: Text('')),
      body: AppEmptyState(
        icon: Icons.collections_bookmark_outlined,
        title: 'Unavailable',
        message: message,
      ),
    );
  }
}
