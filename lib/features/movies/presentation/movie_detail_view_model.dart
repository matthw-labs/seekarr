import 'package:flutter/material.dart';

import 'package:seekarr/core/utils/image_utils.dart';
import 'package:seekarr/core/utils/string_utils.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/movies/domain/models/radarr_movie.dart';

class MovieDetailViewModel {
  final String title;
  final String overview;
  final String posterUrl;
  final Map<String, String>? posterHeaders;
  final String? backdropUrl;
  final String status;
  final bool hasFile;
  final bool isInLibrary;
  final bool isMonitored;
  final String year;
  final String? runtimeStr;
  final String? studio;
  final List<String> genres;
  final List<RatingSource> ratings;
  final String? path;
  final String? filename;
  final int? qualityProfileId;
  final String? certification;
  final String? originalLanguage;
  final String? inCinemas;
  final String? digitalRelease;
  final String? physicalRelease;

  const MovieDetailViewModel({
    required this.title,
    required this.overview,
    required this.posterUrl,
    this.posterHeaders,
    this.backdropUrl,
    required this.status,
    required this.hasFile,
    required this.isInLibrary,
    required this.isMonitored,
    required this.year,
    this.runtimeStr,
    this.studio,
    required this.genres,
    required this.ratings,
    this.path,
    this.filename,
    this.qualityProfileId,
    this.certification,
    this.originalLanguage,
    this.inCinemas,
    this.digitalRelease,
    this.physicalRelease,
  });

  List<String> get metadataItems => [
    year,
    if (runtimeStr != null) runtimeStr!,
  ].where((item) => item.isNotEmpty).toList(growable: false);

  List<MediaInfoGroup> buildInfoGroups([String? qualityProfileName]) {
    if (qualityProfileName == null) {
      return _buildLegacyInfoGroups();
    }

    final releaseFacts = _buildReleaseFacts();
    final fileFacts = _buildFileFacts(qualityProfileName);

    return [
      if (fileFacts.isNotEmpty) ...fileFacts,
      if (releaseFacts.isNotEmpty)
        ...releaseFacts.map(
          (fact) => MediaInfoGroup(title: fact.label, child: Text(fact.value)),
        ),
      if (_hasText(studio))
        MediaInfoGroup(title: 'Studio', child: Text(studio!)),
      if (_hasText(certification))
        MediaInfoGroup(title: 'Certification', child: Text(certification!)),
      if (_hasText(originalLanguage))
        MediaInfoGroup(title: 'Language', child: Text(originalLanguage!)),
    ];
  }

  List<MediaInfoGroup> _buildLegacyInfoGroups() {
    final releaseFacts = _buildReleaseFacts();

    return [
      if (_hasText(certification))
        MediaInfoGroup(title: 'Certification', child: Text(certification!)),
      if (_hasText(originalLanguage))
        MediaInfoGroup(
          title: 'Original Language',
          child: Text(originalLanguage!),
        ),
      if (releaseFacts.isNotEmpty)
        MediaInfoGroup(
          title: 'Release Dates',
          child: MediaFactsList(facts: releaseFacts),
        ),
      if (genres.isNotEmpty)
        MediaInfoGroup(
          title: 'Genre',
          child: Wrap(
            children: genres
                .map((genre) => GenreChip(genre: genre))
                .toList(growable: false),
          ),
        ),
      if (_hasText(studio))
        MediaInfoGroup(title: 'Studio', child: Text(studio!)),
    ];
  }

  List<MediaInfoGroup> _buildFileFacts(String? qualityProfileName) => [
    if (isInLibrary)
      MediaInfoGroup(
        title: 'Monitored',
        child: Text(isMonitored ? 'Yes' : 'No'),
      ),
    if (_hasText(qualityProfileName))
      MediaInfoGroup(title: 'Profile', child: Text(qualityProfileName!)),
  ];

  List<MediaFact> _buildReleaseFacts() => [
    if (_hasText(inCinemas))
      MediaFact('In Cinemas', formatMediumDate(inCinemas!)),
    if (_hasText(digitalRelease))
      MediaFact('Digital', formatMediumDate(digitalRelease!)),
    if (_hasText(physicalRelease))
      MediaFact('Physical', formatMediumDate(physicalRelease!)),
  ];

  bool _hasText(String? value) => value != null && value.isNotEmpty;

  factory MovieDetailViewModel.fromMovie(
    RadarrMovie movie, {
    required String baseUrl,
    required String apiKey,
  }) {
    final posterSource = ImageUtils.extractPosterUrl(
      movie.images,
      baseUrl: baseUrl,
      apiKey: apiKey,
    );
    final backdropSource = ImageUtils.extractPosterUrl(
      movie.images,
      baseUrl: baseUrl,
      apiKey: apiKey,
      coverTypes: const ['fanart'],
    );
    final moviePath = movie.path;
    final isInLibrary = movie.id > 0 && moviePath?.isNotEmpty == true;
    // `formatRuntimeMinutes` answers '' for a runtime the service does not
    // have, and the metadata line only drops nulls — so the empty string has
    // to become one here.
    final runtime = formatRuntimeMinutes(movie.runtime);

    return MovieDetailViewModel(
      title: movie.title,
      overview: movie.overview?.trim().isNotEmpty == true
          ? movie.overview!.trim()
          : 'No description available.',
      posterUrl: posterSource.url,
      posterHeaders: posterSource.headers,
      backdropUrl: ImageUtils.safeBackdropUrl(backdropSource),
      status: movie.status,
      hasFile: movie.hasFile,
      isInLibrary: isInLibrary,
      isMonitored: movie.monitored,
      year: movie.year > 0 ? movie.year.toString() : '',
      runtimeStr: runtime.isEmpty ? null : runtime,
      studio: movie.studio,
      genres: movie.genres,
      ratings: movie.ratings,
      path: moviePath,
      filename: movie.hasFile && moviePath != null
          ? moviePath.split(RegExp(r'[\\/]')).last
          : null,
      qualityProfileId: movie.qualityProfileId,
      certification: movie.certification,
      originalLanguage: movie.originalLanguage?['name'] as String?,
      inCinemas: movie.inCinemas,
      digitalRelease: movie.digitalRelease,
      physicalRelease: movie.physicalRelease,
    );
  }
}
