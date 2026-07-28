import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/providers/navigation_refresh_provider.dart';
import 'package:seekarr/core/utils/service_routes.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/movies/domain/models/radarr_movie.dart';
import 'package:seekarr/features/movies/domain/radarr_status.dart';
import 'package:seekarr/features/movies/presentation/movies_provider.dart';
import 'package:seekarr/features/movies/presentation/movies_search_provider.dart';
import 'package:seekarr/features/services/presentation/service_kpi_provider.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

class MoviesScreen extends ConsumerWidget {
  final bool showAppBar;
  final double topPadding;

  const MoviesScreen({super.key, this.showAppBar = true, this.topPadding = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref
        .watch(radarrQueueSnapshotProvider)
        .maybeWhen(data: (snapshot) => snapshot, orElse: () => null);

    return MediaBrowseScaffold<RadarrMovie>(
      title: 'Movies',
      searchHint: 'Search movies...',
      activityRoute: '/activity/movies',
      navigationSection: NavigationSection.services,
      serviceName: 'Radarr',
      accentColor: ServiceKey.radarr.accent,
      heroTagPrefix: 'movie',
      searchHeroTagPrefix: 'movie_search',
      libraryProvider: moviesProvider,
      searchQueryProvider: moviesSearchQueryProvider,
      searchResultsProvider: moviesSearchResultsProvider,
      titleExtractor: (movie) => movie.title,
      subtitleExtractor: (movie) => movie.year > 0 ? '${movie.year}' : '',
      sortTitleExtractor: (movie) => movie.sortTitle,
      imagesExtractor: (movie) => movie.images,
      idExtractor: (movie) => movie.id,
      statusExtractor: (movie) =>
          radarrMovieStatus(movie, queueEntry: queue?.entryFor(movie.id)),
      onRefresh: (ref) {
        ref.invalidate(radarrQueueSnapshotProvider);
      },
      settingsSelector: (settings) =>
          (settings.radarrUrl, settings.radarrApiKey),
      onItemTap: (context, movie, heroTag) {
        context.push(
          ServiceRoutes.radarrMovie(movie.id, heroTag: heroTag),
          extra: movie,
        );
      },
      showAppBar: showAppBar,
      topPadding: topPadding,
      kpiPeek: ServiceKpiPeek(
        kpis: ref.watch(serviceKpiProvider(ServiceKey.radarr)),
        accent: ServiceKey.radarr.accent,
      ),
    );
  }
}
