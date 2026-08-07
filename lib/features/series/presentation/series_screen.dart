import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/series/domain/sonarr_status.dart';
import 'package:cupola/features/series/presentation/series_provider.dart';
import 'package:cupola/features/series/presentation/series_search_provider.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

class SeriesScreen extends ConsumerWidget {
  final bool showAppBar;
  final double topPadding;

  const SeriesScreen({super.key, this.showAppBar = true, this.topPadding = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref
        .watch(sonarrQueueSnapshotProvider)
        .maybeWhen(data: (snapshot) => snapshot, orElse: () => null);

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
      statusExtractor: (series) =>
          sonarrSeriesStatus(series, queueEntry: queue?.entryFor(series.id)),
      onRefresh: (ref) {
        ref.invalidate(sonarrQueueSnapshotProvider);
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
