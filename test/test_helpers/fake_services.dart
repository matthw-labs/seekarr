/// Shared base fakes for the `*arr` / Seerr services.
///
/// These classes provide a correctly-initialised `super(ApiClient(...))` and
/// default implementations for the activity surface (`queue/history/blocklist/
/// missing/cutoff`) and the most common read methods used across widget and
/// provider tests. Individual tests extend these fakes to override only the
/// handful of methods they need, keeping per-test boilerplate to a minimum.
library;

import 'package:dio/dio.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_genre.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/domain/models/lidarr_track.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_episode.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';

export 'fake_bazarr_service.dart';

ApiClient _client(String baseUrl) => ApiClient(baseUrl: baseUrl, apiKey: 'key');

class FakeRadarrService extends RadarrService {
  FakeRadarrService() : super(_client('https://radarr.example.com'));

  @override
  Future<List<RadarrMovie>> getMovies() async => const [];

  @override
  Future<RadarrMovie?> getMovie(int movieId) async => null;

  @override
  Future<List<Map<String, dynamic>>> getQualityProfiles() async => const [];

  @override
  Future<List<RadarrMovie>> lookupMovies(
    String term, {
    CancelToken? cancelToken,
  }) async => const [];

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => const [];

  @override
  Future<List<dynamic>> getHistory({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async => const [];

  @override
  Future<List<dynamic>> getAllHistory({
    Map<String, dynamic>? queryParameters,
  }) async => const [];

  @override
  Future<List<dynamic>> getBlocklist() async => const [];

  @override
  Future<List<dynamic>> getMissing({int page = 1, int pageSize = 20}) async =>
      const [];

  @override
  Future<List<dynamic>> getCutoff({int page = 1, int pageSize = 20}) async =>
      const [];

  @override
  Future<List<dynamic>> getAllMissing() async => const [];

  @override
  Future<List<dynamic>> getAllCutoff() async => const [];
}

class FakeSonarrService extends SonarrService {
  FakeSonarrService() : super(_client('https://sonarr.example.com'));

  @override
  Future<List<SonarrSeries>> getSeries() async => const [];

  @override
  Future<SonarrSeries?> getSeriesById(int seriesId) async => null;

  @override
  Future<List<SonarrEpisode>> getEpisodes(int seriesId) async => const [];

  @override
  Future<List<Map<String, dynamic>>> getQualityProfiles() async => const [];

  @override
  Future<List<SonarrSeries>> lookupSeries(
    String term, {
    CancelToken? cancelToken,
  }) async => const [];

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => const [];

  @override
  Future<List<dynamic>> getHistory({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async => const [];

  @override
  Future<List<dynamic>> getAllHistory({
    Map<String, dynamic>? queryParameters,
  }) async => const [];

  @override
  Future<List<dynamic>> getBlocklist() async => const [];

  @override
  Future<List<dynamic>> getMissing({int page = 1, int pageSize = 20}) async =>
      const [];

  @override
  Future<List<dynamic>> getCutoff({int page = 1, int pageSize = 20}) async =>
      const [];

  @override
  Future<List<dynamic>> getAllMissing() async => const [];

  @override
  Future<List<dynamic>> getAllCutoff() async => const [];
}

class FakeLidarrService extends LidarrService {
  FakeLidarrService() : super(_client('https://lidarr.example.com'));

  @override
  Future<List<LidarrArtist>> getArtists() async => const [];

  @override
  Future<LidarrArtist?> getArtistById(int artistId) async => null;

  @override
  Future<List<LidarrAlbum>> getAlbums(int artistId) async => const [];

  @override
  Future<List<LidarrTrack>> getTracks(int albumId) async => const [];

  @override
  Future<List<Map<String, dynamic>>> getQualityProfiles() async => const [];

  @override
  Future<List<LidarrArtist>> lookupArtists(
    String term, {
    CancelToken? cancelToken,
  }) async => const [];

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => const [];

  @override
  Future<List<dynamic>> getHistory({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async => const [];

  @override
  Future<List<dynamic>> getAllHistory({
    Map<String, dynamic>? queryParameters,
  }) async => const [];

  @override
  Future<List<dynamic>> getBlocklist() async => const [];

  @override
  Future<List<dynamic>> getMissing({int page = 1, int pageSize = 20}) async =>
      const [];

  @override
  Future<List<dynamic>> getCutoff({int page = 1, int pageSize = 20}) async =>
      const [];

  @override
  Future<List<dynamic>> getAllMissing() async => const [];

  @override
  Future<List<dynamic>> getAllCutoff() async => const [];
}

class FakeSeerrService extends SeerrService {
  FakeSeerrService({
    Map<String, dynamic>? movieDetails,
    Map<String, dynamic>? tvDetails,
  }) : _movieDetails = movieDetails ?? _defaultMovieDetails,
       _tvDetails = tvDetails ?? _defaultTvDetails,
       super(_client('https://seerr.example.com'));

  final Map<String, dynamic> _movieDetails;
  final Map<String, dynamic> _tvDetails;

  @override
  Future<List<MediaPreview>> getDiscoverMovies({
    int page = 1,
    int? genre,
    String? sortBy,
  }) async => const [];

  @override
  Future<List<MediaPreview>> getDiscoverTV({
    int page = 1,
    int? genre,
    String? sortBy,
  }) async => const [];

  @override
  Future<List<MediaPreview>> getDiscoverTrending({int page = 1}) async =>
      const [];

  @override
  Future<List<MediaPreview>> getDiscoverUpcomingMovies({int page = 1}) async =>
      const [];

  @override
  Future<List<MediaPreview>> getDiscoverUpcomingTv({int page = 1}) async =>
      const [];

  @override
  Future<List<SeerrGenre>> getMovieGenres() async => const [];

  @override
  Future<List<SeerrGenre>> getTvGenres() async => const [];

  @override
  Future<List<MediaPreview>> search(
    String query, {
    int page = 1,
    CancelToken? cancelToken,
  }) async => const [];

  @override
  Future<List<SeerrRequest>> getRequests() async => const [];

  @override
  Future<Map<String, dynamic>> getMovie(int movieId) async => _movieDetails;

  @override
  Future<Map<String, dynamic>> getTv(int tvId) async => _tvDetails;
}

const Map<String, dynamic> _defaultMovieDetails = {
  'title': 'Discover Movie',
  'overview': 'A movie overview.',
  'posterPath': '/poster.jpg',
  'genres': [],
  'credits': {'cast': [], 'crew': []},
  'keywords': [],
};

const Map<String, dynamic> _defaultTvDetails = {
  'name': 'Discover Show',
  'overview': 'A show overview.',
  'posterPath': '/show.jpg',
  'genres': [],
  'credits': {'cast': [], 'crew': []},
  'keywords': [],
};
