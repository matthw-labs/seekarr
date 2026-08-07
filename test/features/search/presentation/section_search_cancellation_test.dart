import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/presentation/movies_search_provider.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/presentation/music_search_provider.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/series/presentation/series_search_provider.dart';

import '../../../test_helpers/fake_services.dart';

/// The per-section search surfaces (`/movies`, `/series`, `/music`) each mint
/// their own [CancelToken], the same way the global fan-out does. Every one of
/// them re-runs on each keystroke against services that can take seconds to
/// answer, so the round a keystroke supersedes has to stop rather than run to
/// completion.
void main() {
  group('movies', () {
    test('hands the lookup a cancel token', () async {
      final radarr = _GateRadarrService();
      final container = ProviderContainer(
        overrides: [radarrServiceProvider.overrideWithValue(radarr)],
      );
      addTearDown(container.dispose);

      container.read(moviesSearchQueryProvider.notifier).state = 'dune';
      await container.read(moviesSearchResultsProvider.future);

      expect(radarr.tokens.single, isNotNull);
    });

    test('cancels the superseded round when the query moves on', () async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final radarr = _GateRadarrService(gate: gate);
      final container = ProviderContainer(
        overrides: [radarrServiceProvider.overrideWithValue(radarr)],
      );
      addTearDown(container.dispose);

      final sub = container.listen(moviesSearchResultsProvider, (_, _) {});
      addTearDown(sub.close);

      container.read(moviesSearchQueryProvider.notifier).state = 'du';
      await Future<void>.delayed(Duration.zero);
      container.read(moviesSearchQueryProvider.notifier).state = 'dune';
      await Future<void>.delayed(Duration.zero);

      expect(radarr.tokens, hasLength(2));
      expect(radarr.tokens.first!.isCancelled, isTrue);
      expect(radarr.tokens.last!.isCancelled, isFalse);
    });
  });

  group('series', () {
    test('hands the lookup a cancel token', () async {
      final sonarr = _GateSonarrService();
      final container = ProviderContainer(
        overrides: [sonarrServiceProvider.overrideWithValue(sonarr)],
      );
      addTearDown(container.dispose);

      container.read(seriesSearchQueryProvider.notifier).state = 'severance';
      await container.read(seriesSearchResultsProvider.future);

      expect(sonarr.tokens.single, isNotNull);
    });

    test('cancels the superseded round when the query moves on', () async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final sonarr = _GateSonarrService(gate: gate);
      final container = ProviderContainer(
        overrides: [sonarrServiceProvider.overrideWithValue(sonarr)],
      );
      addTearDown(container.dispose);

      final sub = container.listen(seriesSearchResultsProvider, (_, _) {});
      addTearDown(sub.close);

      container.read(seriesSearchQueryProvider.notifier).state = 'sev';
      await Future<void>.delayed(Duration.zero);
      container.read(seriesSearchQueryProvider.notifier).state = 'severance';
      await Future<void>.delayed(Duration.zero);

      expect(sonarr.tokens, hasLength(2));
      expect(sonarr.tokens.first!.isCancelled, isTrue);
      expect(sonarr.tokens.last!.isCancelled, isFalse);
    });
  });

  group('music', () {
    test('hands the lookup a cancel token', () async {
      final lidarr = _GateLidarrService();
      final container = ProviderContainer(
        overrides: [lidarrServiceProvider.overrideWithValue(lidarr)],
      );
      addTearDown(container.dispose);

      container.read(musicSearchQueryProvider.notifier).state = 'charli';
      await container.read(musicSearchResultsProvider.future);

      expect(lidarr.tokens.single, isNotNull);
    });

    test('cancels the superseded round when the query moves on', () async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final lidarr = _GateLidarrService(gate: gate);
      final container = ProviderContainer(
        overrides: [lidarrServiceProvider.overrideWithValue(lidarr)],
      );
      addTearDown(container.dispose);

      final sub = container.listen(musicSearchResultsProvider, (_, _) {});
      addTearDown(sub.close);

      container.read(musicSearchQueryProvider.notifier).state = 'char';
      await Future<void>.delayed(Duration.zero);
      container.read(musicSearchQueryProvider.notifier).state = 'charli';
      await Future<void>.delayed(Duration.zero);

      expect(lidarr.tokens, hasLength(2));
      expect(lidarr.tokens.first!.isCancelled, isTrue);
      expect(lidarr.tokens.last!.isCancelled, isFalse);
    });
  });
}

/// Records the token of every lookup and, with a [gate], parks the request so
/// the first round is genuinely still in flight when the second arrives —
/// which is the only state in which cancelling means anything.
class _GateRadarrService extends FakeRadarrService {
  _GateRadarrService({this.gate});

  final Completer<void>? gate;
  final List<CancelToken?> tokens = [];

  @override
  Future<List<RadarrMovie>> lookupMovies(
    String term, {
    CancelToken? cancelToken,
  }) async {
    tokens.add(cancelToken);
    await gate?.future;
    return const [];
  }
}

class _GateSonarrService extends FakeSonarrService {
  _GateSonarrService({this.gate});

  final Completer<void>? gate;
  final List<CancelToken?> tokens = [];

  @override
  Future<List<SonarrSeries>> lookupSeries(
    String term, {
    CancelToken? cancelToken,
  }) async {
    tokens.add(cancelToken);
    await gate?.future;
    return const [];
  }
}

class _GateLidarrService extends FakeLidarrService {
  _GateLidarrService({this.gate});

  final Completer<void>? gate;
  final List<CancelToken?> tokens = [];

  @override
  Future<List<LidarrArtist>> lookupArtists(
    String term, {
    CancelToken? cancelToken,
  }) async {
    tokens.add(cancelToken);
    await gate?.future;
    return const [];
  }
}
