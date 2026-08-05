class SonarrEpisode {
  final int id;
  final int seasonNumber;
  final int episodeNumber;
  final String title;
  final bool hasFile;
  final bool monitored;

  /// Broadcast date in the series' own timezone, `YYYY-MM-DD`.
  ///
  /// The one fact that makes an episode row decidable without a second request:
  /// the row used to be a number, a truncated title and a magnifier, which is
  /// nothing to choose between. Sonarr returns both this and [airDateUtc] on
  /// `/api/v3/episode` by default, so neither costs an extra call.
  final String? airDate;

  /// Broadcast instant in UTC, used to tell an unaired episode from a missing
  /// one — "Not Released" and "Missing" are very different rows.
  final String? airDateUtc;

  /// Episode length in minutes, when Sonarr knows it.
  final int? runtime;

  const SonarrEpisode({
    required this.id,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.title,
    required this.hasFile,
    required this.monitored,
    this.airDate,
    this.airDateUtc,
    this.runtime,
  });

  /// When this episode airs, preferring the UTC instant over the local date.
  DateTime? get airsAt {
    final utc = airDateUtc?.trim();
    if (utc != null && utc.isNotEmpty) {
      final parsed = DateTime.tryParse(utc);
      if (parsed != null) return parsed;
    }

    final local = airDate?.trim();
    if (local != null && local.isNotEmpty) return DateTime.tryParse(local);

    return null;
  }

  /// True when the broadcast is in the future.
  ///
  /// An episode with no air date at all is treated as aired: Sonarr leaves the
  /// field empty for older catalogues, and reporting "Not Released" for
  /// something from 1994 would be worse than saying nothing.
  bool isUnairedAt(DateTime now) {
    final airsAt = this.airsAt;
    if (airsAt == null) return false;
    return airsAt.isAfter(now);
  }

  factory SonarrEpisode.fromJson(Map<String, dynamic> json) {
    final episodeNumber = (json['episodeNumber'] as num?)?.toInt() ?? 0;

    return SonarrEpisode(
      id: (json['id'] as num?)?.toInt() ?? 0,
      seasonNumber: (json['seasonNumber'] as num?)?.toInt() ?? 0,
      episodeNumber: episodeNumber,
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? (json['title'] as String).trim()
          : 'Episode ${episodeNumber == 0 ? '?' : episodeNumber}',
      hasFile: json['hasFile'] as bool? ?? false,
      monitored: json['monitored'] as bool? ?? false,
      airDate: json['airDate'] as String?,
      airDateUtc: json['airDateUtc'] as String?,
      runtime: (json['runtime'] as num?)?.toInt(),
    );
  }
}
