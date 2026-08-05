/// One season of a Sonarr series.
///
/// Sonarr returns seasons nested inside the series payload, so they arrived —
/// and were rendered — as raw `dynamic` maps: the season pill read
/// `season['seasonNumber']` while the panel beside it read
/// `season['statistics']['episodeFileCount']`, with nothing to stop the two
/// halves of one control disagreeing about the shape they were handed. This is
/// that shape, written down once.
class SonarrSeason {
  final int seasonNumber;
  final bool monitored;

  /// Episodes Sonarr expects to hold: aired and monitored ones only.
  ///
  /// Deliberately not [totalEpisodeCount], which counts unaired episodes and
  /// would leave any currently-airing season permanently `partial` — the same
  /// distinction `SonarrSeries.episodeCount` documents at series level.
  final int episodeCount;

  /// Every known episode of the season, including unaired ones.
  final int totalEpisodeCount;

  final int episodeFileCount;

  const SonarrSeason({
    required this.seasonNumber,
    required this.monitored,
    required this.episodeCount,
    required this.totalEpisodeCount,
    required this.episodeFileCount,
  });

  bool get isSpecials => seasonNumber == 0;

  /// Full name, for a summary line or a picker row.
  String get label => isSpecials ? 'Specials' : 'Season $seasonNumber';

  /// One-line pill label. Kept to three characters so a 40-season rail stays
  /// scannable.
  String get shortLabel => isSpecials ? 'Sp' : 'S$seasonNumber';

  /// Share of the expected episodes that are on disk, or null when nothing is
  /// expected yet (an announced season that has not started airing).
  double? get completionPercent {
    if (episodeCount <= 0) return null;
    return (episodeFileCount / episodeCount).clamp(0.0, 1.0);
  }

  /// True while more episodes of this season are still expected to air.
  bool get hasUnairedEpisodes => totalEpisodeCount > episodeCount;

  factory SonarrSeason.fromJson(Map<String, dynamic> json) {
    final rawStatistics = json['statistics'];
    final statistics = rawStatistics is Map<String, dynamic>
        ? rawStatistics
        : const <String, dynamic>{};

    return SonarrSeason(
      seasonNumber: (json['seasonNumber'] as num?)?.toInt() ?? 0,
      monitored: json['monitored'] as bool? ?? false,
      episodeCount: (statistics['episodeCount'] as num?)?.toInt() ?? 0,
      totalEpisodeCount:
          (statistics['totalEpisodeCount'] as num?)?.toInt() ??
          (statistics['episodeCount'] as num?)?.toInt() ??
          0,
      episodeFileCount: (statistics['episodeFileCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// Maps `SonarrSeries.seasons`' raw entries, dropping anything that is not a
  /// JSON object, and returns them in display order.
  static List<SonarrSeason> listFrom(List<dynamic> raw) {
    final seasons = <SonarrSeason>[];
    for (final entry in raw) {
      if (entry is Map<String, dynamic>) {
        seasons.add(SonarrSeason.fromJson(entry));
      }
    }

    seasons.sort(compare);
    return List<SonarrSeason>.unmodifiable(seasons);
  }

  /// Ascending by season number, with specials last — they are an appendix, not
  /// season zero.
  static int compare(SonarrSeason left, SonarrSeason right) {
    if (left.isSpecials != right.isSpecials) return left.isSpecials ? 1 : -1;
    return left.seasonNumber.compareTo(right.seasonNumber);
  }
}
