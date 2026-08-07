import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/features/bazarr/data/bazarr_service.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/search/presentation/global_search_provider.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

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

  test('hands every service leg of one round the same cancel token', () async {
    final seerr = _SearchSeerrService();
    final radarr = _SearchRadarrService();
    final sonarr = _SearchSonarrService();
    final lidarr = _SearchLidarrService();
    final bazarr = _SearchBazarrService();
    final container = _container(
      seerr: seerr,
      radarr: radarr,
      sonarr: sonarr,
      lidarr: lidarr,
      bazarr: bazarr,
    );
    addTearDown(container.dispose);
    container.read(globalSearchQueryProvider.notifier).state = 'dune';

    await container.read(globalSearchResultsProvider.future);

    final token = radarr.leg.tokens.single;
    expect(token, isNotNull);
    for (final leg in [seerr.leg, sonarr.leg, lidarr.leg, bazarr.leg]) {
      expect(leg.tokens.single, same(token));
    }
  });

  test('cancels the superseded round when the query moves on', () async {
    // Every leg parks here, so the first round is genuinely still in flight
    // when the second query arrives — which is the only state in which
    // cancelling means anything.
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final seerr = _SearchSeerrService(gate: gate);
    final radarr = _SearchRadarrService(gate: gate);
    final sonarr = _SearchSonarrService(gate: gate);
    final lidarr = _SearchLidarrService(gate: gate);
    final bazarr = _SearchBazarrService(gate: gate);
    final container = _container(
      seerr: seerr,
      radarr: radarr,
      sonarr: sonarr,
      lidarr: lidarr,
      bazarr: bazarr,
    );
    addTearDown(container.dispose);

    // A live listener is what keeps the autoDispose provider alive between the
    // two rounds; without it the first build would be torn down on its own and
    // the cancellation would prove nothing.
    final sub = container.listen(globalSearchResultsProvider, (_, _) {});
    addTearDown(sub.close);

    container.read(globalSearchQueryProvider.notifier).state = 'du';
    container.read(globalSearchResultsProvider);
    await Future<void>.delayed(Duration.zero);

    container.read(globalSearchQueryProvider.notifier).state = 'dune';
    container.read(globalSearchResultsProvider);
    await Future<void>.delayed(Duration.zero);

    for (final leg in [
      seerr.leg,
      radarr.leg,
      sonarr.leg,
      lidarr.leg,
      bazarr.leg,
    ]) {
      expect(leg.tokens, hasLength(2));
      expect(leg.tokens.first!.isCancelled, isTrue);
      expect(leg.tokens.last!.isCancelled, isFalse);
    }
  });

  test(
    'a settings write it does not depend on leaves the round alone',
    () async {
      // The fan-out watches the five connections, not the whole model. With the
      // cancel token above, watching the model meant a theme-mode toggle aborted
      // five in-flight requests and re-issued them.
      final radarr = _SearchRadarrService();
      final container = _container(radarr: radarr);
      addTearDown(container.dispose);

      final sub = container.listen(globalSearchResultsProvider, (_, _) {});
      addTearDown(sub.close);

      container.read(globalSearchQueryProvider.notifier).state = 'dune';
      await container.read(globalSearchResultsProvider.future);
      expect(radarr.leg.tokens, hasLength(1));

      container.read(_testSettings.notifier).state = container
          .read(_testSettings)
          .copyWith(themeMode: AppThemeMode.dark);
      await Future<void>.delayed(Duration.zero);

      expect(radarr.leg.tokens, hasLength(1));
      expect(radarr.leg.tokens.single!.isCancelled, isFalse);

      // A connection it *does* depend on still re-runs it.
      container.read(_testSettings.notifier).state = container
          .read(_testSettings)
          .copyWith(radarrApiKey: 'rotated');
      await container.read(globalSearchResultsProvider.future);

      expect(radarr.leg.tokens, hasLength(2));
    },
  );
}

/// The settings the fan-out reads, mutable so a test can write to a field the
/// search does not depend on.
final _testSettings = StateProvider<SettingsModel>(
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
);

ProviderContainer _container({
  SeerrService? seerr,
  RadarrService? radarr,
  SonarrService? sonarr,
  LidarrService? lidarr,
  BazarrService? bazarr,
}) {
  return ProviderContainer(
    overrides: [
      if (bazarr != null) bazarrServiceProvider.overrideWithValue(bazarr),
      currentSettingsProvider.overrideWith((ref) => ref.watch(_testSettings)),
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

/// Records the cancel token every search leg is handed, and — when a [gate] is
/// supplied — parks there so a round can still be in flight when the next
/// query supersedes it.
class _LegRecorder {
  final List<CancelToken?> tokens = [];
  final Completer<void>? gate;

  _LegRecorder(this.gate);

  Future<void> record(CancelToken? cancelToken) async {
    tokens.add(cancelToken);
    if (gate != null) await gate!.future;
  }
}

class _SearchSeerrService extends FakeSeerrService {
  final List<MediaPreview> results;
  final _LegRecorder leg;

  _SearchSeerrService({this.results = const [], Completer<void>? gate})
    : leg = _LegRecorder(gate);

  @override
  Future<List<MediaPreview>> search(
    String query, {
    int page = 1,
    CancelToken? cancelToken,
  }) async {
    await leg.record(cancelToken);
    return results;
  }
}

class _SearchRadarrService extends FakeRadarrService {
  final List<RadarrMovie> results;
  final bool throwOnLookup;
  final _LegRecorder leg;

  _SearchRadarrService({
    this.results = const [],
    this.throwOnLookup = false,
    Completer<void>? gate,
  }) : leg = _LegRecorder(gate);

  @override
  Future<List<RadarrMovie>> lookupMovies(
    String term, {
    CancelToken? cancelToken,
  }) async {
    await leg.record(cancelToken);
    if (throwOnLookup) throw Exception('radarr down');
    return results;
  }
}

class _SearchSonarrService extends FakeSonarrService {
  final List<SonarrSeries> results;
  final _LegRecorder leg;

  _SearchSonarrService({this.results = const [], Completer<void>? gate})
    : leg = _LegRecorder(gate);

  @override
  Future<List<SonarrSeries>> lookupSeries(
    String term, {
    CancelToken? cancelToken,
  }) async {
    await leg.record(cancelToken);
    return results;
  }
}

class _SearchLidarrService extends FakeLidarrService {
  final List<LidarrArtist> results;
  final _LegRecorder leg;

  _SearchLidarrService({this.results = const [], Completer<void>? gate})
    : leg = _LegRecorder(gate);

  @override
  Future<List<LidarrArtist>> lookupArtists(
    String term, {
    CancelToken? cancelToken,
  }) async {
    await leg.record(cancelToken);
    return results;
  }
}

class _SearchBazarrService extends FakeBazarrService {
  final _LegRecorder leg;

  _SearchBazarrService({Completer<void>? gate}) : leg = _LegRecorder(gate);

  @override
  Future<List<BazarrSearchHit>> searchLibrary(
    String query, {
    int length = 500,
    CancelToken? cancelToken,
  }) async {
    await leg.record(cancelToken);
    return const [];
  }
}
