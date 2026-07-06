class ServiceRoutes {
  ServiceRoutes._();

  static const services = '/services';
  static const seerr = '$services/seerr';
  static const radarr = '$services/radarr';
  static const sonarr = '$services/sonarr';
  static const lidarr = '$services/lidarr';
  static const qbittorrent = '$services/qbittorrent';
  static const bazarr = '$services/bazarr';

  static const seerrRequests = '$seerr/requests';
  static const seerrMoviesAll = '$seerr/movies/all';
  static const seerrTvAll = '$seerr/tv/all';
  static const seerrTrendingAll = '$seerr/trending/all';
  static const seerrGenreBase = '$seerr/genre';
  static const seerrPersonBase = '$seerr/person';
  static const seerrCollectionBase = '$seerr/collection';

  /// Person (cast member) detail page, e.g. `/services/seerr/person/287`.
  static String seerrPerson(int id, {String? heroTag, String? posterUrl}) {
    return _withQuery('$seerrPersonBase/$id', {
      'heroTag': heroTag,
      'posterUrl': posterUrl,
    });
  }

  /// Movie collection detail page, e.g. `/services/seerr/collection/10`.
  static String seerrCollection(int id, {String? heroTag}) {
    return _withQuery('$seerrCollectionBase/$id', {'heroTag': heroTag});
  }

  /// See-all for a single genre row, e.g. `/services/seerr/genre/movie/28?title=Action`.
  static String seerrGenre({
    required String mediaType,
    required int genreId,
    String? title,
  }) {
    final normalizedMediaType = mediaType == 'tv' ? 'tv' : 'movie';
    return _withQuery('$seerrGenreBase/$normalizedMediaType/$genreId', {
      'title': title,
    });
  }

  static const radarrMovieBase = '$radarr/movie';
  static const sonarrSeriesBase = '$sonarr/series';
  static const lidarrArtistBase = '$lidarr/artist';
  static const qbittorrentTorrentBase = '$qbittorrent/torrent';

  static const bazarrWanted = '$bazarr/wanted';
  static const bazarrLibrary = '$bazarr/library';
  static const bazarrSeriesBase = '$bazarr/series';
  static const bazarrMovieBase = '$bazarr/movie';

  static String radarrMovie(int id, {String? heroTag}) {
    return _withQuery('$radarrMovieBase/$id', {'heroTag': heroTag});
  }

  static String sonarrSeries(int id, {String? heroTag}) {
    return _withQuery('$sonarrSeriesBase/$id', {'heroTag': heroTag});
  }

  static String lidarrArtist(int id, {String? heroTag}) {
    return _withQuery('$lidarrArtistBase/$id', {'heroTag': heroTag});
  }

  static String qbittorrentTorrent(String hash) {
    return '$qbittorrentTorrentBase/$hash';
  }

  static String bazarrSeries(int sonarrSeriesId, {String? heroTag}) {
    return _withQuery('$bazarrSeriesBase/$sonarrSeriesId', {
      'heroTag': heroTag,
    });
  }

  static String bazarrMovie(int radarrId, {String? heroTag}) {
    return _withQuery('$bazarrMovieBase/$radarrId', {'heroTag': heroTag});
  }

  static String seerrDetail({
    required String mediaType,
    required int id,
    String? heroTag,
    String? posterUrl,
  }) {
    final normalizedMediaType = mediaType == 'tv' ? 'tv' : 'movie';
    return _withQuery('$seerr/$normalizedMediaType/$id', {
      'heroTag': heroTag,
      'posterUrl': posterUrl,
    });
  }

  static String _withQuery(String path, Map<String, String?> queryParameters) {
    final values = {
      for (final entry in queryParameters.entries)
        if (entry.value != null && entry.value!.isNotEmpty)
          entry.key: entry.value!,
    };

    if (values.isEmpty) {
      return path;
    }

    return Uri(path: path, queryParameters: values).toString();
  }
}
