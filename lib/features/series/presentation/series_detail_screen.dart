import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/api/quality_profile_mixin.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/utils/snack_bar_helper.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/discover/presentation/widgets/arr_media_extras_section.dart';
import 'package:seekarr/features/import/presentation/manual_import_routes.dart';
import 'package:seekarr/features/series/data/sonarr_service.dart';
import 'package:seekarr/features/series/domain/models/sonarr_episode.dart';
import 'package:seekarr/features/series/domain/models/sonarr_series.dart';
import 'package:seekarr/features/series/domain/sonarr_status.dart';
import 'package:seekarr/features/series/presentation/series_detail_provider.dart';
import 'package:seekarr/features/series/presentation/series_detail_view_model.dart';
import 'package:seekarr/features/series/presentation/series_provider.dart';
import 'package:seekarr/features/series/presentation/widgets/series_seasons_list.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

class SeriesDetailScreen extends ConsumerStatefulWidget {
  final int seriesId;
  final String heroTag;
  final SonarrSeries? initialSeries;

  const SeriesDetailScreen({
    super.key,
    required this.seriesId,
    required this.heroTag,
    this.initialSeries,
  });

  @override
  ConsumerState<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends ConsumerState<SeriesDetailScreen>
    with QualityProfileMixin<SeriesDetailScreen> {
  bool _isSearching = false;
  bool _isDeleting = false;
  bool _isUpdatingMonitoredState = false;
  final Set<int> _searchingSeasons = {};
  final Set<int> _searchingEpisodes = {};

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(currentSettingsProvider);
    final seriesAsync = widget.seriesId > 0
        ? ref.watch(seriesDetailProvider(widget.seriesId))
        : const AsyncData<SonarrSeries?>(null);
    final episodesAsync = widget.seriesId > 0
        ? ref.watch(seriesEpisodesProvider(widget.seriesId))
        : const AsyncData<List<SonarrEpisode>>(<SonarrEpisode>[]);
    final series = seriesAsync.asData?.value ?? widget.initialSeries;

    if (series == null) {
      if (seriesAsync.isLoading) {
        return const MediaDetailLoadingView(subtitleWidth: 180);
      }

      return _SeriesDetailErrorState(
        error: seriesAsync.asError?.error ?? 'Series not found.',
        serviceName: 'Sonarr',
      );
    }

    _syncQualityProfiles(series);

    final viewModel = SeriesDetailViewModel.fromSeries(
      series,
      baseUrl: settings.sonarrUrl,
      apiKey: settings.sonarrApiKey,
    );
    final infoGroups = viewModel.buildInfoGroups(currentProfileName ?? '');

    // Without the queue the badge cannot tell "nothing on disk" from "being
    // downloaded right now", and every in-flight series reads as Missing.
    final queueEntry = ref
        .watch(sonarrQueueSnapshotProvider)
        .maybeWhen(
          data: (snapshot) => snapshot.entryFor(series.id),
          orElse: () => null,
        );
    final status = sonarrSeriesStatus(series, queueEntry: queueEntry);

    return MediaDetailView(
      accent: ServiceKey.sonarr.accent,
      posterUrl: viewModel.posterUrl,
      posterHeaders: viewModel.posterHeaders,
      backdropUrl: viewModel.backdropUrl,
      posterRow: (collapseFactor) =>
          _buildPosterRow(context, viewModel, status, collapseFactor),
      contentSections: _buildContentSections(
        viewModel,
        infoGroups,
        episodesAsync,
        series.id > 0 ? series.id : widget.seriesId,
        series.tmdbId,
      ),
    );
  }

  void _syncQualityProfiles(SonarrSeries series) {
    if (series.id <= 0 || series.path?.isNotEmpty != true) {
      return;
    }

    ensureQualityProfiles(
      profileId: series.qualityProfileId,
      fetchProfiles: () => ref.read(sonarrServiceProvider).getQualityProfiles(),
    );
  }

  Widget _buildPosterRow(
    BuildContext context,
    SeriesDetailViewModel viewModel,
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
        fallbackIcon: Icons.tv_outlined,
      ),
    );
  }

  List<Widget> _buildContentSections(
    SeriesDetailViewModel viewModel,
    List<MediaInfoGroup> infoGroups,
    AsyncValue<List<SonarrEpisode>> episodesAsync,
    int seriesId,
    int tmdbId,
  ) {
    final detailInfoGroups = _detailInfoGroups(infoGroups);

    return [
      LibraryDetailActions(
        collapseFactor: 0,
        accent: ServiceKey.sonarr.accent,
        isInLibrary: viewModel.isInLibrary,
        isMonitored: viewModel.isMonitored,
        addLabel: 'Add Series',
        isSearching: _isSearching,
        isDeleting: _isDeleting,
        isUpdatingMonitoredState: _isUpdatingMonitoredState,
        currentProfileName: currentProfileName,
        currentProfileId: currentProfileId,
        qualityProfiles: qualityProfiles,
        onPrimaryAction: () => _handlePrimaryAction(
          context,
          viewModel: viewModel,
          seriesId: seriesId,
        ),
        onInteractiveSearch: () =>
            _showInteractiveSearch(context, title: viewModel.title),
        onAutoSearch: () => _triggerSearch(context),
        onProfileSelected: _updateProfile,
        onImport: openManualImportCallback(
          context,
          ServiceKey.sonarr,
          seriesId,
        ),
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
              accent: ServiceKey.sonarr.accent,
            ),
          ),
        ),
      ],
      if (viewModel.hasFiles && viewModel.path != null) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: FileInfoSection(
            path: viewModel.path,
            accent: ServiceKey.sonarr.accent,
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
                accent: ServiceKey.sonarr.accent,
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
      if (viewModel.isInLibrary) ...[
        _buildSeasonsSection(context, viewModel, episodesAsync),
        const SizedBox(height: AppSpacing.lg),
      ],
      ArrMediaExtrasSection(
        tmdbId: tmdbId,
        mediaType: 'tv',
        accent: ServiceKey.sonarr.accent,
      ),
      if (viewModel.genres.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: MediaDetailTagsSection(
            tags: viewModel.genres,
            accent: ServiceKey.sonarr.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    ];
  }

  List<Widget> _buildSummaryTags(SeriesDetailViewModel viewModel) {
    return viewModel.genres
        .map((genre) => GenreChip(genre: genre))
        .toList(growable: false);
  }

  List<MediaInfoGroup> _detailInfoGroups(List<MediaInfoGroup> infoGroups) =>
      infoGroups;

  Future<void> _handlePrimaryAction(
    BuildContext context, {
    required SeriesDetailViewModel viewModel,
    required int seriesId,
  }) async {
    if (!viewModel.isInLibrary || seriesId <= 0) {
      SnackBarHelper.info(
        context,
        'Add Series is not available yet from this view.',
      );
      return;
    }

    await _updateMonitoredState(
      context,
      seriesId: seriesId,
      monitored: !viewModel.isMonitored,
    );
  }

  Future<void> _updateMonitoredState(
    BuildContext context, {
    required int seriesId,
    required bool monitored,
  }) async {
    setState(() => _isUpdatingMonitoredState = true);
    try {
      final sonarrService = ref.read(sonarrServiceProvider);
      await sonarrService.updateSeriesMonitored(seriesId, monitored);
      if (!mounted) return;
      ref.invalidate(seriesDetailProvider(seriesId));
      ref.invalidate(seriesProvider);
      SnackBarHelper.success(
        context,
        monitored ? 'Series monitored' : 'Series unmonitored',
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.error(context, 'Failed to update monitoring: $e');
    } finally {
      if (mounted) setState(() => _isUpdatingMonitoredState = false);
    }
  }

  Widget _buildSeasonsSection(
    BuildContext context,
    SeriesDetailViewModel viewModel,
    AsyncValue<List<SonarrEpisode>> episodesAsync,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MediaDetailSectionHeader(
            title: 'Seasons',
            accent: ServiceKey.sonarr.accent,
          ),
          SeriesSeasonsList(
            seasons: viewModel.seasons,
            episodesAsync: episodesAsync,
            onSearchSeason: (seasonNumber) =>
                _searchSeason(context, seasonNumber),
            onInteractiveSearchSeason: (seasonNumber) =>
                _interactiveSearchSeason(
                  context,
                  seasonNumber,
                  title: viewModel.title,
                ),
            onSearchEpisode: (episodeId) => _searchEpisode(context, episodeId),
            onInteractiveSearchEpisode: (episodeId) =>
                _interactiveSearchEpisode(context, episodeId),
            searchingSeasons: _searchingSeasons,
            searchingEpisodes: _searchingEpisodes,
          ),
        ],
      ),
    );
  }

  Future<void> _triggerSearch(BuildContext context) async {
    setState(() => _isSearching = true);
    try {
      final sonarrService = ref.read(sonarrServiceProvider);
      await sonarrService.searchSeries(widget.seriesId);
      if (!context.mounted) return;
      SnackBarHelper.success(context, 'Search started for entire series');
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
    int? seasonNumber,
  }) async {
    final sonarrService = ref.read(sonarrServiceProvider);
    await InteractiveSearchSheet.showAsync(
      context: context,
      accent: ServiceKey.sonarr.accent,
      title: seasonNumber != null
          ? 'Releases for $title - Season $seasonNumber'
          : 'Releases for $title',
      fetchReleases: (token) => sonarrService.getReleases(
        seriesId: widget.seriesId,
        seasonNumber: seasonNumber ?? 1,
        cancelToken: token,
      ),
      onGrabRelease: (guid, indexerId) async {
        await sonarrService.grabRelease(guid: guid, indexerId: indexerId);
      },
    );
  }

  Future<void> _searchSeason(BuildContext context, int seasonNumber) async {
    setState(() => _searchingSeasons.add(seasonNumber));
    try {
      final sonarrService = ref.read(sonarrServiceProvider);
      await sonarrService.searchSeason(widget.seriesId, seasonNumber);
      if (!context.mounted) return;
      SnackBarHelper.success(
        context,
        'Search started for Season $seasonNumber',
      );
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.error(context, 'Search failed: $e');
    } finally {
      if (mounted) setState(() => _searchingSeasons.remove(seasonNumber));
    }
  }

  Future<void> _interactiveSearchSeason(
    BuildContext context,
    int seasonNumber, {
    required String title,
  }) async {
    setState(() => _searchingSeasons.add(seasonNumber));
    try {
      await _showInteractiveSearch(
        context,
        title: title,
        seasonNumber: seasonNumber,
      );
    } finally {
      if (mounted) setState(() => _searchingSeasons.remove(seasonNumber));
    }
  }

  Future<void> _searchEpisode(BuildContext context, int episodeId) async {
    setState(() => _searchingEpisodes.add(episodeId));
    try {
      final sonarrService = ref.read(sonarrServiceProvider);
      await sonarrService.searchEpisodes([episodeId]);
      if (!context.mounted) return;
      SnackBarHelper.success(context, 'Episode search started');
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.error(context, 'Search failed: $e');
    } finally {
      if (mounted) setState(() => _searchingEpisodes.remove(episodeId));
    }
  }

  Future<void> _interactiveSearchEpisode(
    BuildContext context,
    int episodeId,
  ) async {
    final sonarrService = ref.read(sonarrServiceProvider);
    await InteractiveSearchSheet.showAsync(
      context: context,
      accent: ServiceKey.sonarr.accent,
      title: 'Episode Releases',
      fetchReleases: (token) =>
          sonarrService.getReleases(episodeId: episodeId, cancelToken: token),
      onGrabRelease: (guid, indexerId) async {
        await sonarrService.grabRelease(guid: guid, indexerId: indexerId);
      },
    );
  }

  Future<void> _updateProfile(int profileId) async {
    try {
      final sonarrService = ref.read(sonarrServiceProvider);
      await sonarrService.updateSeriesProfile(widget.seriesId, profileId);
      if (mounted) {
        updateProfileState(profileId);
        ref.invalidate(seriesProvider);
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
    final result = await showDeleteMediaDialog(
      context: context,
      title: title,
      mediaType: DeleteMediaType.series,
    );

    if (!result.confirmed || !context.mounted) return;

    setState(() => _isDeleting = true);
    try {
      final sonarrService = ref.read(sonarrServiceProvider);
      await sonarrService.deleteSeries(
        widget.seriesId,
        deleteFiles: result.deleteFiles,
        addImportListExclusion: result.addExclusion,
      );
      if (!context.mounted) return;
      SnackBarHelper.success(context, 'Series deleted');
      context.pop();
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.error(context, 'Failed to delete series: $e');
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }
}

class _SeriesDetailErrorState extends StatelessWidget {
  final Object error;
  final String serviceName;

  const _SeriesDetailErrorState({
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
