import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

import 'package:seekarr/core/models/media_preview.dart';
import 'package:seekarr/features/bazarr/data/bazarr_service.dart';
import 'package:seekarr/features/bazarr/presentation/bazarr_provider.dart';
import 'package:seekarr/core/utils/image_utils.dart';
import 'package:seekarr/core/utils/service_routes.dart';
import 'package:seekarr/features/discover/data/seerr_service.dart';
import 'package:seekarr/features/movies/data/radarr_service.dart';
import 'package:seekarr/features/movies/domain/models/radarr_movie.dart';
import 'package:seekarr/features/music/data/lidarr_service.dart';
import 'package:seekarr/features/music/domain/models/lidarr_artist.dart';
import 'package:seekarr/features/search/domain/global_search_result.dart';
import 'package:seekarr/features/series/data/sonarr_service.dart';
import 'package:seekarr/features/series/domain/models/sonarr_series.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';

final globalSearchQueryProvider = StateProvider<String>((ref) => '');

final globalSearchResultsProvider = FutureProvider.autoDispose((ref) async {
  final query = ref.watch(globalSearchQueryProvider).trim();
  final settings = ref.watch(currentSettingsProvider);
  if (query.isEmpty) return const <GlobalSearchServiceResults>[];

  return Future.wait([
    _loadSeerrResults(ref, query),
    _loadRadarrResults(ref, query, settings),
    _loadSonarrResults(ref, query, settings),
    _loadLidarrResults(ref, query, settings),
    _loadBazarrResults(ref, query),
  ]);
});

Future<GlobalSearchServiceResults> _loadSeerrResults(
  Ref ref,
  String query,
) async {
  return _loadServiceResults(
    service: ServiceKey.seerr,
    loadItems: () => ref.read(seerrServiceProvider).search(query),
    toResult: _seerrResult,
  );
}

Future<GlobalSearchServiceResults> _loadRadarrResults(
  Ref ref,
  String query,
  SettingsModel settings,
) async {
  return _loadServiceResults(
    service: ServiceKey.radarr,
    loadItems: () => ref.read(radarrServiceProvider).lookupMovies(query),
    toResult: (item) => _radarrResult(item, settings),
  );
}

Future<GlobalSearchServiceResults> _loadSonarrResults(
  Ref ref,
  String query,
  SettingsModel settings,
) async {
  return _loadServiceResults(
    service: ServiceKey.sonarr,
    loadItems: () => ref.read(sonarrServiceProvider).lookupSeries(query),
    toResult: (item) => _sonarrResult(item, settings),
  );
}

Future<GlobalSearchServiceResults> _loadLidarrResults(
  Ref ref,
  String query,
  SettingsModel settings,
) async {
  return _loadServiceResults(
    service: ServiceKey.lidarr,
    loadItems: () => ref.read(lidarrServiceProvider).lookupArtists(query),
    toResult: (item) => _lidarrResult(item, settings),
  );
}

Future<GlobalSearchServiceResults> _loadBazarrResults(
  Ref ref,
  String query,
) async {
  return _loadServiceResults(
    service: ServiceKey.bazarr,
    loadItems: () => ref.read(bazarrServiceProvider).searchLibrary(query),
    toResult: _bazarrResult,
  );
}

Future<GlobalSearchServiceResults> _loadServiceResults<T>({
  required ServiceKey service,
  required Future<List<T>> Function() loadItems,
  required GlobalSearchResult Function(T item) toResult,
}) async {
  try {
    final items = await loadItems();
    return GlobalSearchServiceResults(
      service: service,
      results: items.map(toResult).toList(growable: false),
    );
  } catch (error) {
    return GlobalSearchServiceResults(
      service: service,
      results: const [],
      error: error,
    );
  }
}

/// Tag shared by a result's poster and the detail page it flies into.
///
/// [kind] discriminates within a service, because Bazarr and Seerr can each
/// return a movie and a series carrying the same id — two Heroes with one tag
/// on the same screen throws.
String _heroTag(ServiceKey service, String kind, int id) =>
    'search_${service.routeParam}_${kind}_$id';

GlobalSearchResult _seerrResult(MediaPreview item) {
  final type = item.mediaType == 'tv' ? 'Series' : 'Movie';
  final year = item.year;
  final imageUrl = ImageUtils.buildTmdbPosterUrl(item.posterPath);
  final heroTag = _heroTag(ServiceKey.seerr, item.mediaType, item.id);
  return GlobalSearchResult(
    service: ServiceKey.seerr,
    id: item.id,
    title: item.title,
    subtitle: [type, year].where((part) => part.isNotEmpty).join(' · '),
    imageUrl: imageUrl,
    imageHeaders: null,
    tags: [type, if (year.isNotEmpty) year],
    heroTag: heroTag,
    // Seerr has no `routeExtra` to preload from, so the poster travels in the
    // URL: the detail page paints real art during its lookup instead of
    // landing the flight on an empty gradient.
    route: ServiceRoutes.seerrDetail(
      mediaType: item.mediaType,
      id: item.id,
      heroTag: heroTag,
      posterUrl: imageUrl,
    ),
  );
}

GlobalSearchResult _radarrResult(RadarrMovie item, SettingsModel settings) {
  final image = ImageUtils.extractPosterUrl(
    item.images,
    baseUrl: settings.radarrUrl,
    apiKey: settings.radarrApiKey,
  );
  final heroTag = _heroTag(ServiceKey.radarr, 'movie', item.id);
  return GlobalSearchResult(
    service: ServiceKey.radarr,
    id: item.id,
    title: item.title,
    subtitle: [
      if (item.year > 0) item.year.toString(),
      item.hasFile ? 'Available' : 'Missing',
    ].join(' · '),
    imageUrl: image.url,
    imageHeaders: image.headers,
    tags: ['Movie', item.hasFile ? 'Available' : 'Missing'],
    heroTag: heroTag,
    route: ServiceRoutes.radarrMovie(item.id, heroTag: heroTag),
    routeExtra: item,
  );
}

GlobalSearchResult _sonarrResult(SonarrSeries item, SettingsModel settings) {
  final image = ImageUtils.extractPosterUrl(
    item.images,
    baseUrl: settings.sonarrUrl,
    apiKey: settings.sonarrApiKey,
  );
  final heroTag = _heroTag(ServiceKey.sonarr, 'series', item.id);
  return GlobalSearchResult(
    service: ServiceKey.sonarr,
    id: item.id,
    title: item.title,
    subtitle: [
      if (item.year > 0) item.year.toString(),
      item.status,
    ].join(' · '),
    imageUrl: image.url,
    imageHeaders: image.headers,
    tags: ['Series', item.status],
    heroTag: heroTag,
    route: ServiceRoutes.sonarrSeries(item.id, heroTag: heroTag),
    routeExtra: item,
  );
}

GlobalSearchResult _bazarrResult(BazarrSearchHit item) {
  final type = item.isMovie ? 'Movie' : 'Series';
  final kind = item.isMovie ? 'movie' : 'series';
  final heroTag = _heroTag(ServiceKey.bazarr, kind, item.id);
  return GlobalSearchResult(
    service: ServiceKey.bazarr,
    id: item.id,
    title: item.title,
    subtitle: 'Subtitles · $type',
    // Bazarr's API carries no artwork, so this row does not fly (see
    // `canFlyPoster`); the tag still travels for the day it does.
    imageUrl: '',
    imageHeaders: null,
    tags: ['Subtitles', type],
    heroTag: heroTag,
    route: item.isMovie
        ? ServiceRoutes.bazarrMovie(item.id, heroTag: heroTag)
        : ServiceRoutes.bazarrSeries(item.id, heroTag: heroTag),
  );
}

GlobalSearchResult _lidarrResult(LidarrArtist item, SettingsModel settings) {
  final image = ImageUtils.extractPosterUrl(
    item.images,
    baseUrl: settings.lidarrUrl,
    apiKey: settings.lidarrApiKey,
    coverTypes: const ['poster', 'fanart', 'banner'],
  );
  final albumLabel = item.albumCount == 1
      ? '1 album'
      : '${item.albumCount} albums';
  final heroTag = _heroTag(ServiceKey.lidarr, 'artist', item.id);
  return GlobalSearchResult(
    service: ServiceKey.lidarr,
    id: item.id,
    title: item.artistName,
    subtitle: albumLabel,
    imageUrl: image.url,
    imageHeaders: image.headers,
    tags: ['Artist', item.hasFiles ? 'Available' : 'Missing'],
    heroTag: heroTag,
    route: ServiceRoutes.lidarrArtist(item.id, heroTag: heroTag),
    routeExtra: item,
  );
}
