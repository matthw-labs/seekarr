import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/utils/route_utils.dart';
import 'package:seekarr/features/movies/domain/models/radarr_movie.dart';
import 'package:seekarr/features/series/domain/models/sonarr_series.dart';
import 'package:seekarr/features/shell/presentation/shell_screen.dart';
import 'package:seekarr/features/discover/presentation/discover_screen.dart';
import 'package:seekarr/features/activity/presentation/activity_screen.dart';
import 'package:seekarr/features/movies/presentation/movies_screen.dart';
import 'package:seekarr/features/movies/presentation/movie_detail_screen.dart';
import 'package:seekarr/features/series/presentation/series_screen.dart';
import 'package:seekarr/features/series/presentation/series_detail_screen.dart';
import 'package:seekarr/features/music/presentation/music_screen.dart';
import 'package:seekarr/features/music/presentation/music_detail_screen.dart';
import 'package:seekarr/features/music/domain/models/lidarr_artist.dart';
import 'package:seekarr/features/search/presentation/search_screen.dart';
import 'package:seekarr/features/services/presentation/service_all_screens.dart';
import 'package:seekarr/features/services/presentation/service_dashboard_screen.dart';
import 'package:seekarr/features/services/presentation/services_screen.dart';
import 'package:seekarr/features/discover/presentation/discover_detail_screen.dart';
import 'package:seekarr/features/discover/presentation/discover_see_all_screen.dart';
import 'package:seekarr/features/settings/presentation/settings_appearance_screen.dart';
import 'package:seekarr/features/settings/presentation/settings_home_screen.dart';
import 'package:seekarr/features/settings/presentation/settings_region_screen.dart';
import 'package:seekarr/features/settings/presentation/settings_services_screen.dart';
import 'package:seekarr/features/settings/presentation/service_settings_screen.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/import/presentation/manual_import_browse_screen.dart';
import 'package:seekarr/features/import/presentation/manual_import_folder_screen.dart';
import 'package:seekarr/features/import/presentation/manual_import_match_screen.dart';
import 'package:seekarr/features/import/presentation/manual_import_progress_screen.dart';
import 'package:seekarr/features/import/presentation/manual_import_routes.dart';
import 'package:seekarr/features/onboarding/data/onboarding_provider.dart';
import 'package:seekarr/features/onboarding/presentation/onboarding_screen.dart';
import 'package:seekarr/features/qbittorrent/presentation/qbittorrent_screen.dart';
import 'package:seekarr/features/qbittorrent/presentation/torrent_detail_screen.dart';
import 'package:seekarr/features/qbittorrent/presentation/widgets/add_torrent_button.dart';
import 'package:seekarr/features/bazarr/domain/models/bazarr_models.dart';
import 'package:seekarr/features/bazarr/presentation/bazarr_screen.dart';
import 'package:seekarr/features/bazarr/presentation/bazarr_wanted_screen.dart';
import 'package:seekarr/features/bazarr/presentation/bazarr_library_screen.dart';
import 'package:seekarr/features/bazarr/presentation/bazarr_series_detail_screen.dart';
import 'package:seekarr/features/bazarr/presentation/bazarr_movie_detail_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

const double _serviceDashboardTopPadding = kToolbarHeight;

Page<void> _discoverDetailPage(
  GoRouterState state, {
  required String mediaType,
}) {
  final id = RouteUtils.safeIntParam(state, 'id');
  if (id == null) {
    return RouteUtils.redirectPage(key: state.pageKey, location: '/services');
  }
  final heroTag =
      state.uri.queryParameters['heroTag'] ?? 'discover_${mediaType}_$id';
  final posterUrl = state.uri.queryParameters['posterUrl'] != null
      ? Uri.decodeComponent(state.uri.queryParameters['posterUrl']!)
      : null;
  return RouteUtils.cupertinoPage(
    key: state.pageKey,
    child: DiscoverDetailScreen(
      mediaId: id,
      mediaType: mediaType,
      heroTag: heroTag,
      initialPosterUrl: posterUrl,
    ),
  );
}

Page<void> _libraryDetailPage<T>(
  GoRouterState state, {
  required String heroPrefix,
  required Widget Function(int id, String heroTag, T? initialItem) buildChild,
}) {
  final id = RouteUtils.safeIntParam(state, 'id');
  if (id == null) {
    return RouteUtils.redirectPage(key: state.pageKey, location: '/services');
  }
  final item = RouteUtils.safeExtra<T>(state);
  final heroTag = state.uri.queryParameters['heroTag'] ?? '${heroPrefix}_$id';
  return RouteUtils.cupertinoPage(
    key: state.pageKey,
    child: buildChild(id, heroTag, item),
  );
}

Page<void> _settingsSubpage(GoRouterState state, Widget child) {
  return RouteUtils.cupertinoPage(key: state.pageKey, child: child);
}

Page<void> _manualImportPage(
  GoRouterState state,
  Widget Function(ServiceKey service, int? targetId) buildChild,
) {
  final service = manualImportServiceFromRoute(
    state.uri.queryParameters['service'],
  );
  if (service == null) {
    return RouteUtils.redirectPage(key: state.pageKey, location: '/activity');
  }

  final targetId = int.tryParse(state.uri.queryParameters['targetId'] ?? '');
  return RouteUtils.cupertinoPage(
    key: state.pageKey,
    child: buildChild(service, targetId),
  );
}

GoRoute _discoverRoutes({required String path, String? redirectLocation}) {
  return GoRoute(
    path: path,
    redirect: redirectLocation == null
        ? null
        : (context, state) => _redirectLegacyDiscover(state),
    builder: path.startsWith('/')
        ? (context, state) => const DiscoverScreen()
        : null,
    pageBuilder: path.startsWith('/')
        ? null
        : (context, state) => RouteUtils.cupertinoPage(
            key: state.pageKey,
            child: ServiceDashboardScreen(
              service: ServiceKey.seerr,
              child: const DiscoverScreen(
                showAppBar: false,
                topPadding: _serviceDashboardTopPadding,
              ),
            ),
          ),
    routes: [
      GoRoute(
        path: 'requests',
        builder: (context, state) => const ServiceAllRequestsScreen(),
      ),
      GoRoute(
        path: 'movies/all',
        builder: (context, state) =>
            const DiscoverSeeAllScreen(type: 'movies', title: 'Movies'),
      ),
      GoRoute(
        path: 'tv/all',
        builder: (context, state) =>
            const DiscoverSeeAllScreen(type: 'tv', title: 'TV Series'),
      ),
      GoRoute(
        path: 'trending/all',
        builder: (context, state) =>
            const DiscoverSeeAllScreen(type: 'trending', title: 'Trending'),
      ),
      GoRoute(
        path: 'movie/:id',
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null ? '/services' : null,
        pageBuilder: (context, state) =>
            _discoverDetailPage(state, mediaType: 'movie'),
      ),
      GoRoute(
        path: 'tv/:id',
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null ? '/services' : null,
        pageBuilder: (context, state) =>
            _discoverDetailPage(state, mediaType: 'tv'),
      ),
    ],
  );
}

GoRoute _moviesRoutes({required String path, String? redirectLocation}) {
  return GoRoute(
    path: path,
    redirect: redirectLocation == null
        ? null
        : (context, state) => _redirectLegacyLibrary(
            state,
            legacyBase: '/movies',
            serviceBase: '/services/radarr/movie',
          ),
    builder: path.startsWith('/')
        ? (context, state) => const MoviesScreen()
        : null,
    pageBuilder: path.startsWith('/')
        ? null
        : (context, state) => RouteUtils.cupertinoPage(
            key: state.pageKey,
            child: ServiceDashboardScreen(
              service: ServiceKey.radarr,
              child: const MoviesScreen(
                showAppBar: false,
                topPadding: _serviceDashboardTopPadding,
              ),
            ),
          ),
    routes: [
      GoRoute(
        path: 'media',
        redirect: (context, state) =>
            _preserveQuery(state.uri, '/services/radarr'),
      ),
      GoRoute(
        path: path.startsWith('/') ? ':id' : 'movie/:id',
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null ? '/services' : null,
        pageBuilder: (context, state) => _libraryDetailPage<RadarrMovie>(
          state,
          heroPrefix: 'movie',
          buildChild: (id, heroTag, movie) => MovieDetailScreen(
            movieId: id,
            heroTag: heroTag,
            initialMovie: movie,
          ),
        ),
      ),
    ],
  );
}

GoRoute _seriesRoutes({required String path, String? redirectLocation}) {
  return GoRoute(
    path: path,
    redirect: redirectLocation == null
        ? null
        : (context, state) => _redirectLegacyLibrary(
            state,
            legacyBase: '/series',
            serviceBase: '/services/sonarr/series',
          ),
    builder: path.startsWith('/')
        ? (context, state) => const SeriesScreen()
        : null,
    pageBuilder: path.startsWith('/')
        ? null
        : (context, state) => RouteUtils.cupertinoPage(
            key: state.pageKey,
            child: ServiceDashboardScreen(
              service: ServiceKey.sonarr,
              child: const SeriesScreen(
                showAppBar: false,
                topPadding: _serviceDashboardTopPadding,
              ),
            ),
          ),
    routes: [
      GoRoute(
        path: 'media',
        redirect: (context, state) =>
            _preserveQuery(state.uri, '/services/sonarr'),
      ),
      GoRoute(
        path: path.startsWith('/') ? ':id' : 'series/:id',
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null ? '/services' : null,
        pageBuilder: (context, state) => _libraryDetailPage<SonarrSeries>(
          state,
          heroPrefix: 'series',
          buildChild: (id, heroTag, series) => SeriesDetailScreen(
            seriesId: id,
            heroTag: heroTag,
            initialSeries: series,
          ),
        ),
      ),
    ],
  );
}

GoRoute _musicRoutes({required String path, String? redirectLocation}) {
  return GoRoute(
    path: path,
    redirect: redirectLocation == null
        ? null
        : (context, state) => _redirectLegacyLibrary(
            state,
            legacyBase: '/music',
            serviceBase: '/services/lidarr/artist',
          ),
    builder: path.startsWith('/')
        ? (context, state) => const MusicScreen()
        : null,
    pageBuilder: path.startsWith('/')
        ? null
        : (context, state) => RouteUtils.cupertinoPage(
            key: state.pageKey,
            child: ServiceDashboardScreen(
              service: ServiceKey.lidarr,
              child: const MusicScreen(
                showAppBar: false,
                topPadding: _serviceDashboardTopPadding,
              ),
            ),
          ),
    routes: [
      GoRoute(
        path: 'media',
        redirect: (context, state) =>
            _preserveQuery(state.uri, '/services/lidarr'),
      ),
      GoRoute(
        path: path.startsWith('/') ? ':id' : 'artist/:id',
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null ? '/services' : null,
        pageBuilder: (context, state) => _libraryDetailPage<LidarrArtist>(
          state,
          heroPrefix: 'artist',
          buildChild: (id, heroTag, artist) => MusicDetailScreen(
            artistId: id,
            heroTag: heroTag,
            initialArtist: artist,
          ),
        ),
      ),
    ],
  );
}

GoRoute _qbittorrentRoutes({required String path}) {
  return GoRoute(
    path: path,
    pageBuilder: (context, state) => RouteUtils.cupertinoPage(
      key: state.pageKey,
      child: ServiceDashboardScreen(
        service: ServiceKey.qbittorrent,
        trailingAction: const AddTorrentButton(),
        child: const QbittorrentScreen(
          showAppBar: false,
          topPadding: _serviceDashboardTopPadding,
        ),
      ),
    ),
    routes: [
      GoRoute(
        path: 'torrent/:hash',
        pageBuilder: (context, state) {
          final hash = state.pathParameters['hash'] ?? '';
          return RouteUtils.cupertinoPage(
            key: state.pageKey,
            child: TorrentDetailScreen(hash: hash),
          );
        },
      ),
    ],
  );
}

GoRoute _bazarrRoutes({required String path}) {
  return GoRoute(
    path: path,
    pageBuilder: (context, state) => RouteUtils.cupertinoPage(
      key: state.pageKey,
      child: ServiceDashboardScreen(
        service: ServiceKey.bazarr,
        child: const BazarrScreen(
          showAppBar: false,
          topPadding: _serviceDashboardTopPadding,
        ),
      ),
    ),
    routes: [
      GoRoute(
        path: 'wanted',
        pageBuilder: (context, state) => RouteUtils.cupertinoPage(
          key: state.pageKey,
          child: const BazarrWantedScreen(),
        ),
      ),
      GoRoute(
        path: 'library',
        pageBuilder: (context, state) => RouteUtils.cupertinoPage(
          key: state.pageKey,
          child: const BazarrLibraryScreen(),
        ),
      ),
      GoRoute(
        path: 'series/:id',
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null ? '/services' : null,
        pageBuilder: (context, state) {
          final id = RouteUtils.safeIntParam(state, 'id')!;
          final wanted = RouteUtils.safeExtra<BazarrWantedItem>(state);
          return RouteUtils.cupertinoPage(
            key: state.pageKey,
            child: BazarrSeriesDetailScreen(
              sonarrSeriesId: id,
              heroTag: state.uri.queryParameters['heroTag'],
              initialWanted: wanted,
            ),
          );
        },
      ),
      GoRoute(
        path: 'movie/:id',
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null ? '/services' : null,
        pageBuilder: (context, state) {
          final id = RouteUtils.safeIntParam(state, 'id')!;
          final wanted = RouteUtils.safeExtra<BazarrWantedItem>(state);
          return RouteUtils.cupertinoPage(
            key: state.pageKey,
            child: BazarrMovieDetailScreen(
              radarrId: id,
              heroTag: state.uri.queryParameters['heroTag'],
              initialWanted: wanted,
            ),
          );
        },
      ),
    ],
  );
}

String? _redirectLegacyDiscover(GoRouterState state) {
  final path = state.uri.path;
  if (path == '/discover') return '/services';

  const legacyBase = '/discover/';
  if (!path.startsWith(legacyBase)) return null;

  final suffix = path.substring(legacyBase.length);
  if (suffix == 'movies/all' ||
      suffix == 'tv/all' ||
      suffix == 'trending/all' ||
      suffix.startsWith('movie/') ||
      suffix.startsWith('tv/')) {
    return _preserveQuery(state.uri, '/services/seerr/$suffix');
  }

  return '/services';
}

String? _redirectLegacyLibrary(
  GoRouterState state, {
  required String legacyBase,
  required String serviceBase,
}) {
  final path = state.uri.path;
  if (path == legacyBase) return '/services';

  final prefix = '$legacyBase/';
  if (!path.startsWith(prefix)) return null;

  final id = path.substring(prefix.length);
  if (id.isEmpty || id.contains('/')) return '/services';
  return _preserveQuery(state.uri, '$serviceBase/$id');
}

String _preserveQuery(Uri source, String path) {
  final query = source.hasQuery ? '?${source.query}' : '';
  return '$path$query';
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(routerRefreshNotifierProvider);
  final onboardingDone = ref.read(onboardingCompletedProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    refreshListenable: notifier,
    initialLocation: onboardingDone ? '/services' : '/onboarding',
    redirect: (context, state) {
      final done = ref.read(onboardingCompletedProvider);
      final isOnboarding = state.matchedLocation == '/onboarding';
      if (!done && !isOnboarding) return '/onboarding';
      if (done && isOnboarding) return '/services';
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) {
          return ShellScreen(child: child);
        },
        routes: [
          GoRoute(
            path: '/services',
            builder: (context, state) => const ServicesScreen(),
            routes: [
              _discoverRoutes(path: 'seerr'),
              _moviesRoutes(path: 'radarr'),
              _seriesRoutes(path: 'sonarr'),
              _musicRoutes(path: 'lidarr'),
              _qbittorrentRoutes(path: 'qbittorrent'),
              _bazarrRoutes(path: 'bazarr'),
            ],
          ),
          GoRoute(
            path: '/activity',
            builder: (context, state) => const GlobalActivityScreen(),
          ),
          GoRoute(
            path: manualImportBrowsePath,
            pageBuilder: (context, state) => _manualImportPage(
              state,
              (service, targetId) => ManualImportBrowseScreen(
                service: service,
                targetId: targetId,
              ),
            ),
          ),
          GoRoute(
            path: manualImportFolderPath,
            pageBuilder: (context, state) => _manualImportPage(
              state,
              (service, targetId) => ManualImportFolderScreen(
                service: service,
                targetId: targetId,
              ),
            ),
          ),
          GoRoute(
            path: manualImportMatchPath,
            pageBuilder: (context, state) => _manualImportPage(
              state,
              (service, targetId) =>
                  ManualImportMatchScreen(service: service, targetId: targetId),
            ),
          ),
          GoRoute(
            path: manualImportProgressPath,
            pageBuilder: (context, state) => _manualImportPage(
              state,
              (service, targetId) =>
                  ManualImportProgressScreen(service: service),
            ),
          ),
          GoRoute(
            path: '/search',
            builder: (context, state) => const SearchScreen(),
          ),
          _discoverRoutes(path: '/discover', redirectLocation: '/services'),
          _moviesRoutes(path: '/movies', redirectLocation: '/services'),
          _seriesRoutes(path: '/series', redirectLocation: '/services'),
          _musicRoutes(path: '/music', redirectLocation: '/services'),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsHomeScreen(),
            routes: [
              GoRoute(
                path: 'appearance',
                pageBuilder: (context, state) =>
                    _settingsSubpage(state, const SettingsAppearanceScreen()),
              ),
              GoRoute(
                path: 'services',
                pageBuilder: (context, state) =>
                    _settingsSubpage(state, const SettingsServicesScreen()),
              ),
              GoRoute(
                path: 'region',
                pageBuilder: (context, state) =>
                    _settingsSubpage(state, const SettingsRegionScreen()),
              ),
              GoRoute(
                path: 'service/:service',
                pageBuilder: (context, state) {
                  final serviceParam = state.pathParameters['service'];
                  // Accept 'jellyseerr' as a legacy alias for 'seerr'.
                  final normalizedParam = serviceParam == 'jellyseerr'
                      ? 'seerr'
                      : serviceParam;
                  final service = ServiceKey.values.firstWhere(
                    (s) => s.routeParam == normalizedParam,
                    orElse: () => ServiceKey.seerr,
                  );
                  return _settingsSubpage(
                    state,
                    ServiceSettingsScreen(service: service),
                  );
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/activity/:type',
        builder: (context, state) {
          final typeStr = state.pathParameters['type']!;
          final type = ServiceType.values.firstWhere(
            (e) => e.name == typeStr,
            orElse: () => ServiceType.movies,
          );
          return ActivityScreen(serviceType: type);
        },
      ),
    ],
  );
});
