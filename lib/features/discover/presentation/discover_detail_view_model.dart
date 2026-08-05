import 'package:seekarr/core/utils/image_utils.dart';
import 'package:seekarr/core/utils/string_utils.dart';
import 'package:seekarr/features/discover/domain/models/discover_detail_model.dart';

typedef DiscoverDetailRating = ({
  String name,
  double value,
  int votes,
  String icon,
});

typedef DiscoverCastMember = ({
  int id,
  String name,
  String character,
  String? profilePath,
});

class DiscoverDetailViewModel {
  final String title;
  final String overview;
  final String posterUrl;
  final String? backdropUrl;
  final String seerrStatus;
  final bool isAvailable;
  final bool isPartiallyAvailable;
  final int? statusCode;
  final Map<String, dynamic>? mediaInfo;
  final String genres;
  final List<String> genresList;
  final String year;
  final String? runtimeStr;
  final int? numberOfSeasons;
  final String networks;
  final List<String> studios;
  final double? voteAverage;
  final int? voteCount;
  final List<DiscoverCastMember> cast;
  final List<String> directors;
  final List<String> writers;
  final List<String> keywords;
  final int? tvdbId;
  final List<WatchProviderRegion> watchProviders;
  final List<RelatedVideo> relatedVideos;
  final CollectionInfo? collection;
  final List<TvSeason> seasons;
  final int? numberOfEpisodes;
  final TvEpisodeSummary? lastEpisodeToAir;
  final TvEpisodeSummary? nextEpisodeToAir;
  final String? firstAirDate;
  final String? lastAirDate;
  final List<MovieRelease> movieReleases;
  final List<TvContentRating> contentRatings;

  DiscoverDetailViewModel({
    required this.title,
    required this.overview,
    required this.posterUrl,
    required this.backdropUrl,
    required this.seerrStatus,
    required this.isAvailable,
    required this.isPartiallyAvailable,
    required this.statusCode,
    required this.mediaInfo,
    required this.genres,
    required this.genresList,
    required this.year,
    required this.runtimeStr,
    required this.numberOfSeasons,
    required this.networks,
    required this.studios,
    required this.voteAverage,
    required this.voteCount,
    required this.cast,
    required this.directors,
    required this.writers,
    required this.keywords,
    required this.tvdbId,
    this.watchProviders = const [],
    this.relatedVideos = const [],
    this.collection,
    this.seasons = const [],
    this.numberOfEpisodes,
    this.lastEpisodeToAir,
    this.nextEpisodeToAir,
    this.firstAirDate,
    this.lastAirDate,
    this.movieReleases = const [],
    this.contentRatings = const [],
  });

  String get metadataLine =>
      [genres, networks].where((value) => value.isNotEmpty).join(' • ');

  String detailMetadataLine({required bool isMovie}) {
    return [
      year,
      isMovie ? runtimeStr : episodeSummary ?? runtimeStr,
      genres,
      if (!isMovie && networks.isNotEmpty) networks,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' • ');
  }

  bool get hasCrew => directors.isNotEmpty || writers.isNotEmpty;

  bool get hasManageableMedia => mediaInfo?['id'] != null;

  String? get servicePath => mediaInfo?['path']?.toString();

  String get directorNames => directors.join(', ');

  String get writerNames => writers.join(', ');

  late final List<RelatedVideo> playableVideos = relatedVideos
      .where((video) => video.url.isNotEmpty)
      .toList(growable: false);

  bool get hasRelatedVideos => playableVideos.isNotEmpty;

  bool get hasCollection => collection != null;

  bool get hasSeasons => seasons.isNotEmpty;

  String? get episodeSummary {
    final parts = <String>[];

    if (numberOfSeasons != null) {
      final seasonsLabel = numberOfSeasons == 1 ? 'Season' : 'Seasons';
      parts.add('$numberOfSeasons $seasonsLabel');
    }

    if (numberOfEpisodes != null) {
      final episodesLabel = numberOfEpisodes == 1 ? 'Episode' : 'Episodes';
      parts.add('$numberOfEpisodes $episodesLabel');
    }

    if (parts.isEmpty) {
      return null;
    }

    return parts.join(' • ');
  }

  WatchProviderRegion? watchProvidersForRegion(String region) {
    final normalizedRegion = _normalizeRegion(region);
    for (final provider in watchProviders) {
      if (provider.iso3166 == normalizedRegion) {
        return provider;
      }
    }

    return null;
  }

  String? movieContentRatingForRegion(String region) {
    for (final release in releasesForRegion(region)) {
      final certification = release.certification ?? '';
      if (certification.isNotEmpty) {
        return certification;
      }
    }

    return null;
  }

  String? tvContentRatingForRegion(String region) {
    final normalizedRegion = _normalizeRegion(region);
    for (final rating in contentRatings) {
      if (rating.iso3166 == normalizedRegion && rating.rating.isNotEmpty) {
        return rating.rating;
      }
    }

    return null;
  }

  List<MovieRelease> releasesForRegion(String region) {
    final normalizedRegion = _normalizeRegion(region);
    final filteredReleases = movieReleases
        .where((release) => release.iso3166 == normalizedRegion)
        .toList(growable: false);

    final sortedReleases = [...filteredReleases]
      ..sort(
        (left, right) => _movieReleasePriority(
          left.type,
        ).compareTo(_movieReleasePriority(right.type)),
      );

    return sortedReleases;
  }

  factory DiscoverDetailViewModel.fromResponse(
    Map<String, dynamic> details, {
    String? initialPosterUrl,
  }) {
    final mediaInfo = _asMap(details['mediaInfo']);
    final externalIds = _asMap(details['externalIds']);
    final statusCode = (mediaInfo?['status'] as num?)?.toInt();
    final releaseDate =
        details['releaseDate'] ??
        details['release_date'] ??
        details['firstAirDate'] ??
        details['first_air_date'];
    final runtime = _extractRuntime(details);
    final credits = _asMap(details['credits']);
    final crew = _asMapList(credits?['crew']);
    final cast = _asMapList(credits?['cast']);
    final posterPath =
        details['posterPath']?.toString() ?? details['poster_path']?.toString();
    final backdropPath =
        details['backdropPath']?.toString() ??
        details['backdrop_path']?.toString();
    final watchProviders = _asMapList(
      details['watchProviders'],
    ).map(WatchProviderRegion.fromJson).toList(growable: false);
    final relatedVideos = _asMapList(
      details['relatedVideos'],
    ).map(RelatedVideo.fromJson).toList(growable: false);
    final collection = _asMap(details['collection']);
    final seasons = _asMapList(
      details['seasons'],
    ).map(TvSeason.fromJson).toList(growable: false);
    final lastEpisodeToAir = _asMap(details['lastEpisodeToAir']);
    final nextEpisodeToAir = _asMap(details['nextEpisodeToAir']);
    final releases = _flattenMovieReleases(_asMap(details['releases']));
    final contentRatings = _asMapList(
      _asMap(details['contentRatings'])?['results'],
    ).map(TvContentRating.fromJson).toList(growable: false);
    final genresList = _takeNames(_asMapList(details['genres']));
    final studios = _takeNames(
      _asMapList(
        details['production_companies'] ?? details['productionCompanies'],
      ),
      limit: 4,
    );

    return DiscoverDetailViewModel(
      title:
          details['title']?.toString() ??
          details['name']?.toString() ??
          'Unknown',
      overview: details['overview']?.toString() ?? '',
      posterUrl: initialPosterUrl != null && initialPosterUrl.isNotEmpty
          ? initialPosterUrl
          : ImageUtils.buildTmdbPosterUrl(posterPath, size: 'w500'),
      backdropUrl: ImageUtils.buildTmdbPosterUrl(backdropPath, size: 'w1280'),
      seerrStatus: mapSeerrStatus(statusCode),
      isAvailable: statusCode == 5,
      isPartiallyAvailable: statusCode == 4,
      statusCode: statusCode,
      mediaInfo: mediaInfo,
      genres: _joinNamedValues(details['genres']),
      genresList: genresList,
      year: _extractYear(releaseDate),
      // One runtime voice with Radarr and Sonarr: `2h 53m`, never `173min`.
      runtimeStr: runtime == null || formatRuntimeMinutes(runtime).isEmpty
          ? null
          : formatRuntimeMinutes(runtime),
      numberOfSeasons: (details['numberOfSeasons'] as num?)?.toInt(),
      networks: _joinNamedValues(details['networks'], take: 2),
      studios: studios,
      voteAverage:
          (details['voteAverage'] as num?)?.toDouble() ??
          (details['vote_average'] as num?)?.toDouble(),
      voteCount:
          (details['voteCount'] as num?)?.toInt() ??
          (details['vote_count'] as num?)?.toInt(),
      cast: cast.take(20).map(_toCastMember).toList(growable: false),
      directors: _takeCrewNames(crew, jobs: const {'Director'}),
      writers: _takeCrewNames(crew, jobs: const {'Writer', 'Screenplay'}),
      keywords: _takeNames(_asMapList(details['keywords'])),
      tvdbId:
          (externalIds?['tvdbId'] as num?)?.toInt() ??
          (details['tvdbId'] as num?)?.toInt(),
      watchProviders: watchProviders,
      relatedVideos: relatedVideos,
      collection: collection != null
          ? CollectionInfo.fromJson(collection)
          : null,
      seasons: seasons,
      numberOfEpisodes: (details['numberOfEpisodes'] as num?)?.toInt(),
      lastEpisodeToAir: lastEpisodeToAir != null
          ? TvEpisodeSummary.fromJson(lastEpisodeToAir)
          : null,
      nextEpisodeToAir: nextEpisodeToAir != null
          ? TvEpisodeSummary.fromJson(nextEpisodeToAir)
          : null,
      firstAirDate: details['firstAirDate']?.toString(),
      lastAirDate: details['lastAirDate']?.toString(),
      movieReleases: releases,
      contentRatings: contentRatings,
    );
  }

  static String mapSeerrStatus(int? status) {
    if (status == null) return 'Available to Request';

    switch (status) {
      case 1:
        return 'Unknown';
      case 2:
        return 'Pending';
      case 3:
        return 'Processing';
      case 4:
        return 'Partially Available';
      case 5:
        return 'Available';
      case 6:
        return 'Deleted';
      default:
        return 'Unknown';
    }
  }
}

int _movieReleasePriority(int type) {
  return switch (type) {
    3 => 0,
    4 => 1,
    5 => 2,
    2 => 3,
    1 => 4,
    6 => 5,
    _ => 99,
  };
}

DiscoverCastMember _toCastMember(Map<String, dynamic> member) {
  return (
    id: (member['id'] as num?)?.toInt() ?? 0,
    name: member['name']?.toString() ?? '',
    character: member['character']?.toString() ?? '',
    profilePath:
        member['profilePath']?.toString() ?? member['profile_path']?.toString(),
  );
}

List<String> _takeCrewNames(
  List<Map<String, dynamic>> crew, {
  required Set<String> jobs,
  int limit = 2,
}) {
  return crew
      .where((member) => jobs.contains(member['job']))
      .map((member) => member['name']?.toString() ?? '')
      .where((name) => name.isNotEmpty)
      .take(limit)
      .toList(growable: false);
}

List<String> _takeNames(List<Map<String, dynamic>> items, {int limit = 8}) {
  return items
      .map((item) => item['name']?.toString() ?? '')
      .where((name) => name.isNotEmpty)
      .take(limit)
      .toList(growable: false);
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }

  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  return null;
}

List<Map<String, dynamic>> _asMapList(Object? value) {
  if (value is! List) {
    return const [];
  }

  return value
      .map(_asMap)
      .whereType<Map<String, dynamic>>()
      .toList(growable: false);
}

String _extractYear(Object? releaseDate) {
  final value = releaseDate?.toString() ?? '';
  return value.length >= 4 ? value.substring(0, 4) : '';
}

int? _extractRuntime(Map<String, dynamic> details) {
  int? parseMinutes(Object? value) {
    return switch (value) {
      int minutes => minutes,
      num minutes => minutes.toInt(),
      String minutes => int.tryParse(minutes),
      _ => null,
    };
  }

  final runtime = parseMinutes(details['runtime']);
  if (runtime != null && runtime > 0) {
    return runtime;
  }

  final episodeRunTime =
      details['episodeRunTime'] ?? details['episode_run_time'];
  if (episodeRunTime is List) {
    for (final value in episodeRunTime) {
      final minutes = parseMinutes(value);
      if (minutes != null && minutes > 0) {
        return minutes;
      }
    }
  }

  return null;
}

String _normalizeRegion(String region) {
  return region.trim().toUpperCase();
}

List<MovieRelease> _flattenMovieReleases(Map<String, dynamic>? releases) {
  if (releases == null) {
    return const [];
  }

  final flattenedReleases = <MovieRelease>[];
  final releaseRegions = _asMapList(releases['results']);

  for (final region in releaseRegions) {
    final iso3166 = region['iso_3166_1']?.toString().toUpperCase() ?? '';
    if (iso3166.isEmpty) {
      continue;
    }

    final releaseDates = _asMapList(region['release_dates']);
    for (final release in releaseDates) {
      flattenedReleases.add(
        MovieRelease.fromJson({
          ...release,
          'iso_3166_1': iso3166,
          'releaseDate':
              release['releaseDate']?.toString() ??
              release['release_date']?.toString() ??
              '',
        }),
      );
    }
  }

  return flattenedReleases;
}

String _joinNamedValues(Object? value, {int? take}) {
  final labels = <String>[];

  if (value is List) {
    for (final item in value) {
      if (item is Map) {
        final label = item['name']?.toString();
        if (label != null && label.isNotEmpty) {
          labels.add(label);
        }
      } else if (item != null) {
        final label = item.toString();
        if (label.isNotEmpty) {
          labels.add(label);
        }
      }
    }
  }

  final limitedLabels = take != null ? labels.take(take) : labels;
  return limitedLabels.join(', ');
}
