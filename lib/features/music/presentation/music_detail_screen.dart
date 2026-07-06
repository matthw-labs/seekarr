import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/api/quality_profile_mixin.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/utils/snack_bar_helper.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/import/presentation/manual_import_routes.dart';
import 'package:seekarr/features/music/data/lidarr_service.dart';
import 'package:seekarr/features/music/domain/models/lidarr_album.dart';
import 'package:seekarr/features/music/domain/models/lidarr_artist.dart';
import 'package:seekarr/features/music/presentation/music_detail_provider.dart';
import 'package:seekarr/features/music/presentation/music_detail_view_model.dart';
import 'package:seekarr/features/music/presentation/music_provider.dart';
import 'package:seekarr/features/music/presentation/widgets/music_albums_list.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

class MusicDetailScreen extends ConsumerStatefulWidget {
  final int artistId;
  final String heroTag;
  final LidarrArtist? initialArtist;

  const MusicDetailScreen({
    super.key,
    required this.artistId,
    required this.heroTag,
    this.initialArtist,
  });

  @override
  ConsumerState<MusicDetailScreen> createState() => _MusicDetailScreenState();
}

class _MusicDetailScreenState extends ConsumerState<MusicDetailScreen>
    with QualityProfileMixin<MusicDetailScreen> {
  bool _isSearching = false;
  bool _isDeleting = false;
  bool _isUpdatingMonitoredState = false;
  final Set<int> _searchingAlbums = {};

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(currentSettingsProvider);
    final artistAsync = widget.artistId > 0
        ? ref.watch(musicDetailProvider(widget.artistId))
        : const AsyncData<LidarrArtist?>(null);
    final albumsAsync = widget.artistId > 0
        ? ref.watch(musicAlbumsProvider(widget.artistId))
        : const AsyncData<List<LidarrAlbum>>(<LidarrAlbum>[]);
    final artist = artistAsync.asData?.value ?? widget.initialArtist;

    if (artist == null) {
      if (artistAsync.isLoading) {
        return const MediaDetailLoadingView(subtitleWidth: 180);
      }

      return _MusicDetailErrorState(
        error: artistAsync.asError?.error ?? 'Artist not found.',
        serviceName: 'Lidarr',
      );
    }

    _syncQualityProfiles(artist);

    final viewModel = MusicDetailViewModel.fromArtist(
      artist,
      baseUrl: settings.lidarrUrl,
      apiKey: settings.lidarrApiKey,
    );
    final infoGroups = viewModel.buildInfoGroups(currentProfileName ?? '');

    return MediaDetailView(
      accent: ServiceKey.lidarr.accent,
      posterUrl: viewModel.posterUrl,
      posterHeaders: viewModel.posterHeaders,
      backdropUrl: viewModel.backdropUrl,
      posterRow: (collapseFactor) =>
          _buildPosterRow(context, viewModel, collapseFactor),
      contentSections: _buildContentSections(
        viewModel,
        infoGroups,
        artist.id > 0 ? artist.id : widget.artistId,
      ),
      slivers: viewModel.isInLibrary
          ? [_buildAlbumsSliver(context, settings, albumsAsync)]
          : const [],
    );
  }

  void _syncQualityProfiles(LidarrArtist artist) {
    if (artist.id <= 0 || artist.path?.isNotEmpty != true) {
      return;
    }

    ensureQualityProfiles(
      profileId: artist.qualityProfileId,
      fetchProfiles: () => ref.read(lidarrServiceProvider).getQualityProfiles(),
    );
  }

  List<Widget> _buildTags(MusicDetailViewModel viewModel) {
    return [
      if (viewModel.albumCountLabel != null)
        TagChip(text: viewModel.albumCountLabel!),
      if (viewModel.trackCountLabel != null)
        TagChip(text: viewModel.trackCountLabel!),
    ];
  }

  Widget _buildPosterRow(
    BuildContext context,
    MusicDetailViewModel viewModel,
    double collapseFactor,
  ) {
    return MediaDetailPosterRow(
      collapseFactor: collapseFactor,
      statusBadge: StatusBadge.fromMedia(
        fileCount: viewModel.trackFileCount,
        totalCount: viewModel.trackCount,
        hasFile: viewModel.hasFiles,
        status: viewModel.status,
      ),
      title: viewModel.title,
      metadataItems: viewModel.metadataItems,
      tags: _buildTags(viewModel),
      circularPoster: true,
      posterCard: MediaPosterCard(
        heroTag: widget.heroTag,
        imageUrl: viewModel.posterUrl,
        imageHeaders: viewModel.posterHeaders,
        fallbackIcon: Icons.album_outlined,
        circular: true,
      ),
    );
  }

  List<Widget> _buildContentSections(
    MusicDetailViewModel viewModel,
    List<MediaInfoGroup> infoGroups,
    int artistId,
  ) {
    return [
      LibraryDetailActions(
        collapseFactor: 0,
        accent: ServiceKey.lidarr.accent,
        isInLibrary: viewModel.isInLibrary,
        isMonitored: viewModel.isMonitored,
        addLabel: 'Add Artist',
        isSearching: _isSearching,
        isDeleting: _isDeleting,
        isUpdatingMonitoredState: _isUpdatingMonitoredState,
        currentProfileName: currentProfileName,
        currentProfileId: currentProfileId,
        qualityProfiles: qualityProfiles,
        onPrimaryAction: () => _handlePrimaryAction(
          context,
          viewModel: viewModel,
          artistId: artistId,
        ),
        onInteractiveSearch: () =>
            _showInteractiveSearch(context, title: viewModel.title),
        onAutoSearch: () => _triggerSearch(context),
        onProfileSelected: _updateProfile,
        onImport: openManualImportCallback(
          context,
          ServiceKey.lidarr,
          artistId,
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
            child: RatingChipsRow(ratings: viewModel.ratings),
          ),
        ),
      ],
      if (infoGroups.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MediaDetailSectionHeader(
                title: 'Details',
                accent: ServiceKey.lidarr.accent,
              ),
              SizedBox(
                width: double.infinity,
                child: MediaInfoCard(groups: infoGroups),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
      if (viewModel.genres.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: MediaDetailTagsSection(tags: viewModel.genres),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    ];
  }

  Future<void> _handlePrimaryAction(
    BuildContext context, {
    required MusicDetailViewModel viewModel,
    required int artistId,
  }) async {
    if (!viewModel.isInLibrary || artistId <= 0) {
      SnackBarHelper.info(
        context,
        'Add Artist is not available yet from this view.',
      );
      return;
    }

    await _updateMonitoredState(
      context,
      artistId: artistId,
      monitored: !viewModel.isMonitored,
    );
  }

  Future<void> _updateMonitoredState(
    BuildContext context, {
    required int artistId,
    required bool monitored,
  }) async {
    setState(() => _isUpdatingMonitoredState = true);
    try {
      final lidarrService = ref.read(lidarrServiceProvider);
      await lidarrService.updateArtistMonitored(artistId, monitored);
      if (!mounted) return;
      ref.invalidate(musicDetailProvider(artistId));
      ref.invalidate(musicProvider);
      SnackBarHelper.success(
        context,
        monitored ? 'Artist monitored' : 'Artist unmonitored',
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.error(context, 'Failed to update monitoring: $e');
    } finally {
      if (mounted) setState(() => _isUpdatingMonitoredState = false);
    }
  }

  Widget _buildAlbumsSliver(
    BuildContext context,
    SettingsModel settings,
    AsyncValue<List<LidarrAlbum>> albumsAsync,
  ) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const MediaDetailSectionHeader(title: 'Albums'),
            albumsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stackTrace) => Text(
                'Failed to load albums.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              data: (albums) => MusicAlbumsList(
                albums: albums,
                lidarrService: ref.read(lidarrServiceProvider),
                baseUrl: settings.lidarrUrl,
                apiKey: settings.lidarrApiKey,
                onSearchAlbum: (albumId) => _searchAlbum(context, albumId),
                onInteractiveSearchAlbum: (albumId) =>
                    _interactiveSearchAlbum(context, albumId),
                searchingAlbums: _searchingAlbums,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateProfile(int profileId) async {
    try {
      final lidarrService = ref.read(lidarrServiceProvider);
      await lidarrService.updateArtistProfile(widget.artistId, profileId);
      if (mounted) {
        updateProfileState(profileId);
        ref.invalidate(musicProvider);
        SnackBarHelper.success(context, 'Quality profile updated');
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.error(context, 'Failed to update profile: $e');
    }
  }

  Future<void> _triggerSearch(BuildContext context) async {
    setState(() => _isSearching = true);
    try {
      final lidarrService = ref.read(lidarrServiceProvider);
      await lidarrService.searchArtist(widget.artistId);
      if (!context.mounted) return;
      SnackBarHelper.success(context, 'Search started for artist');
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
    final lidarrService = ref.read(lidarrServiceProvider);
    await InteractiveSearchSheet.showAsync(
      context: context,
      title: 'Releases for $title',
      fetchReleases: (token) => lidarrService.getReleases(
        artistId: widget.artistId,
        cancelToken: token,
      ),
      onGrabRelease: (guid, indexerId) async {
        await lidarrService.grabRelease(guid: guid, indexerId: indexerId);
      },
    );
  }

  Future<void> _searchAlbum(BuildContext context, int albumId) async {
    setState(() => _searchingAlbums.add(albumId));
    try {
      final lidarrService = ref.read(lidarrServiceProvider);
      await lidarrService.searchAlbums([albumId]);
      if (!context.mounted) return;
      SnackBarHelper.success(context, 'Album search started');
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.error(context, 'Search failed: $e');
    } finally {
      if (mounted) setState(() => _searchingAlbums.remove(albumId));
    }
  }

  Future<void> _interactiveSearchAlbum(
    BuildContext context,
    int albumId,
  ) async {
    final lidarrService = ref.read(lidarrServiceProvider);
    await InteractiveSearchSheet.showAsync(
      context: context,
      title: 'Album Releases',
      fetchReleases: (token) =>
          lidarrService.getReleases(albumId: albumId, cancelToken: token),
      onGrabRelease: (guid, indexerId) async {
        await lidarrService.grabRelease(guid: guid, indexerId: indexerId);
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context, {
    required String title,
  }) async {
    final result = await showDeleteMediaDialog(
      context: context,
      title: title,
      mediaType: DeleteMediaType.artist,
    );

    if (!result.confirmed || !context.mounted) return;

    setState(() => _isDeleting = true);
    try {
      final lidarrService = ref.read(lidarrServiceProvider);
      await lidarrService.deleteArtist(
        widget.artistId,
        deleteFiles: result.deleteFiles,
        addImportListExclusion: result.addExclusion,
      );
      if (!context.mounted) return;
      SnackBarHelper.success(context, 'Artist deleted');
      context.pop();
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.error(context, 'Failed to delete artist: $e');
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }
}

class _MusicDetailErrorState extends StatelessWidget {
  final Object error;
  final String serviceName;

  const _MusicDetailErrorState({
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
