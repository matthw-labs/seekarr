import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/api/quality_profile_mixin.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/utils/snack_bar_helper.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/discover/presentation/widgets/arr_media_extras_section.dart';
import 'package:seekarr/features/import/presentation/manual_import_routes.dart';
import 'package:seekarr/features/movies/data/radarr_service.dart';
import 'package:seekarr/features/movies/domain/models/radarr_movie.dart';
import 'package:seekarr/features/movies/domain/radarr_status.dart';
import 'package:seekarr/features/movies/presentation/movie_detail_provider.dart';
import 'package:seekarr/features/movies/presentation/movie_detail_view_model.dart';
import 'package:seekarr/features/movies/presentation/movies_provider.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// Detail screen for a Radarr movie with M3 styling.
class MovieDetailScreen extends ConsumerStatefulWidget {
  final int movieId;
  final String heroTag;
  final RadarrMovie? initialMovie;

  const MovieDetailScreen({
    super.key,
    required this.movieId,
    required this.heroTag,
    this.initialMovie,
  });

  @override
  ConsumerState<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends ConsumerState<MovieDetailScreen>
    with QualityProfileMixin<MovieDetailScreen> {
  bool _isSearching = false;
  bool _isDeleting = false;
  bool _isUpdatingMonitoredState = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(currentSettingsProvider);
    final movieAsync = widget.movieId > 0
        ? ref.watch(movieDetailProvider(widget.movieId))
        : const AsyncData<RadarrMovie?>(null);
    final movie = movieAsync.asData?.value ?? widget.initialMovie;

    if (movie == null) {
      if (movieAsync.isLoading) {
        return const MediaDetailLoadingView();
      }

      return _MovieDetailErrorState(
        error: movieAsync.asError?.error ?? 'Movie not found.',
        serviceName: 'Radarr',
      );
    }

    _syncQualityProfiles(movie);

    final viewModel = MovieDetailViewModel.fromMovie(
      movie,
      baseUrl: settings.radarrUrl,
      apiKey: settings.radarrApiKey,
    );
    final infoGroups = viewModel.buildInfoGroups(currentProfileName ?? '');

    // Without the queue the badge cannot tell "nothing on disk" from "being
    // downloaded right now", and every in-flight movie reads as Missing.
    final queueEntry = ref
        .watch(radarrQueueSnapshotProvider)
        .maybeWhen(
          data: (snapshot) => snapshot.entryFor(movie.id),
          orElse: () => null,
        );
    final status = radarrMovieStatus(movie, queueEntry: queueEntry);

    return MediaDetailView(
      accent: ServiceKey.radarr.accent,
      posterUrl: viewModel.posterUrl,
      posterHeaders: viewModel.posterHeaders,
      backdropUrl: viewModel.backdropUrl,
      posterRow: (collapseFactor) =>
          _buildPosterRow(context, viewModel, status, collapseFactor),
      contentSections: _buildContentSections(
        viewModel,
        infoGroups,
        movie.id > 0 ? movie.id : widget.movieId,
        movie.tmdbId,
      ),
    );
  }

  void _syncQualityProfiles(RadarrMovie movie) {
    if (movie.id <= 0 || movie.path?.isNotEmpty != true) {
      return;
    }

    ensureQualityProfiles(
      profileId: movie.qualityProfileId,
      fetchProfiles: () => ref.read(radarrServiceProvider).getQualityProfiles(),
    );
  }

  Widget _buildPosterRow(
    BuildContext context,
    MovieDetailViewModel viewModel,
    MediaStatusInfo status,
    double collapseFactor,
  ) {
    return MediaDetailPosterRow(
      collapseFactor: collapseFactor,
      statusBadge: StatusBadge(info: status),
      title: viewModel.title,
      metadataItems: viewModel.metadataItems,
      tags: _buildSummaryTags(viewModel),
      posterCard: MediaPosterCard(
        heroTag: widget.heroTag,
        imageUrl: viewModel.posterUrl,
        imageHeaders: viewModel.posterHeaders,
        fallbackIcon: Icons.movie_outlined,
      ),
    );
  }

  List<Widget> _buildContentSections(
    MovieDetailViewModel viewModel,
    List<MediaInfoGroup> infoGroups,
    int movieId,
    int tmdbId,
  ) {
    final detailInfoGroups = _detailInfoGroups(infoGroups);

    return [
      LibraryDetailActions(
        collapseFactor: 0,
        accent: ServiceKey.radarr.accent,
        isInLibrary: viewModel.isInLibrary,
        isMonitored: viewModel.isMonitored,
        addLabel: 'Add Movie',
        isSearching: _isSearching,
        isDeleting: _isDeleting,
        isUpdatingMonitoredState: _isUpdatingMonitoredState,
        currentProfileName: currentProfileName,
        currentProfileId: currentProfileId,
        qualityProfiles: qualityProfiles,
        onPrimaryAction: () => _handlePrimaryAction(
          context,
          viewModel: viewModel,
          movieId: movieId,
        ),
        onInteractiveSearch: () =>
            _showInteractiveSearch(context, title: viewModel.title),
        onAutoSearch: () => _triggerSearch(context),
        onProfileSelected: _updateProfile,
        onImport: openManualImportCallback(context, ServiceKey.radarr, movieId),
        onDelete: () => _confirmDelete(context, title: viewModel.title),
      ),
      if (viewModel.overview.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: MediaDetailOverviewSection(overview: viewModel.overview),
        ),
      ],
      if (viewModel.ratings.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: SizedBox(
            width: double.infinity,
            child: RatingChipsRow(
              ratings: viewModel.ratings,
              accent: ServiceKey.radarr.accent,
            ),
          ),
        ),
      ],
      if (viewModel.hasFile && viewModel.path != null) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: FileInfoSection(
            path: viewModel.path,
            filename: viewModel.filename,
            accent: ServiceKey.radarr.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      if (detailInfoGroups.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MediaDetailSectionHeader(
                title: 'Details',
                accent: ServiceKey.radarr.accent,
              ),
              SizedBox(
                width: double.infinity,
                child: MediaInfoCard(groups: detailInfoGroups),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
      ArrMediaExtrasSection(
        tmdbId: tmdbId,
        mediaType: 'movie',
        accent: ServiceKey.radarr.accent,
      ),
      if (viewModel.genres.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: MediaDetailTagsSection(
            tags: viewModel.genres,
            accent: ServiceKey.radarr.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    ];
  }

  List<Widget> _buildSummaryTags(MovieDetailViewModel viewModel) {
    return viewModel.genres
        .map((genre) => GenreChip(genre: genre))
        .toList(growable: false);
  }

  List<MediaInfoGroup> _detailInfoGroups(List<MediaInfoGroup> infoGroups) =>
      infoGroups;

  Future<void> _handlePrimaryAction(
    BuildContext context, {
    required MovieDetailViewModel viewModel,
    required int movieId,
  }) async {
    if (!viewModel.isInLibrary || movieId <= 0) {
      SnackBarHelper.info(
        context,
        'Add Movie is not available yet from this view.',
      );
      return;
    }

    await _updateMonitoredState(
      context,
      movieId: movieId,
      monitored: !viewModel.isMonitored,
    );
  }

  Future<void> _updateMonitoredState(
    BuildContext context, {
    required int movieId,
    required bool monitored,
  }) async {
    setState(() => _isUpdatingMonitoredState = true);
    try {
      final radarrService = ref.read(radarrServiceProvider);
      await radarrService.updateMovieMonitored(movieId, monitored);
      if (!mounted) return;
      ref.invalidate(movieDetailProvider(movieId));
      ref.invalidate(moviesProvider);
      SnackBarHelper.success(
        context,
        monitored ? 'Movie monitored' : 'Movie unmonitored',
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.error(context, 'Failed to update monitoring: $e');
    } finally {
      if (mounted) setState(() => _isUpdatingMonitoredState = false);
    }
  }

  Future<void> _updateProfile(int profileId) async {
    try {
      final radarrService = ref.read(radarrServiceProvider);
      await radarrService.updateMovieProfile(widget.movieId, profileId);
      if (mounted) {
        updateProfileState(profileId);
        ref.invalidate(moviesProvider);
        SnackBarHelper.success(context, 'Quality profile updated');
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.error(context, 'Failed to update profile: $e');
    }
  }

  Future<void> _confirmDelete(
    BuildContext context, {
    required String title,
  }) async {
    HapticFeedback.mediumImpact();

    final result = await showDeleteMediaDialog(
      context: context,
      title: title,
      mediaType: DeleteMediaType.movie,
    );

    if (!result.confirmed || !context.mounted) return;

    setState(() => _isDeleting = true);
    try {
      final radarrService = ref.read(radarrServiceProvider);
      await radarrService.deleteMovie(
        widget.movieId,
        deleteFiles: result.deleteFiles,
        addImportExclusion: result.addExclusion,
      );
      if (!context.mounted) return;
      SnackBarHelper.success(context, 'Movie deleted');
      context.pop();
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.error(context, 'Failed to delete movie: $e');
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<void> _triggerSearch(BuildContext context) async {
    HapticFeedback.selectionClick();
    setState(() => _isSearching = true);
    try {
      final radarrService = ref.read(radarrServiceProvider);
      await radarrService.searchMovie(widget.movieId);
      if (!context.mounted) return;
      SnackBarHelper.success(context, 'Search started');
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.error(context, 'Search failed: $e');
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _showInteractiveSearch(
    BuildContext context, {
    required String title,
  }) async {
    HapticFeedback.selectionClick();
    final radarrService = ref.read(radarrServiceProvider);
    await InteractiveSearchSheet.showAsync(
      context: context,
      accent: ServiceKey.radarr.accent,
      title: 'Releases for $title',
      fetchReleases: (token) =>
          radarrService.getReleases(widget.movieId, cancelToken: token),
      onGrabRelease: (guid, indexerId) async {
        await radarrService.grabRelease(guid: guid, indexerId: indexerId);
      },
    );
  }
}

class _MovieDetailErrorState extends StatelessWidget {
  final Object error;
  final String serviceName;

  const _MovieDetailErrorState({
    required this.error,
    required this.serviceName,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isNotConfigured = error.toString().contains('not configured');

    return Material(
      color: colorScheme.surface,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(pinned: true, backgroundColor: colorScheme.surface),
          SliverFillRemaining(
            child: isNotConfigured
                ? NotConfiguredPlaceholder(serviceName: serviceName)
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Text(
                        'Error: $error',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
