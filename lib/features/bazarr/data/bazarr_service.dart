import 'package:seekarr/core/api/api_client.dart';
import 'package:seekarr/core/utils/dynamic_map_utils.dart';
import 'package:seekarr/features/bazarr/domain/models/bazarr_models.dart';

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
