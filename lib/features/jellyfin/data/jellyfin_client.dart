import 'dart:io' show Platform;
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/jellyfin/domain/models/jellyfin_item_mapper.dart';
import 'package:cupola/features/jellyfin/domain/models/jellyfin_models.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/models/stream_library_page.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';

/// Jellyfin's implementation of [StreamServerClient].
///
/// ## The privilege model, which decides the shape of this whole file
///
/// A Jellyfin API key authenticates as `role=Administrator` with `IsApiKey=true`
/// and **no user attached** — the `UserId` claim is the empty GUID. So the key
/// passes every admin policy (it can read `/Sessions`, `/Users`,
/// `/Library/VirtualFolders`, and stop a playback) while having no idea who "I"
/// am. Every user-scoped question — what did I not finish, what is next up, what
/// have I not played — therefore has to name a user explicitly, and the
/// endpoints that need one 404 rather than defaulting when it is missing.
///
/// That is why [viewerId] threads through the browse methods and why
/// `settings.jellyfinUserId` is a first-class setting rather than an optional
/// nicety. It is also the asymmetry the Stream contract was built around: a Plex
/// token *is* a user and cannot impersonate, an API key is nobody and must.
///
/// ## Units
///
/// Four of them, all in `jellyfin_units.dart`; nothing in this file divides by a
/// magic constant.
class JellyfinClient implements StreamServerClient {
  /// [userId] is the household member whose watch state the per-viewer lenses
  /// read by default (`settings.jellyfinUserId`); a per-call `viewerId` overrides
  /// it.
  ///
  /// [clientName], [deviceName], [deviceId] and [appVersion] only decorate the
  /// `Authorization` header — Jellyfin requires none of them functionally, and
  /// they exist so the server's Dashboard → Devices list names Cupola instead of
  /// showing an anonymous row.
  JellyfinClient({
    required String baseUrl,
    required String apiKey,
    String userId = '',
    String clientName = kJellyfinClientName,
    String? deviceName,
    String? deviceId,
    String appVersion = kJellyfinClientVersion,
    String? pinnedCertFingerprint,
  }) : _baseUrl = UrlUtils.normalizeBaseUrl(baseUrl),
       _userId = userId.trim(),
       _authHeader = buildJellyfinAuthorizationHeader(
         token: apiKey.trim(),
         client: clientName,
         device: deviceName ?? defaultJellyfinDeviceName(),
         deviceId: deviceId ?? defaultJellyfinDeviceId(deviceName),
         version: appVersion,
       ) {
    // `ApiClient.authenticatedBy` rather than a bespoke `Dio`: it carries the
    // shared timeouts and, decisively, `SameOriginRedirectInterceptor`. Without
    // that interceptor a single 302 from a misconfigured reverse proxy would
    // replay the `Authorization` header — a full-privilege admin key — to a host
    // the user never configured.
    _api = ApiClient.authenticatedBy(
      baseUrl: _baseUrl,
      headers: {'Authorization': _authHeader},
      pinnedCertFingerprint: pinnedCertFingerprint,
    );
  }

  final String _baseUrl;
  final String _userId;
  final String _authHeader;
  late final ApiClient _api;

  /// How far back a client counts as "active".
  ///
  /// `/Sessions` otherwise includes every client that has ever connected and not
  /// been reaped, so a phone that watched something last Tuesday shows up as a
  /// live row. Three minutes is long enough to survive a paused stream's
  /// keep-alive gap and short enough that a closed app disappears promptly.
  static const int kActiveWithinSeconds = 180;

  /// Requested on every browse call.
  ///
  /// `PrimaryImageAspectRatio` lets a poster reserve its box before the bytes
  /// arrive; `Overview` is what an item detail opens with, and asking for it here
  /// means a tap on a grid tile can render text immediately instead of waiting
  /// for `/Items/{id}`.
  static const String _browseFields = 'PrimaryImageAspectRatio,Overview';

  /// Lets a test swap in a stubbed transport, exactly as the per-service clients
  /// do with an injected `Dio` — and lets it assert on the real request this
  /// client builds, headers included.
  ///
  /// Propagating [ApiClient]'s own test seam rather than taking a `Dio` in the
  /// constructor: an injected transport would come pre-built with whatever headers
  /// the *test* chose, and then "the `Authorization` header is exactly right on
  /// the wire" would only ever be asserting about the test's own string. This
  /// getter keeps header construction where it belongs and still stubs the socket.
  /// Marked `@visibleForTesting` in turn, so nothing in `lib/` can reach through
  /// it either.
  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  Dio get dio => _api.dio;

  /// `CollectionType`-derived kinds, cached from [getLibraries].
  ///
  /// Used to constrain a browse to the item type a library is *about*:
  /// `recursive=true` is required to see items rather than folders, but on a TV
  /// library it also returns every season and every episode, so an A–Z page would
  /// interleave 12 series with 400 episodes. Populated lazily on a deep link
  /// (where the library list was never loaded) so
  /// `/services/jellyfin/library/<id>` still resolves from the path alone.
  final Map<String, StreamLibraryKind> _libraryKinds = {};

  /// The in-flight (or completed) lazy library lookup, so several lenses opening
  /// at once share one request instead of each firing its own.
  Future<List<StreamLibrary>>? _libraryKindLookup;

  @override
  Future<String?> probeVersion() async {
    try {
      // The credential-free endpoint on purpose: "the box is down" and "the
      // token is wrong" must not arrive as the same error. It can also answer 503
      // with a `Retry-After` while the server is still starting, which lands in
      // the catch below as "no version yet" rather than as a hard failure.
      final response = await _api.get('/System/Info/Public');
      final data = response.data;
      if (data is! Map) return null;
      final info = JellyfinPublicSystemInfo.fromJson(
        data.cast<String, dynamic>(),
      );
      return info.isJellyfin ? info.version : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> verifyCredential() async {
    try {
      // The authenticated twin of the public probe: 401 means the token is
      // absent or wrong, 403 means it is valid but under-privileged. Both are
      // "no" here, and a caller that wants to tell an unreachable host apart
      // pairs this with [probeVersion].
      final response = await _api.get('/System/Info');
      final code = response.statusCode ?? 0;
      return code >= 200 && code < 300;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<StreamSession>> getSessions() async {
    try {
      final response = await _api.get(
        '/Sessions',
        queryParameters: {'activeWithinSeconds': kActiveWithinSeconds},
      );
      return _mapInIsolate(response.data, jellyfinStreamSessionsFromJson);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> stopSession(String sessionId) async {
    // A write action, so the error surfaces — the UI needs to say "the stop did
    // not go through". Note the 204 means *dispatched*, not stopped: the client
    // may ignore the command, which is why callers re-read [getSessions] instead
    // of trusting this returning normally.
    await _api.post('/Sessions/$sessionId/Playing/Stop');
  }

  @override
  Future<List<StreamLibrary>> getLibraries() async {
    try {
      final response = await _api.get('/Library/VirtualFolders');
      final folders = jellyfinVirtualFoldersFromJson(response.data);
      final libraries = <StreamLibrary>[];
      for (final folder in folders) {
        // A library with no `ItemId` cannot be browsed or rescanned — there is
        // nothing to pass as `parentId` — so listing it would only offer a dead
        // end. This happens on a folder added to the config but never scanned.
        if (folder.itemId.isEmpty) continue;
        final library = folder.toStreamLibrary();
        _libraryKinds[library.id] = library.kind;
        libraries.add(library);
      }
      return libraries;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> refreshLibrary(String libraryId) async {
    // `metadataRefreshMode` and `imageRefreshMode` both default to `None`, so
    // omitting them queues a task that does *nothing* and still answers 204 —
    // the single most misleading default in this API.
    //
    // `Default` scans for new and changed files; `FullRefresh` re-downloads
    // metadata for everything, which is not what "rescan this library" means and
    // would hammer the metadata providers.
    await _api.post(
      '/Items/$libraryId/Refresh',
      queryParameters: {
        'metadataRefreshMode': 'Default',
        'imageRefreshMode': 'Default',
        'replaceAllMetadata': false,
        'replaceAllImages': false,
      },
    );
  }

  /// [cancelToken] is an addition to the interface, not part of it — an override
  /// may widen its signature with optional parameters, and the project's rule is
  /// that list fetches are cancellable. A page scrolled past mid-flight is a real
  /// case here: the browse is paged, Riverpod disposes the provider for a page
  /// that leaves the viewport, and the in-flight request should go with it.
  @override
  Future<List<StreamItem>> getLibraryItems({
    required String libraryId,
    required StreamLibraryLens lens,
    String? viewerId,
    int startIndex = 0,
    int limit = 50,
    CancelToken? cancelToken,
  }) async {
    final page = await getLibraryPage(
      libraryId: libraryId,
      lens: lens,
      viewerId: viewerId,
      startIndex: startIndex,
      limit: limit,
      cancelToken: cancelToken,
    );
    return page.items;
  }

  @override
  Future<StreamLibraryPage> getLibraryPage({
    required String libraryId,
    required StreamLibraryLens lens,
    String? viewerId,
    int startIndex = 0,
    int limit = 50,
    CancelToken? cancelToken,
  }) async {
    final userId = _resolveViewerId(viewerId);
    // The genuinely per-viewer lenses are user-scoped end to end, and the
    // endpoints behind them 404 without a userId rather than falling back to the
    // token's own identity — the API key has none. Saying so is the point:
    // returning a bare empty list here is what made the browse claim the library
    // was empty when the user had simply not picked a household member yet.
    //
    // `all` is deliberately not in that set — see [StreamLibraryLens.isPerViewer].
    if (userId == null && lens.isPerViewer) {
      return const StreamLibraryPage.viewerRequired();
    }

    try {
      // Only the `/Items` lenses take `includeItemTypes`, so only they need the
      // library's kind.
      if (lens == StreamLibraryLens.recentlyAdded ||
          lens == StreamLibraryLens.unplayed ||
          lens == StreamLibraryLens.all) {
        await _ensureLibraryKind(libraryId);
      }

      final _JellyfinItemsPage page;
      switch (lens) {
        case StreamLibraryLens.continueWatching:
          // `/UserItems/Resume` replaces the deprecated
          // `/Users/{userId}/Items/Resume` and is always sorted by DatePlayed
          // desc, so no sort parameters are sent. `excludeActiveSessions` keeps
          // the item somebody is watching *right now* out of their own
          // continue-watching row, where it would be a duplicate of the session
          // board.
          page = await _fetchItemsPage('/UserItems/Resume', {
            'userId': userId,
            'parentId': libraryId,
            'startIndex': startIndex,
            'limit': limit,
            'fields': _browseFields,
            'enableUserData': true,
            'excludeActiveSessions': true,
          }, cancelToken: cancelToken);
        case StreamLibraryLens.nextUp:
          page = await _fetchItemsPage('/Shows/NextUp', {
            'userId': userId,
            'parentId': libraryId,
            'startIndex': startIndex,
            'limit': limit,
            'fields': _browseFields,
            'enableUserData': true,
            // Default anyway, but explicit: "next up" must not resurface a
            // series the viewer already finished.
            'enableRewatching': false,
          }, cancelToken: cancelToken);
        case StreamLibraryLens.recentlyAdded:
          page = await _fetchItemsPage('/Items', {
            ..._itemsBaseQuery(libraryId, userId, startIndex, limit),
            'sortBy': 'DateCreated',
            'sortOrder': 'Descending',
          }, cancelToken: cancelToken);
        case StreamLibraryLens.unplayed:
          page = await _fetchItemsPage('/Items', {
            ..._itemsBaseQuery(libraryId, userId, startIndex, limit),
            'isPlayed': false,
            'sortBy': 'SortName',
            'sortOrder': 'Ascending',
          }, cancelToken: cancelToken);
        case StreamLibraryLens.all:
          page = await _fetchItemsPage('/Items', {
            ..._itemsBaseQuery(libraryId, userId, startIndex, limit),
            'sortBy': 'SortName',
            'sortOrder': 'Ascending',
          }, cancelToken: cancelToken);
      }
      return page.toLibraryPage(startIndex);
    } catch (_) {
      return StreamLibraryPage.failed(startIndex: startIndex);
    }
  }

  @override
  Future<StreamItem?> getItem(
    String itemId, {
    String? viewerId,
    CancelToken? cancelToken,
  }) async {
    // `userId` is optional on `GET /Items/{itemId}` — it is a `Guid?`, and
    // omitting it costs the `UserData` block (played flag, resume point) and
    // nothing else. Refusing to call at all without one is what made a deep link
    // into `/services/jellyfin/item/<id>` render "Not on the server" on an
    // install where the item plainly was, before the household member had been
    // chosen in settings.
    final userId = _resolveViewerId(viewerId);
    try {
      final item = await _fetchRawItem(
        itemId,
        userId,
        cancelToken: cancelToken,
      );
      return item == null ? null : jellyfinStreamItemFromJson(item);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<StreamItem?> findByExternalId({
    String? tmdbId,
    String? tvdbId,
    String? imdbId,
    CancelToken? cancelToken,
  }) async {
    // `anyProviderIdEquals` takes `provider.value` pairs; passing several is an
    // OR, which is what we want — an arr may know a film by TMDB and a series by
    // TVDB, and either identifies the same thing here.
    final pairs = <String>[
      if (tmdbId != null && tmdbId.isNotEmpty) 'tmdb.$tmdbId',
      if (tvdbId != null && tvdbId.isNotEmpty) 'tvdb.$tvdbId',
      if (imdbId != null && imdbId.isNotEmpty) 'imdb.$imdbId',
    ];
    if (pairs.isEmpty) return null;

    // A viewer is a bonus here, not a precondition. Without one `/Items` still
    // answers "is this in the library", which is the media server's own fact and
    // the one the availability slot needs to exist; what is lost is the watch
    // state, so the slot reads "Ready to watch" rather than "34 min in". Bailing
    // out without a viewer made the slot Plex-only in practice.
    final userId = _resolveViewerId(null);

    try {
      final items = await _fetchItems('/Items', {
        'recursive': true,
        'anyProviderIdEquals': pairs.join(','),
        'limit': 1,
        'fields': _browseFields,
        // `UserData` is omitted from the response entirely unless both are
        // present, so they travel together or not at all.
        if (userId != null) 'userId': userId,
        if (userId != null) 'enableUserData': true,
      }, cancelToken: cancelToken);
      return items.isEmpty ? null : items.first;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<StreamItem>> getChildren(
    String itemId, {
    String? viewerId,
    CancelToken? cancelToken,
  }) async {
    final userId = _resolveViewerId(viewerId);
    if (userId == null) return const [];

    try {
      // The interface takes an id and nothing else, so that a detail route can be
      // reached from a deep link — which means the kind has to be discovered
      // here. It cannot be inferred from the id (every id is a GUID) and the
      // three shapes need three different endpoints, one of which needs an id
      // this method was not given: `/Shows/{seriesId}/Episodes` wants the
      // **series**, even when listing a single season, and a season id does not
      // contain its parent's.
      final item = await _fetchRawItem(
        itemId,
        userId,
        cancelToken: cancelToken,
      );
      if (item == null) return const [];

      final kind = jellyfinItemKind(item['Type']);
      switch (kind) {
        case StreamItemKind.series:
          // Unpaged by design — `/Shows/{id}/Seasons` takes no startIndex or
          // limit. A series has tens of seasons at worst.
          return await _fetchItems('/Shows/$itemId/Seasons', {
            'userId': userId,
            'enableUserData': true,
            'fields': _browseFields,
          }, cancelToken: cancelToken);
        case StreamItemKind.season:
          final seriesId = item['SeriesId']?.toString() ?? '';
          if (seriesId.isEmpty) return const [];
          return await _fetchItems('/Shows/$seriesId/Episodes', {
            'userId': userId,
            'seasonId': itemId,
            'enableUserData': true,
            'fields': _browseFields,
            // A single value, not a CSV, unlike `/Items`. Aired order is what an
            // episode list means; `SortName` would order "Episode 10" before
            // "Episode 2".
            'sortBy': 'AiredEpisodeOrder',
          }, cancelToken: cancelToken);
        case StreamItemKind.album:
          return await _fetchItems('/Items', {
            'userId': userId,
            'parentId': itemId,
            'recursive': false,
            'enableUserData': true,
            'fields': _browseFields,
            // Disc, then track. `SortName` on an album is alphabetical, which is
            // never what a track listing wants.
            'sortBy': 'ParentIndexNumber,IndexNumber,SortName',
            'sortOrder': 'Ascending',
          }, cancelToken: cancelToken);
        case StreamItemKind.movie:
        case StreamItemKind.episode:
        case StreamItemKind.track:
        case StreamItemKind.other:
          // A leaf. No request at all rather than one that returns an empty page.
          return const [];
      }
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<StreamViewer>> getViewers() async {
    try {
      final response = await _api.get('/Users');
      final users = jellyfinUsersFromJson(response.data);
      return users
          // A disabled account cannot watch anything, so offering it as a lens
          // would only ever produce empty rows. Filtered here rather than with
          // the `isDisabled` query parameter because that filter's polarity
          // changed across 10.x and an empty viewer list is a much worse failure
          // than one extra row.
          .where((user) => !user.isDisabled && user.id.isNotEmpty)
          .map((user) => user.toStreamViewer())
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  StreamImageSource? imageFor(String posterPath, {int? width}) {
    final path = posterPath.trim();
    if (path.isEmpty) return null;

    // A bare id rather than a path: a deep-linked detail screen knows the item
    // but not its artwork tag yet. Untagged, so it is cacheable but not
    // cache-busted — the tagged form from `jellyfinPosterPath` is preferred
    // everywhere it is available.
    final relative = path.contains('/') ? path : '/Items/$path/Images/Primary';

    if (relative.startsWith('http://') || relative.startsWith('https://')) {
      // Already absolute: hand it back without the credential. Jellyfin never
      // produces one of these, and attaching an admin key to a URL that might
      // point anywhere is not a risk worth taking for a poster.
      return (url: relative, headers: null);
    }

    final uri = Uri.parse(UrlUtils.buildUrl(_baseUrl, relative));
    final query = {
      ...uri.queryParameters,
      if (width != null && width > 0) 'maxWidth': '$width',
    };

    // The credential travels as a header, never in the query string: a token in
    // the URL becomes part of `CachedNetworkImage`'s cache key, which puts it in
    // a file name on disk and in every log line that records the request.
    return (
      url: uri
          .replace(queryParameters: query.isEmpty ? null : query)
          .toString(),
      headers: {'Authorization': _authHeader},
    );
  }

  @override
  void close() => _api.close();

  /// Makes sure [libraryId]'s kind is known, fetching the library list once when
  /// it is not.
  ///
  /// The dashboard always lists libraries before a browse opens, so this is a
  /// no-op in the normal flow. It exists for the deep link: a detail route has to
  /// resolve from its path parameters alone, and `/services/jellyfin/library/<id>`
  /// arrives with no prior `getLibraries` call.
  Future<void> _ensureLibraryKind(String libraryId) async {
    if (_libraryKinds.containsKey(libraryId)) return;
    final lookup = _libraryKindLookup ??= getLibraries();
    final libraries = await lookup;
    // An empty result means the lookup failed (it degrades rather than throwing).
    // Caching that would leave every browse unfiltered for the life of the
    // client, so the next call is allowed to try again.
    if (libraries.isEmpty) _libraryKindLookup = null;
  }

  /// Shared `/Items` parameters for the three non-personal lenses.
  Map<String, dynamic> _itemsBaseQuery(
    String libraryId,
    String? userId,
    int startIndex,
    int limit,
  ) {
    final includeItemTypes = _includeItemTypesFor(libraryId);
    return {
      'parentId': libraryId,
      // Without this, `/Items` returns the library's *folders* rather than what
      // is in them.
      'recursive': true,
      'startIndex': startIndex,
      'limit': limit,
      'fields': _browseFields,
      'enableImages': true,
      if (includeItemTypes != null) 'includeItemTypes': includeItemTypes,
      // `UserData` is omitted from the response entirely unless both of these are
      // present, and without it every item reads as unwatched with no resume
      // point. Passed even on `recentlyAdded`, which does not *need* a viewer, so
      // that the row still shows progress for the configured one.
      if (userId != null) 'userId': userId,
      if (userId != null) 'enableUserData': true,
    };
  }

  /// The item type a library is about, or null when it is unknown or mixed.
  String? _includeItemTypesFor(String libraryId) {
    switch (_libraryKinds[libraryId]) {
      case StreamLibraryKind.movies:
        return 'Movie';
      case StreamLibraryKind.shows:
        // Series, not Episode: a TV library browses as shows. The episodes are
        // reached through [getChildren], two taps deeper.
        return 'Series';
      case StreamLibraryKind.music:
        return 'MusicAlbum';
      case StreamLibraryKind.photos:
      case StreamLibraryKind.other:
      case null:
        // Unknown or genuinely mixed: no filter is better than a wrong one, which
        // would render an empty library.
        return null;
    }
  }

  Future<List<StreamItem>> _fetchItems(
    String path,
    Map<String, dynamic> queryParameters, {
    CancelToken? cancelToken,
  }) async {
    final page = await _fetchItemsPage(
      path,
      queryParameters,
      cancelToken: cancelToken,
    );
    return page.items;
  }

  /// [_fetchItems] with the `BaseItemDtoQueryResult` envelope kept.
  ///
  /// [_JellyfinItemsPage.rows] is the count the *server* sent, before mapping
  /// dropped anything, because that is what a pager has to advance by.
  Future<_JellyfinItemsPage> _fetchItemsPage(
    String path,
    Map<String, dynamic> queryParameters, {
    CancelToken? cancelToken,
  }) async {
    final response = await _api.get(
      path,
      queryParameters: {
        for (final entry in queryParameters.entries)
          if (entry.value != null) entry.key: entry.value,
      },
      cancelToken: cancelToken,
    );
    final data = response.data;
    // Every paged endpoint answers `BaseItemDtoQueryResult`; the unpaged ones
    // (`/Shows/{id}/Seasons`) also wrap their array in `Items`, but a bare array
    // has shown up behind reverse proxies that unwrap single-key objects, so both
    // shapes are accepted.
    final raw = data is Map ? data['Items'] : data;
    return (
      items: await _mapInIsolate(raw, jellyfinStreamItemsFromJson),
      rows: raw is List ? raw.length : 0,
      // Absent on the unwrapped shape and on some builds of `/Shows/NextUp`,
      // which is why it is nullable rather than defaulted — see
      // [_JellyfinItemsPage.toLibraryPage].
      total: data is Map ? _asInt(data['TotalRecordCount']) : null,
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Future<Map<String, dynamic>?> _fetchRawItem(
    String itemId,
    String? userId, {
    CancelToken? cancelToken,
  }) async {
    // `fields` is ignored by this endpoint — it always returns the full DTO
    // including MediaSources, MediaStreams and People — so none is sent.
    final response = await _api.get(
      '/Items/$itemId',
      queryParameters: {if (userId != null) 'userId': userId},
      cancelToken: cancelToken,
    );
    final data = response.data;
    return data is Map ? data.cast<String, dynamic>() : null;
  }

  /// The viewer a per-user query should be issued for: the explicit argument,
  /// else the configured household member, else nobody.
  String? _resolveViewerId(String? viewerId) {
    final explicit = viewerId?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;
    return _userId.isEmpty ? null : _userId;
  }

  /// Maps a decoded list, moving to an isolate once the page is big enough to
  /// drop a frame.
  ///
  /// [mapper] must be a top-level function: `Isolate.run` sends the closure, and
  /// one that captured `this` would drag a `Dio` across the port and throw.
  static Future<List<T>> _mapInIsolate<T>(
    Object? raw,
    List<T> Function(Object?) mapper,
  ) async {
    if (raw is! List) return const [];
    if (raw.length <= kJellyfinIsolateMapThreshold) return mapper(raw);
    return Isolate.run(() => mapper(raw));
  }
}

/// A `BaseItemDtoQueryResult` reduced to what a pager needs.
///
/// [rows] is the number of elements the *server* sent, which is deliberately not
/// `items.length`: mapping drops anything malformed, and a page whose rows all
/// failed to parse still has to move the offset forward rather than declare the
/// library finished.
typedef _JellyfinItemsPage = ({List<StreamItem> items, int rows, int? total});

extension _JellyfinItemsPageX on _JellyfinItemsPage {
  StreamLibraryPage toLibraryPage(int startIndex) {
    final nextStartIndex = startIndex + rows;
    final total = this.total;
    return StreamLibraryPage(
      items: items,
      nextStartIndex: nextStartIndex,
      // With a `TotalRecordCount` this is arithmetic. Without one — the
      // unwrapped shape, and some builds of `/Shows/NextUp` — the only honest
      // signal is "the server sent rows", so the pager asks once more and stops
      // on the empty answer.
      hasMore: total == null ? rows > 0 : nextStartIndex < total,
    );
  }
}

/// What Jellyfin's Dashboard → Devices list calls this app.
const String kJellyfinClientName = 'Cupola';

/// Sent as `Version` in the `Authorization` header. Cosmetic — it appears beside
/// the client name in the server's device list — and tracks `pubspec.yaml`.
const String kJellyfinClientVersion = '0.8.0';

/// The `Device` value: which platform this install is.
String defaultJellyfinDeviceName() => Platform.operatingSystem;

/// A `DeviceId` that is stable for the life of the install without storing
/// anything.
///
/// Jellyfin registers a device row per distinct id it sees, so a value
/// regenerated each launch would litter the user's dashboard with a permanent
/// row per app start — the same trap `settings.plexClientId` exists to avoid.
/// Plex needed a persisted random identifier because its id is also an identity;
/// Jellyfin's is only a label, and an API key creates no session against it at
/// all, so deriving it deterministically is enough and costs no settings field
/// (and no `uuid` dependency, which this project does not have).
///
/// Hashed rather than used raw so the value looks like the opaque id the API
/// expects and carries nothing about the host.
String defaultJellyfinDeviceId([String? deviceName]) {
  final seed = 'cupola.jellyfin:${deviceName ?? defaultJellyfinDeviceName()}';
  return sha256.convert(seed.codeUnits).toString().substring(0, 32);
}

/// Builds the only non-deprecated Jellyfin auth header in 10.11.
///
/// ```
/// Authorization: MediaBrowser Token="…", Client="Cupola", Device="macos",
///                DeviceId="…", Version="0.8.0"
/// ```
///
/// `AuthorizationContext` parses the scheme word case-insensitively, then splits
/// on commas into `Key="Value"` pairs. Three details are load-bearing:
///
///  * the keys are **case-sensitive** (`token=` is not read);
///  * the values **must** be double-quoted;
///  * the values are **URL-decoded** by the server, so any comma or quote inside
///    one has to be percent-encoded — an unencoded comma in a client name would
///    otherwise split the pair and silently drop the credential that follows it.
///
/// Only `Token` is functionally required; the rest is what makes the server's
/// device list legible.
String buildJellyfinAuthorizationHeader({
  required String token,
  required String client,
  required String device,
  required String deviceId,
  required String version,
}) {
  final pairs = <String, String>{
    'Token': token,
    'Client': client,
    'Device': device,
    'DeviceId': deviceId,
    'Version': version,
  };
  final encoded = pairs.entries
      .where((entry) => entry.value.isNotEmpty)
      // `Uri.encodeComponent` escapes `,` as `%2C` and `"` as `%22`, which is
      // exactly what the server's `UrlDecode` on each value expects back.
      .map((entry) => '${entry.key}="${Uri.encodeComponent(entry.value)}"')
      .join(', ');
  return 'MediaBrowser $encoded';
}
