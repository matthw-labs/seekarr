import 'package:seekarr/core/models/media_preview.dart';
import 'package:seekarr/core/models/rating_source.dart';
import 'package:seekarr/core/utils/arr_model_helpers.dart';

export 'package:seekarr/core/models/rating_source.dart';

class RadarrMovie {
  final int id;
  final String title;
  final String sortTitle;
  final int sizeOnDisk;
  final String status;
  final String? overview;
  final String? path;
  final bool hasFile;
  final bool monitored;
  final int year;
  final List<dynamic> images;
  final int tmdbId;
  final int runtime;
  final String? studio;
  final List<String> genres;
  final int? qualityProfileId;
  final List<RatingSource> ratings;
  final String? certification;
  final Map<String, dynamic>? originalLanguage;
  final String? inCinemas;
  final String? digitalRelease;
  final String? physicalRelease;
  final String? added;
  final String? minimumAvailability;

  /// Radarr's own verdict on whether the movie can be grabbed yet — it already
  /// weighs [minimumAvailability] against the release dates, so prefer it over
  /// re-deriving availability from [status].
  final bool? isAvailable;

  const RadarrMovie({
    required this.id,
    required this.title,
    required this.sortTitle,
    required this.sizeOnDisk,
    required this.status,
    this.overview,
    this.path,
    required this.hasFile,
    required this.monitored,
    required this.year,
    required this.images,
    required this.tmdbId,
    required this.runtime,
    this.studio,
    required this.genres,
    this.qualityProfileId,
    this.ratings = const [],
    this.certification,
    this.originalLanguage,
    this.inCinemas,
    this.digitalRelease,
    this.physicalRelease,
    this.added,
    this.minimumAvailability,
    this.isAvailable,
  });

  /// Whether a file is expected to exist by now.
  ///
  /// Distinguishes "released and genuinely missing" from "not out yet", which
  /// the old badge collapsed into a single red `Missing`.
  bool get isExpectedOnDisk {
    final radarrVerdict = isAvailable;
    if (radarrVerdict != null) return radarrVerdict;

    // Older Radarr payloads omit `isAvailable`; fall back to the same reading
    // used by the Wanted list.
    final normalized = status.toLowerCase();
    return normalized == 'released' || normalized == 'incinemas';
  }

  factory RadarrMovie.fromJson(Map<String, dynamic> json) {
    final ratings = parseArrRatings(json['ratings'], allowSingleSource: false);

    return RadarrMovie(
      id: json['id'] ?? 0,
      title: json['title'] ?? 'Unknown',
      sortTitle: json['sortTitle'] ?? '',
      sizeOnDisk: json['sizeOnDisk'] ?? 0,
      status: json['status'] ?? 'unknown',
      overview: json['overview'],
      path: json['path'],
      hasFile: json['hasFile'] ?? false,
      monitored: json['monitored'] ?? false,
      year: json['year'] ?? 0,
      images: json['images'] ?? [],
      tmdbId: json['tmdbId'] ?? 0,
      runtime: json['runtime'] ?? 0,
      studio: json['studio'],
      genres: parseGenreList(json['genres']),
      qualityProfileId: json['qualityProfileId'],
      ratings: ratings,
      certification: json['certification'],
      originalLanguage: json['originalLanguage'] is Map<String, dynamic>
          ? json['originalLanguage'] as Map<String, dynamic>
          : null,
      inCinemas: json['inCinemas'],
      digitalRelease: json['digitalRelease'],
      physicalRelease: json['physicalRelease'],
      added: json['added'],
      minimumAvailability: json['minimumAvailability'],
      isAvailable: json['isAvailable'] is bool
          ? json['isAvailable'] as bool
          : null,
    );
  }

  /// Converts to the shared [MediaPreview] model for generic lists
  MediaPreview toMediaPreview() {
    final posterPath = extractPosterPathFromImages(images);

    return MediaPreview(
      id: id,
      title: title,
      posterPath: posterPath,
      overview: overview,
      releaseDate: year.toString(),
      mediaType: 'movie',
    );
  }
}
