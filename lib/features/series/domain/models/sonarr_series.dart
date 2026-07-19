import 'package:seekarr/core/models/media_preview.dart';
import 'package:seekarr/core/models/rating_source.dart';
import 'package:seekarr/core/utils/arr_model_helpers.dart';

export 'package:seekarr/core/models/rating_source.dart';

class SonarrSeries {
  final int id;
  final String title;
  final String sortTitle;
  final String status;
  final String? overview;
  final String? path;
  final bool monitored;
  final int year;
  final List<dynamic> images;
  final int tvdbId;
  final int tmdbId;
  final int runtime;
  final String? network;
  final List<String> genres;
  final List<dynamic> seasons;
  final Map<String, dynamic>? statistics;
  final int? qualityProfileId;
  final List<RatingSource> ratings;
  final String? seriesType;
  final String? certification;
  final String? firstAired;
  final String? lastAired;
  final String? added;
  final Map<String, dynamic>? originalLanguage;

  const SonarrSeries({
    required this.id,
    required this.title,
    required this.sortTitle,
    required this.status,
    this.overview,
    this.path,
    required this.monitored,
    required this.year,
    required this.images,
    required this.tvdbId,
    this.tmdbId = 0,
    required this.runtime,
    this.network,
    required this.genres,
    required this.seasons,
    this.statistics,
    this.qualityProfileId,
    this.ratings = const [],
    this.seriesType,
    this.certification,
    this.firstAired,
    this.lastAired,
    this.added,
    this.originalLanguage,
  });

  factory SonarrSeries.fromJson(Map<String, dynamic> json) {
    final ratings = parseArrRatings(json['ratings'], singleSourceIcon: 'TVDB');

    return SonarrSeries(
      id: json['id'] ?? 0,
      title: json['title'] ?? 'Unknown',
      sortTitle: json['sortTitle'] ?? '',
      status: json['status'] ?? 'unknown',
      overview: json['overview'],
      path: json['path'],
      monitored: json['monitored'] ?? false,
      year: json['year'] ?? 0,
      images: json['images'] ?? [],
      tvdbId: json['tvdbId'] ?? 0,
      tmdbId: json['tmdbId'] ?? 0,
      runtime: json['runtime'] ?? 0,
      network: json['network'],
      genres: parseGenreList(json['genres']),
      seasons: json['seasons'] ?? [],
      statistics: json['statistics'],
      qualityProfileId: json['qualityProfileId'],
      ratings: ratings,
      seriesType: json['seriesType'],
      certification: json['certification'],
      firstAired: json['firstAired'],
      lastAired: json['lastAired'],
      added: json['added'],
      originalLanguage: json['originalLanguage'] is Map<String, dynamic>
          ? json['originalLanguage'] as Map<String, dynamic>
          : null,
    );
  }

  MediaPreview toMediaPreview() {
    final posterPath = extractPosterPathFromImages(images);

    return MediaPreview(
      id: id,
      title: title,
      posterPath: posterPath,
      overview: overview,
      releaseDate: year.toString(),
      mediaType: 'tv',
    );
  }
}
