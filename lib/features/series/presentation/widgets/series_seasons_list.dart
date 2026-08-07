import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/series/domain/models/sonarr_episode.dart';
import 'package:cupola/features/series/domain/models/sonarr_season.dart';
import 'package:cupola/features/series/domain/sonarr_status.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Sonarr's seasons and the selected season's episodes.
///
/// **This builds slivers**, so it belongs in a sliver slot —
/// `MediaDetailSlot.lazy(sliver: SeriesSeasonsList(...))`. It used to be a
/// `Column` inside one `SliverToBoxAdapter`, which meant a 250-episode season
/// built 250 rows to show eight; `bazarr_series_detail_screen.dart` had already
/// solved the same problem with a lazy `SliverList.builder`.
///
/// Everything else about the region is [MediaChildGroupSliver] and
/// [MediaChildTile] — one selector vocabulary, one status vocabulary, one row —
/// shared with Lidarr's albums and Seerr's seasons.
class SeriesSeasonsList extends StatelessWidget {
  /// Seasons, typed. `SonarrSeries.seasons` is raw JSON; pass
  /// `series.seasonList` (or `SonarrSeason.listFrom(...)`).
  final List<SonarrSeason> seasons;

  final AsyncValue<List<SonarrEpisode>> episodesAsync;

  /// Optional background-search indicators, injected rather than resolved here.
  ///
  /// This widget is deliberately provider-free — it takes callbacks and sets, not
  /// providers — so the caller supplies these and a test needs no `ProviderScope`.
  /// Both default to nothing, which is also the correct state when the feature
  /// has no job for that row.
  final Widget Function(int seasonNumber)? seasonIndicator;
  final Widget Function(SonarrEpisode episode)? episodeIndicator;
  final void Function(int seasonNumber) onSearchSeason;
  final void Function(int seasonNumber) onInteractiveSearchSeason;
  final void Function(int episodeId) onSearchEpisode;

  /// Carries the season alongside the episode: without it the release-search
  /// entry point cannot tell that this episode is covered by a season search
  /// that may already be running, and would start a second overlapping pass.
  final void Function(int episodeId, int seasonNumber)
  onInteractiveSearchEpisode;
  final Set<int> searchingSeasons;
  final Set<int> searchingEpisodes;

  /// Retries the episode fetch. Without it a failed load is a dead end on the
  /// one section that is the reason to open a series.
  final VoidCallback? onRetryEpisodes;

  const SeriesSeasonsList({
    super.key,
    required this.seasons,
    required this.episodesAsync,
    this.seasonIndicator,
    this.episodeIndicator,
    required this.onSearchSeason,
    required this.onInteractiveSearchSeason,
    required this.onSearchEpisode,
    required this.onInteractiveSearchEpisode,
    required this.searchingSeasons,
    required this.searchingEpisodes,
    this.onRetryEpisodes,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ServiceKey.sonarr.accent;
    final ordered = List<SonarrSeason>.of(seasons)..sort(SonarrSeason.compare);
    final episodesBySeason = _episodesBySeason();

    return MediaChildGroupSliver(
      accent: accent,
      pickerTitle: 'Seasons',
      childNoun: 'episodes',
      pickerLabel: 'All ${ordered.length} seasons',
      groups: ordered
          .map(
            (season) => MediaChildGroup(
              id: season.seasonNumber,
              shortLabel: season.shortLabel,
              label: season.label,
              status: sonarrSeasonStatus(season),
              summary: sonarrSeasonSummary(season),
              progress: season.completionPercent,
            ),
          )
          .toList(growable: false),
      emptyState: AppEmptyState.compact(
        icon: Icons.tv_off_rounded,
        title: 'No seasons yet',
        message:
            'Sonarr has not listed a season for this series. It picks new ones '
            'up on its next refresh.',
        accentColor: accent,
      ),
      groupAction: (context, group) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (seasonIndicator != null)
            Flexible(child: seasonIndicator!(group.id)),
          MediaSearchPopupMenu(
            onAutoSearch: () => onSearchSeason(group.id),
            onInteractiveSearch: () => onInteractiveSearchSeason(group.id),
            isLoading: searchingSeasons.contains(group.id),
            iconSize: 18,
            tooltip: 'Search ${group.label}',
          ),
        ],
      ),
      childOverride: (context, group) =>
          _childOverride(context, group, episodesBySeason),
      childCount: (group) => (episodesBySeason[group.id] ?? const []).length,
      childBuilder: (context, group, index) =>
          _episodeRow(episodesBySeason[group.id]![index]),
    );
  }

  Map<int, List<SonarrEpisode>> _episodesBySeason() {
    final bySeason = <int, List<SonarrEpisode>>{};
    for (final episode in episodesAsync.asData?.value ?? const []) {
      bySeason.putIfAbsent(episode.seasonNumber, () => []).add(episode);
    }
    for (final episodes in bySeason.values) {
      episodes.sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    }

    return bySeason;
  }

  Widget? _childOverride(
    BuildContext context,
    MediaChildGroup group,
    Map<int, List<SonarrEpisode>> episodesBySeason,
  ) {
    final loaded = episodesAsync.asData;
    if (loaded == null && episodesAsync.isLoading) {
      return const _EpisodesLoading();
    }

    if (loaded == null && episodesAsync.hasError) {
      return AppErrorState.compact(
        error: episodesAsync.error ?? 'Unknown error',
        serviceName: 'Sonarr',
        onRetry: onRetryEpisodes,
      );
    }

    if ((episodesBySeason[group.id] ?? const []).isEmpty) {
      return AppEmptyState.compact(
        icon: Icons.event_busy_rounded,
        title: group.id == 0 ? 'No specials' : 'No episodes',
        message: 'Sonarr lists nothing under ${group.label} yet.',
        accentColor: ServiceKey.sonarr.accent,
      );
    }

    return null;
  }

  Widget _episodeRow(SonarrEpisode episode) {
    final status = sonarrEpisodeStatus(episode);

    return MediaChildTile.numbered(
      ordinal: 'E${episode.episodeNumber.toString().padLeft(2, '0')}',
      ordinalLabel: 'Episode ${episode.episodeNumber}',
      title: episode.title,
      facts: _episodeFacts(episode, status),
      status: status,
      // The magnifier appeared on all twenty-five rows of a fully-downloaded
      // season, which made it furniture rather than an affordance. It shows on
      // the rows a search would actually change: nothing on disk, aired, and not
      // already in the pipeline. The season menu above still covers the rest.
      trailing: _isSearchable(status)
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (episodeIndicator != null) episodeIndicator!(episode),
                MediaSearchPopupMenu(
                  onAutoSearch: () => onSearchEpisode(episode.id),
                  onInteractiveSearch: () => onInteractiveSearchEpisode(
                    episode.id,
                    episode.seasonNumber,
                  ),
                  isLoading: searchingEpisodes.contains(episode.id),
                  iconSize: 18,
                  tooltip: 'Search episode ${episode.episodeNumber}',
                ),
              ],
            )
          : null,
    );
  }

  static bool _isSearchable(MediaStatusInfo status) {
    if (status.isAvailable || status.isInPipeline) return false;
    return status.availability != MediaAvailability.unavailable;
  }

  static List<String> _episodeFacts(
    SonarrEpisode episode,
    MediaStatusInfo status,
  ) {
    final facts = <String>[];
    final airDate = formatMediumDateOrNull(
      episode.airDateUtc ?? episode.airDate,
    );
    if (airDate != null) facts.add(airDate);

    final runtime = episode.runtime;
    // Runtime only stands in for a missing air date: on a series it is the same
    // number on every row, so printing it beside the date is noise.
    if (airDate == null && runtime != null && runtime > 0) {
      facts.add('$runtime min');
    }

    final statusWord = mediaStatusWord(status);
    if (statusWord != null) facts.add(statusWord);

    return facts;
  }
}

/// A labelled skeleton. An unlabelled one reads as an empty screen.
class _EpisodesLoading extends StatelessWidget {
  const _EpisodesLoading();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Loading episodes',
      child: const ExcludeSemantics(
        child: ShimmerList(itemCount: 4, itemHeight: 56),
      ),
    );
  }
}
