import 'package:seekarr/core/models/media_preview.dart';

/// A movie collection as returned by Overseerr/Jellyseerr `/collection/{id}`,
/// including its member movies (`parts`).
class CollectionDetail {
  final int id;
  final String name;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final List<MediaPreview> parts;

  const CollectionDetail({
    required this.id,
    required this.name,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.parts = const [],
  });

  factory CollectionDetail.fromJson(Map<String, dynamic> json) {
    final rawParts = json['parts'] as List<dynamic>? ?? const [];
    final parts = rawParts
        .whereType<Map<String, dynamic>>()
        .map((e) => MediaPreview.fromJson(e, forcedMediaType: 'movie'))
        .toList(growable: false);
    return CollectionDetail(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      overview: json['overview']?.toString(),
      posterPath:
          json['posterPath']?.toString() ?? json['poster_path']?.toString(),
      backdropPath:
          json['backdropPath']?.toString() ?? json['backdrop_path']?.toString(),
      parts: parts,
    );
  }

  bool get isEmpty => id == 0 && parts.isEmpty;
}
