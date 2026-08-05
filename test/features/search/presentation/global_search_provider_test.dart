import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/models/media_preview.dart';
import 'package:seekarr/features/discover/data/seerr_service.dart';
import 'package:seekarr/features/movies/data/radarr_service.dart';
import 'package:seekarr/features/movies/domain/models/radarr_movie.dart';
import 'package:seekarr/features/music/data/lidarr_service.dart';
import 'package:seekarr/features/music/domain/models/lidarr_artist.dart';
import 'package:seekarr/features/search/presentation/global_search_provider.dart';
import 'package:seekarr/features/series/data/sonarr_service.dart';
import 'package:seekarr/features/series/domain/models/sonarr_series.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/model_builders.dart';

void main() {
  test('returns no grouped results for an empty query', () async {
    final container = _container();
    addTearDown(container.dispose);

    final results = await container.read(globalSearchResultsProvider.future);

    expect(results, isEmpty);
  });

  test('normalizes mixed service results into grouped search rows', () async {
    final container = _container(
      seerr: _SearchSeerrService(
        results: const [
          MediaPreview(
            id: 101,
            title: 'Dune: Part Two',
            releaseDate: '2024-03-01',
            mediaType: 'movie',
          ),
        ],
      ),
      radarr: _SearchRadarrService(
        results: [buildMovie(id: 10, title: 'Dune', year: 2024)],
      ),
      sonarr: _SearchSonarrService(
        results: [buildSeries(id: 20, title: 'The Boys', year: 2024)],
      ),
      lidarr: _SearchLidarrService(
        results: [
          buildArtist(
            id: 30,
            artistName: 'Charli XCX',
            statistics: const {'albumCount': 6, 'trackFileCount': 90},
          ),
        ],
      ),
    );
    addTearDown(container.dispose);
    container.read(globalSearchQueryProvider.notifier).state = 'dune';

    final groups = await container.read(globalSearchResultsProvider.future);

    expect(
      groups.map((group) => group.service),
      ServiceKey.values.where((s) => s.isSearchable),
    );
    expect(groups.expand((group) => group.results).map((item) => item.title), [
      'Dune: Part Two',
      'Dune',
      'The Boys',
      'Charli XCX',
    ]);
    // Each route carries its poster's shared-element tag, so the detail page it
    // opens has a matching Hero destination to fly into.
    final routes = groups
        .expand((group) => group.results)
        .map((item) => Uri.parse(item.route))
        .toList(growable: false);
    expect(routes.map((uri) => uri.path), [
      '/services/seerr/movie/101',
      '/services/radarr/movie/10',
      '/services/sonarr/series/20',
      '/services/lidarr/artist/30',
    ]);
    expect(routes.map((uri) => uri.queryParameters['heroTag']), [
      'search_seerr_movie_101',
      'search_radarr_movie_10',
      'search_sonarr_series_20',
      'search_lidarr_artist_30',
    ]);
    // The tag on the model and the tag in its route are the same string —
    // a mismatch would silently produce a flightless navigation.
    for (final result in groups.expand((group) => group.results)) {
      expect(
        Uri.parse(result.route).queryParameters['heroTag'],
        result.heroTag,
      );
    }
  });

  test('preserves partial service failures', () async {
    final container = _container(
      radarr: _SearchRadarrService(throwOnLookup: true),
      sonarr: _SearchSonarrService(
        results: [buildSeries(id: 20, title: 'Foundation')],
      ),
    );
    addTearDown(container.dispose);
    container.read(globalSearchQueryProvider.notifier).state = 'foundation';

    final groups = await container.read(globalSearchResultsProvider.future);
    final radarr = groups.singleWhere(
      (group) => group.service == ServiceKey.radarr,
    );
    final sonarr = groups.singleWhere(
      (group) => group.service == ServiceKey.sonarr,
    );

    expect(radarr.hasError, isTrue);
    expect(radarr.results, isEmpty);
    expect(sonarr.hasError, isFalse);
    expect(sonarr.results.single.title, 'Foundation');
  });
}

ProviderContainer _container({
  SeerrService? seerr,
  RadarrService? radarr,
  SonarrService? sonarr,
  LidarrService? lidarr,
}) {
  return ProviderContainer(
    overrides: [
      currentSettingsProvider.overrideWith(
        (ref) => const SettingsModel(
          seerrUrl: 'http://seerr.local:5055',
          seerrApiKey: 'key',
          radarrUrl: 'http://radarr.local:7878',
          radarrApiKey: 'key',
          sonarrUrl: 'http://sonarr.local:8989',
          sonarrApiKey: 'key',
          lidarrUrl: 'http://lidarr.local:8686',
          lidarrApiKey: 'key',
        ),
      ),
      seerrServiceProvider.overrideWith(
        (ref) => seerr ?? _SearchSeerrService(),
      ),
      radarrServiceProvider.overrideWith(
        (ref) => radarr ?? _SearchRadarrService(),
      ),
      sonarrServiceProvider.overrideWith(
        (ref) => sonarr ?? _SearchSonarrService(),
      ),
      lidarrServiceProvider.overrideWith(
        (ref) => lidarr ?? _SearchLidarrService(),
      ),
    ],
  );
}

class _SearchSeerrService extends FakeSeerrService {
  final List<MediaPreview> results;

  _SearchSeerrService({this.results = const []});

  @override
  Future<List<MediaPreview>> search(String query, {int page = 1}) async =>
      results;
}

class _SearchRadarrService extends FakeRadarrService {
  final List<RadarrMovie> results;
  final bool throwOnLookup;

  _SearchRadarrService({this.results = const [], this.throwOnLookup = false});

  @override
  Future<List<RadarrMovie>> lookupMovies(String term) async {
    if (throwOnLookup) throw Exception('radarr down');
    return results;
  }
}

class _SearchSonarrService extends FakeSonarrService {
  final List<SonarrSeries> results;

  _SearchSonarrService({this.results = const []});

  @override
  Future<List<SonarrSeries>> lookupSeries(String term) async => results;
}

class _SearchLidarrService extends FakeLidarrService {
  final List<LidarrArtist> results;

  _SearchLidarrService({this.results = const []});

  @override
  Future<List<LidarrArtist>> lookupArtists(String term) async => results;
}
