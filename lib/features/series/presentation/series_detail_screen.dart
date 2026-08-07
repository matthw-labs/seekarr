import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/api/quality_profile_mixin.dart';
import 'package:seekarr/core/app_animation.dart';
import 'package:seekarr/core/utils/rating_display.dart';
import 'package:seekarr/core/utils/snack_bar_helper.dart';
import 'package:seekarr/core/utils/string_utils.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/discover/presentation/widgets/arr_media_extras_section.dart';
import 'package:seekarr/features/release_search/domain/release_search_target.dart';
import 'package:seekarr/features/release_search/presentation/release_search_entry.dart';
import 'package:seekarr/features/release_search/presentation/widgets/release_search_indicators.dart';
import 'package:seekarr/features/release_search/presentation/widgets/release_search_status_card.dart';
import 'package:seekarr/features/stream/presentation/widgets/stream_availability_slot.dart';
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
        return MediaDetailLoadingView(
          accent: ServiceKey.sonarr.accent,
          // Passed even though it has a default: without it the skeleton shows a
          // film reel and the loaded hero a television, one frame apart.
          heroFallbackIcon: Icons.tv_rounded,
        );
      }

      return MediaDetailPlaceholderView.error(
        error: seriesAsync.asError?.error ?? 'Series not found.',
        serviceName: 'Sonarr',
        accent: ServiceKey.sonarr.accent,
        // Recover in place. Both loads share one outage, so one retry re-runs
        // both. With no id there is no provider to re-run, so no retry is
        // offered rather than one that does nothing.
        onRetry: widget.seriesId > 0
            ? () {
                ref.invalidate(seriesDetailProvider(widget.seriesId));
                ref.invalidate(seriesEpisodesProvider(widget.seriesId));
              }
            : null,
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
      // Sonarr's own page used to pass nothing here, so a backdrop-less show got
      // a film reel on the first-party page and a television on the Bazarr one.
      heroFallbackIcon: Icons.tv_rounded,
      posterUrl: viewModel.posterUrl,
      posterHeaders: viewModel.posterHeaders,
      backdropUrl: viewModel.backdropUrl,
      title: viewModel.title,
      posterRow: _buildPosterRow(context, viewModel, status),
      // Both loads share one outage, so one pull re-runs both — the same pair the
      // retry button re-runs.
      onRefresh: widget.seriesId > 0
          ? () async {
              ref.invalidate(seriesDetailProvider(widget.seriesId));
              ref.invalidate(seriesEpisodesProvider(widget.seriesId));
            }
          : null,
      body: _buildBody(
        viewModel,
        status,
        infoGroups,
        episodesAsync,
        series.id > 0 ? series.id : widget.seriesId,
        series.tmdbId,
        series.tvdbId,
      ),
    );
  }

  /// `41/48 episodes` — how much of the manifest exists, for the hero chip slot.
  String? _episodeCounter(SeriesDetailViewModel viewModel) {
    final total = viewModel.episodeCount ?? 0;
    if (total <= 0) return null;
    return '${viewModel.episodeFileCount ?? 0}/$total episodes';
  }

  String? _seasonCounter(SeriesDetailViewModel viewModel) {
    final seasons = viewModel.seasonCount ?? 0;
    if (seasons <= 0) return null;
    return '$seasons ${seasons == 1 ? 'season' : 'seasons'}';
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
  ) {
    final episodeCounter = _episodeCounter(viewModel);
    final seasonCounter = _seasonCounter(viewModel);

    return MediaDetailPosterRow(
      statusBadge: StatusBadge.animated(info: status),
      title: viewModel.title,
      // The season/episode summary moved into the chip slot below, so it is
      // stated once rather than in the metadata line and in a chip.
      metadataItems: [
        viewModel.year,
        if (viewModel.runtimeStr != null) viewModel.runtimeStr!,
      ].where((item) => item.isNotEmpty).toList(growable: false),
      // One meaning for the chip slot on every variant: how much of the manifest
      // exists. Genres moved to the catalogue block below.
      tags: [
        if (episodeCounter != null)
          TagChip(text: episodeCounter, color: ServiceKey.sonarr.accent),
        if (seasonCounter != null)
          TagChip(text: seasonCounter, color: ServiceKey.sonarr.accent),
      ],
      posterCard: MediaPosterCard(
        heroTag: widget.heroTag,
        imageUrl: viewModel.posterUrl,
        imageHeaders: viewModel.posterHeaders,
        fallbackIcon: Icons.tv_outlined,
      ),
    );
  }

  MediaDetailBody _buildBody(
    SeriesDetailViewModel viewModel,
    MediaStatusInfo status,
    List<MediaInfoGroup> infoGroups,
    AsyncValue<List<SonarrEpisode>> episodesAsync,
    int seriesId,
    int tmdbId,
    int tvdbId,
  ) {
    final accent = ServiceKey.sonarr.accent;
    final total = viewModel.episodeCount ?? 0;
    final onDisk = viewModel.episodeFileCount ?? 0;

    return MediaDetailBody(
      deck: viewModel.isInLibrary
          ? LibraryDetailActions(
              service: ServiceKey.sonarr,
              status: status,
              mediaTitle: viewModel.title,
              isMonitored: viewModel.isMonitored,
              partialSummary: total > 0
                  ? '$onDisk of $total episodes on disk.'
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
                ServiceKey.sonarr,
                seriesId,
              ),
              // Every in-flight pipeline state promotes 'Open queue' only if the
              // host actually has a route for it; without this the most common
              // transient state on a real page degraded to a sentence. Pushed, not
              // gone: checking on a download should leave the title behind you.
              onOpenQueue: () => context.push('/activity/series'),
              onMonitoredChanged: (monitored) => _updateMonitoredState(
                context,
                seriesId: seriesId,
                monitored: monitored,
              ),
              onProfileSelected: (profileId) =>
                  _updateProfile(profileId, mediaTitle: viewModel.title),
              onDelete: () => _confirmDelete(context, title: viewModel.title),
            )
          // See the Radarr screen: no add path from this view, so an untracked
          // title gets a sentence instead of a CTA that apologises.
          : const MediaDetailUnavailableSection(
              message:
                  'Sonarr is not tracking this series, so there is nothing to '
                  'manage here yet. Add it in Sonarr, or request it in Seerr.',
            ),
      // Region 3 — the manifest: the episodes Sonarr expects under this title,
      // checked against what actually arrived. It sits above the synopsis
      // because prose about a show is never more operational than the list of
      // episodes you are missing.
      operate: [
        if (viewModel.isInLibrary) ...[
          MediaDetailSlot.lazy(
            label: 'Seasons',
            count: total > 0 ? '$onDisk of $total on disk' : null,
            // State at the point of intent: a live search for this title's
            // primary target rewrites what the action would have promised. The
            // caller owns this box's gutter — see MediaDetailSlot.leadingBox.
            leadingBox: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: ReleaseSearchStatusCard(
                target: sonarrSeasonTarget(
                  seriesId: widget.seriesId,
                  seasonNumber: null,
                  label: truncateTitle(viewModel.title),
                ),
              ),
            ),
            // A lazy sliver mid-page: a 250-episode season builds the rows on
            // screen instead of all 250 inside one box adapter.
            sliver: SeriesSeasonsList(
              seasons: viewModel.seasons,
              episodesAsync: episodesAsync,
              // State only at the granularity it was launched: a season header
              // shows its own search, an episode row its own — never each
              // other's.
              seasonIndicator: (seasonNumber) => ReleaseSearchRowChip(
                target: ReleaseSearchTarget.season(
                  seriesId: widget.seriesId,
                  seasonNumber: seasonNumber,
                  label: 'Season $seasonNumber',
                ),
              ),
              episodeIndicator: (episode) => ReleaseSearchRowDot(
                target: ReleaseSearchTarget.episode(
                  episodeId: episode.id,
                  seriesId: widget.seriesId,
                  seasonNumber: episode.seasonNumber,
                  label: 'Episode ${episode.episodeNumber}',
                ),
              ),
              onSearchSeason: (seasonNumber) =>
                  _searchSeason(context, seasonNumber),
              onInteractiveSearchSeason: (seasonNumber) =>
                  _interactiveSearchSeason(
                    context,
                    seasonNumber,
                    title: viewModel.title,
                  ),
              onSearchEpisode: (episodeId) =>
                  _searchEpisode(context, episodeId),
              onInteractiveSearchEpisode: (episodeId, seasonNumber) =>
                  _interactiveSearchEpisode(
                    context,
                    episodeId,
                    seasonNumber: seasonNumber,
                    title: viewModel.title,
                  ),
              searchingSeasons: _searchingSeasons,
              searchingEpisodes: _searchingEpisodes,
            ),
          ),
          if (viewModel.hasFiles && viewModel.path != null)
            MediaDetailSlot.box(
              label: 'Files',
              child: FileInfoSection(path: viewModel.path, accent: accent),
            ),
        ],
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
            // See the Radarr screen: one legible source name per pill, and for
            // Sonarr's single-source payload it also fixes what a screen reader
            // says — the parser puts a vote count in the name field, so the pill
            // used to announce itself as "145000 voti rating 7.2".
            child: RatingChipsRow(
              ratings: legibleRatings(viewModel.ratings),
              accent: accent,
            ),
          ),
        if (viewModel.genres.isNotEmpty)
          MediaDetailSlot.box(
            // Not 'Tags' — a Sonarr tag targets release profiles and import
            // lists, and these are genres.
            label: 'Genres',
            child: MediaChipSection.neutral(values: viewModel.genres),
          ),
      ],
      // See the movie screen: labelled slots, each omitted when empty.
      related: [
        // Sonarr's own identifier is the TVDB one, so the join goes through that
        // rather than through `tmdbId`: both servers index it, and matching on a
        // title across two catalogues would be a guess.
        ...streamAvailabilitySlots(
          ref,
          accent: accent,
          tvdbId: tvdbId == 0 ? null : '$tvdbId',
          tmdbId: tmdbId == 0 ? null : '$tmdbId',
        ),
        ...arrMediaExtrasSlots(
          ref,
          tmdbId: tmdbId,
          mediaType: 'tv',
          accent: accent,
        ),
      ],
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
      // The consequence, not the flag — the same sentence shape Radarr and
      // Lidarr use for the same action.
      SnackBarHelper.success(
        context,
        monitored
            ? 'Sonarr is monitoring this series'
            : 'Sonarr has stopped monitoring this series',
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.error(
        context,
        "Couldn't change monitoring in Sonarr.",
        detail: e,
      );
    } finally {
      if (mounted) setState(() => _isUpdatingMonitoredState = false);
    }
  }

  Future<void> _triggerSearch(BuildContext context) async {
    HapticFeedback.selectionClick();
    setState(() => _isAutoSearching = true);
    try {
      final sonarrService = ref.read(sonarrServiceProvider);
      await sonarrService.searchSeries(widget.seriesId);
      if (!context.mounted) return;
      // "<Service> is searching <what>", the shape every library page uses. The
      // scope matters here more than anywhere: this one search covers every
      // monitored episode of the show.
      SnackBarHelper.success(
        context,
        'Sonarr is searching for every monitored episode',
      );
      _showSearchConfirmation();
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.error(
        context,
        "Couldn't start a search in Sonarr.",
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
    int? seasonNumber,
  }) async {
    // The sheet titles itself "Releases" and this lands in the subtitle, so
    // "Releases for X" said it twice. Capped: the subtitle has no maxLines, and
    // a long show name plus a season suffix used to grow the header until it
    // crowded out the list.
    await showReleaseSearch(
      context,
      ref,
      sonarrSeasonTarget(
        seriesId: widget.seriesId,
        seasonNumber: seasonNumber,
        label: seasonNumber != null
            ? '${truncateTitle(title)} · Season $seasonNumber'
            : truncateTitle(title),
      ),
    );
  }

  Future<void> _searchSeason(BuildContext context, int seasonNumber) async {
    HapticFeedback.selectionClick();
    setState(() => _searchingSeasons.add(seasonNumber));
    try {
      final sonarrService = ref.read(sonarrServiceProvider);
      await sonarrService.searchSeason(widget.seriesId, seasonNumber);
      if (!context.mounted) return;
      SnackBarHelper.success(
        context,
        'Sonarr is searching Season $seasonNumber',
      );
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.error(
        context,
        "Couldn't start a search for Season $seasonNumber in Sonarr.",
        detail: e,
      );
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
    HapticFeedback.selectionClick();
    setState(() => _searchingEpisodes.add(episodeId));
    try {
      final sonarrService = ref.read(sonarrServiceProvider);
      await sonarrService.searchEpisodes([episodeId]);
      if (!context.mounted) return;
      SnackBarHelper.success(context, 'Sonarr is searching this episode');
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.error(
        context,
        "Couldn't start a search for this episode.",
        detail: e,
      );
    } finally {
      if (mounted) setState(() => _searchingEpisodes.remove(episodeId));
    }
  }

  Future<void> _interactiveSearchEpisode(
    BuildContext context,
    int episodeId, {
    required String title,
    required int seasonNumber,
  }) async {
    // "Episode Releases" under a heading that already reads "Releases" named
    // neither the show nor which scope was searched. This says both, in the
    // same shape as the series and season sheets.
    //
    // seriesId and seasonNumber travel with the target so this episode can be
    // recognised as part of a season that may already be searching.
    await showReleaseSearch(
      context,
      ref,
      ReleaseSearchTarget.episode(
        episodeId: episodeId,
        seriesId: widget.seriesId,
        seasonNumber: seasonNumber,
        label: '${truncateTitle(title)} · one episode',
      ),
    );
  }

  /// Changes the quality profile behind a confirmation that names the
  /// transition and its consequence — see the note on Radarr's equivalent for
  /// why this is a confirm and not an Undo: putting the old profile back does
  /// not recall searches Sonarr has already queued.
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
          '${truncateTitle(mediaTitle)} moves from $from to $to. Sonarr may '
          'start searching for upgrades across every monitored episode as soon '
          'as this lands, and a search cannot be called back from here.',
      confirmLabel: 'Change profile',
    );

    if (!result.confirmed || !mounted) return;

    try {
      final sonarrService = ref.read(sonarrServiceProvider);
      await sonarrService.updateSeriesProfile(widget.seriesId, profileId);
      if (mounted) {
        updateProfileState(profileId);
        ref.invalidate(seriesProvider);
        SnackBarHelper.success(context, 'Quality profile changed to $to');
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.error(
        context,
        "Couldn't change the quality profile in Sonarr.",
        detail: e,
      );
    }
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
      // heading sits above the scrollable content, so a long name pushes the
      // checkboxes and the buttons off the screen.
      title: truncateTitle(title),
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
      // Which destruction happened, since the dialog offered two.
      SnackBarHelper.success(
        context,
        result.deleteFiles
            ? 'Removed from Sonarr and deleted from disk'
            : 'Removed from Sonarr',
      );
      context.pop();
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.error(
        context,
        "Couldn't delete this series from Sonarr.",
        detail: e,
      );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }
}
