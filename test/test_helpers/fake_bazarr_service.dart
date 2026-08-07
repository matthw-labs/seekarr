import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/bazarr/data/bazarr_service.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';

ApiClient _client(String baseUrl) => ApiClient(baseUrl: baseUrl, apiKey: 'key');

class FakeBazarrService extends BazarrService {
  FakeBazarrService() : super(_client('https://bazarr.example.com'));

  BazarrSystemStatus status = const BazarrSystemStatus(bazarrVersion: '1.4.5');
  BazarrBadges badges = const BazarrBadges(
    episodes: 0,
    movies: 0,
    providers: 0,
    status: false,
    sonarrSignalR: false,
    radarrSignalR: false,
    announcements: 0,
  );
  BazarrPagedResult<BazarrSeries> seriesResult = const BazarrPagedResult(
    data: [],
    total: 0,
  );
  BazarrPagedResult<BazarrMovie> moviesResult = const BazarrPagedResult(
    data: [],
    total: 0,
  );
  BazarrPagedResult<BazarrWantedItem> wantedEpisodesResult =
      const BazarrPagedResult(data: [], total: 0);
  BazarrPagedResult<BazarrWantedItem> wantedMoviesResult =
      const BazarrPagedResult(data: [], total: 0);
  BazarrPagedResult<Map<String, dynamic>> episodesHistoryResult =
      const BazarrPagedResult(data: [], total: 0);
  BazarrPagedResult<Map<String, dynamic>> moviesHistoryResult =
      const BazarrPagedResult(data: [], total: 0);
  List<BazarrSystemTask> tasks = const [];
  List<BazarrJob> jobs = const [];

  /// Override the result returned by the by-id lookup providers. The fake
  /// service returns this value without paging when [seriesByIdOverride] or
  /// [movieByIdOverride] is non-null; otherwise the [seriesResult] /
  /// [moviesResult] is paged through like in production.
  BazarrSeries? seriesByIdOverride;
  BazarrMovie? movieByIdOverride;
  List<BazarrWantedItem> wantedEpisodesForSeriesResult = const [];
  BazarrWantedItem? wantedMovieByIdOverride;

  Object? throwOnCall;

  /// Thrown only by the wanted endpoints, so a test can fail the secondary
  /// section while the primary lookup succeeds.
  Object? throwOnWanted;

  /// Call counters for retry assertions.
  int wantedMoviesCalls = 0;
  int wantedEpisodesCalls = 0;

  @override
  Future<BazarrSystemStatus> getStatus() async {
    if (throwOnCall != null) throw throwOnCall!;
    return status;
  }

  @override
  Future<BazarrBadges> getBadges() async {
    if (throwOnCall != null) throw throwOnCall!;
    return badges;
  }

  @override
  Future<BazarrPagedResult<BazarrSeries>> getSeries({
    int start = 0,
    int length = 50,
  }) async {
    if (throwOnCall != null) throw throwOnCall!;
    if (seriesByIdOverride != null) {
      return BazarrPagedResult(
        data: [seriesByIdOverride!],
        total: 1,
        start: start,
      );
    }
    return seriesResult;
  }

  @override
  Future<BazarrPagedResult<BazarrMovie>> getMovies({
    int start = 0,
    int length = 50,
  }) async {
    if (throwOnCall != null) throw throwOnCall!;
    if (movieByIdOverride != null) {
      return BazarrPagedResult(
        data: [movieByIdOverride!],
        total: 1,
        start: start,
      );
    }
    return moviesResult;
  }

  @override
  Future<BazarrPagedResult<BazarrWantedItem>> getWantedEpisodes({
    int start = 0,
    int length = 50,
  }) async {
    wantedEpisodesCalls++;
    if (throwOnCall != null) throw throwOnCall!;
    if (throwOnWanted != null) throw throwOnWanted!;
    if (wantedEpisodesForSeriesResult.isNotEmpty) {
      return BazarrPagedResult(
        data: wantedEpisodesForSeriesResult,
        total: wantedEpisodesForSeriesResult.length,
        start: start,
      );
    }
    return wantedEpisodesResult;
  }

  @override
  Future<BazarrPagedResult<BazarrWantedItem>> getWantedMovies({
    int start = 0,
    int length = 50,
  }) async {
    wantedMoviesCalls++;
    if (throwOnCall != null) throw throwOnCall!;
    if (throwOnWanted != null) throw throwOnWanted!;
    if (wantedMovieByIdOverride != null) {
      return BazarrPagedResult(
        data: [wantedMovieByIdOverride!],
        total: 1,
        start: start,
      );
    }
    return wantedMoviesResult;
  }

  @override
  Future<BazarrPagedResult<Map<String, dynamic>>> getEpisodesHistory({
    int start = 0,
    int length = 50,
  }) async {
    if (throwOnCall != null) throw throwOnCall!;
    return episodesHistoryResult;
  }

  @override
  Future<BazarrPagedResult<Map<String, dynamic>>> getMoviesHistory({
    int start = 0,
    int length = 50,
  }) async {
    if (throwOnCall != null) throw throwOnCall!;
    return moviesHistoryResult;
  }

  @override
  Future<List<BazarrSystemTask>> getSystemTasks() async {
    if (throwOnCall != null) throw throwOnCall!;
    return tasks;
  }

  @override
  Future<List<BazarrJob>> getJobs({String? status}) async {
    if (throwOnCall != null) throw throwOnCall!;
    return jobs;
  }
}
