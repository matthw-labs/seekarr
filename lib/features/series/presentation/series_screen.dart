import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/providers/navigation_refresh_provider.dart';
import 'package:seekarr/core/utils/service_routes.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/series/domain/models/sonarr_series.dart';
import 'package:seekarr/features/series/presentation/series_provider.dart';
import 'package:seekarr/features/series/presentation/series_search_provider.dart';
import 'package:seekarr/features/services/presentation/service_kpi_provider.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

class SeriesScreen extends ConsumerWidget {
  final bool showAppBar;
  final double topPadding;

  const SeriesScreen({super.key, this.showAppBar = true, this.topPadding = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queuedSeriesIds = ref
        .watch(sonarrQueuedSeriesIdsProvider)
        .maybeWhen(data: (ids) => ids, orElse: () => const <int>{});

    return MediaBrowseScaffold<SonarrSeries>(
      title: 'TV Series',
      searchHint: 'Search TV series...',
      activityRoute: '/activity/series',
      navigationSection: NavigationSection.services,
      serviceName: 'Sonarr',
      accentColor: ServiceKey.sonarr.accent,
      heroTagPrefix: 'series',
      searchHeroTagPrefix: 'series_search',
      libraryProvider: seriesProvider,
      searchQueryProvider: seriesSearchQueryProvider,
      searchResultsProvider: seriesSearchResultsProvider,
      titleExtractor: (series) => series.title,
      subtitleExtractor: (series) => series.year > 0 ? '${series.year}' : '',
      sortTitleExtractor: (series) => series.sortTitle,
      imagesExtractor: (series) => series.images,
      idExtractor: (series) => series.id,
      statusExtractor: (series) {
        final stats = series.statistics;
        final episodeFileCount =
            (stats?['episodeFileCount'] as num?)?.toInt() ?? 0;
        final episodeCount = (stats?['episodeCount'] as num?)?.toInt() ?? 0;
        return MediaAvailabilityInfo(
          hasFile: episodeFileCount > 0,
          status: series.status,
          fileCount: episodeFileCount,
          totalCount: episodeCount,
        );
      },
      browseStatusExtractor: (series) =>
          queuedSeriesIds.contains(series.id) ? MediaStatus.queued : null,
      onRefresh: (ref) {
        ref.invalidate(sonarrQueuedSeriesIdsProvider);
      },
      settingsSelector: (settings) =>
          (settings.sonarrUrl, settings.sonarrApiKey),
      onItemTap: (context, series, heroTag) {
        context.push(
          ServiceRoutes.sonarrSeries(series.id, heroTag: heroTag),
          extra: series,
        );
      },
      showAppBar: showAppBar,
      topPadding: topPadding,
      kpiPeek: ServiceKpiPeek(
        kpis: ref.watch(serviceKpiProvider(ServiceKey.sonarr)),
        accent: ServiceKey.sonarr.accent,
      ),
    );
  }
}
