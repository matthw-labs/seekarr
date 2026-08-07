import 'package:flutter/material.dart';

import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';

class MusicDetailViewModel {
  final String title;
  final String overview;
  final String posterUrl;
  final Map<String, String>? posterHeaders;
  final String? backdropUrl;
  final String status;
  final bool hasFiles;
  final bool isInLibrary;
  final bool isMonitored;
  final int trackFileCount;
  final List<String> genres;
  final List<RatingSource> ratings;
  final int? qualityProfileId;
  final int albumCount;
  final int trackCount;
  final String? artistType;
  final String? disambiguation;
  final String? path;

  const MusicDetailViewModel({
    required this.title,
    required this.overview,
    required this.posterUrl,
    this.posterHeaders,
    this.backdropUrl,
    required this.status,
    required this.hasFiles,
    required this.isInLibrary,
    required this.isMonitored,
    this.trackFileCount = 0,
    required this.genres,
    required this.ratings,
    this.qualityProfileId,
    required this.albumCount,
    required this.trackCount,
    this.artistType,
    this.disambiguation,
    this.path,
  });

  List<String> get metadataItems => [
    if (albumCountLabel != null) albumCountLabel!,
    if (trackCountLabel != null) trackCountLabel!,
  ];

  String? get albumCountLabel => albumCount > 0
      ? '$albumCount ${albumCount == 1 ? 'Album' : 'Albums'}'
      : null;

  String? get trackCountLabel => trackCount > 0
      ? '$trackCount ${trackCount == 1 ? 'Track' : 'Tracks'}'
      : null;

  List<MediaInfoGroup> buildInfoGroups([String? qualityProfileName]) {
    if (qualityProfileName == null) {
      return _buildLegacyInfoGroups();
    }

    return [
      if (albumCountLabel != null)
        MediaInfoGroup(title: 'Albums', child: Text(albumCount.toString())),
      if (trackCountLabel != null)
        MediaInfoGroup(title: 'Tracks', child: Text(trackCount.toString())),
      if (_hasText(qualityProfileName))
        MediaInfoGroup(title: 'Quality', child: Text(qualityProfileName)),
      MediaInfoGroup(
        title: 'Missing',
        child: Text(
          (trackCount - trackFileCount).clamp(0, trackCount).toString(),
        ),
      ),
      if (_hasText(artistType))
        MediaInfoGroup(
          title: 'Artist Type',
          child: Text(capitalizeFirst(artistType!)),
        ),
      if (_hasText(disambiguation))
        MediaInfoGroup(title: 'Disambiguation', child: Text(disambiguation!)),
      if (_hasText(path))
        MediaInfoGroup(title: 'Library Path', child: Text(path!)),
    ];
  }

  List<MediaInfoGroup> _buildLegacyInfoGroups() {
    return [
      if (_hasText(artistType))
        MediaInfoGroup(
          title: 'Artist Type',
          child: Text(capitalizeFirst(artistType!)),
        ),
      if (_hasText(disambiguation))
        MediaInfoGroup(title: 'Disambiguation', child: Text(disambiguation!)),
      if (genres.isNotEmpty)
        MediaInfoGroup(
          title: 'Genre',
          child: Wrap(
            children: genres
                .map((genre) => GenreChip(genre: genre))
                .toList(growable: false),
          ),
        ),
      if (_hasText(path))
        MediaInfoGroup(title: 'Library Path', child: Text(path!)),
    ];
  }

  bool _hasText(String? value) => value != null && value.isNotEmpty;

  factory MusicDetailViewModel.fromArtist(
    LidarrArtist artist, {
    required String baseUrl,
    required String apiKey,
  }) {
    final posterSource = ImageUtils.extractPosterUrl(
      artist.images,
      baseUrl: baseUrl,
      apiKey: apiKey,
      coverTypes: const ['poster', 'fanart', 'banner', 'logo'],
    );
    final backdropSource = ImageUtils.extractPosterUrl(
      artist.images,
      baseUrl: baseUrl,
      apiKey: apiKey,
      coverTypes: const ['fanart'],
    );
    final isInLibrary = artist.id > 0 && artist.path?.isNotEmpty == true;

    return MusicDetailViewModel(
      title: artist.artistName,
      overview: artist.overview?.trim().isNotEmpty == true
          ? artist.overview!.trim()
          : 'No description available.',
      posterUrl: posterSource.url,
      posterHeaders: posterSource.headers,
      backdropUrl: ImageUtils.safeBackdropUrl(backdropSource),
      status: artist.status,
      hasFiles: artist.hasFiles,
      isInLibrary: isInLibrary,
      isMonitored: artist.monitored,
      trackFileCount: artist.trackFileCount,
      genres: artist.genres,
      ratings: artist.ratings,
      qualityProfileId: artist.qualityProfileId,
      albumCount: artist.albumCount,
      trackCount: artist.trackCount,
      artistType: artist.artistType,
      disambiguation: artist.disambiguation,
      path: artist.path,
    );
  }
}
