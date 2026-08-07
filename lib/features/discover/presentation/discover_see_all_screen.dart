import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/core/widgets/media_poster_card.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';

class DiscoverSeeAllScreen extends ConsumerStatefulWidget {
  final String type; // 'movies', 'tv', 'trending', 'genre'
  final String title;

  /// Set when [type] is 'genre' to paginate a single genre row.
  final GenreRowKey? genreKey;

  const DiscoverSeeAllScreen({
    super.key,
    required this.type,
    required this.title,
    this.genreKey,
  });

  @override
  ConsumerState<DiscoverSeeAllScreen> createState() =>
      _DiscoverSeeAllScreenState();
}

class _DiscoverSeeAllScreenState extends ConsumerState<DiscoverSeeAllScreen> {
  late final PagingController<int, MediaPreview> _pagingController;

  @override
  void initState() {
    _pagingController = PagingController<int, MediaPreview>(
      getNextPageKey: (state) =>
          state.lastPageIsEmpty ? null : state.nextIntPageKey,
      fetchPage: (pageKey) => _fetchPage(pageKey),
    );
    super.initState();
  }

  @override
  void dispose() {
    _pagingController.dispose();
    super.dispose();
  }

  Future<List<MediaPreview>> _fetchPage(int pageKey) async {
    // Determine which provider family to use based on type
    late Future<List<MediaPreview>> future;

    switch (widget.type) {
      case 'movies':
        future = ref.read(discoverMoviesPageProvider(pageKey).future);
        break;
      case 'tv':
        future = ref.read(discoverTVPageProvider(pageKey).future);
        break;
      case 'trending':
        // Trending implies all, but usually mixed or dependent on implementation.
        // Seerr trending endpoint returns mixed results.
        future = ref.read(discoverTrendingPageProvider(pageKey).future);
        break;
      case 'genre':
        final key = widget.genreKey;
        if (key == null) {
          throw Exception('genre type requires a genreKey');
        }
        future = ref.read(
          discoverByGenrePageProvider((key: key, page: pageKey)).future,
        );
        break;
      default:
        throw Exception('Unknown type: ${widget.type}');
    }

    final newItems = await future;
    return newItems;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: PagingListener<int, MediaPreview>(
        controller: _pagingController,
        builder: (context, state, fetchNextPage) =>
            PagedGridView<int, MediaPreview>(
              state: state,
              fetchNextPage: fetchNextPage,
              padding: const EdgeInsets.all(AppSpacing.lg),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 2 / 3,
                crossAxisSpacing: AppSpacing.gridGap,
                mainAxisSpacing: AppSpacing.gridGap,
              ),
              builderDelegate: PagedChildBuilderDelegate<MediaPreview>(
                itemBuilder: (context, item, index) {
                  final imageUrl = ImageUtils.buildTmdbPosterUrl(
                    item.posterPath,
                  );

                  // For genre rows the media type is fixed by the row; trending
                  // stays mixed per-item.
                  final mediaType =
                      widget.genreKey?.mediaType ?? item.mediaType;
                  final heroTag =
                      'discover_seeall_${mediaType}_${item.id}_$index';

                  return PressableScale(
                    onTap: () {
                      context.push(
                        ServiceRoutes.seerrDetail(
                          mediaType: mediaType,
                          id: item.id,
                          heroTag: heroTag,
                          posterUrl: imageUrl,
                        ),
                      );
                    },
                    child: Hero(
                      tag: heroTag,
                      transitionOnUserGestures:
                          MediaPosterCard.flightOnUserGestures,
                      child: ContentCard(imageUrl: imageUrl),
                    ),
                  );
                },
              ),
            ),
      ),
    );
  }
}
