import 'package:seekarr/features/prowlarr/domain/models/prowlarr_models.dart';

class ServiceRoutes {
  ServiceRoutes._();

  static const services = '/services';
  static const seerr = '$services/seerr';
  static const radarr = '$services/radarr';
  static const sonarr = '$services/sonarr';
  static const lidarr = '$services/lidarr';
  static const qbittorrent = '$services/qbittorrent';
  static const bazarr = '$services/bazarr';
  static const truenas = '$services/truenas';
  static const dockge = '$services/dockge';
  static const prowlarr = '$services/prowlarr';
  static const readarr = '$services/readarr';
  static const sabnzbd = '$services/sabnzbd';
  static const nzbget = '$services/nzbget';
  static const unraid = '$services/unraid';
  static const jellyfin = '$services/jellyfin';
  static const plex = '$services/plex';

  // ── Stream sections ───────────────────────────────────────────────────────
  //
  // Both media servers share one route shape because both APIs are uniform in
  // the way the arrs are not: a Jellyfin `BaseItemDto` and a Plex `Metadata`
  // describe a movie, a series, a season and an episode with the same fields, so
  // **one** recursive item route covers the whole tree where Radarr, Sonarr and
  // Lidarr each needed their own screen.
  static const jellyfinLibraries = '$jellyfin/library';
  static const jellyfinItemBase = '$jellyfin/item';
  static const plexLibraries = '$plex/library';
  static const plexItemBase = '$plex/item';

  /// One library's browse route, e.g. `/services/jellyfin/library/f137a2dd`.
  ///
  /// The id travels as a path segment and the display name as a query parameter,
  /// following [seerrGenre]: a deep link has to resolve from the path alone, but
  /// a caller that already knows the name can spare the destination a fetch
  /// before its first frame.
  static String jellyfinLibrary(String id, {String? title}) =>
      _streamLibrary(jellyfinLibraries, id, title);
  static String plexLibrary(String id, {String? title}) =>
      _streamLibrary(plexLibraries, id, title);

  static String _streamLibrary(String base, String id, String? title) {
    final route = '$base/$id';
    final name = title?.trim() ?? '';
    return name.isEmpty ? route : _withQuery(route, {'title': name});
  }

  /// One item at any depth of the tree — film, show, season or episode.
  ///
  /// Jellyfin ids are GUIDs and a Plex `ratingKey` is documented as an opaque
  /// string that only *often* looks numeric, so neither can go through
  /// `RouteUtils.safeIntParam`. Both are single path segments containing no `/`,
  /// which is why this stays a path route rather than taking
  /// [truenasDataset]'s query-parameter escape hatch.
  static String jellyfinItem(String id) => '$jellyfinItemBase/$id';
  static String plexItem(String id) => '$plexItemBase/$id';

  // ── TrueNAS sections ──────────────────────────────────────────────────────
  static const truenasDashboard = '$truenas/dashboard';
  static const truenasStorage = '$truenas/storage';
  static const truenasPoolBase = '$truenasStorage/pool';
  static const truenasDatasets = '$truenas/datasets';
  static const truenasDatasetDetail = '$truenasDatasets/detail';
  static const truenasShares = '$truenas/shares';
  static const truenasDataProtection = '$truenas/data-protection';
  static const truenasContainers = '$truenas/containers';
  static const truenasContainerBase = '$truenasContainers/instance';
  static const truenasVms = '$truenas/vms';
  static const truenasVmBase = '$truenasVms/instance';
  static const truenasApps = '$truenas/apps';
  static const truenasAppBase = '$truenasApps/app';
  static const truenasReporting = '$truenas/reporting';
  static const truenasSystem = '$truenas/system';

  /// Pool detail, e.g. `/services/truenas/storage/pool/tank`.
  static String truenasPool(String name) => '$truenasPoolBase/$name';

  /// Dataset detail. ZFS ids contain `/`, so the id travels as a query
  /// parameter rather than a path segment.
  static String truenasDataset(String id) =>
      _withQuery(truenasDatasetDetail, {'id': id});

  /// Container/VM instance detail (Incus instance name is a single segment).
  static String truenasContainer(String id) => '$truenasContainerBase/$id';
  static String truenasVm(String id) => '$truenasVmBase/$id';

  /// Installed app detail by app name.
  static String truenasApp(String name) => '$truenasAppBase/$name';

  /// A System sub-section, e.g. `/services/truenas/system/network`.
  static String truenasSystemSection(String section) =>
      '$truenasSystem/$section';

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

  // ── Prowlarr ──────────────────────────────────────────────────────────────
  static const prowlarrLibrary = '$prowlarr/library';
  static const prowlarrIndexerBase = '$prowlarr/indexer';
  static const prowlarrSettings = '$prowlarr/settings';
  static const prowlarrSyncProfiles = '$prowlarrSettings/sync-profiles';
  static const prowlarrTags = '$prowlarrSettings/tags';

  /// Indexer detail, e.g. `/services/prowlarr/indexer/3`.
  static String prowlarrIndexer(int id) => '$prowlarrIndexerBase/$id';

  /// One of the field-driven settings sections, e.g.
  /// `/services/prowlarr/settings/apps`.
  static String prowlarrSettingsSection(ProwlarrProviderKind kind) =>
      '$prowlarrSettings/${kind.routeSegment}';

  // ── Readarr ─────────────────────────────────────────────────────────────
  static const readarrLibrary = '$readarr/library';

  // ── Dockge ────────────────────────────────────────────────────────────────
  static const dockgeStackBase = '$dockge/stack';
  static const dockgeNewStack = '$dockge/new';

  /// Stack detail, e.g. `/services/dockge/stack/immich`.
  static String dockgeStack(String name) => '$dockgeStackBase/$name';

  /// Compose editor for a stack, e.g. `/services/dockge/stack/immich/edit`.
  static String dockgeStackEdit(String name) => '$dockgeStackBase/$name/edit';

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
