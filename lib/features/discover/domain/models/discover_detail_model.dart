import 'package:cupola/core/utils/url_utils.dart';

class WatchProviderEntry {
  final int id;
  final String name;
  final String? logoPath;

  const WatchProviderEntry({
    required this.id,
    required this.name,
    this.logoPath,
  });

  factory WatchProviderEntry.fromJson(Map<String, dynamic> json) {
    return WatchProviderEntry(
      id: _asInt(json['id']) ?? 0,
      name: json['name']?.toString() ?? '',
      logoPath: json['logoPath']?.toString() ?? json['logo_path']?.toString(),
    );
  }
}

class WatchProviderRegion {
  final String iso3166;
  final String? link;
  final List<WatchProviderEntry> flatrate;
  final List<WatchProviderEntry> buy;

  const WatchProviderRegion({
    required this.iso3166,
    this.link,
    this.flatrate = const [],
    this.buy = const [],
  });

  factory WatchProviderRegion.fromJson(Map<String, dynamic> json) {
    return WatchProviderRegion(
      iso3166:
          json['iso_3166_1']?.toString().toUpperCase() ??
          json['iso3166']?.toString().toUpperCase() ??
          '',
      link: json['link']?.toString(),
      flatrate: _asMapList(
        json['flatrate'],
      ).map(WatchProviderEntry.fromJson).toList(growable: false),
      buy: _asMapList(
        json['buy'],
      ).map(WatchProviderEntry.fromJson).toList(growable: false),
    );
  }
}

class RelatedVideo {
  final String url;
  final String key;
  final String name;
  final String type;
  final String site;
  final int? size;

  const RelatedVideo({
    required this.url,
    required this.key,
    required this.name,
    required this.type,
    required this.site,
    this.size,
  });

  factory RelatedVideo.fromJson(Map<String, dynamic> json) {
    final key = json['key']?.toString() ?? '';
    final site = json['site']?.toString() ?? '';

    return RelatedVideo(
      // The server's `url` is only taken when it is a web address. It is the
      // one field here that ends up being *launched*, and this app hands it to
      // the platform's external handler — where `javascript:`, `data:`,
      // `intent:` and `file:` are all syntactically valid URIs that
      // `Uri.tryParse` happily accepts. Anything else falls back to the builder
      // below, which can only ever produce https, and an empty string makes the
      // row untappable (`playableVideos` drops it).
      url: _webUrl(json['url']) ?? _buildVideoUrl(site, key),
      key: key,
      name: json['name']?.toString() ?? 'Video',
      type: json['type']?.toString() ?? '',
      site: site,
      size: _asInt(json['size']),
    );
  }

  /// [value] as a launchable http(s) URL, or null when it is anything else.
  static String? _webUrl(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) return null;
    return UrlUtils.isLaunchableWebUrl(raw) ? raw : null;
  }

  static String _buildVideoUrl(String site, String key) {
    if (key.isEmpty) {
      return '';
    }

    switch (site.toLowerCase()) {
      case 'youtube':
        return 'https://www.youtube.com/watch?v=$key';
      case 'vimeo':
        return 'https://vimeo.com/$key';
      default:
        return '';
    }
  }
}

class MovieRelease {
  final String iso3166;
  final String? certification;
  final String releaseDate;
  final int type;

  const MovieRelease({
    required this.iso3166,
    this.certification,
    required this.releaseDate,
    required this.type,
  });

  factory MovieRelease.fromJson(Map<String, dynamic> json) {
    final certification = json['certification']?.toString().trim();

    return MovieRelease(
      iso3166:
          json['iso_3166_1']?.toString().toUpperCase() ??
          json['iso3166']?.toString().toUpperCase() ??
          '',
      certification: certification == null || certification.isEmpty
          ? null
          : certification,
      releaseDate:
          json['releaseDate']?.toString() ??
          json['release_date']?.toString() ??
          '',
      type: _asInt(json['type']) ?? 0,
    );
  }
}

class TvContentRating {
  final String iso3166;
  final String rating;

  const TvContentRating({required this.iso3166, required this.rating});

  factory TvContentRating.fromJson(Map<String, dynamic> json) {
    return TvContentRating(
      iso3166: json['iso_3166_1']?.toString().toUpperCase() ?? '',
      rating: json['rating']?.toString() ?? '',
    );
  }
}

class TvSeason {
  final int id;
  final int seasonNumber;
  final String name;
  final int episodeCount;
  final String? airDate;
  final String? posterPath;
  final List<TvEpisodeSummary> episodes;

  const TvSeason({
    required this.id,
    required this.seasonNumber,
    required this.name,
    required this.episodeCount,
    this.airDate,
    this.posterPath,
    this.episodes = const [],
  });

  factory TvSeason.fromJson(Map<String, dynamic> json) {
    return TvSeason(
      id: _asInt(json['id']) ?? 0,
      seasonNumber:
          _asInt(json['seasonNumber']) ?? _asInt(json['season_number']) ?? 0,
      name: json['name']?.toString() ?? '',
      episodeCount:
          _asInt(json['episodeCount']) ?? _asInt(json['episode_count']) ?? 0,
      airDate: json['airDate']?.toString() ?? json['air_date']?.toString(),
      posterPath:
          json['posterPath']?.toString() ?? json['poster_path']?.toString(),
      episodes: _asMapList(
        json['episodes'],
      ).map(TvEpisodeSummary.fromJson).toList(growable: false),
    );
  }
}

class TvEpisodeSummary {
  final String? name;
  final String? airDate;
  final int? seasonNumber;
  final int? episodeNumber;

  const TvEpisodeSummary({
    this.name,
    this.airDate,
    this.seasonNumber,
    this.episodeNumber,
  });

  factory TvEpisodeSummary.fromJson(Map<String, dynamic> json) {
    return TvEpisodeSummary(
      name: json['name']?.toString(),
      airDate: json['airDate']?.toString() ?? json['air_date']?.toString(),
      seasonNumber:
          _asInt(json['seasonNumber']) ?? _asInt(json['season_number']),
      episodeNumber:
          _asInt(json['episodeNumber']) ?? _asInt(json['episode_number']),
    );
  }
}

class CollectionInfo {
  final int id;
  final String name;
  final String? posterPath;
  final String? backdropPath;

  const CollectionInfo({
    required this.id,
    required this.name,
    this.posterPath,
    this.backdropPath,
  });

  factory CollectionInfo.fromJson(Map<String, dynamic> json) {
    return CollectionInfo(
      id: _asInt(json['id']) ?? 0,
      name: json['name']?.toString() ?? '',
      posterPath:
          json['posterPath']?.toString() ?? json['poster_path']?.toString(),
      backdropPath:
          json['backdropPath']?.toString() ?? json['backdrop_path']?.toString(),
    );
  }
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  if (value is String) {
    return int.tryParse(value);
  }

  return null;
}

List<Map<String, dynamic>> _asMapList(Object? value) {
  if (value is! List) {
    return const [];
  }

  return value
      .whereType<Map>()
      .map((entry) => entry.map((key, item) => MapEntry(key.toString(), item)))
      .toList(growable: false);
}
