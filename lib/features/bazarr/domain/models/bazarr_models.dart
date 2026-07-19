import 'package:seekarr/core/utils/dynamic_map_utils.dart';

class BazarrSubtitleLanguage {
  final String? name;
  final String? code2;
  final String? code3;
  final bool forced;
  final bool hi;

  const BazarrSubtitleLanguage({
    this.name,
    this.code2,
    this.code3,
    this.forced = false,
    this.hi = false,
  });

  factory BazarrSubtitleLanguage.fromJson(Map<String, dynamic> json) {
    return BazarrSubtitleLanguage(
      name: stringOrNull(json['name']),
      code2: stringOrNull(json['code2']),
      code3: stringOrNull(json['code3']),
      forced: json['forced'] == true,
      hi: json['hi'] == true,
    );
  }
}

List<BazarrSubtitleLanguage> parseBazarrSubtitleLanguages(dynamic value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map(stringKeyMap)
        .map(BazarrSubtitleLanguage.fromJson)
        .toList(growable: false);
  }
  return const <BazarrSubtitleLanguage>[];
}

class BazarrSeries {
  final int sonarrSeriesId;
  final String? title;
  final String? sortTitle;
  final int? year;
  final String? path;
  final bool monitored;
  final int? episodeMissingCount;
  final int? episodeCount;
  final int? profileId;
  final List<String> tags;

  const BazarrSeries({
    required this.sonarrSeriesId,
    this.title,
    this.sortTitle,
    this.year,
    this.path,
    required this.monitored,
    this.episodeMissingCount,
    this.episodeCount,
    this.profileId,
    this.tags = const [],
  });

  factory BazarrSeries.fromJson(Map<String, dynamic> json) {
    final tagsRaw = json['tags'];
    final tags = tagsRaw is List
        ? tagsRaw
              .map((e) => stringOrNull(e))
              .whereType<String>()
              .toList(growable: false)
        : const <String>[];

    return BazarrSeries(
      sonarrSeriesId: intOrNull(json['sonarrSeriesId']) ?? 0,
      title: stringOrNull(json['title']),
      sortTitle: stringOrNull(json['sortTitle']),
      year: intOrNull(json['year']),
      path: stringOrNull(json['path']),
      monitored: json['monitored'] == true,
      episodeMissingCount: intOrNull(json['episodeMissingCount']),
      episodeCount: intOrNull(json['episodeFileCount']),
      profileId: intOrNull(json['profileId']),
      tags: tags,
    );
  }
}

class BazarrMovie {
  final int radarrId;
  final String? title;
  final String? sortTitle;
  final int? year;
  final String? path;
  final bool monitored;
  final List<BazarrSubtitleLanguage> missingLanguages;
  final int? profileId;
  final List<String> tags;

  const BazarrMovie({
    required this.radarrId,
    this.title,
    this.sortTitle,
    this.year,
    this.path,
    required this.monitored,
    this.missingLanguages = const [],
    this.profileId,
    this.tags = const [],
  });

  int get missingSubtitlesCount => missingLanguages.length;

  factory BazarrMovie.fromJson(Map<String, dynamic> json) {
    final tagsRaw = json['tags'];
    final tags = tagsRaw is List
        ? tagsRaw
              .map((e) => stringOrNull(e))
              .whereType<String>()
              .toList(growable: false)
        : const <String>[];

    return BazarrMovie(
      radarrId: intOrNull(json['radarrId']) ?? 0,
      title: stringOrNull(json['title']),
      sortTitle: stringOrNull(json['sortTitle']),
      year: intOrNull(json['year']),
      path: stringOrNull(json['path']),
      monitored: json['monitored'] == true,
      missingLanguages: parseBazarrSubtitleLanguages(json['missing_subtitles']),
      profileId: intOrNull(json['profileId']),
      tags: tags,
    );
  }
}

class BazarrWantedItem {
  final String? title;
  final String? seriesTitle;
  final String? episodeNumber;
  final String? episodeTitle;
  final int? season;
  final List<BazarrSubtitleLanguage> missingLanguages;
  final int? sonarrSeriesId;
  final int? sonarrEpisodeId;
  final int? radarrId;
  final String? sceneName;
  final List<String> tags;

  const BazarrWantedItem({
    this.title,
    this.seriesTitle,
    this.episodeNumber,
    this.episodeTitle,
    this.season,
    this.missingLanguages = const [],
    this.sonarrSeriesId,
    this.sonarrEpisodeId,
    this.radarrId,
    this.sceneName,
    this.tags = const [],
  });

  int get missingSubtitlesCount => missingLanguages.length;

  factory BazarrWantedItem.fromJson(Map<String, dynamic> json) {
    final seasonRaw = intOrNull(json['season']);
    final episodeNumberRaw = stringOrNull(json['episode_number']);
    final seasonFromEpisode =
        seasonRaw ?? _seasonFromEpisodeCode(episodeNumberRaw);

    final tagsRaw = json['tags'];
    final tags = tagsRaw is List
        ? tagsRaw
              .map((e) => stringOrNull(e))
              .whereType<String>()
              .toList(growable: false)
        : const <String>[];

    return BazarrWantedItem(
      title: stringOrNull(json['title']),
      seriesTitle: stringOrNull(json['seriesTitle']),
      episodeNumber: episodeNumberRaw,
      episodeTitle: stringOrNull(json['episodeTitle']),
      season: seasonFromEpisode,
      missingLanguages: parseBazarrSubtitleLanguages(json['missing_subtitles']),
      sonarrSeriesId: intOrNull(json['sonarrSeriesId']),
      sonarrEpisodeId: intOrNull(json['sonarrEpisodeId']),
      radarrId: intOrNull(json['radarrId']),
      sceneName: stringOrNull(json['sceneName']),
      tags: tags,
    );
  }

  static int? _seasonFromEpisodeCode(String? value) {
    if (value == null || value.isEmpty) return null;
    final separatorIndex = value.indexOf('x');
    if (separatorIndex <= 0) return null;
    final season = int.tryParse(value.substring(0, separatorIndex));
    return season;
  }
}

class BazarrBadges {
  final int episodes;
  final int movies;
  final int providers;
  final bool status;
  final bool sonarrSignalR;
  final bool radarrSignalR;
  final int announcements;

  const BazarrBadges({
    required this.episodes,
    required this.movies,
    required this.providers,
    required this.status,
    required this.sonarrSignalR,
    required this.radarrSignalR,
    required this.announcements,
  });

  int get totalWanted => episodes + movies;

  factory BazarrBadges.fromJson(Map<String, dynamic> json) {
    return BazarrBadges(
      episodes: intOrNull(json['episodes']) ?? 0,
      movies: intOrNull(json['movies']) ?? 0,
      providers: intOrNull(json['providers']) ?? 0,
      status: json['status'] == true,
      sonarrSignalR: json['sonarr_signalr'] == true,
      radarrSignalR: json['radarr_signalr'] == true,
      announcements: intOrNull(json['announcements']) ?? 0,
    );
  }
}

class BazarrSystemStatus {
  final String? bazarrVersion;
  final String? packageVersion;
  final String? sonarrVersion;
  final String? radarrVersion;
  final String? operatingSystem;
  final String? pythonVersion;
  final String? databaseEngine;
  final int? databaseMigration;
  final String? timezone;

  const BazarrSystemStatus({
    this.bazarrVersion,
    this.packageVersion,
    this.sonarrVersion,
    this.radarrVersion,
    this.operatingSystem,
    this.pythonVersion,
    this.databaseEngine,
    this.databaseMigration,
    this.timezone,
  });

  factory BazarrSystemStatus.fromJson(Map<String, dynamic> json) {
    return BazarrSystemStatus(
      bazarrVersion: stringOrNull(json['bazarr_version']),
      packageVersion: stringOrNull(json['package_version']),
      sonarrVersion: stringOrNull(json['sonarr_version']),
      radarrVersion: stringOrNull(json['radarr_version']),
      operatingSystem: stringOrNull(json['operating_system']),
      pythonVersion: stringOrNull(json['python_version']),
      databaseEngine: stringOrNull(json['database_engine']),
      databaseMigration: intOrNull(json['database_migration']),
      timezone: stringOrNull(json['timezone']),
    );
  }
}

class BazarrSystemTask {
  final String? interval;
  final String? jobId;
  final bool jobRunning;
  final String? name;
  final String? nextRunIn;
  final String? nextRunTime;

  const BazarrSystemTask({
    this.interval,
    this.jobId,
    required this.jobRunning,
    this.name,
    this.nextRunIn,
    this.nextRunTime,
  });

  factory BazarrSystemTask.fromJson(Map<String, dynamic> json) {
    return BazarrSystemTask(
      interval: stringOrNull(json['interval']),
      jobId: stringOrNull(json['job_id']),
      jobRunning: json['job_running'] == true,
      name: stringOrNull(json['name']),
      nextRunIn: stringOrNull(json['next_run_in']),
      nextRunTime: stringOrNull(json['next_run_time']),
    );
  }
}

class BazarrJob {
  final String? jobId;
  final String? jobName;
  final String? status;
  final String? lastRunTime;
  final bool isProgress;
  final bool isSignalR;
  final double? progressValue;
  final double? progressMax;
  final String? progressMessage;

  const BazarrJob({
    this.jobId,
    this.jobName,
    this.status,
    this.lastRunTime,
    required this.isProgress,
    required this.isSignalR,
    this.progressValue,
    this.progressMax,
    this.progressMessage,
  });

  factory BazarrJob.fromJson(Map<String, dynamic> json) {
    return BazarrJob(
      jobId: stringOrNull(json['job_id']),
      jobName: stringOrNull(json['job_name']),
      status: stringOrNull(json['status']),
      lastRunTime: stringOrNull(json['last_run_time']),
      isProgress: json['is_progress'] == true,
      isSignalR: json['is_signalr'] == true,
      progressValue: doubleOrNull(json['progress_value']),
      progressMax: doubleOrNull(json['progress_max']),
      progressMessage: stringOrNull(json['progress_message']),
    );
  }
}

/// Bazarr's integer action codes for `TableHistory.action` /
/// `TableHistoryMovie.action` columns.
class BazarrHistoryActionCode {
  BazarrHistoryActionCode._();
  static const downloaded = 1;
  static const upgraded = 2;
  static const removed = 3;
}

enum BazarrHistoryAction {
  downloaded,
  upgraded,
  matched,
  failed,
  removed,
  unknown,
}

extension BazarrHistoryActionX on BazarrHistoryAction {
  String get label {
    return switch (this) {
      BazarrHistoryAction.downloaded => 'DOWNLOADED',
      BazarrHistoryAction.upgraded => 'UPGRADED',
      BazarrHistoryAction.matched => 'MATCHED',
      BazarrHistoryAction.failed => 'FAILED',
      BazarrHistoryAction.removed => 'REMOVED',
      BazarrHistoryAction.unknown => 'EVENT',
    };
  }

  /// Maps a Bazarr history action integer (1=downloaded, 2=upgraded,
  /// 3=removed) plus well-known string fallbacks for legacy payloads.
  static BazarrHistoryAction fromActionCode(dynamic raw) {
    if (raw is num) {
      switch (raw.toInt()) {
        case BazarrHistoryActionCode.downloaded:
          return BazarrHistoryAction.downloaded;
        case BazarrHistoryActionCode.upgraded:
          return BazarrHistoryAction.upgraded;
        case BazarrHistoryActionCode.removed:
          return BazarrHistoryAction.removed;
      }
    }
    if (raw is String) {
      switch (raw.toLowerCase()) {
        case 'downloaded':
        case 'download':
          return BazarrHistoryAction.downloaded;
        case 'upgraded':
        case 'upgrade':
          return BazarrHistoryAction.upgraded;
        case 'matched':
        case 'match':
        case 'synced':
          return BazarrHistoryAction.matched;
        case 'failed':
        case 'failure':
          return BazarrHistoryAction.failed;
        case 'removed':
        case 'removed_subtitle':
          return BazarrHistoryAction.removed;
      }
    }
    return BazarrHistoryAction.unknown;
  }
}

enum BazarrHistoryKind { episode, movie }

/// Lightweight typed view of recent Bazarr history used by the dashboard.
///
/// Bazarr returns untyped maps for `/api/episodes/history` and
/// `/api/movies/history`. The endpoints expose:
/// - `action` as an integer (1=downloaded, 2=upgraded, 3=removed)
/// - `language` as a nested object `{name, code2, code3, forced, hi}`
///   after `postprocess()` runs
/// - `timestamp` as a `pretty.date()` human-readable string and
///   `parsed_timestamp` as the underlying `strftime('%x %X')` value.
/// The helpers below extract the fields the dashboard actually displays.
class BazarrHistoryItem {
  final BazarrHistoryKind kind;
  final String? title;
  final String? subtitle;
  final String? languageLabel;
  final String? provider;
  final int? actionCode;
  final String? timestamp;
  final String? parsedTimestamp;
  final int? score;
  final bool upgradable;
  final bool blacklisted;

  const BazarrHistoryItem({
    required this.kind,
    this.title,
    this.subtitle,
    this.languageLabel,
    this.provider,
    this.actionCode,
    this.timestamp,
    this.parsedTimestamp,
    this.score,
    this.upgradable = false,
    this.blacklisted = false,
  });

  BazarrHistoryAction get action =>
      BazarrHistoryActionX.fromActionCode(actionCode);

  factory BazarrHistoryItem.fromEpisodeMap(Map<String, dynamic> json) {
    return BazarrHistoryItem(
      kind: BazarrHistoryKind.episode,
      title: stringOrNull(json['seriesTitle']) ?? stringOrNull(json['title']),
      subtitle: stringOrNull(json['episodeTitle']),
      languageLabel: _languageLabel(json['language']),
      provider: stringOrNull(json['provider']),
      actionCode: intOrNull(json['action']),
      timestamp: stringOrNull(json['timestamp']),
      parsedTimestamp: stringOrNull(json['parsed_timestamp']),
      score: intOrNull(json['score']),
      upgradable: json['upgradable'] == true,
      blacklisted: json['blacklisted'] == true,
    );
  }

  factory BazarrHistoryItem.fromMovieMap(Map<String, dynamic> json) {
    return BazarrHistoryItem(
      kind: BazarrHistoryKind.movie,
      title: stringOrNull(json['title']),
      subtitle: stringOrNull(json['description']),
      languageLabel: _languageLabel(json['language']),
      provider: stringOrNull(json['provider']),
      actionCode: intOrNull(json['action']),
      timestamp: stringOrNull(json['timestamp']),
      parsedTimestamp: stringOrNull(json['parsed_timestamp']),
      score: intOrNull(json['score']),
      upgradable: json['upgradable'] == true,
      blacklisted: json['blacklisted'] == true,
    );
  }

  /// `language` may be a Bazarr `subtitles_language_model` object (after
  /// `postprocess`) or a raw language string. We extract a short display
  /// label (code2 or name).
  static String? _languageLabel(dynamic value) {
    if (value is Map) {
      final typed = stringKeyMap(value);
      return stringOrNull(typed['code2']) ?? stringOrNull(typed['name']);
    }
    return stringOrNull(value);
  }
}

/// Documented actions for `PATCH /api/series` and `PATCH /api/movies`.
class BazarrSeriesAction {
  BazarrSeriesAction._();
  static const scanDisk = 'scan-disk';
  static const searchMissing = 'search-missing';
  static const searchWanted = 'search-wanted';
  static const sync = 'sync';
}

/// Documented actions for `POST /api/system/jobs` (job queue control).
class BazarrJobAction {
  BazarrJobAction._();
  static const forceStart = 'force_start';
  static const moveTop = 'move_top';
  static const moveBottom = 'move_bottom';
}

/// Documented queue names for `PATCH /api/system/jobs` (empty queue).
class BazarrJobQueue {
  BazarrJobQueue._();
  static const pending = 'pending';
  static const failed = 'failed';
  static const completed = 'completed';
}

/// Documented status filters for `GET /api/system/jobs`.
class BazarrJobStatus {
  BazarrJobStatus._();
  static const pending = 'pending';
  static const running = 'running';
  static const failed = 'failed';
  static const completed = 'completed';
}
