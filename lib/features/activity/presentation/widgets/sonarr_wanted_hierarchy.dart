import 'package:flutter/material.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/media_search_popup_menu.dart';
import 'package:seekarr/features/activity/presentation/activity_screen.dart';
import 'package:seekarr/features/activity/presentation/widgets/activity_formatters.dart';
import 'package:seekarr/features/activity/presentation/widgets/activity_tab_helpers.dart';
import 'package:seekarr/features/activity/presentation/widgets/detail_sheets.dart';
import 'package:seekarr/features/series/data/sonarr_service.dart';

class SonarrWantedHierarchy extends StatelessWidget {
  final List<dynamic> items;
  final SonarrService service;
  final bool isCutoff;

  const SonarrWantedHierarchy({
    super.key,
    required this.items,
    required this.service,
    this.isCutoff = false,
  });

  @override
  Widget build(BuildContext context) {
    final grouped = _groupEpisodesBySeriesAndSeason(items);

    final sortedSeries = grouped.keys.toList()..sort();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        children: sortedSeries
            .map((seriesTitle) {
              final seasons = grouped[seriesTitle]!;
              final totalEpisodes = seasons.values.fold<int>(
                0,
                (sum, entries) => sum + entries.length,
              );

              return _SeriesExpansionTile(
                seriesTitle: seriesTitle,
                seasons: seasons,
                totalEpisodes: totalEpisodes,
                service: service,
                isCutoff: isCutoff,
                initiallyExpanded: sortedSeries.length == 1,
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

Map<String, Map<int, List<Map<String, dynamic>>>>
_groupEpisodesBySeriesAndSeason(List<dynamic> items) {
  final grouped = <String, Map<int, List<Map<String, dynamic>>>>{};

  for (final item in items.whereType<Map<String, dynamic>>()) {
    final seriesTitle =
        stringOrNull(
          asActivityMap(item['series'])?['title'] ?? item['seriesTitle'],
        ) ??
        'Unknown Series';
    final seasonNumber = intOrNull(item['seasonNumber']) ?? 0;

    grouped
        .putIfAbsent(seriesTitle, () => <int, List<Map<String, dynamic>>>{})
        .putIfAbsent(seasonNumber, () => <Map<String, dynamic>>[])
        .add(item);
  }

  return grouped;
}

class _SeriesExpansionTile extends StatelessWidget {
  final String seriesTitle;
  final Map<int, List<Map<String, dynamic>>> seasons;
  final int totalEpisodes;
  final SonarrService service;
  final bool isCutoff;
  final bool initiallyExpanded;

  const _SeriesExpansionTile({
    required this.seriesTitle,
    required this.seasons,
    required this.totalEpisodes,
    required this.service,
    required this.isCutoff,
    required this.initiallyExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;
    final sortedSeasons = seasons.keys.toList()..sort();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard.outlined(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          leading: Icon(Icons.tv_rounded, color: colorScheme.tertiary),
          title: Text(
            seriesTitle,
            style: textTheme.titleMedium?.weight(FontWeight.w700),
          ),
          subtitle: Text(
            '$totalEpisodes episode${totalEpisodes == 1 ? '' : 's'}',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          children: sortedSeasons
              .map(
                (seasonNumber) => _SeasonExpansionTile(
                  seasonNumber: seasonNumber,
                  episodes: seasons[seasonNumber]!,
                  service: service,
                  isCutoff: isCutoff,
                  initiallyExpanded: sortedSeasons.length == 1,
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _SeasonExpansionTile extends StatelessWidget {
  final int seasonNumber;
  final List<Map<String, dynamic>> episodes;
  final SonarrService service;
  final bool isCutoff;
  final bool initiallyExpanded;

  const _SeasonExpansionTile({
    required this.seasonNumber,
    required this.episodes,
    required this.service,
    required this.isCutoff,
    required this.initiallyExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;
    final seasonEpisodes = [...episodes]
      ..sort(
        (a, b) => (intOrNull(a['episodeNumber']) ?? 0).compareTo(
          intOrNull(b['episodeNumber']) ?? 0,
        ),
      );

    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      tilePadding: const EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.md,
      ),
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: colorScheme.tertiaryContainer,
        child: Text(
          '$seasonNumber',
          style: textTheme.labelSmall
              ?.weight(FontWeight.w700)
              .copyWith(color: colorScheme.onTertiaryContainer),
        ),
      ),
      title: Text(
        'Season $seasonNumber',
        style: textTheme.bodyLarge?.weight(FontWeight.w600),
      ),
      subtitle: Text(
        '${seasonEpisodes.length} episode${seasonEpisodes.length == 1 ? '' : 's'}',
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      children: seasonEpisodes
          .map(
            (episode) => _EpisodeListTile(
              episode: episode,
              service: service,
              isCutoff: isCutoff,
            ),
          )
          .toList(growable: false),
    );
  }
}

class _EpisodeListTile extends StatelessWidget {
  final Map<String, dynamic> episode;
  final SonarrService service;
  final bool isCutoff;

  const _EpisodeListTile({
    required this.episode,
    required this.service,
    required this.isCutoff,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;
    final episodeNumber = intOrNull(episode['episodeNumber']) ?? 0;
    final episodeTitle = stringOrNull(episode['title']) ?? 'Unknown Episode';
    final isMonitored = episode['monitored'] != false;
    final episodeId = extractWantedItemId(ServiceType.series, episode);
    final title =
        'E${episodeNumber.toString().padLeft(2, '0')} · $episodeTitle';
    final subtitle = joinActivityParts([
      formatRelativeActivityDate(stringOrNull(episode['airDateUtc'])),
      if (!isMonitored) 'Unmonitored',
      if (isCutoff) formatCutoffSize(episode, ServiceType.series),
    ]);

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(
        left: AppSpacing.xxxl,
        right: AppSpacing.lg,
      ),
      title: Text(title, style: textTheme.bodyMedium?.weight(FontWeight.w600)),
      subtitle: Text(
        subtitle,
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: episodeId == null
          ? null
          : MediaSearchPopupMenu(
              iconSize: 18,
              onAutoSearch: () {
                runWantedAutoSearch(
                  context,
                  service,
                  ServiceType.series,
                  episode,
                );
              },
              onInteractiveSearch: () {
                showWantedInteractiveSearch(
                  context,
                  service,
                  ServiceType.series,
                  episode,
                  title: title,
                );
              },
            ),
      onTap: () =>
          DetailSheets.showWantedDetail(context, episode, ServiceType.series),
    );
  }
}
