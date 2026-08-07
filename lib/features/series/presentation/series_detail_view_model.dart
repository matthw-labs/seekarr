import 'package:flutter/material.dart';

import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/series/domain/models/sonarr_season.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';

class SeriesDetailViewModel {
  final String title;
  final String overview;
  final String posterUrl;
  final Map<String, String>? posterHeaders;
  final String? backdropUrl;
  final String status;
  final bool hasFiles;
  final bool isInLibrary;
  final bool isMonitored;
  final int? episodeFileCount;
  final String year;
  final String? runtimeStr;
  final String? network;
  final List<String> genres;
  final List<RatingSource> ratings;
  final String? path;
  final int? qualityProfileId;

  /// Seasons, already narrowed out of Sonarr's raw nested JSON.
  ///
  /// The view model is the layer that owns the conversion: a widget that
  /// receives `List<dynamic>` has to guess at the shape, and two widgets
  /// guessing differently is how the season pill and the season panel came to
  /// read different fields.
  final List<SonarrSeason> seasons;
  final int? seasonCount;
  final int? episodeCount;
  final String? seriesType;
  final String? certification;
  final String? firstAired;
  final String? lastAired;
  final String? originalLanguage;

  const SeriesDetailViewModel({
    required this.title,
    required this.overview,
    required this.posterUrl,
    this.posterHeaders,
    this.backdropUrl,
    required this.status,
    required this.hasFiles,
    required this.isInLibrary,
    required this.isMonitored,
    this.episodeFileCount,
    required this.year,
    this.runtimeStr,
    this.network,
    required this.genres,
    required this.ratings,
    this.path,
    this.qualityProfileId,
    required this.seasons,
    this.seasonCount,
    this.episodeCount,
    this.seriesType,
    this.certification,
    this.firstAired,
    this.lastAired,
    this.originalLanguage,
  });

  String? get episodeSummary {
    final parts = <String>[];

    if (seasonCount != null && seasonCount! > 0) {
      parts.add('$seasonCount ${seasonCount == 1 ? 'Season' : 'Seasons'}');
    }

    if (episodeCount != null && episodeCount! > 0) {
      parts.add('$episodeCount ${episodeCount == 1 ? 'Episode' : 'Episodes'}');
    }

    if (parts.isEmpty) {
      return null;
    }

    return parts.join(' • ');
  }

  List<String> get metadataItems => [
    year,
    if (episodeSummary != null) episodeSummary!,
    if (runtimeStr != null) runtimeStr!,
  ].where((item) => item.isNotEmpty).toList(growable: false);

  List<MediaInfoGroup> buildInfoGroups([String? qualityProfileName]) {
    if (qualityProfileName == null) {
      return _buildLegacyInfoGroups();
    }

    final airDateFacts = _buildAirDateFacts();

    return [
      if (_hasText(status))
        MediaInfoGroup(title: 'Status', child: Text(capitalizeFirst(status))),
      if (episodeCount != null || episodeFileCount != null)
        MediaInfoGroup(
          title: 'Episodes',
          child: Text('${episodeFileCount ?? 0} / ${episodeCount ?? 0}'),
        ),
      if (_hasText(network))
        MediaInfoGroup(title: 'Network', child: Text(network!)),
      if (_hasText(qualityProfileName))
        MediaInfoGroup(title: 'Profile', child: Text(qualityProfileName)),
      if (_hasText(seriesType))
        MediaInfoGroup(
          title: 'Series Type',
          child: Text(capitalizeFirst(seriesType!)),
        ),
      if (_hasText(certification))
        MediaInfoGroup(title: 'Certification', child: Text(certification!)),
      if (airDateFacts.isNotEmpty)
        ...airDateFacts.map(
          (fact) => MediaInfoGroup(title: fact.label, child: Text(fact.value)),
        ),
      if (_hasText(originalLanguage))
        MediaInfoGroup(title: 'Language', child: Text(originalLanguage!)),
    ];
  }

  List<MediaInfoGroup> _buildLegacyInfoGroups() {
    final airDateFacts = _buildAirDateFacts();

    return [
      if (_hasText(seriesType))
        MediaInfoGroup(
          title: 'Series Type',
          child: Text(capitalizeFirst(seriesType!)),
        ),
      if (_hasText(certification))
        MediaInfoGroup(title: 'Certification', child: Text(certification!)),
      if (_hasText(originalLanguage))
        MediaInfoGroup(
          title: 'Original Language',
          child: Text(originalLanguage!),
        ),
      if (airDateFacts.isNotEmpty)
        MediaInfoGroup(
          title: 'Air Dates',
          child: MediaFactsList(facts: airDateFacts),
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
      if (_hasText(network))
        MediaInfoGroup(title: 'Network', child: Text(network!)),
    ];
  }

  List<MediaFact> _buildAirDateFacts() => [
    if (_hasText(firstAired))
      MediaFact('First Aired', formatMediumDate(firstAired!)),
    if (_hasText(lastAired))
      MediaFact('Last Aired', formatMediumDate(lastAired!)),
  ];

  bool _hasText(String? value) => value != null && value.isNotEmpty;

  factory SeriesDetailViewModel.fromSeries(
    SonarrSeries series, {
    required String baseUrl,
    required String apiKey,
  }) {
    final posterSource = ImageUtils.extractPosterUrl(
      series.images,
      baseUrl: baseUrl,
      apiKey: apiKey,
    );
    final backdropSource = ImageUtils.extractPosterUrl(
      series.images,
      baseUrl: baseUrl,
      apiKey: apiKey,
      coverTypes: const ['fanart'],
    );
    final stats = series.statistics;
    final episodeFileCount = (stats?['episodeFileCount'] as num?)?.toInt();
    final seasonCount = (stats?['seasonCount'] as num?)?.toInt();
    final episodeCount = (stats?['episodeCount'] as num?)?.toInt();
    final isInLibrary = series.id > 0 && series.path?.isNotEmpty == true;
    // `formatRuntimeMinutes` answers '' for a runtime the service does not
    // have, and the metadata line only drops nulls — so the empty string has
    // to become one here.
    final runtime = formatRuntimeMinutes(series.runtime);

    return SeriesDetailViewModel(
      title: series.title,
      overview: series.overview?.trim().isNotEmpty == true
          ? series.overview!.trim()
          : 'No description available.',
      posterUrl: posterSource.url,
      posterHeaders: posterSource.headers,
      backdropUrl: ImageUtils.safeBackdropUrl(backdropSource),
      status: series.status,
      hasFiles: (episodeFileCount ?? 0) > 0,
      isInLibrary: isInLibrary,
      isMonitored: series.monitored,
      episodeFileCount: episodeFileCount,
      year: series.year > 0 ? series.year.toString() : '',
      runtimeStr: runtime.isEmpty ? null : runtime,
      network: series.network,
      genres: series.genres,
      ratings: series.ratings,
      path: series.path,
      qualityProfileId: series.qualityProfileId,
      seasons: series.seasonList,
      seasonCount: seasonCount,
      episodeCount: episodeCount,
      seriesType: series.seriesType,
      certification: series.certification,
      firstAired: series.firstAired,
      lastAired: series.lastAired,
      originalLanguage: series.originalLanguage?['name'] as String?,
    );
  }
}
