import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_gradients.dart';
import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/models/media_preview.dart';
import 'package:seekarr/core/providers/navigation_refresh_provider.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/image_utils.dart';
import 'package:seekarr/core/utils/service_routes.dart';
import 'package:seekarr/core/widgets/ambient_scaffold.dart';
import 'package:seekarr/core/widgets/app_empty_state.dart';
import 'package:seekarr/core/widgets/app_error_state.dart';
import 'package:seekarr/core/widgets/app_skeleton.dart';
import 'package:seekarr/core/widgets/content_card.dart';
import 'package:seekarr/core/widgets/floating_bottom_nav_bar.dart';
import 'package:seekarr/core/widgets/glass_app_bar.dart';
import 'package:seekarr/core/widgets/pressable_scale.dart';
import 'package:seekarr/core/widgets/search_bar_header.dart';
import 'package:seekarr/core/widgets/service_kpi_peek.dart';
import 'package:seekarr/features/discover/domain/models/seerr_genre.dart';
import 'package:seekarr/features/discover/presentation/discover_provider.dart';
import 'package:seekarr/features/discover/presentation/discover_search_provider.dart';
import 'package:seekarr/features/discover/presentation/widgets/discover_carousel.dart';
import 'package:seekarr/features/services/presentation/service_kpi_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// Premium Seerr discover catalog: featured banner, curated rows and per-genre
/// carousels. Falls back to a grid of results while searching.
class DiscoverScreen extends ConsumerWidget {
  final bool showAppBar;
  final double topPadding;

  const DiscoverScreen({
    super.key,
    this.showAppBar = true,
    this.topPadding = 0,
  });

  /// How many genre rows to render on the catalog.
  static const _genreRowLimit = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchQuery = ref.watch(discoverSearchQueryProvider);

    ref.listen<int>(navigationRefreshProvider(NavigationSection.services), (
      previous,
      next,
    ) {
      ref.read(discoverSearchQueryProvider.notifier).state = '';
      _invalidateCatalog(ref);
    });

    return AmbientScaffold(
      accent: ServiceKey.seerr.accent,
      appBar: showAppBar
          ? GlassAppBar(
              leading: searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () =>
                          ref.read(discoverSearchQueryProvider.notifier).state =
                              '',
                      tooltip: 'Exit search',
                    )
                  : null,
              title: const Text('Discover'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.history_rounded),
                  onPressed: () => context.push('/activity/discover'),
                  tooltip: 'Activity',
                ),
              ],
            )
          : null,
      // Header (search + KPI) scrolls away with the catalog, consistent with
      // the arr library screens.
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          if (topPadding > 0)
            SliverToBoxAdapter(
              child: SizedBox(
                height: topPadding + MediaQuery.paddingOf(context).top,
              ),
            ),
          SliverToBoxAdapter(
            child: SearchBarHeader(
              hintText: 'Search movies & TV shows...',
              accent: ServiceKey.seerr.accent,
              onQueryChanged: (query) {
                ref.read(discoverSearchQueryProvider.notifier).state = query;
              },
            ),
          ),
          if (searchQuery.isEmpty)
            SliverToBoxAdapter(
              child: ServiceKpiPeek(
                kpis: ref.watch(serviceKpiProvider(ServiceKey.seerr)),
                accent: ServiceKey.seerr.accent,
              ),
            ),
        ],
        body: searchQuery.isEmpty
            ? _buildCatalog(context, ref)
            : const _DiscoverSearchResults(),
      ),
    );
  }

  Widget _buildCatalog(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async => _invalidateCatalog(ref),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          top: AppSpacing.sm,
          bottom:
              AppSpacing.xl +
              FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: [
          const _DiscoverFeatured(),
          DiscoverCarousel(
            title: 'Trending',
            sectionId: 'trending',
            items: ref.watch(discoverTrendingProvider),
            onSeeAll: () => context.push(ServiceRoutes.seerrTrendingAll),
          ),
          DiscoverCarousel(
            title: 'Popular Movies',
            sectionId: 'movies',
            items: ref.watch(discoverMoviesProvider),
            forcedMediaType: 'movie',
            onSeeAll: () => context.push(ServiceRoutes.seerrMoviesAll),
          ),
          DiscoverCarousel(
            title: 'Popular Series',
            sectionId: 'tv',
            items: ref.watch(discoverTVProvider),
            forcedMediaType: 'tv',
            onSeeAll: () => context.push(ServiceRoutes.seerrTvAll),
          ),
          DiscoverCarousel(
            title: 'Upcoming Movies',
            sectionId: 'upcoming_movies',
            items: ref.watch(discoverUpcomingMoviesProvider),
            forcedMediaType: 'movie',
          ),
          DiscoverCarousel(
            title: 'Top Rated Movies',
            sectionId: 'top_rated',
            items: ref.watch(discoverTopRatedMoviesProvider),
            forcedMediaType: 'movie',
          ),
          DiscoverCarousel(
            title: 'Upcoming Series',
            sectionId: 'upcoming_tv',
            items: ref.watch(discoverUpcomingTvProvider),
            forcedMediaType: 'tv',
          ),
          const _GenreRows(limit: _genreRowLimit),
        ],
      ),
    );
  }

  void _invalidateCatalog(WidgetRef ref) {
    ref.invalidate(discoverTrendingProvider);
    ref.invalidate(discoverMoviesProvider);
    ref.invalidate(discoverTVProvider);
    ref.invalidate(discoverUpcomingMoviesProvider);
    ref.invalidate(discoverUpcomingTvProvider);
    ref.invalidate(discoverTopRatedMoviesProvider);
    ref.invalidate(movieGenresProvider);
    ref.invalidate(requestsProvider);
  }
}

/// Genre rows built from the available movie genres.
class _GenreRows extends ConsumerWidget {
  final int limit;

  const _GenreRows({required this.limit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genresAsync = ref.watch(movieGenresProvider);
    return genresAsync.maybeWhen(
      data: (genres) {
        final visible = genres.take(limit).toList(growable: false);
        return Column(
          children: [
            for (final genre in visible)
              _GenreCarousel(genre: genre, mediaType: 'movie'),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _GenreCarousel extends ConsumerWidget {
  final SeerrGenre genre;
  final String mediaType;

  const _GenreCarousel({required this.genre, required this.mediaType});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (mediaType: mediaType, genreId: genre.id);
    return DiscoverCarousel(
      title: genre.name,
      sectionId: 'genre_${genre.id}',
      items: ref.watch(discoverByGenreProvider(key)),
      forcedMediaType: mediaType,
      onSeeAll: () => context.push(
        ServiceRoutes.seerrGenre(
          mediaType: mediaType,
          genreId: genre.id,
          title: genre.name,
        ),
      ),
    );
  }
}

/// Cinematic featured banner built from the first trending item.
class _DiscoverFeatured extends ConsumerWidget {
  const _DiscoverFeatured();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trending = ref.watch(discoverTrendingProvider);
    return trending.maybeWhen(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return _FeaturedBanner(item: items.first);
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _FeaturedBanner extends StatelessWidget {
  final MediaPreview item;

  const _FeaturedBanner({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final imageUrl = ImageUtils.buildTmdbPosterUrl(item.posterPath);
    final heroTag = 'discover_featured_${item.id}';
    final year = item.year;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: PressableScale(
        onTap: () => context.push(
          ServiceRoutes.seerrDetail(
            mediaType: item.mediaType,
            id: item.id,
            heroTag: heroTag,
            posterUrl: imageUrl,
          ),
        ),
        child: ClipRRect(
          borderRadius: AppRadius.borderRadiusLg,
          child: SizedBox(
            height: 200,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Poster fill as the textured backdrop.
                if (imageUrl.isNotEmpty)
                  ContentCard(imageUrl: imageUrl)
                else
                  ColoredBox(color: colorScheme.surfaceContainerHigh),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppGradients.heroScrim(colorScheme.surface),
                  ),
                ),
                Positioned(
                  left: AppSpacing.lg,
                  right: AppSpacing.lg,
                  bottom: AppSpacing.lg,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox(
                        width: 74,
                        height: 111,
                        child: Hero(
                          tag: heroTag,
                          child: ContentCard(imageUrl: imageUrl),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'FEATURED',
                              style: AppTheme.eyebrow(colorScheme.primary),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: colorScheme.onSurface,
                                height: 1.1,
                              ),
                            ),
                            if (year.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                year,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Search results grid with premium loading/empty/error states.
class _DiscoverSearchResults extends ConsumerWidget {
  const _DiscoverSearchResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchResults = ref.watch(discoverSearchResultsProvider);

    return searchResults.when(
      loading: () => AppSkeleton.posterGrid(),
      error: (error, _) =>
          AppErrorState(error: error, serviceName: 'search results'),
      data: (results) {
        if (results == null || results.isEmpty) {
          return const AppEmptyState(
            icon: Icons.search_off_rounded,
            title: 'No results found',
            message: 'Try a different title or spelling.',
          );
        }

        return GridView.builder(
          padding: EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.lg,
            bottom:
                AppSpacing.lg +
                FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 2 / 3,
            crossAxisSpacing: AppSpacing.gridGap,
            mainAxisSpacing: AppSpacing.gridGap,
          ),
          itemCount: results.length,
          itemBuilder: (context, index) {
            final item = results[index];
            final imageUrl = ImageUtils.buildTmdbPosterUrl(item.posterPath);
            final heroTag =
                'discover_search_${item.mediaType}_${item.id}_$index';

            return PressableScale(
              onTap: () => context.push(
                ServiceRoutes.seerrDetail(
                  mediaType: item.mediaType,
                  id: item.id,
                  heroTag: heroTag,
                  posterUrl: imageUrl,
                ),
              ),
              child: Hero(
                tag: heroTag,
                child: ContentCard(imageUrl: imageUrl),
              ),
            );
          },
        );
      },
    );
  }
}
