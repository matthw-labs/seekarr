import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/models/rating_source.dart';
import 'package:cupola/core/utils/arr_model_helpers.dart';

export 'package:cupola/core/models/rating_source.dart';

class LidarrArtist {
  final int id;
  final String artistName;
  final String status;
  final String? overview;
  final bool monitored;
  final List<dynamic> images;
  final Map<String, dynamic>? statistics;
  final List<String> genres;
  final int? qualityProfileId;
  final List<RatingSource> ratings;
  final String? artistType;
  final String? disambiguation;
  final List<Map<String, dynamic>>? links;
  final String? added;
  final String? path;

  const LidarrArtist({
    required this.id,
    required this.artistName,
    required this.status,
    this.overview,
    required this.monitored,
    required this.images,
    this.statistics,
    required this.genres,
    this.qualityProfileId,
    this.ratings = const [],
    this.artistType,
    this.disambiguation,
    this.links,
    this.added,
    this.path,
  });

  int get albumCount => (statistics?['albumCount'] as num?)?.toInt() ?? 0;

  int get trackCount => (statistics?['trackCount'] as num?)?.toInt() ?? 0;

  int get trackFileCount =>
      (statistics?['trackFileCount'] as num?)?.toInt() ?? 0;

  bool get hasFiles => trackFileCount > 0;

  factory LidarrArtist.fromJson(Map<String, dynamic> json) {
    final ratings = parseArrRatings(
      json['ratings'],
      allowMultiSource: false,
      singleSourceIcon: 'MB',
    );

    return LidarrArtist(
      id: json['id'] ?? 0,
      artistName: json['artistName'] ?? 'Unknown',
      status: json['status'] ?? 'unknown',
      overview: json['overview'],
      monitored: json['monitored'] ?? false,
      images: json['images'] ?? [],
      statistics: json['statistics'],
      genres: parseGenreList(json['genres']),
      qualityProfileId: json['qualityProfileId'],
      ratings: ratings,
      artistType: json['artistType'],
      disambiguation: json['disambiguation'],
      links: (json['links'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .toList(),
      added: json['added'],
      path: json['path'],
    );
  }

  MediaPreview toMediaPreview() {
    final posterPath = extractPosterPathFromImages(images);

    return MediaPreview(
      id: id,
      title: artistName,
      posterPath: posterPath,
      overview: overview,
      // Lidarr artists don't have a single "year" usually, maybe started/ended?
      // Leaving releaseDate null or empty.
      mediaType: 'music',
    );
  }
}
