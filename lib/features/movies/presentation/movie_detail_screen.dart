import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/api/quality_profile_mixin.dart';
import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/utils/rating_display.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/presentation/widgets/arr_media_extras_section.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/release_search/presentation/release_search_entry.dart';
import 'package:cupola/features/release_search/presentation/widgets/release_search_status_card.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_availability_slot.dart';
import 'package:cupola/features/import/presentation/manual_import_routes.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/domain/radarr_status.dart';
import 'package:cupola/features/movies/presentation/movie_detail_provider.dart';
import 'package:cupola/features/movies/presentation/movie_detail_view_model.dart';
import 'package:cupola/features/movies/presentation/movies_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

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
  bool _isAutoSearching = false;
  bool _isAutoSearchConfirmed = false;
  Timer? _searchConfirmTimer;
  bool _isDeleting = false;
  bool _isUpdatingMonitoredState = false;

  @override
  void dispose() {
    _searchConfirmTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(currentSettingsProvider);
    final movieAsync = widget.movieId > 0
        ? ref.watch(movieDetailProvider(widget.movieId))
        : const AsyncData<RadarrMovie?>(null);
    final movie = movieAsync.asData?.value ?? widget.initialMovie;

    if (movie == null) {
      if (movieAsync.isLoading) {
        return MediaDetailLoadingView(
          accent: ServiceKey.radarr.accent,
          heroFallbackIcon: Icons.movie_outlined,
        );
      }

      return MediaDetailPlaceholderView.error(
        error: movieAsync.asError?.error ?? 'Movie not found.',
        serviceName: 'Radarr',
        accent: ServiceKey.radarr.accent,
        // Recover in place. With no id there is no provider to re-run, so the
        // retry is withheld rather than offered and doing nothing.
        onRetry: widget.movieId > 0
            ? () => ref.invalidate(movieDetailProvider(widget.movieId))
            : null,
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
      heroFallbackIcon: Icons.movie_outlined,
      posterUrl: viewModel.posterUrl,
      posterHeaders: viewModel.posterHeaders,
      backdropUrl: viewModel.backdropUrl,
      title: viewModel.title,
      posterRow: _buildPosterRow(context, viewModel, status),
      // The same load the retry button re-runs, on the gesture the hero was
      // already accepting and doing nothing with.
      onRefresh: widget.movieId > 0
          ? () async => ref.invalidate(movieDetailProvider(widget.movieId))
          : null,
      body: _buildBody(
        viewModel,
        status,
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
  ) {
    return MediaDetailPosterRow(
      statusBadge: StatusBadge.animated(info: status),
      title: viewModel.title,
      metadataItems: viewModel.metadataItems,
      // The hero's chip slot has one meaning on every variant: how much of the
      // manifest exists. Genres moved to the catalogue block below, where they
      // now appear exactly once instead of in the hero *and* in a section
      // mislabelled "Tags".
      tags: [
        TagChip(
          text: viewModel.hasFile ? '1 file' : 'No file',
          color: ServiceKey.radarr.accent,
        ),
      ],
      posterCard: MediaPosterCard(
        heroTag: widget.heroTag,
        imageUrl: viewModel.posterUrl,
        imageHeaders: viewModel.posterHeaders,
        fallbackIcon: Icons.movie_outlined,
      ),
    );
  }

  MediaDetailBody _buildBody(
    MovieDetailViewModel viewModel,
    MediaStatusInfo status,
    List<MediaInfoGroup> infoGroups,
    int movieId,
    int tmdbId,
  ) {
    final accent = ServiceKey.radarr.accent;

    return MediaDetailBody(
      deck: viewModel.isInLibrary
          ? LibraryDetailActions(
              service: ServiceKey.radarr,
              status: status,
              mediaTitle: viewModel.title,
              isMonitored: viewModel.isMonitored,
              // One flag, mapped from whichever per-action flag can be in flight
              // on this page: only one action is ever promoted.
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
                ServiceKey.radarr,
                movieId,
              ),
              // Every in-flight pipeline state promotes 'Open queue' only if the
              // host actually has a route for it; without this the most common
              // transient state on a real page degraded to a sentence. Pushed, not
              // gone: checking on a download should leave the title behind you.
              onOpenQueue: () => context.push('/activity/movies'),
              onMonitoredChanged: (monitored) => _updateMonitoredState(
                context,
                movieId: movieId,
                monitored: monitored,
              ),
              onProfileSelected: (profileId) =>
                  _updateProfile(profileId, mediaTitle: viewModel.title),
              onDelete: () => _confirmDelete(context, title: viewModel.title),
            )
          // No add path exists from this view, so an untracked title falls
          // through to a sentence rather than to the full-width accent CTA whose
          // only behaviour was a snackbar saying it is not available.
          : const MediaDetailUnavailableSection(
              message:
                  'Radarr is not tracking this movie, so there is nothing to '
                  'manage here yet. Add it in Radarr, or request it in Seerr.',
            ),
      // Region 3 — the manifest. A movie has no child records, so the manifest
      // is the file, and the path a self-hoster actually hunts for lives here
      // rather than at the bottom of an encyclopaedic grid.
      operate: [
        if (viewModel.isInLibrary)
          MediaDetailSlot.box(
            child: ReleaseSearchStatusCard(
              target: ReleaseSearchTarget.movie(
                movieId: widget.movieId,
                label: truncateTitle(viewModel.title),
              ),
            ),
          ),
        if (viewModel.isInLibrary)
          MediaDetailSlot.box(
            label: 'File',
            child: viewModel.hasFile && viewModel.path != null
                ? FileInfoSection(
                    path: viewModel.path,
                    filename: viewModel.filename,
                    accent: accent,
                  )
                // One footprint in both states: the region does not jump when a
                // file arrives, and the hint spends its two lines suggesting the
                // route the promoted "Auto search" button does not cover.
                : FileInfoSection.missing(accent: accent),
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
            // Through `legibleRatings` so a pill names its source the way the
            // source names itself. Radarr's keys arrive as `metacritic`,
            // `rottenTomatoes`, `trakt` and the parser badges them `MC`, `RO`,
            // `TR` — abbreviations that appear nowhere else in the app and are
            // not what anyone calls those sites.
            child: RatingChipsRow(
              ratings: legibleRatings(viewModel.ratings),
              accent: accent,
            ),
          ),
        if (viewModel.genres.isNotEmpty)
          MediaDetailSlot.box(
            // Not 'Tags': in this domain a tag is a Radarr concept that targets
            // release profiles and import lists, so calling genres tags
            // asserted something false about the user's server.
            label: 'Genres',
            child: MediaChipSection.neutral(values: viewModel.genres),
          ),
      ],
      // One `CAST` slot and one `COLLECTION` slot, each labelled by the spine and
      // each omitted when Seerr has nothing for it — rather than one
      // undifferentiated extras section that drew its own headings.
      related: [
        // "On Jellyfin · 34 min in" — the pipeline closing. Radarr answers "do I
        // own it"; only a media server knows whether anyone can play it and where
        // they stopped. Omitted entirely when there is nothing to say, so it never
        // leaves a labelled region over empty air.
        ...streamAvailabilitySlots(
          ref,
          accent: accent,
          tmdbId: tmdbId == 0 ? null : '$tmdbId',
        ),
        ...arrMediaExtrasSlots(
          ref,
          tmdbId: tmdbId,
          mediaType: 'movie',
          accent: accent,
        ),
      ],
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
      // What changed, in the words of the thing that will act on it. "Movie
      // unmonitored" states a flag; "Radarr has stopped monitoring" states the
      // consequence, and Monitored is a term a self-hoster genuinely needs.
      SnackBarHelper.success(
        context,
        monitored
            ? 'Radarr is monitoring this movie'
            : 'Radarr has stopped monitoring this movie',
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.error(
        context,
        "Couldn't change monitoring in Radarr.",
        detail: e,
      );
    } finally {
      if (mounted) setState(() => _isUpdatingMonitoredState = false);
    }
  }

  /// Changes the quality profile behind a confirmation that names the
  /// transition and its consequence.
  ///
  /// This used to fire straight off a tap in the icon row, which made a
  /// server-side write with real cost — Radarr can start hunting upgrades for
  /// the whole title the moment the profile lands — the one action on the page
  /// with no confirmation and no way back. An Undo would be a lie here: putting
  /// the old profile back does not recall searches that are already queued on
  /// the user's connection, so the recoverable moment is *before* the write.
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
          '${truncateTitle(mediaTitle)} moves from $from to $to. Radarr may '
          'start searching for an upgrade as soon as this lands, and a search '
          'cannot be called back from here.',
      confirmLabel: 'Change profile',
    );

    if (!result.confirmed || !mounted) return;

    try {
      final radarrService = ref.read(radarrServiceProvider);
      await radarrService.updateMovieProfile(widget.movieId, profileId);
      if (mounted) {
        updateProfileState(profileId);
        ref.invalidate(moviesProvider);
        SnackBarHelper.success(context, 'Quality profile changed to $to');
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.error(
        context,
        "Couldn't change the quality profile in Radarr.",
        detail: e,
      );
    }
  }

  Future<void> _confirmDelete(
    BuildContext context, {
    required String title,
  }) async {
    HapticFeedback.mediumImpact();

    final result = await showDeleteMediaDialog(
      context: context,
      // The dialog builds "Delete <title>?" as its heading, which sits above the
      // scrollable content in an AlertDialog — so a 200-character release name
      // pushes the two checkboxes and both buttons off the screen. Capped here,
      // where the untrusted string enters.
      title: truncateTitle(title),
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
      // "Movie deleted" left the one thing the user just decided unstated. The
      // dialog offered two different destructions; the confirmation says which
      // one happened.
      SnackBarHelper.success(
        context,
        result.deleteFiles
            ? 'Removed from Radarr and deleted from disk'
            : 'Removed from Radarr',
      );
      context.pop();
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.error(
        context,
        "Couldn't delete this movie from Radarr.",
        detail: e,
      );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<void> _triggerSearch(BuildContext context) async {
    HapticFeedback.selectionClick();
    setState(() => _isAutoSearching = true);
    try {
      final radarrService = ref.read(radarrServiceProvider);
      await radarrService.searchMovie(widget.movieId);
      if (!context.mounted) return;
      // One shape for every search confirmation on every library page:
      // "<Service> is searching <what>". The old set drifted between "Search
      // started", "Search started for entire series" and "Album search
      // started", which read as three different features.
      SnackBarHelper.success(context, 'Radarr is searching for this movie');
      _showSearchConfirmation();
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.error(
        context,
        "Couldn't start a search in Radarr.",
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
    // The sheet's own heading is already "Releases" and this string lands in
    // the subtitle beneath it, so "Releases for X" printed the word twice.
    // Capped because the subtitle Text has no maxLines: a long title used to
    // grow the header until it ate the list it was introducing.
    await showReleaseSearch(
      context,
      ref,
      ReleaseSearchTarget.movie(
        movieId: widget.movieId,
        label: truncateTitle(title),
      ),
    );
  }
}
