import 'package:flutter/material.dart';

import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/discover/domain/models/discover_detail_model.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

class DiscoverReleaseInfoCard extends StatelessWidget {
  final List<MediaFact> releaseEntries;
  final String? emptyMessage;
  final List<String> studios;
  final List<String> directors;
  final List<String> writers;
  final String networks;

  const DiscoverReleaseInfoCard._({
    required this.releaseEntries,
    this.emptyMessage,
    this.studios = const [],
    this.directors = const [],
    this.writers = const [],
    this.networks = '',
  });

  factory DiscoverReleaseInfoCard.movie({
    required List<MovieRelease> releases,
    required String region,
    List<String> studios = const [],
    List<String> directors = const [],
    List<String> writers = const [],
  }) {
    final theatrical = _releaseByType(releases, 3);
    final digital = _releaseByType(releases, 4);
    final physical = _releaseByType(releases, 5);
    final entries = <MediaFact>[];

    _addDatedFactEntry(entries, 'Theatrical', theatrical?.releaseDate);
    _addDatedFactEntry(entries, 'Digital', digital?.releaseDate);
    _addDatedFactEntry(entries, 'Physical', physical?.releaseDate);

    return DiscoverReleaseInfoCard._(
      releaseEntries: entries,
      emptyMessage: entries.isEmpty
          ? 'Release info is not available in your region ($region).'
          : null,
      studios: studios,
      directors: directors,
      writers: writers,
    );
  }

  factory DiscoverReleaseInfoCard.tv({
    String? firstAirDate,
    String? lastAirDate,
    TvEpisodeSummary? nextEpisodeToAir,
    List<String> studios = const [],
    List<String> directors = const [],
    List<String> writers = const [],
    String networks = '',
  }) {
    final entries = <MediaFact>[];

    _addDatedFactEntry(entries, 'First Aired', firstAirDate);
    _addDatedFactEntry(entries, 'Last Aired', lastAirDate);
    if (nextEpisodeToAir != null &&
        (nextEpisodeToAir.airDate?.isNotEmpty ?? false)) {
      final parts = <String>[];
      if (nextEpisodeToAir.seasonNumber != null &&
          nextEpisodeToAir.episodeNumber != null) {
        parts.add(
          'S${nextEpisodeToAir.seasonNumber}E${nextEpisodeToAir.episodeNumber}',
        );
      }
      if ((nextEpisodeToAir.name?.isNotEmpty ?? false)) {
        parts.add(nextEpisodeToAir.name!);
      }
      parts.add(_formatDate(nextEpisodeToAir.airDate!));

      entries.add(MediaFact('Next Episode', parts.join(' • ')));
    }

    return DiscoverReleaseInfoCard._(
      releaseEntries: entries,
      emptyMessage: entries.isEmpty ? 'No release info available.' : null,
      studios: studios,
      directors: directors,
      writers: writers,
      networks: networks,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sectionChildren = <MediaInfoGroup>[
      MediaInfoGroup(
        title: 'Release Dates',
        child: emptyMessage != null
            ? Text(
                emptyMessage!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            : MediaFactsList(facts: releaseEntries),
      ),
      if (studios.isNotEmpty)
        MediaInfoGroup(
          title: 'Studios',
          child: Text(studios.join(', '), style: theme.textTheme.bodyMedium),
        ),
      if (networks.isNotEmpty)
        MediaInfoGroup(
          title: 'Networks',
          child: Text(networks, style: theme.textTheme.bodyMedium),
        ),
      if (directors.isNotEmpty || writers.isNotEmpty)
        MediaInfoGroup(
          title: 'Crew',
          child: MediaFactsList(
            facts: [
              if (directors.isNotEmpty)
                MediaFact('Director', directors.join(', ')),
              if (writers.isNotEmpty) MediaFact('Writer', writers.join(', ')),
            ],
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MediaDetailSectionHeader(
          title: 'Details',
          accent: ServiceKey.seerr.accent,
        ),
        MediaInfoCard(groups: sectionChildren),
      ],
    );
  }
}

void _addDatedFactEntry(List<MediaFact> entries, String label, String? value) {
  if (value == null || value.isEmpty) {
    return;
  }

  entries.add(MediaFact(label, _formatDate(value)));
}

MovieRelease? _releaseByType(List<MovieRelease> releases, int type) {
  for (final release in releases) {
    if (release.type == type && release.releaseDate.isNotEmpty) {
      return release;
    }
  }

  return null;
}

String _formatDate(String value) {
  if (value.isEmpty) {
    return '';
  }

  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    return value.split('T').first;
  }

  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
}
