import 'package:flutter/material.dart';

import 'package:seekarr/core/utils/string_utils.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/discover/domain/models/discover_detail_model.dart';
import 'package:seekarr/features/discover/domain/seerr_status.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// Seerr's seasons and the selected season's episodes.
///
/// **This builds slivers** — hand it to `MediaDetailSlot.lazy(sliver: ...)`. It
/// is the same [MediaChildGroupSliver] Sonarr's seasons use, which is the point:
/// this file and `series_seasons_list.dart` each carried their own `_SeasonPill`
/// and their own selected-season panel, near-duplicates that had already drifted
/// (one showed a check glyph inside the pill, the other did not).
///
/// Episode rows deliberately carry **no status**. Seerr models availability per
/// season, not per episode, so a per-episode badge here would be invented data;
/// the air date is what the row is for, and the season badge above states
/// availability in words.
class DiscoverSeasonsList extends StatelessWidget {
  final List<TvSeason> seasons;

  /// Resolved per-season status, keyed by season number.
  ///
  /// Build it with `seerrSeasonStatuses(mediaInfo, seasons)` from
  /// `features/discover/domain/seerr_status.dart`. This widget used to take
  /// Seerr's raw `mediaInfo` map and mine `mediaInfo['seasons']` for
  /// availability inside `build`.
  final Map<int, MediaStatusInfo> seasonStatuses;

  const DiscoverSeasonsList({
    super.key,
    required this.seasons,
    required this.seasonStatuses,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ServiceKey.seerr.accent;
    final ordered = List<TvSeason>.of(seasons)..sort(_compareSeasons);
    final episodesBySeason = <int, List<TvEpisodeSummary>>{
      for (final season in ordered)
        season.seasonNumber: List<TvEpisodeSummary>.of(season.episodes)
          ..sort(
            (a, b) => (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0),
          ),
    };
    final countsBySeason = <int, int>{
      for (final season in ordered) season.seasonNumber: season.episodeCount,
    };

    return MediaChildGroupSliver(
      accent: accent,
      pickerTitle: 'Seasons',
      pickerLabel: 'All ${ordered.length} seasons',
      groups: ordered
          .map(
            (season) => MediaChildGroup(
              id: season.seasonNumber,
              shortLabel: _shortLabel(season),
              label: _label(season),
              // `seerrSeasonStatuses` covers every season it is handed, so this
              // fallback is Dart's nullable-lookup tax and not a second opinion
              // about what an untracked season is — it reads the domain layer's
              // own answer rather than restating it.
              status:
                  seasonStatuses[season.seasonNumber] ??
                  seerrUntrackedSeasonStatus,
              summary: season.episodeCount > 0
                  ? '${season.episodeCount} episodes'
                  : null,
            ),
          )
          .toList(growable: false),
      emptyState: AppEmptyState.compact(
        icon: Icons.tv_off_rounded,
        title: 'No seasons listed',
        message: 'Seerr has no season details for this title.',
        accentColor: accent,
      ),
      childOverride: (context, group) {
        if ((episodesBySeason[group.id] ?? const []).isNotEmpty) return null;

        final listed = countsBySeason[group.id] ?? 0;
        return AppEmptyState.compact(
          icon: Icons.event_note_outlined,
          title: listed > 0 ? '$listed episodes listed' : 'No episodes listed',
          message: 'Seerr has no per-episode details for ${group.label}.',
          accentColor: accent,
        );
      },
      childCount: (group) => (episodesBySeason[group.id] ?? const []).length,
      childBuilder: (context, group, index) =>
          _episodeRow(episodesBySeason[group.id]![index]),
    );
  }

  static Widget _episodeRow(TvEpisodeSummary episode) {
    final episodeNumber = episode.episodeNumber;
    final title = episode.name?.trim().isNotEmpty == true
        ? episode.name!.trim()
        : 'Episode ${episodeNumber ?? '?'}';
    final airDate = formatMediumDateOrNull(episode.airDate);

    return MediaChildTile.numbered(
      ordinal: episodeNumber == null
          ? '--'
          : 'E${episodeNumber.toString().padLeft(2, '0')}',
      ordinalLabel: episodeNumber == null
          ? ''
          : 'Episode ${episode.episodeNumber}',
      title: title,
      facts: <String>[if (airDate != null) airDate],
    );
  }

  static String _label(TvSeason season) {
    final name = season.name.trim();
    if (name.isNotEmpty) return name;
    return season.seasonNumber == 0
        ? 'Specials'
        : 'Season ${season.seasonNumber}';
  }

  static String _shortLabel(TvSeason season) =>
      season.seasonNumber == 0 ? 'Sp' : 'S${season.seasonNumber}';

  /// Ascending by season number, with specials last — an appendix, not season
  /// zero.
  static int _compareSeasons(TvSeason left, TvSeason right) {
    final leftSpecials = left.seasonNumber == 0;
    final rightSpecials = right.seasonNumber == 0;
    if (leftSpecials != rightSpecials) return leftSpecials ? 1 : -1;
    return left.seasonNumber.compareTo(right.seasonNumber);
  }
}
