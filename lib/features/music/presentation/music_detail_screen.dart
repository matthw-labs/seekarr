import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/api/quality_profile_mixin.dart';
import 'package:seekarr/core/app_animation.dart';
import 'package:seekarr/core/status/arr_queue_snapshot.dart';
import 'package:seekarr/core/utils/rating_display.dart';
import 'package:seekarr/core/utils/snack_bar_helper.dart';
import 'package:seekarr/core/utils/string_utils.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/import/presentation/manual_import_routes.dart';
import 'package:seekarr/features/music/data/lidarr_service.dart';
import 'package:seekarr/features/music/domain/lidarr_status.dart';
import 'package:seekarr/features/music/domain/models/lidarr_album.dart';
import 'package:seekarr/features/music/domain/models/lidarr_artist.dart';
import 'package:seekarr/features/music/presentation/music_detail_provider.dart';
import 'package:seekarr/features/music/presentation/music_detail_view_model.dart';
import 'package:seekarr/features/music/presentation/music_provider.dart';
import 'package:seekarr/features/music/presentation/widgets/music_albums_list.dart';
import 'package:seekarr/features/release_search/domain/release_search_target.dart';
import 'package:seekarr/features/release_search/presentation/release_search_entry.dart';
import 'package:seekarr/features/release_search/presentation/widgets/release_search_status_card.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
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
  bool _isAutoSearching = false;
  bool _isAutoSearchConfirmed = false;
  Timer? _searchConfirmTimer;

  @override
  void dispose() {
    _searchConfirmTimer?.cancel();
    super.dispose();
  }

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
        return MediaDetailLoadingView(
          accent: ServiceKey.lidarr.accent,
          heroFallbackIcon: Icons.album_outlined,
        );
      }

      return MediaDetailPlaceholderView.error(
        error: artistAsync.asError?.error ?? 'Artist not found.',
        serviceName: 'Lidarr',
        accent: ServiceKey.lidarr.accent,
        // Recover in place. Both loads share one outage, so one retry re-runs
        // both. With no id there is no provider to re-run, so no retry is
        // offered rather than one that does nothing.
        onRetry: widget.artistId > 0
            ? () {
                ref.invalidate(musicDetailProvider(widget.artistId));
                ref.invalidate(musicAlbumsProvider(widget.artistId));
              }
            : null,
      );
    }

    _syncQualityProfiles(artist);

    final viewModel = MusicDetailViewModel.fromArtist(
      artist,
      baseUrl: settings.lidarrUrl,
      apiKey: settings.lidarrApiKey,
    );
    final infoGroups = viewModel.buildInfoGroups(currentProfileName ?? '');

    // One fetch feeds both the artist badge and the per-album badges below.
    final queues = ref
        .watch(lidarrQueueSnapshotsProvider)
        .maybeWhen(data: (snapshots) => snapshots, orElse: () => null);
    final status = lidarrArtistStatus(
      artist,
      queueEntry: queues?.byArtist.entryFor(artist.id),
    );

    return MediaDetailView(
      accent: ServiceKey.lidarr.accent,
      heroFallbackIcon: Icons.album_outlined,
      posterUrl: viewModel.posterUrl,
      posterHeaders: viewModel.posterHeaders,
      backdropUrl: viewModel.backdropUrl,
      title: viewModel.title,
      posterRow: _buildPosterRow(context, viewModel, status),
      onRefresh: widget.artistId > 0
          ? () async {
              ref.invalidate(musicDetailProvider(widget.artistId));
              ref.invalidate(musicAlbumsProvider(widget.artistId));
            }
          : null,
      body: _buildBody(
        context,
        viewModel,
        status,
        infoGroups,
        settings,
        albumsAsync,
        queues?.byAlbum ?? ArrQueueSnapshot.empty,
        artist.id > 0 ? artist.id : widget.artistId,
      ),
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

  /// The hero chip slot: how much of the manifest exists. Lidarr already did
  /// this by accident, which is why it is the case the other six variants were
  /// generalised onto.
  List<Widget> _buildTags(MusicDetailViewModel viewModel) {
    return [
      if (viewModel.albumCountLabel != null)
        TagChip(
          text: viewModel.albumCountLabel!,
          color: ServiceKey.lidarr.accent,
        ),
      if (viewModel.trackCountLabel != null)
        TagChip(
          text: viewModel.trackCountLabel!,
          color: ServiceKey.lidarr.accent,
        ),
    ];
  }

  Widget _buildPosterRow(
    BuildContext context,
    MusicDetailViewModel viewModel,
    MediaStatusInfo status,
  ) {
    return MediaDetailPosterRow(
      statusBadge: StatusBadge.animated(info: status),
      title: viewModel.title,
      // The counts are the chip slot's one meaning, so they are stated there and
      // not also in the metadata line, which used to carry the identical pair.
      metadataItems: const [],
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

  MediaDetailBody _buildBody(
    BuildContext context,
    MusicDetailViewModel viewModel,
    MediaStatusInfo status,
    List<MediaInfoGroup> infoGroups,
    SettingsModel settings,
    AsyncValue<List<LidarrAlbum>> albumsAsync,
    ArrQueueSnapshot albumQueue,
    int artistId,
  ) {
    final accent = ServiceKey.lidarr.accent;
    final tracks = viewModel.trackCount;

    return MediaDetailBody(
      deck: viewModel.isInLibrary
          ? LibraryDetailActions(
              service: ServiceKey.lidarr,
              status: status,
              mediaTitle: viewModel.title,
              isMonitored: viewModel.isMonitored,
              partialSummary: tracks > 0
                  ? '${viewModel.trackFileCount} of $tracks tracks on disk.'
                  : null,
              isBusy:
                  _isAutoSearching || _isUpdatingMonitoredState || _isDeleting,
              isConfirmed: _isAutoSearchConfirmed,
              currentProfileName: currentProfileName,
              currentProfileId: currentProfileId,
              qualityProfiles: qualityProfiles,
              onSearch: () => _triggerSearch(context),
              onInteractiveSearch: () =>
                  _showInteractiveSearch(context, title: viewModel.title),
              onImport: openManualImportCallback(
                context,
                ServiceKey.lidarr,
                artistId,
              ),
              // Every in-flight pipeline state promotes 'Open queue' only if the
              // host actually has a route for it; without this the most common
              // transient state on a real page degraded to a sentence. Pushed, not
              // gone: checking on a download should leave the title behind you.
              onOpenQueue: () => context.push('/activity/music'),
              onMonitoredChanged: (monitored) => _updateMonitoredState(
                context,
                artistId: artistId,
                monitored: monitored,
              ),
              onProfileSelected: (profileId) =>
                  _updateProfile(profileId, mediaTitle: viewModel.title),
              onDelete: () => _confirmDelete(context, title: viewModel.title),
            )
          // See the Radarr screen: no add path from this view, so an untracked
          // artist gets a sentence instead of a CTA that apologises.
          : const MediaDetailUnavailableSection(
              message:
                  'Lidarr is not tracking this artist, so there is nothing to '
                  'manage here yet. Add it in Lidarr.',
            ),
      // Region 3 — the manifest, and the whole reason to open an artist page.
      // Albums used to be handed to the view as a sliver while the genres stayed
      // a content section, and the old spine emitted every content section before
      // every sliver — so the albums rendered dead last, after the genre chips.
      // In a named region that is structurally unreachable.
      operate: [
        if (viewModel.isInLibrary)
          // The list builds slivers and the two non-list states build boxes, so
          // the state picks the slot shape. Keeping the list in a `.lazy` slot is
          // what preserves its laziness *and* lands it mid-page.
          albumsAsync.when(
            // The project's own loading and failure vocabulary, the way the
            // Bazarr screens already use it: album-shaped shimmer rows while the
            // list is on its way, and a named failure with a retry when it does
            // not arrive.
            loading: () => MediaDetailSlot.box(
              label: 'Albums',
              count: _albumsCount(viewModel),
              child: ShimmerList(itemCount: 4, itemHeight: 64),
            ),
            error: (error, stackTrace) => MediaDetailSlot.box(
              label: 'Albums',
              count: _albumsCount(viewModel),
              child: AppErrorState.compact(
                error: error,
                serviceName: 'Lidarr',
                onRetry: () =>
                    ref.invalidate(musicAlbumsProvider(widget.artistId)),
              ),
            ),
            data: (albums) => MediaDetailSlot.lazy(
              label: 'Albums',
              count: _albumsCount(viewModel),
              leadingBox: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: ReleaseSearchStatusCard(
                  target: ReleaseSearchTarget.artist(
                    artistId: widget.artistId,
                    label: truncateTitle(viewModel.title),
                  ),
                ),
              ),
              sliver: MusicAlbumsList(
                albums: albums,
                lidarrService: ref.read(lidarrServiceProvider),
                baseUrl: settings.lidarrUrl,
                apiKey: settings.lidarrApiKey,
                onSearchAlbum: (albumId) => _searchAlbum(context, albumId),
                onInteractiveSearchAlbum: (albumId) => _interactiveSearchAlbum(
                  context,
                  albumId,
                  title: viewModel.title,
                ),
                searchingAlbums: _searchingAlbums,
                albumQueue: albumQueue,
              ),
            ),
          ),
      ],
      synopsis: [
        if (viewModel.overview.isNotEmpty)
          MediaDetailSlot.box(
            label: 'Overview',
            child: MediaProseSection(text: viewModel.overview),
          ),
      ],
      reference: [
        if (infoGroups.isNotEmpty)
          MediaDetailSlot.box(
            label: 'Details',
            child: AppCard.surfaceOutlined(
              child: MediaInfoCard(groups: infoGroups),
            ),
          ),
        if (viewModel.ratings.isNotEmpty)
          MediaDetailSlot.box(
            label: 'Scores',
            // See the Radarr screen. Lidarr's single-source payload is badged
            // `MB`, which is MusicBrainz — and it announced itself to a screen
            // reader as a vote count in Italian.
            child: RatingChipsRow(
              ratings: legibleRatings(viewModel.ratings),
              accent: accent,
            ),
          ),
        if (viewModel.genres.isNotEmpty)
          MediaDetailSlot.box(
            // Not 'Tags' — these are genres, and a Lidarr tag is a different
            // thing the user configured on their server.
            label: 'Genres',
            child: MediaChipSection.neutral(values: viewModel.genres),
          ),
      ],
      // Lidarr has no cast and no collections.
      related: const [],
    );
  }

  /// `9 albums · 100 of 120 tracks` — the gap the manifest exists to render.
  String? _albumsCount(MusicDetailViewModel viewModel) {
    final parts = <String>[
      if (viewModel.albumCount > 0)
        '${viewModel.albumCount} '
            '${viewModel.albumCount == 1 ? 'album' : 'albums'}',
      if (viewModel.trackCount > 0)
        '${viewModel.trackFileCount} of ${viewModel.trackCount} tracks',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
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
      // The consequence, not the flag — the same sentence shape Radarr and
      // Sonarr use for the same action.
      SnackBarHelper.success(
        context,
        monitored
            ? 'Lidarr is monitoring this artist'
            : 'Lidarr has stopped monitoring this artist',
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.error(
        context,
        "Couldn't change monitoring in Lidarr.",
        detail: e,
      );
    } finally {
      if (mounted) setState(() => _isUpdatingMonitoredState = false);
    }
  }

  /// Changes the quality profile behind a confirmation that names the
  /// transition and its consequence — see the note on Radarr's equivalent for
  /// why this is a confirm and not an Undo: putting the old profile back does
  /// not recall searches Lidarr has already queued.
  Future<void> _updateProfile(
    int profileId, {
    required String mediaTitle,
  }) async {
    if (profileId == currentProfileId) return;

    final from = currentProfileName ?? 'its current profile';
    final to = getProfileName(profileId) ?? 'the selected profile';

    final result = await showAppConfirmDialog(
      context: context,
      title: 'Change quality profile?',
      icon: Icons.high_quality_rounded,
      message:
          '${truncateTitle(mediaTitle)} moves from $from to $to. Lidarr may '
          'start searching for upgrades across every monitored album as soon '
          'as this lands, and a search cannot be called back from here.',
      confirmLabel: 'Change profile',
    );

    if (!result.confirmed || !mounted) return;

    try {
      final lidarrService = ref.read(lidarrServiceProvider);
      await lidarrService.updateArtistProfile(widget.artistId, profileId);
      if (mounted) {
        updateProfileState(profileId);
        ref.invalidate(musicProvider);
        SnackBarHelper.success(context, 'Quality profile changed to $to');
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.error(
        context,
        "Couldn't change the quality profile in Lidarr.",
        detail: e,
      );
    }
  }

  Future<void> _triggerSearch(BuildContext context) async {
    HapticFeedback.selectionClick();
    setState(() => _isAutoSearching = true);
    try {
      final lidarrService = ref.read(lidarrServiceProvider);
      await lidarrService.searchArtist(widget.artistId);
      if (!context.mounted) return;
      // "<Service> is searching <what>", naming the scope: this covers every
      // monitored album, not just the one the user was looking at.
      SnackBarHelper.success(
        context,
        'Lidarr is searching for every monitored album',
      );
      _showSearchConfirmation();
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.error(
        context,
        "Couldn't start a search in Lidarr.",
        detail: e,
      );
    } finally {
      if (mounted) setState(() => _isAutoSearching = false);
    }
  }

  void _showSearchConfirmation() {
    if (!mounted) return;
    setState(() => _isAutoSearchConfirmed = true);
    _searchConfirmTimer?.cancel();
    _searchConfirmTimer = Timer(AppAnimation.confirmationHold, () {
      if (mounted) setState(() => _isAutoSearchConfirmed = false);
    });
  }

  Future<void> _showInteractiveSearch(
    BuildContext context, {
    required String title,
  }) async {
    // The sheet heading already says "Releases"; this is its subtitle. Capped
    // because that subtitle has no maxLines.
    await showReleaseSearch(
      context,
      ref,
      ReleaseSearchTarget.artist(
        artistId: widget.artistId,
        label: truncateTitle(title),
      ),
    );
  }

  Future<void> _searchAlbum(BuildContext context, int albumId) async {
    HapticFeedback.selectionClick();
    setState(() => _searchingAlbums.add(albumId));
    try {
      final lidarrService = ref.read(lidarrServiceProvider);
      await lidarrService.searchAlbums([albumId]);
      if (!context.mounted) return;
      SnackBarHelper.success(context, 'Lidarr is searching this album');
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.error(
        context,
        "Couldn't start a search for this album.",
        detail: e,
      );
    } finally {
      if (mounted) setState(() => _searchingAlbums.remove(albumId));
    }
  }

  Future<void> _interactiveSearchAlbum(
    BuildContext context,
    int albumId, {
    required String title,
  }) async {
    // "Album Releases" under a heading reading "Releases" named neither the
    // artist nor the scope. Same shape as the artist-wide sheet.
    //
    // artistId travels with it so an album can be recognised as covered by an
    // artist-wide search that may already be running.
    await showReleaseSearch(
      context,
      ref,
      ReleaseSearchTarget.album(
        albumId: albumId,
        artistId: widget.artistId,
        label: '${truncateTitle(title)} · one album',
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context, {
    required String title,
  }) async {
    // Same tactile weight Radarr gives the same action: the destructive button
    // announces itself in the hand before the dialog arrives. Tactility is a
    // property of the action, not of which service happens to own the screen.
    HapticFeedback.mediumImpact();

    final result = await showDeleteMediaDialog(
      context: context,
      // Capped where the untrusted string enters: the dialog's "Delete <title>?"
      // heading is not scrollable, so a long name pushes its own buttons away.
      title: truncateTitle(title),
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
      // Which destruction happened, since the dialog offered two.
      SnackBarHelper.success(
        context,
        result.deleteFiles
            ? 'Removed from Lidarr and deleted from disk'
            : 'Removed from Lidarr',
      );
      context.pop();
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.error(
        context,
        "Couldn't delete this artist from Lidarr.",
        detail: e,
      );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }
}
