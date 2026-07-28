import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/discover/domain/seerr_status.dart';
import 'package:seekarr/features/discover/presentation/discover_detail_extras_provider.dart';
import 'package:seekarr/features/discover/presentation/discover_detail_view_model.dart';
import 'package:seekarr/features/discover/presentation/discover_details_provider.dart';
import 'package:seekarr/features/discover/presentation/widgets/discover_action_buttons.dart';
import 'package:seekarr/features/discover/presentation/widgets/discover_cast_list.dart';
import 'package:seekarr/features/discover/presentation/widgets/discover_collection_banner.dart';
import 'package:seekarr/features/discover/presentation/widgets/discover_release_facts.dart';
import 'package:seekarr/features/discover/presentation/widgets/discover_seasons_list.dart';
import 'package:seekarr/features/discover/presentation/widgets/discover_watch_providers.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

class DiscoverDetailScreen extends ConsumerWidget {
  final int mediaId;
  final String mediaType;
  final String heroTag;
  final String? initialPosterUrl;

  const DiscoverDetailScreen({
    super.key,
    required this.mediaId,
    required this.mediaType,
    required this.heroTag,
    this.initialPosterUrl,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final normalizedMediaType = mediaType == 'movie' ? 'movie' : 'tv';
    final region = ref.watch(regionProvider);
    final detailsAsync = ref.watch(
      discoverDetailProvider((id: mediaId, type: normalizedMediaType)),
    );

    final hasInitialPoster =
        initialPosterUrl != null && initialPosterUrl!.isNotEmpty;

    return detailsAsync.when(
      loading: () => MediaDetailLoadingView(
        // Guard against an empty (non-null) poster URL: ImageUtils returns ''
        // when there is no posterPath, which would otherwise spawn a blank
        // destination Hero with no source counterpart and fade in.
        posterCard: hasInitialPoster
            ? MediaPosterCard(
                heroTag: heroTag,
                imageUrl: initialPosterUrl,
                fallbackIcon: Icons.movie_outlined,
              )
            : null,
        backdropPosterUrl: hasInitialPoster ? initialPosterUrl : null,
      ),
      error: (error, stackTrace) => _DiscoverDetailErrorState(error: error),
      data: (details) {
        final viewModel = DiscoverDetailViewModel.fromResponse(
          details,
          initialPosterUrl: initialPosterUrl,
        );
        final isMovie = normalizedMediaType == 'movie';
        final extrasAsync = ref.watch(
          discoverDetailExtrasProvider((
            mediaId: mediaId,
            mediaType: normalizedMediaType,
            tvdbId: viewModel.tvdbId,
            voteAverage: viewModel.voteAverage,
          )),
        );
        final extras =
            extrasAsync.asData?.value ??
            (isInLibrary: null, libraryCheckDone: false, lookupRatings: null);
        final watchProviders = viewModel.watchProvidersForRegion(region);
        final contentRating = isMovie
            ? viewModel.movieContentRatingForRegion(region)
            : viewModel.tvContentRatingForRegion(region);
        final regionReleases = viewModel.releasesForRegion(region);
        final metadataItems = [
          viewModel.year,
          if (isMovie) viewModel.runtimeStr,
          if (!isMovie) viewModel.episodeSummary,
          if (!isMovie && viewModel.runtimeStr != null) viewModel.runtimeStr,
        ].whereType<String>().where((value) => value.isNotEmpty).toList();

        final isInService = extras.libraryCheckDone
            ? extras.isInLibrary ?? false
            : false;

        final tags = <Widget>[
          if (contentRating != null && contentRating.isNotEmpty)
            _CertificationChip(text: contentRating),
        ];
        final ratingWidgets = _buildRatingWidgets(
          viewModel,
          extras.lookupRatings,
        );

        return MediaDetailView(
          accent: ServiceKey.seerr.accent,
          posterUrl: viewModel.posterUrl,
          backdropUrl: viewModel.backdropUrl,
          posterRow: (collapseFactor) => MediaDetailPosterRow(
            collapseFactor: collapseFactor,
            statusBadge: StatusBadge(
              info: seerrMediaStatus(viewModel.mediaInfo),
            ),
            title: viewModel.title,
            metadataItems: metadataItems,
            tags: [
              ...tags,
              ...viewModel.genresList
                  .take(3)
                  .map((genre) => GenreChip(genre: genre)),
            ],
            posterCard: MediaPosterCard(
              heroTag: heroTag,
              imageUrl: viewModel.posterUrl,
              fallbackIcon: isMovie ? Icons.movie_outlined : Icons.tv_outlined,
            ),
          ),
          contentSections: [
            DiscoverActionButtons(
              mediaId: mediaId,
              mediaType: normalizedMediaType,
              hasManageableMedia: viewModel.hasManageableMedia,
              isInService: isInService,
              isAvailable: viewModel.isAvailable,
              tvdbId: viewModel.tvdbId,
              mediaInfo: viewModel.mediaInfo,
              title: viewModel.title,
              voteAverage: viewModel.voteAverage,
              collapseFactor: 0,
              videos: viewModel.hasRelatedVideos
                  ? viewModel.playableVideos
                  : const [],
            ),
            if (viewModel.overview.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: MediaDetailOverviewSection(overview: viewModel.overview),
              ),
            if (ratingWidgets.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: ratingWidgets,
                  ),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: SizedBox(
                width: double.infinity,
                child: isMovie
                    ? DiscoverReleaseInfoCard.movie(
                        releases: regionReleases,
                        region: region,
                        studios: viewModel.studios,
                        directors: viewModel.directors,
                        writers: viewModel.writers,
                      )
                    : DiscoverReleaseInfoCard.tv(
                        firstAirDate: viewModel.firstAirDate,
                        lastAirDate: viewModel.lastAirDate,
                        nextEpisodeToAir: viewModel.nextEpisodeToAir,
                        studios: viewModel.studios,
                        directors: viewModel.directors,
                        writers: viewModel.writers,
                        networks: viewModel.networks,
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: SizedBox(
                width: double.infinity,
                child: DiscoverWatchProviders(
                  providers: watchProviders,
                  region: region,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          slivers: [
            if (viewModel.hasSeasons)
              _DetailSectionSliver(
                child: DiscoverSeasonsList(
                  seasons: viewModel.seasons,
                  mediaInfo: viewModel.mediaInfo,
                ),
              ),
            if (viewModel.cast.isNotEmpty)
              SliverToBoxAdapter(child: DiscoverCastList(cast: viewModel.cast)),
            if (viewModel.hasCollection)
              _DetailSectionSliver(
                child: DiscoverCollectionBanner(
                  collection: viewModel.collection!,
                ),
              ),
            if (viewModel.keywords.isNotEmpty)
              SliverToBoxAdapter(
                child: _DiscoverKeywordsSection(keywords: viewModel.keywords),
              ),
          ],
        );
      },
    );
  }

  static List<Widget> _buildRatingWidgets(
    DiscoverDetailViewModel viewModel,
    List<DiscoverDetailRating>? lookupRatings,
  ) {
    if (lookupRatings != null) {
      return lookupRatings
          // A 0.0 with no votes is "not rated yet", not a score of zero.
          .where((rating) => rating.value > 0 || rating.votes > 0)
          .map(
            (rating) => RatingChip(
              value: rating.value.toStringAsFixed(1),
              votes: rating.votes,
              sourceName: rating.name,
              sourceIcon: rating.icon,
            ),
          )
          .toList(growable: false);
    }

    final voteAverage = viewModel.voteAverage;
    if (voteAverage == null || voteAverage <= 0) {
      return const [];
    }

    return [
      RatingChip(
        value: voteAverage.toStringAsFixed(1),
        votes: viewModel.voteCount ?? 0,
        sourceName: 'TMDB',
        sourceIcon: 'TMDB',
      ),
    ];
  }
}

class _DiscoverDetailErrorState extends StatelessWidget {
  final Object error;

  const _DiscoverDetailErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surface,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(pinned: true, backgroundColor: colorScheme.surface),
          SliverFillRemaining(child: Center(child: Text('Error: $error'))),
        ],
      ),
    );
  }
}

class _DiscoverKeywordsSection extends StatelessWidget {
  final List<String> keywords;

  const _DiscoverKeywordsSection({required this.keywords});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MediaDetailSectionHeader(
            title: 'Tags',
            accent: ServiceKey.seerr.accent,
          ),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: keywords
                .map(
                  (keyword) => Chip(
                    label: Text(keyword),
                    visualDensity: VisualDensity.compact,
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _DetailSectionSliver extends StatelessWidget {
  final Widget child;

  const _DetailSectionSliver({required this.child});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.md,
        ),
        child: child,
      ),
    );
  }
}

class _CertificationChip extends StatelessWidget {
  final String text;

  const _CertificationChip({required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outline),
        borderRadius: AppRadius.borderRadiusSm,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
