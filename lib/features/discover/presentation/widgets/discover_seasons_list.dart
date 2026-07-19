import 'package:flutter/material.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/discover/domain/models/discover_detail_model.dart';
import 'package:seekarr/features/discover/domain/models/seerr_request.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

class DiscoverSeasonsList extends StatefulWidget {
  final List<TvSeason> seasons;
  final Map<String, dynamic>? mediaInfo;

  const DiscoverSeasonsList({
    super.key,
    required this.seasons,
    required this.mediaInfo,
  });

  @override
  State<DiscoverSeasonsList> createState() => _DiscoverSeasonsListState();
}

class _DiscoverSeasonsListState extends State<DiscoverSeasonsList> {
  int? _selectedSeasonNumber;

  @override
  Widget build(BuildContext context) {
    final orderedSeasons = [...widget.seasons]..sort(_compareSeasons);
    final availabilityBySeason = _availabilityBySeason(widget.mediaInfo);
    final selectedSeason = _selectedSeason(orderedSeasons);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MediaDetailSectionHeader(
          title: 'Seasons',
          accent: ServiceKey.seerr.accent,
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var index = 0; index < orderedSeasons.length; index++) ...[
                _SeasonPill(
                  season: orderedSeasons[index],
                  availability:
                      availabilityBySeason[orderedSeasons[index].seasonNumber],
                  selected:
                      orderedSeasons[index].seasonNumber ==
                      selectedSeason.seasonNumber,
                  onSelected: () => setState(
                    () => _selectedSeasonNumber =
                        orderedSeasons[index].seasonNumber,
                  ),
                ),
                if (index < orderedSeasons.length - 1)
                  const SizedBox(width: AppSpacing.xs),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _SelectedSeasonEpisodes(season: selectedSeason),
      ],
    );
  }

  TvSeason _selectedSeason(List<TvSeason> orderedSeasons) {
    final selectedNumber = _selectedSeasonNumber;
    if (selectedNumber != null) {
      for (final season in orderedSeasons) {
        if (season.seasonNumber == selectedNumber) {
          return season;
        }
      }
    }

    return orderedSeasons.first;
  }

  Map<int, MediaAvailability> _availabilityBySeason(
    Map<String, dynamic>? currentMediaInfo,
  ) {
    final seasonsData = currentMediaInfo?['seasons'];
    if (seasonsData is! List) {
      return const {};
    }

    final results = <int, MediaAvailability>{};

    for (final item in seasonsData) {
      if (item is! Map) {
        continue;
      }

      final seasonNumber = _asInt(item['seasonNumber']);
      if (seasonNumber == null) {
        continue;
      }

      results[seasonNumber] = MediaAvailability.fromCode(item['status']);
    }

    return results;
  }
}

class _SelectedSeasonEpisodes extends StatelessWidget {
  final TvSeason season;

  const _SelectedSeasonEpisodes({required this.season});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final episodes = [...season.episodes]
      ..sort((a, b) => (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0));

    if (episodes.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: AppRadius.borderRadiusSm,
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Text(
          season.episodeCount > 0
              ? '${season.episodeCount} episodes listed for this season.'
              : 'No episode details available for this season.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Column(
      children: [
        for (var index = 0; index < episodes.length; index++) ...[
          _EpisodeRow(episode: episodes[index]),
          if (index < episodes.length - 1)
            const SizedBox(height: AppSpacing.xs),
        ],
      ],
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  final TvEpisodeSummary episode;

  const _EpisodeRow({required this.episode});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final episodeNumber = episode.episodeNumber;
    final title = episode.name?.isNotEmpty == true
        ? episode.name!
        : 'Episode ${episodeNumber ?? '?'}';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusSm,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              episodeNumber?.toString().padLeft(2, '0') ?? '--',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (episode.airDate?.isNotEmpty == true)
            Text(
              episode.airDate!.split('T').first,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _SeasonPill extends StatelessWidget {
  final TvSeason season;
  final MediaAvailability? availability;
  final bool selected;
  final VoidCallback onSelected;

  const _SeasonPill({
    required this.season,
    required this.availability,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final displayName = season.seasonNumber == 0
        ? 'Specials'
        : 'Season ${season.seasonNumber}';

    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(displayName),
          if (availability == MediaAvailability.available) ...[
            const SizedBox(width: AppSpacing.xs),
            Icon(
              Icons.check_circle_rounded,
              size: 14,
              color: colorScheme.primary,
            ),
          ] else if (availability == MediaAvailability.partiallyAvailable) ...[
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.adjust_rounded, size: 14, color: colorScheme.tertiary),
          ],
        ],
      ),
      selected: selected,
      onSelected: (_) => onSelected(),
      visualDensity: VisualDensity.compact,
      labelStyle: theme.textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: selected ? colorScheme.onSecondaryContainer : null,
      ),
    );
  }
}

int _compareSeasons(TvSeason left, TvSeason right) {
  if (left.seasonNumber == 0 && right.seasonNumber != 0) {
    return 1;
  }

  if (left.seasonNumber != 0 && right.seasonNumber == 0) {
    return -1;
  }

  return left.seasonNumber.compareTo(right.seasonNumber);
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
