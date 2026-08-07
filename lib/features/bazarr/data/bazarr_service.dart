import 'package:dio/dio.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';

/// Service for interacting with the Bazarr API.
///
/// Bazarr is intentionally NOT modeled via the *arr activity mixin because the
/// envelope shape and data model diverge (e.g. episodes/movies wanted, jobs
/// queue, badges count). The Riverpod provider wiring lives in
/// `bazarr_provider.dart`; this file only defines the transport class.
class BazarrService {
  final ApiClient client;

  BazarrService(this.client);

  /// Returns the authenticated system status (version, OS, database...).
  Future<BazarrSystemStatus> getStatus() async {
    final response = await client.get('/api/system/status');
    final payload = _unwrapData(response.data);
    return BazarrSystemStatus.fromJson(payload);
  }

  /// Returns aggregated counts exposed by the navbar (episodes/movies wanted
  /// plus signalR/provider indicators).
  Future<BazarrBadges> getBadges() async {
    final response = await client.get('/api/badges');
    final raw = response.data;
    if (raw is Map<String, dynamic>) {
      return BazarrBadges.fromJson(raw);
    }
    return const BazarrBadges(
      episodes: 0,
      movies: 0,
      providers: 0,
      status: false,
      sonarrSignalR: false,
      radarrSignalR: false,
      announcements: 0,
    );
  }

  /// Paged list of series known to Bazarr.
  Future<BazarrPagedResult<BazarrSeries>> getSeries({
    int start = 0,
    int length = 50,
  }) async {
    final response = await client.get(
      '/api/series',
      queryParameters: {'start': start, 'length': length},
    );
    return _parsePaged(response.data, BazarrSeries.fromJson, start: start);
  }

  /// Paged list of movies known to Bazarr.
  Future<BazarrPagedResult<BazarrMovie>> getMovies({
    int start = 0,
    int length = 50,
  }) async {
    final response = await client.get(
      '/api/movies',
      queryParameters: {'start': start, 'length': length},
    );
    return _parsePaged(response.data, BazarrMovie.fromJson, start: start);
  }

  /// Client-side search across the Bazarr library.
  ///
  /// Bazarr exposes no search endpoint, so matching happens here, against a
  /// cached snapshot of the library's titles — see [_libraryIndex].
  ///
  /// [cancelToken] is honoured *cooperatively*, and only after the snapshot
  /// resolves: the download itself is shared with whatever query comes next, so
  /// aborting it would abandon the request the successor is waiting on (again,
  /// see [_libraryIndex]). What a superseded caller does skip is scanning a
  /// thousand titles for an answer nobody will read.
  Future<List<BazarrSearchHit>> searchLibrary(
    String query, {
    int length = _searchIndexLength,
    CancelToken? cancelToken,
  }) async {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];

    final index = await _libraryIndex(length);
    if (cancelToken?.isCancelled ?? false) return const [];
    return index
        .where((hit) => hit.title.toLowerCase().contains(needle))
        .toList(growable: false);
  }

  /// Every title Bazarr knows, as `(id, title, isMovie)` triples.
  ///
  /// Two mechanisms, both about the same problem: with no server-side search,
  /// one query means downloading the whole series list *and* the whole movie
  /// list, and the global search surface re-runs its query on every debounced
  /// keystroke pause. That turned typing one title into several thousand
  /// records over the wire.
  ///
  /// **The snapshot is reused for [_searchIndexTtl].** Library membership does
  /// not churn on a typing timescale — a series added while the user is midway
  /// through a word is not what the search is for — so after the first query a
  /// keystroke costs nothing at all.
  ///
  /// **A fetch already in flight is shared, not restarted.** This is also why
  /// the fetch deliberately takes no `CancelToken`: cancelling the in-flight
  /// download when a superseded query is discarded would abort the very request
  /// the *next* query is waiting on, and the round would start over. Sharing it
  /// gets what cancellation was after — one download, not one per keystroke —
  /// without that trade.
  Future<List<BazarrSearchHit>> _libraryIndex(int length) {
    final cached = _searchIndex;
    final cachedAt = _searchIndexAt;
    if (cached != null &&
        cachedAt != null &&
        _searchIndexLengthUsed == length &&
        DateTime.now().difference(cachedAt) < _searchIndexTtl) {
      return Future.value(cached);
    }

    return _searchIndexInFlight ??= _fetchLibraryIndex(length);
  }

  Future<List<BazarrSearchHit>> _fetchLibraryIndex(int length) async {
    try {
      final (series, movies) = await (
        getSeries(length: length),
        getMovies(length: length),
      ).wait;

      final hits = <BazarrSearchHit>[
        for (final item in series.data)
          if (item.title case final title? when title.isNotEmpty)
            BazarrSearchHit(
              id: item.sonarrSeriesId,
              title: title,
              isMovie: false,
            ),
        for (final item in movies.data)
          if (item.title case final title? when title.isNotEmpty)
            BazarrSearchHit(id: item.radarrId, title: title, isMovie: true),
      ];

      _searchIndex = hits;
      _searchIndexAt = DateTime.now();
      _searchIndexLengthUsed = length;
      return hits;
    } finally {
      // Released whether the fetch succeeded or threw: a failed round must not
      // leave every later query awaiting a future that already lost.
      _searchIndexInFlight = null;
    }
  }

  /// How long a library snapshot stays usable for search.
  static const _searchIndexTtl = Duration(minutes: 2);

  /// Page size of the snapshot. Large enough to hold an ordinary library in one
  /// round trip; a smaller window would silently drop titles from the results.
  static const _searchIndexLength = 500;

  List<BazarrSearchHit>? _searchIndex;
  DateTime? _searchIndexAt;
  int? _searchIndexLengthUsed;
  Future<List<BazarrSearchHit>>? _searchIndexInFlight;

  /// Paged list of missing episode subtitles.
  Future<BazarrPagedResult<BazarrWantedItem>> getWantedEpisodes({
    int start = 0,
    int length = 50,
  }) async {
    final response = await client.get(
      '/api/episodes/wanted',
      queryParameters: {'start': start, 'length': length},
    );
    return _parsePaged(response.data, BazarrWantedItem.fromJson, start: start);
  }

  /// Paged list of missing movie subtitles.
  Future<BazarrPagedResult<BazarrWantedItem>> getWantedMovies({
    int start = 0,
    int length = 50,
  }) async {
    final response = await client.get(
      '/api/movies/wanted',
      queryParameters: {'start': start, 'length': length},
    );
    return _parsePaged(response.data, BazarrWantedItem.fromJson, start: start);
  }

  /// Returns the scheduler task definitions.
  Future<List<BazarrSystemTask>> getSystemTasks() async {
    final response = await client.get('/api/system/tasks');
    final data = _unwrapList(response.data);
    return data.map(BazarrSystemTask.fromJson).toList(growable: false);
  }

  /// Returns the job queue entries (pending/running/failed/completed).
  Future<List<BazarrJob>> getJobs({String? status}) async {
    final response = await client.get(
      '/api/system/jobs',
      queryParameters: {if (status != null) 'status': status},
    );
    final data = _unwrapList(response.data);
    return data.map(BazarrJob.fromJson).toList(growable: false);
  }

  /// Returns recent history events for episodes.
  Future<BazarrPagedResult<Map<String, dynamic>>> getEpisodesHistory({
    int start = 0,
    int length = 50,
  }) async {
    final response = await client.get(
      '/api/episodes/history',
      queryParameters: {'start': start, 'length': length},
    );
    return _parsePaged(response.data, (m) => m, start: start);
  }

  /// Returns recent history events for movies.
  Future<BazarrPagedResult<Map<String, dynamic>>> getMoviesHistory({
    int start = 0,
    int length = 50,
  }) async {
    final response = await client.get(
      '/api/movies/history',
      queryParameters: {'start': start, 'length': length},
    );
    return _parsePaged(response.data, (m) => m, start: start);
  }

  /// Triggers one of the documented PATCH actions on a series.
  Future<void> patchSeriesAction(int sonarrSeriesId, String action) async {
    await client.patch(
      '/api/series',
      queryParameters: {
        'seriesid': sonarrSeriesId.toString(),
        'action': action,
      },
    );
  }

  /// Triggers one of the documented PATCH actions on a movie.
  Future<void> patchMovieAction(int radarrId, String action) async {
    await client.patch(
      '/api/movies',
      queryParameters: {'radarrid': radarrId.toString(), 'action': action},
    );
  }

  /// Triggers a scheduler task to run now.
  Future<void> runSystemTask(String taskId) async {
    await client.post('/api/system/tasks', queryParameters: {'taskid': taskId});
  }

  /// Executes a job-queue action (force_start, move_top, move_bottom).
  Future<void> runJobAction(String jobId, String action) async {
    await client.post(
      '/api/system/jobs',
      queryParameters: {'id': jobId, 'action': action},
    );
  }

  /// Empties a job queue (pending/failed/completed).
  Future<void> emptyJobQueue(String queueName) async {
    await client.patch(
      '/api/system/jobs',
      queryParameters: {'queueName': queueName},
    );
  }

  /// Deletes a pending job.
  Future<void> deleteJob(String jobId) async {
    await client.delete('/api/system/jobs', queryParameters: {'id': jobId});
  }
}

/// A single global-search match from the Bazarr library.
///
/// [id] is the upstream Sonarr series id or Radarr movie id, matching the
/// route parameters used by [ServiceRoutes.bazarrSeries] / `bazarrMovie`.
class BazarrSearchHit {
  final int id;
  final String title;
  final bool isMovie;

  const BazarrSearchHit({
    required this.id,
    required this.title,
    required this.isMovie,
  });
}

/// Paged result from a Bazarr list endpoint.
///
/// Bazarr returns the total count of the entire filtered list (not the
/// current page), so [hasMore] must combine [start] with [data.length].
class BazarrPagedResult<T> {
  final List<T> data;
  final int? total;
  final int start;

  const BazarrPagedResult({required this.data, this.total, this.start = 0});

  bool get hasMore => total == null ? false : start + data.length < total!;
}

Map<String, dynamic> _unwrapData(dynamic value) {
  final unwrapped = mapOrNull(value)?['data'];
  if (unwrapped is Map<String, dynamic>) return unwrapped;
  if (unwrapped is Map) return stringKeyMap(unwrapped);
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _unwrapList(dynamic value) {
  final unwrapped = mapOrNull(value)?['data'];
  if (unwrapped is List) {
    return unwrapped.whereType<Map>().map(stringKeyMap).toList(growable: false);
  }
  return const <Map<String, dynamic>>[];
}

BazarrPagedResult<T> _parsePaged<T>(
  dynamic raw,
  T Function(Map<String, dynamic>) builder, {
  int start = 0,
}) {
  final map = mapOrNull(raw);
  final data = map?['data'];
  final total = intOrNull(map?['total']);
  if (data is List) {
    final items = data
        .whereType<Map>()
        .map(stringKeyMap)
        .map(builder)
        .toList(growable: false);
    return BazarrPagedResult(data: items, total: total, start: start);
  }
  return BazarrPagedResult(data: const [], total: total, start: start);
}
