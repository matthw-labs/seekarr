import 'dart:convert';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:seekarr/core/api/api_client.dart';
import 'package:seekarr/core/network/connection_failure.dart';
import 'package:seekarr/core/utils/url_utils.dart';
import 'package:seekarr/features/plex/domain/models/plex_models.dart';
import 'package:seekarr/features/plex/domain/models/plex_transcode_session.dart';
import 'package:seekarr/features/stream/domain/models/stream_item.dart';
import 'package:seekarr/features/stream/domain/models/stream_library.dart';
import 'package:seekarr/features/stream/domain/models/stream_library_page.dart';
import 'package:seekarr/features/stream/domain/models/stream_session.dart';
import 'package:seekarr/features/stream/domain/stream_server_client.dart';

/// Identifies Seekarr to the user's server. Plex shows this in
/// Settings → Authorized Devices, so it is a name a stranger has to recognise as
/// theirs.
const String kPlexProduct = 'Seekarr';

/// Sent as `X-Plex-Version`. Tracks `pubspec.yaml`'s `version:` by hand — the
/// project takes no new dependencies, and `package_info_plus` would be one.
const String kPlexProductVersion = '0.8.0';

/// Sent as `X-Plex-Device-Name`, i.e. the row label in Authorized Devices.
const String kPlexDeviceName = 'Seekarr';

/// The reason attached to a terminate call.
///
/// Plex forwards this string to the player, where the viewer sees it as the
/// explanation for their stream stopping. It is therefore an API payload rather
/// than app chrome, which is why it lives here and not in a widget.
const String kPlexTerminationReason = 'Stopped from Seekarr';

/// Poster aspect used when asking Plex's photo transcoder to resize.
///
/// [StreamServerClient.imageFor] offers a width only, and `/photo/:/transcode`
/// requires both dimensions. With `minSize=1` Plex fits the image inside the box
/// preserving its own aspect, so this is a bounding height rather than a crop —
/// 2:3 is the poster ratio every library in the app already lays out to.
const double _kPosterHeightRatio = 3 / 2;

/// Default page size for a library browse.
const int kPlexLibraryPageSize = 50;

/// Plex's own type ids for `/library/sections/{id}/all?type=`.
const int _kPlexTypeMovie = 1;
const int _kPlexTypeShow = 2;
const int _kPlexTypeArtist = 8;

/// Plex's non-standard "token expired" status, alongside the ordinary 401.
const int _kPlexTokenExpiredStatus = 498;

/// What the user has to fix when a reply is not JSON.
///
/// Plex answers XML unless `Accept: application/json` reaches it, so naming XML
/// is the whole point of the message: the two things the user can act on are the
/// address and whatever sits between here and it rewriting the header. Shared so
/// the two places that detect it — a body `jsonDecode` refuses, and a body Dio's
/// own transformer refused before this file ever saw it — say the same thing.
/// The third case, a body that visibly starts with `<`, gets its own wording
/// because there the XML is not a guess.
const String kPlexNotJsonMessage =
    'The server did not answer JSON. Plex serves XML unless the Accept header '
    'reaches it, so check that the address points at Plex Media Server and that '
    'nothing between here and it rewrites Accept.';

/// Row count above which a `Metadata` array is mapped off the main isolate.
///
/// Below it the isolate spawn costs more than the mapping does — a season of
/// episodes or a hub row is a handful of objects, while a `titleSort` page of a
/// film library is hundreds, each with nested `Media`/`Part`/`Stream` arrays.
const int _kIsolateMappingThreshold = 50;

/// Error thrown by [PlexClient].
///
/// Carries [reason] so onboarding can distinguish an unreachable box from a
/// rejected token, and [tokenIssue] so it can distinguish *which* token problem —
/// a 401 asks for a fresh paste, whereas a JWT can never be made to work here at
/// all and the user needs different advice.
class PlexException implements Exception, HasFailureReason {
  const PlexException(
    this.message, {
    this.reason = ServiceFailureReason.unknown,
    this.tokenIssue = PlexTokenIssue.none,
  });

  final String message;

  @override
  final ServiceFailureReason reason;

  final PlexTokenIssue tokenIssue;

  @override
  String toString() => 'PlexException: $message';
}

/// Plex Media Server client.
///
/// **Never contacts plex.tv.** Every capability below is served by the box the
/// user pasted an address for: `/identity` for reachability, `/` for the
/// capability sheet, `/status/sessions` for live playback, `/library/*` for the
/// collection. That constraint is what shapes the two visible asymmetries with
/// Jellyfin — [getViewers] returns exactly one person, and [verifyCredential]
/// refuses a JWT outright instead of refreshing it — because both would
/// otherwise require a plex.tv round trip.
///
/// Transport is [ApiClient.authenticatedBy] rather than a bespoke `Dio`, which
/// is not a stylistic choice: it carries `SameOriginRedirectInterceptor`, and
/// without it a single 302 from a misconfigured reverse proxy would replay the
/// user's `X-Plex-Token` to a host they never configured.
class PlexClient implements StreamServerClient {
  PlexClient({
    required String url,
    required String token,
    required String clientIdentifier,
    String product = kPlexProduct,
    String productVersion = kPlexProductVersion,
    String? platform,
    String deviceName = kPlexDeviceName,
    String? pinnedCertFingerprint,
  }) : baseUrl = UrlUtils.normalizeBaseUrl(url),
       _token = token.trim(),
       _clientIdentifier = clientIdentifier.trim(),
       _product = product,
       _productVersion = productVersion,
       _platform = platform ?? _defaultPlatform(),
       _deviceName = deviceName {
    _api = ApiClient.authenticatedBy(
      baseUrl: baseUrl,
      headers: _headers(),
      pinnedCertFingerprint: pinnedCertFingerprint,
    );
  }

  final String baseUrl;
  final String _token;
  final String _clientIdentifier;
  final String _product;
  final String _productVersion;
  final String _platform;
  final String _deviceName;

  late final ApiClient _api;

  /// Section id → kind, filled by [getLibraries].
  ///
  /// A lens has to know whether a section holds films or shows before it can be
  /// expressed as a filter — `unwatched=1` is the movie form and
  /// `show.unwatchedLeaves=1` the show form, and sending the wrong one returns
  /// the whole library instead of an error. Caching the answer keeps a browse
  /// from re-reading `/library/sections` on every page.
  final Map<String, StreamLibraryKind> _sectionKinds = {};

  /// Lets a test attach a stubbed transport while leaving the header building —
  /// the part most worth asserting on — under test.
  @visibleForTesting
  ApiClient get api => _api;

  /// The client-identity headers Plex expects on **every** request.
  ///
  /// `X-Plex-Client-Identifier` is the one that matters operationally: Plex
  /// registers a new device row per distinct value, so it comes from persisted
  /// settings rather than being minted here. `Accept: application/json` is
  /// supplied by [ApiClient] and is mandatory — the API answers XML by default,
  /// and every parse in this file would fail on it.
  Map<String, String> _headers() {
    return {
      // Omitted rather than sent empty when there is no token yet, so an
      // onboarding reachability probe against `/identity` is a clean
      // unauthenticated request instead of one carrying a blank credential.
      if (_token.isNotEmpty) 'X-Plex-Token': _asciiHeader(_token),
      'X-Plex-Client-Identifier': _asciiHeader(_clientIdentifier),
      'X-Plex-Product': _asciiHeader(_product),
      'X-Plex-Version': _asciiHeader(_productVersion),
      'X-Plex-Platform': _asciiHeader(_platform),
      'X-Plex-Device-Name': _asciiHeader(_deviceName),
    };
  }

  /// Headers that authenticate an artwork request.
  ///
  /// The token stays in a header so it never reaches `CachedNetworkImage`'s
  /// cache key, which is the resolved URL — a token in the query string would be
  /// written to the on-disk cache index and invalidate every cached poster the
  /// day the user rotates it.
  Map<String, String> get _imageHeaders => {
    if (_token.isNotEmpty) 'X-Plex-Token': _asciiHeader(_token),
    'X-Plex-Client-Identifier': _asciiHeader(_clientIdentifier),
  };

  /// Strips everything outside printable ASCII from a header value.
  ///
  /// Two reasons, both real. `dart:io` writes header values as Latin-1 and
  /// throws on anything it cannot encode, so a non-ASCII device name would turn
  /// every request into a `FormatException` rather than a connection error. And
  /// dropping CR/LF closes header injection on the two values that come from
  /// outside this file — the pasted token and the persisted client id.
  static String _asciiHeader(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      if (rune >= 0x20 && rune <= 0x7e) buffer.writeCharCode(rune);
    }
    return buffer.toString().trim();
  }

  /// What Plex should call this platform in Authorized Devices.
  static String _defaultPlatform() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'iOS';
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.macOS:
        return 'macOS';
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.linux:
        return 'Linux';
      case TargetPlatform.fuchsia:
        return 'Fuchsia';
    }
  }

  // ---------------------------------------------------------------------------
  // Transport
  // ---------------------------------------------------------------------------

  /// Fetches [path] and returns its `MediaContainer`.
  ///
  /// Every Plex response is wrapped in one, including the ones that carry only
  /// attributes (`/identity`, `/`), so unwrapping in one place is what keeps the
  /// twelve call sites below from each re-deciding what a malformed reply means.
  Future<Map<String, dynamic>> _container(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _api.get(
        path,
        queryParameters: queryParameters,
        cancelToken: cancelToken,
      );
      return _mediaContainer(response.data);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  static Map<String, dynamic> _mediaContainer(dynamic raw) {
    var decoded = raw;
    if (decoded is String) {
      final text = decoded.trimLeft();
      // Plex serves XML unless `Accept: application/json` is honoured. Reaching
      // here means either the header was stripped in transit — a reverse proxy
      // that rewrites Accept — or the address points at something that is not a
      // Plex server. Both are configuration problems, and saying so beats the
      // `FormatException` a bare `jsonDecode` would raise.
      if (text.startsWith('<')) {
        throw const PlexException(
          'The server answered XML instead of JSON. Check that the address '
          'points at Plex and that nothing between here and it rewrites the '
          'Accept header.',
          reason: ServiceFailureReason.notFound,
        );
      }
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        throw const PlexException(
          kPlexNotJsonMessage,
          reason: ServiceFailureReason.notFound,
        );
      }
    }
    if (decoded is Map) {
      final container = decoded['MediaContainer'];
      if (container is Map) return container.cast<String, dynamic>();
    }
    throw const PlexException(
      'The Plex API did not answer at this address.',
      reason: ServiceFailureReason.notFound,
    );
  }

  PlexException _mapDioError(DioException error) {
    final status = error.response?.statusCode;
    // A body Dio could not decode. Reached when a reverse proxy labels an XML
    // reply `application/json`, in which case Dio's transformer fails before
    // [_mediaContainer] can see the leading `<` and explain it.
    if (error.error is FormatException) {
      return const PlexException(
        kPlexNotJsonMessage,
        reason: ServiceFailureReason.notFound,
      );
    }
    if (status == 401 || status == _kPlexTokenExpiredStatus) {
      return const PlexException(
        'Plex rejected the token. Copy a fresh X-Plex-Token from the server '
        'and paste it again.',
        reason: ServiceFailureReason.unauthorized,
        tokenIssue: PlexTokenIssue.rejected,
      );
    }
    return PlexException(
      error.message ?? 'Plex request failed',
      reason: classifyConnectionFailure(error),
    );
  }

  /// Refuses to send a token that cannot work, before it is sent.
  ///
  /// A plex.tv JWT authenticates for seven days and is refreshable only through
  /// plex.tv, which this client will not call. Letting it through would buy a
  /// week of working software followed by a failure the user has no way to read.
  void _assertUsableToken() {
    if (inspectPlexToken(_token) == PlexTokenIssue.jsonWebToken) {
      throw const PlexException(
        'That is a temporary plex.tv sign-in token: it expires in seven days '
        'and can only be renewed by plex.tv, which Seekarr never contacts. '
        'Paste a device token from your server instead.',
        reason: ServiceFailureReason.unauthorized,
        tokenIssue: PlexTokenIssue.jsonWebToken,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Reachability and credential
  // ---------------------------------------------------------------------------

  /// `GET /identity` — the only Plex endpoint that needs no credential.
  ///
  /// Using it means "the box is down" and "the token is wrong" can never arrive
  /// as the same error: this answers 200 for a valid address regardless of the
  /// token, so a null here is always about reachability.
  @override
  Future<String?> probeVersion() async {
    try {
      return (await getIdentity())?.version;
    } catch (_) {
      return null;
    }
  }

  Future<PlexServerIdentity?> getIdentity() async {
    try {
      return PlexServerIdentity.fromMediaContainer(
        await _container('/identity'),
      );
    } catch (_) {
      return null;
    }
  }

  /// Whether the token is accepted, via `GET /` — which 401s on a bad one.
  ///
  /// Returns false only for an actual refusal. A timeout or a DNS failure
  /// rethrows, because answering "the credential is wrong" to an unreachable
  /// host is how a user ends up rotating a token that was never the problem.
  @override
  Future<bool> verifyCredential() async {
    _assertUsableToken();
    if (_token.isEmpty) return false;
    try {
      await _container('/');
      return true;
    } on PlexException catch (e) {
      if (e.tokenIssue == PlexTokenIssue.rejected) return false;
      rethrow;
    }
  }

  /// `GET /` — friendly name, version, and the Plex Pass flag that decides
  /// whether stopping a stream is even offered.
  Future<PlexServerCapabilities?> getCapabilities() async {
    try {
      return PlexServerCapabilities.fromMediaContainer(await _container('/'));
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Sessions
  // ---------------------------------------------------------------------------

  /// `GET /status/sessions`, most expensive first.
  ///
  /// Mapped on the main isolate on purpose, unlike the library lists below: a
  /// server with thirty concurrent streams is extraordinary, and spawning an
  /// isolate to map a dozen objects costs more than the map.
  @override
  Future<List<StreamSession>> getSessions({CancelToken? cancelToken}) async {
    try {
      final container = await _container(
        '/status/sessions',
        cancelToken: cancelToken,
      );
      // An idle Plex server sends `{"size": 0}` with **no `Metadata` key at
      // all** — not an empty array, the way Jellyfin does. `container['Metadata']
      // as List` throws here, and this is the single most common shape trap in
      // the API because the happy path never exercises it.
      final metadata = container['Metadata'];
      if (metadata is! List) return const [];

      final sessions = metadata
          .whereType<Map>()
          .map((raw) => plexSessionFromJson(raw.cast<String, dynamic>()))
          .nonNulls
          .toList();

      // Cost order, so the session actually charging the box for something is at
      // the top. Bitrate breaks ties within a method.
      sessions.sort((a, b) {
        final byMethod = b.playMethod.index.compareTo(a.playMethod.index);
        if (byMethod != 0) return byMethod;
        return (b.bitrate ?? 0).compareTo(a.bitrate ?? 0);
      });
      return sessions;
    } catch (_) {
      return const [];
    }
  }

  /// `POST /status/sessions/terminate`.
  ///
  /// [sessionId] must be the nested `Session.id`. `sessionKey` and
  /// `Player.machineIdentifier` sit on the same object and both produce a 404,
  /// which is why [plexSessionFromJson] reads only the first.
  ///
  /// A write action, so failures surface — and they are surfaced *specifically*,
  /// because Plex's two error codes here mean the opposite of what they usually
  /// do: 401 documents "the server does not have the feature enabled" (a Plex
  /// Pass gate, not a bad token) and 403 documents "sessionId is empty" (not a
  /// permission problem). Reporting either as "your token expired" would send the
  /// user to re-paste a credential that is working.
  @override
  Future<void> stopSession(
    String sessionId, {
    String reason = kPlexTerminationReason,
  }) async {
    _assertUsableToken();

    final id = sessionId.trim();
    if (id.isEmpty) {
      // A `/status/sessions` entry with no nested `Session` element has no id,
      // so there is nothing to terminate. Caught here rather than sent as an
      // empty parameter, which the server answers with a 403 whose message is
      // about permissions.
      throw const PlexException(
        'Plex did not give this stream a session id, so it cannot be stopped '
        'from here.',
        reason: ServiceFailureReason.notFound,
      );
    }

    try {
      // `sessionId` is case-sensitive with a capital I; Dio percent-encodes the
      // reason.
      await _api.post(
        '/status/sessions/terminate',
        queryParameters: {'sessionId': id, 'reason': reason},
      );
    } on DioException catch (e) {
      throw await _mapTerminateError(e);
    }
  }

  Future<PlexException> _mapTerminateError(DioException error) async {
    final status = error.response?.statusCode;
    if (status == 401) {
      // Not a credential failure. Ask the server which of the two it is so the
      // message names the actual blocker.
      final capabilities = await getCapabilities();
      if (capabilities?.myPlexSubscription == false) {
        return const PlexException(
          'Stopping a stream is a Plex Pass feature, and this server does not '
          'have one. Your token is fine.',
          reason: ServiceFailureReason.unauthorized,
        );
      }
      return const PlexException(
        'This server refused to stop the stream. Session termination has to be '
        'enabled on the server — the token is not the problem.',
        reason: ServiceFailureReason.unauthorized,
      );
    }
    if (status == 403) {
      return const PlexException(
        'The server did not accept that session id. Refresh the list and try '
        'again.',
        reason: ServiceFailureReason.notFound,
      );
    }
    return _mapDioError(error);
  }

  // ---------------------------------------------------------------------------
  // Libraries
  // ---------------------------------------------------------------------------

  /// `GET /library/sections`.
  ///
  /// Populates [_sectionKinds] as a side effect, which is what lets a lens be
  /// built later without a second round trip.
  @override
  Future<List<StreamLibrary>> getLibraries({CancelToken? cancelToken}) async {
    try {
      final container = await _container(
        '/library/sections',
        cancelToken: cancelToken,
      );
      final directories = container['Directory'];
      if (directories is! List) return const [];

      final libraries = <StreamLibrary>[];
      for (final raw in directories.whereType<Map>()) {
        final library = plexLibraryFromJson(raw.cast<String, dynamic>());
        if (library == null) continue;
        _sectionKinds[library.id] = library.kind;
        libraries.add(library);
      }
      return libraries;
    } catch (_) {
      return const [];
    }
  }

  /// Queues a scan. `GET`, not `POST` — Plex's refresh is a GET.
  @override
  Future<void> refreshLibrary(String libraryId) async {
    _assertUsableToken();
    try {
      await _api.get('/library/sections/${_pathSegment(libraryId)}/refresh');
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// How many items a section holds, without downloading any of them.
  ///
  /// `X-Plex-Container-Size=0` returns a page of nothing alongside the
  /// `totalSize` — the cheapest count Plex offers. Kept off [getLibraries]
  /// deliberately: doing it there would turn one request into one-per-section on
  /// every dashboard load, which is why `StreamLibrary.itemCount` arrives null
  /// and this is opt-in.
  Future<int?> getLibraryItemCount(
    String libraryId, {
    CancelToken? cancelToken,
  }) async {
    try {
      final kind = await _sectionKind(libraryId);
      final type = _primaryTypeFor(kind);
      final container = await _container(
        '/library/sections/${_pathSegment(libraryId)}/all',
        queryParameters: {
          if (type != null) 'type': type,
          'X-Plex-Container-Start': 0,
          'X-Plex-Container-Size': 0,
        },
        cancelToken: cancelToken,
      );
      return plexInt(container['totalSize']) ?? plexInt(container['size']);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Library items
  // ---------------------------------------------------------------------------

  /// One page of a library under one lens.
  ///
  /// [viewerId] is accepted to satisfy [StreamServerClient] and then **ignored**,
  /// and the reason is structural rather than an omission: on Plex the token *is*
  /// the user. `/library/*` has no `accountID` and no impersonation parameter, so
  /// `viewCount`, `viewOffset`, `unwatched` and `onDeck` can only ever describe
  /// the token's owner. The only way to read another household member's state is
  /// to hold their token, and tokens are obtainable only from plex.tv. See
  /// [getViewers].
  @override
  Future<List<StreamItem>> getLibraryItems({
    required String libraryId,
    required StreamLibraryLens lens,
    String? viewerId,
    int startIndex = 0,
    int limit = kPlexLibraryPageSize,
    CancelToken? cancelToken,
  }) async {
    final page = await getLibraryItemsPage(
      libraryId: libraryId,
      lens: lens,
      startIndex: startIndex,
      limit: limit,
      cancelToken: cancelToken,
    );
    return page?.items ?? const [];
  }

  @override
  Future<StreamLibraryPage> getLibraryPage({
    required String libraryId,
    required StreamLibraryLens lens,
    String? viewerId,
    int startIndex = 0,
    int limit = kPlexLibraryPageSize,
    CancelToken? cancelToken,
  }) async {
    final page = await getLibraryItemsPage(
      libraryId: libraryId,
      lens: lens,
      startIndex: startIndex,
      limit: limit,
      cancelToken: cancelToken,
    );
    if (page == null) {
      return StreamLibraryPage.failed(startIndex: startIndex);
    }
    return StreamLibraryPage(
      items: page.items,
      // The server's own accounting, which is the whole reason [PlexPage]
      // exists: the on-deck lenses drop rows *after* the container is counted,
      // so a page that kept nothing still has to advance the offset instead of
      // ending the list.
      nextStartIndex: page.nextOffset,
      hasMore: page.hasMore,
    );
  }

  /// [getLibraryItems] with the paging envelope kept, or **null** when the
  /// request failed.
  ///
  /// The extra return value is not decoration. Plex's guidance is that a
  /// response "might include a different number of items than requested", so a
  /// pager has to advance by `MediaContainer.offset + size` and stop at
  /// `totalSize` rather than by the page size it asked for. Returning only a
  /// `List` — as the shared interface must, since Jellyfin reports its totals
  /// differently — throws exactly the numbers a pager needs away.
  ///
  /// Null rather than `PlexPage.empty()` on failure, because an empty page and
  /// a failed request are the two things a browse must never conflate — see
  /// [StreamLibraryPage]. [getLibraryItems] still flattens both to `[]`, which
  /// is the read-path convention for every caller that only wants rows.
  Future<PlexPage<StreamItem>?> getLibraryItemsPage({
    required String libraryId,
    required StreamLibraryLens lens,
    int startIndex = 0,
    int limit = kPlexLibraryPageSize,
    CancelToken? cancelToken,
  }) async {
    try {
      final kind = await _sectionKind(libraryId);
      final request = _lensRequest(libraryId, lens, kind);

      final container = await _container(
        request.path,
        queryParameters: {
          ...request.query,
          // Both parameters, always. Plex accepts them as headers or query args
          // and honours neither half on its own: a start without a size returns
          // the server's default page, and a size without a start silently
          // re-reads page one.
          'X-Plex-Container-Start': startIndex,
          'X-Plex-Container-Size': limit,
        },
        cancelToken: cancelToken,
      );

      final page = await _pageFromContainer(container, startIndex);
      final keep = request.keep;
      if (keep == null) return page;
      return page.copyWithItems(page.items.where(keep).toList(growable: false));
    } catch (_) {
      return null;
    }
  }

  /// `GET /library/metadata/{ratingKey}`.
  ///
  /// `checkFiles=0` and `skipRefresh=1` are not micro-optimisations: a bare GET
  /// here makes the server stat every file in the item and can kick off an agent
  /// refresh, both synchronously, which on a spun-down NAS turns opening a detail
  /// page into a thirty-second wait and a disk spin-up.
  @override
  Future<StreamItem?> getItem(
    String itemId, {
    String? viewerId,
    CancelToken? cancelToken,
  }) async {
    try {
      final container = await _container(
        '/library/metadata/${_pathSegment(itemId)}',
        queryParameters: {'checkFiles': 0, 'skipRefresh': 1},
        cancelToken: cancelToken,
      );
      final metadata = container['Metadata'];
      if (metadata is! List) return null;
      final first = metadata.whereType<Map>().firstOrNull;
      if (first == null) return null;
      return plexItemFromJson(first.cast<String, dynamic>());
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
    // Plex indexes external ids as `Guid[]` entries and filters on them through
    // `?guid=`, one value at a time — unlike Jellyfin's comma-delimited OR. So
    // this tries each id in turn and stops at the first hit, cheapest identifier
    // first: TMDB is what Radarr carries and what Plex's Movie agent writes.
    final guids = <String>[
      if (tmdbId != null && tmdbId.isNotEmpty) 'tmdb://$tmdbId',
      if (tvdbId != null && tvdbId.isNotEmpty) 'tvdb://$tvdbId',
      if (imdbId != null && imdbId.isNotEmpty) 'imdb://$imdbId',
    ];

    for (final guid in guids) {
      try {
        final container = await _container(
          '/library/all',
          queryParameters: {
            'guid': guid,
            // Without this the response omits Guid entries and a caller cannot
            // verify the match it just asked for.
            'includeGuids': 1,
          },
          cancelToken: cancelToken,
        );
        final items = await _itemsFromAsync(container['Metadata']);
        if (items.isNotEmpty) return items.first;
      } catch (_) {
        // `?guid=` is not honoured by every server version, and an unfiltered
        // fallback would return the whole library and pick something arbitrary.
        // Silence is the correct answer: the caller renders nothing.
        continue;
      }
    }
    return null;
  }

  /// `GET /library/metadata/{ratingKey}/children` — show → seasons, season →
  /// episodes, album → tracks.
  ///
  /// Reads `Metadata` and falls back to `Directory`: current builds return
  /// seasons as `Metadata` in JSON, but the same elements are `Directory` in the
  /// XML the JSON layer was grafted onto, and older servers still say so.
  @override
  Future<List<StreamItem>> getChildren(
    String itemId, {
    String? viewerId,
    CancelToken? cancelToken,
  }) async {
    try {
      final container = await _container(
        '/library/metadata/${_pathSegment(itemId)}/children',
        cancelToken: cancelToken,
      );
      return _itemsFrom(container['Metadata'] ?? container['Directory']);
    } catch (_) {
      return const [];
    }
  }

  /// The household members whose watch state can be read: exactly one, always.
  ///
  /// This is not a stub. `GET /accounts` would list every Plex Home user, and
  /// offering them as pickable viewers would be a lie — `/library/*` takes no
  /// impersonation parameter, so every lens would still answer for the token's
  /// owner while the UI claimed otherwise. Reading another member's state
  /// requires their token, and tokens come only from plex.tv, which this client
  /// never calls. So the one honest list is the owner alone, which is also why
  /// `StreamLibraryLens.isPerViewer` hides the viewer chip on Plex instead of
  /// showing a list of one.
  ///
  /// `GET /` rather than `/accounts` on purpose: `/accounts` is admin-only in
  /// practice, so a non-admin token would get nothing at all from it, while `/`
  /// answers for any valid token.
  @override
  Future<List<StreamViewer>> getViewers() async {
    final capabilities = await getCapabilities();
    if (capabilities == null) return const [];
    final name = capabilities.myPlexUsername ?? capabilities.friendlyName;
    if (name == null) return const [];
    // 'me' rather than an account id: there is no endpoint that says which
    // account a token belongs to, and the value is never sent anywhere — every
    // read is already scoped to this token.
    return [StreamViewer(id: 'me', name: name)];
  }

  // ---------------------------------------------------------------------------
  // Hubs
  // ---------------------------------------------------------------------------

  /// `GET /hubs/continueWatching` — in-progress playback across every library.
  ///
  /// Hub responses are where a no-plex.tv client leaks: Plex mixes *provider*
  /// rows into the same arrays as local ones, with absolute plex.tv keys and
  /// artwork. [plexItemFromJson] drops them at the parse boundary.
  Future<List<StreamItem>> getContinueWatching({
    int count = kPlexLibraryPageSize,
    CancelToken? cancelToken,
  }) async {
    try {
      final container = await _container(
        '/hubs/continueWatching',
        queryParameters: {'count': count},
        cancelToken: cancelToken,
      );
      return _itemsFromHubs(container);
    } catch (_) {
      return const [];
    }
  }

  /// `GET /hubs/search`.
  ///
  /// `limit` is per hub and defaults to 3, so it is always sent explicitly.
  /// `includeExternalMedia=0` asks Plex not to mix its catalogue in — belt to
  /// [plexIsServerItem]'s braces, since the parameter is advisory and the
  /// provider rows still arrive on some builds.
  Future<List<StreamItem>> search(
    String query, {
    int limit = 20,
    CancelToken? cancelToken,
  }) async {
    final term = query.trim();
    if (term.isEmpty) return const [];
    try {
      final container = await _container(
        '/hubs/search',
        queryParameters: {
          'query': term,
          'limit': limit,
          'includeExternalMedia': 0,
        },
        cancelToken: cancelToken,
      );
      return _itemsFromHubs(container);
    } catch (_) {
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // Artwork
  // ---------------------------------------------------------------------------

  /// Resolves a relative Plex artwork key.
  ///
  /// Without [width] the key is served directly and the credential travels in a
  /// header. With one, the request goes through `/photo/:/transcode`, because
  /// Plex resizes an image far more cheaply than shipping a 2000px poster to
  /// Flutter to scale down.
  ///
  /// The proxy's inner `url=` parameter is the part that needs care: Plex's own
  /// documentation says that if that URL needs a token, the token has to be a
  /// query parameter on it — a header cannot reach it. This client only ever
  /// passes a **relative** inner url, which the server resolves internally under
  /// the outer request's own authentication, so no token enters a query string.
  /// If an absolute inner url were ever required, the correct credential for it
  /// is a delegation token (`POST /security/token?type=delegation&scope=all`,
  /// valid 48 hours and destroyed on server restart) and never the user's own.
  @override
  StreamImageSource? imageFor(String posterPath, {int? width}) {
    // Rejecting anything non-relative is what stops a cloud artwork URL that
    // slipped through parsing from being fetched from plex.tv.
    final key = plexArtworkKey(posterPath);
    if (key == null || baseUrl.isEmpty) return null;

    if (width == null || width <= 0) {
      return (url: UrlUtils.buildUrl(baseUrl, key), headers: _imageHeaders);
    }

    final target = Uri.parse(UrlUtils.buildUrl(baseUrl, '/photo/:/transcode'))
        .replace(
          queryParameters: {
            'url': key,
            'width': '$width',
            'height': '${(width * _kPosterHeightRatio).round()}',
            // Fit inside the box, never enlarge a small source.
            'minSize': '1',
            'upscale': '0',
          },
        );
    return (url: target.toString(), headers: _imageHeaders);
  }

  @override
  void close() => _api.close();

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// Percent-encodes an opaque id for use in a path.
  ///
  /// `ratingKey` and a section `key` are documented as opaque strings that only
  /// usually look numeric, so neither may be interpolated raw.
  static String _pathSegment(String value) => Uri.encodeComponent(value.trim());

  Future<StreamLibraryKind?> _sectionKind(String libraryId) async {
    final cached = _sectionKinds[libraryId];
    if (cached != null) return cached;
    await getLibraries();
    return _sectionKinds[libraryId];
  }

  static int? _primaryTypeFor(StreamLibraryKind? kind) {
    switch (kind) {
      case StreamLibraryKind.movies:
        return _kPlexTypeMovie;
      case StreamLibraryKind.shows:
        return _kPlexTypeShow;
      case StreamLibraryKind.music:
        return _kPlexTypeArtist;
      // Photo and unknown sections: let the server return the section's own
      // primary type rather than guessing an id for it.
      case StreamLibraryKind.photos:
      case StreamLibraryKind.other:
      case null:
        return null;
    }
  }

  /// Turns a lens into a request, plus an optional post-filter.
  _PlexLensRequest _lensRequest(
    String libraryId,
    StreamLibraryLens lens,
    StreamLibraryKind? kind,
  ) {
    final section = '/library/sections/${_pathSegment(libraryId)}';
    final type = _primaryTypeFor(kind);

    switch (lens) {
      // Plex has no separate "continue" and "next up" endpoints. `onDeck` is
      // both at once: part-watched items carry a `viewOffset`, and the next
      // unwatched episode of a finished season does not. Splitting on that is
      // what keeps the two lenses from being the same list twice — and it is
      // done after mapping, so a page can legitimately return fewer rows than
      // asked for. `PlexPage.size` stays the server's figure so the pager still
      // advances correctly.
      case StreamLibraryLens.continueWatching:
        return (
          path: '$section/onDeck',
          query: const {},
          keep: (item) => (item.resumeOffsetMs ?? 0) > 0,
        );
      case StreamLibraryLens.nextUp:
        return (
          path: '$section/onDeck',
          query: const {},
          keep: (item) => (item.resumeOffsetMs ?? 0) == 0,
        );
      case StreamLibraryLens.recentlyAdded:
        return (
          path: '$section/all',
          query: {if (type != null) 'type': type, 'sort': 'addedAt:desc'},
          keep: null,
        );
      case StreamLibraryLens.unplayed:
        return (
          path: '$section/all',
          query: {
            if (type != null) 'type': type,
            // The filter is spelled differently per section type, and sending
            // the wrong spelling returns the *whole* library rather than an
            // error — a silently wrong lens. A show is unplayed when it has
            // unwatched leaves, not when the show object itself is unwatched.
            if (kind == StreamLibraryKind.shows)
              'show.unwatchedLeaves': 1
            else if (kind == StreamLibraryKind.movies)
              'unwatched': 1,
            'sort': 'titleSort',
          },
          keep: null,
        );
      case StreamLibraryLens.all:
        return (
          path: '$section/all',
          query: {if (type != null) 'type': type, 'sort': 'titleSort'},
          keep: null,
        );
    }
  }

  Future<PlexPage<StreamItem>> _pageFromContainer(
    Map<String, dynamic> container,
    int requestedStart,
  ) async {
    final items = await _itemsFromAsync(container['Metadata']);
    return PlexPage<StreamItem>(
      items: items,
      // Trust the server's echo over what was asked for; only fall back to the
      // request when the response omits it.
      offset: plexInt(container['offset']) ?? requestedStart,
      size: plexInt(container['size']) ?? items.length,
      totalSize: plexInt(container['totalSize']),
    );
  }

  /// Maps a `Metadata` array, off the main isolate once it is worth it.
  ///
  /// **`static` is load-bearing.** The mapping entry point is a top-level pure
  /// function and the closure captures only the decoded list, but a closure
  /// written inside an *instance* method can drag `this` into its context — and
  /// `this` holds an `ApiClient`, which is not sendable. `Isolate.run` would then
  /// throw at the boundary, and because every read path here degrades on error
  /// the failure would surface as a silently empty library rather than as a
  /// crash. Being static makes that unrepresentable.
  static Future<List<StreamItem>> _itemsFromAsync(dynamic raw) async {
    if (raw is! List || raw.isEmpty) return const [];
    if (raw.length < _kIsolateMappingThreshold) {
      return plexItemsFromMetadata(raw);
    }
    return Isolate.run(() => plexItemsFromMetadata(raw));
  }

  List<StreamItem> _itemsFrom(dynamic raw) {
    if (raw is! List) return const [];
    return plexItemsFromMetadata(raw);
  }

  /// Flattens `Hub[] → Metadata[]`, keeping hub order.
  List<StreamItem> _itemsFromHubs(Map<String, dynamic> container) {
    final hubs = container['Hub'];
    if (hubs is! List) {
      // `/hubs/continueWatching` answers with a bare `Metadata` array on some
      // builds instead of wrapping it in a single hub.
      return _itemsFrom(container['Metadata']);
    }
    final items = <StreamItem>[];
    for (final hub in hubs.whereType<Map>()) {
      items.addAll(_itemsFrom(hub['Metadata']));
    }
    return items;
  }
}

/// A lens resolved to a request: where to ask, what to ask for, and what to keep.
typedef _PlexLensRequest = ({
  String path,
  Map<String, dynamic> query,
  bool Function(StreamItem item)? keep,
});

// -----------------------------------------------------------------------------
// Mapping — top-level and pure, so `Isolate.run` can carry them.
// -----------------------------------------------------------------------------

/// Maps a `Metadata` array, dropping anything that is not a local item.
List<StreamItem> plexItemsFromMetadata(List<dynamic> metadata) {
  return metadata
      .whereType<Map>()
      .map((raw) => plexItemFromJson(raw.cast<String, dynamic>()))
      .nonNulls
      .toList(growable: false);
}

/// Maps one `Metadata` element, or null when it is not the user's own server's.
StreamItem? plexItemFromJson(Map<String, dynamic> json) {
  if (!plexIsServerItem(json)) return null;

  // Officially "an opaque string… while it often appears to be numeric, this is
  // not guaranteed", which is why nothing in this file models it as an int.
  final ratingKey = plexString(json['ratingKey']);
  if (ratingKey == null) return null;

  final kind = plexItemKindFromType(json['type']);
  final title = plexString(json['title']) ?? '';
  final parentTitle = plexString(json['parentTitle']);
  final grandparentTitle = plexString(json['grandparentTitle']);

  final viewCount = plexInt(json['viewCount']) ?? 0;
  final viewOffset = plexInt(json['viewOffset']);
  final leafCount = plexInt(json['leafCount']);
  final viewedLeafCount = plexInt(json['viewedLeafCount']);

  // There is no boolean `watched` anywhere in the API. A leaf is watched when
  // `viewCount >= 1`; a container is watched when every leaf is.
  final isPlayed = leafCount != null && leafCount > 0
      ? (viewedLeafCount ?? 0) >= leafCount
      : viewCount >= 1;

  // `viewedLeafCount` is omitted on a show nobody has started, so an absent
  // value alongside a present `leafCount` means zero watched — treating it as
  // unknown would hide the badge on exactly the shows the badge is for.
  final unplayed = leafCount == null
      ? null
      : leafCount - (viewedLeafCount ?? 0);

  return StreamItem(
    id: ratingKey,
    title: title,
    subtitle: switch (kind) {
      // Contract: an episode's subtitle is the series name, a track's is the
      // artist. Both live on `grandparentTitle` — Plex names the levels by
      // distance, not by role.
      StreamItemKind.episode => grandparentTitle,
      StreamItemKind.track => grandparentTitle ?? parentTitle,
      StreamItemKind.season => parentTitle,
      StreamItemKind.album => parentTitle,
      StreamItemKind.movie => plexInt(json['year'])?.toString(),
      _ => parentTitle,
    },
    kind: kind,
    posterPath:
        plexArtworkKey(json['thumb']) ??
        plexArtworkKey(json['parentThumb']) ??
        plexArtworkKey(json['grandparentThumb']),
    year: plexInt(json['year']),
    // Already milliseconds on Plex, unlike Jellyfin's 100ns ticks.
    runtimeMs: plexInt(json['duration']),
    isPlayed: isPlayed,
    // Absent means "no resume point", which is not the same as 0 — and a 0 that
    // reached the UI would render a progress bar at the very start of an
    // untouched item.
    resumeOffsetMs: (viewOffset ?? 0) > 0 ? viewOffset : null,
    unplayedChildCount: unplayed != null && unplayed > 0 ? unplayed : null,
  );
}

/// Maps Plex's `type` string onto the shared item vocabulary.
///
/// `artist` is the one place this bends. [StreamItemKind] has no artist member,
/// and the enum's only behavioural consumer is `hasChildren` — so mapping an
/// artist to `other` would assert that an artist contains nothing and dead-end
/// a music browse before it reaches an album. `album` keeps the traversal
/// artist → album → track working and is wrong only about the level's name.
StreamItemKind plexItemKindFromType(dynamic type) {
  switch (plexString(type)?.toLowerCase()) {
    case 'movie':
      return StreamItemKind.movie;
    case 'show':
      return StreamItemKind.series;
    case 'season':
      return StreamItemKind.season;
    case 'episode':
      return StreamItemKind.episode;
    case 'artist':
    case 'album':
      return StreamItemKind.album;
    case 'track':
      return StreamItemKind.track;
    default:
      return StreamItemKind.other;
  }
}

/// Maps a `/library/sections` `Directory` element.
StreamLibrary? plexLibraryFromJson(Map<String, dynamic> json) {
  // Relative to `/library/sections`, so `'1'` and not `'/library/sections/1'`.
  final key = plexString(json['key']);
  if (key == null) return null;
  return StreamLibrary(
    id: key,
    name: plexString(json['title']) ?? key,
    kind: plexLibraryKindFromType(json['type']),
    // Plex does not put a count on the section; `getLibraryItemCount` fetches
    // one on request rather than making the dashboard pay per library.
    itemCount: null,
    // Plex is the server that *does* report this per section, which is why
    // `StreamLibrary.lastScannedAt` exists at all — and it is epoch seconds.
    lastScannedAt: plexEpochSeconds(json['scannedAt']),
    isRefreshing: plexBool(json['refreshing']) ?? false,
  );
}

StreamLibraryKind plexLibraryKindFromType(dynamic type) {
  switch (plexString(type)?.toLowerCase()) {
    case 'movie':
      return StreamLibraryKind.movies;
    case 'show':
      return StreamLibraryKind.shows;
    case 'artist':
      return StreamLibraryKind.music;
    case 'photo':
      return StreamLibraryKind.photos;
    default:
      return StreamLibraryKind.other;
  }
}

/// Maps one `/status/sessions` entry.
///
/// A session is an ordinary `Metadata` object with `User`, `Player`, `Session`
/// and possibly `TranscodeSession` grafted on, so most of it is read the same
/// way [plexItemFromJson] reads a library row.
StreamSession? plexSessionFromJson(Map<String, dynamic> json) {
  final transcode = PlexTranscodeSession.maybeFrom(json);
  final player = _childObject(json['Player']);
  final user = _childObject(json['User']);
  final session = _childObject(json['Session']);

  final kind = plexItemKindFromType(json['type']);
  final title = plexString(json['title']) ?? '';
  final parentTitle = plexString(json['parentTitle']);
  final grandparentTitle = plexString(json['grandparentTitle']);

  final durationMs = plexInt(json['duration']);
  final viewOffsetMs = plexInt(json['viewOffset']);

  return StreamSession(
    // `Session.id`. Empty when the server reported no nested `Session` element,
    // in which case there is nothing to terminate — `stopSession` refuses an
    // empty id locally rather than sending one and getting a misleading 403.
    id: plexString(session?['id']) ?? '',
    // Empty rather than a placeholder: how an unnamed viewer reads is the
    // board's decision, not the client's.
    userName: plexString(user?['title']) ?? '',
    // For an episode the headline is the series and the subtitle carries the
    // episode — the inverse of a library row, where the episode is the thing
    // being listed.
    title: kind == StreamItemKind.episode ? (grandparentTitle ?? title) : title,
    subtitle: switch (kind) {
      StreamItemKind.episode => _episodeSubtitle(json, title),
      StreamItemKind.track => [
        grandparentTitle,
        parentTitle,
      ].nonNulls.join(' · ').ifEmptyNull,
      StreamItemKind.movie => plexInt(json['year'])?.toString(),
      _ => parentTitle,
    },
    // `Infuse · iPhone`: the app first, then the hardware it is running on.
    deviceLabel: [
      plexString(player?['product']),
      plexString(player?['device']) ??
          plexString(player?['platform']) ??
          plexString(player?['title']),
    ].nonNulls.join(' · '),
    posterPath: kind == StreamItemKind.episode
        // The series poster reads better than an episode still at grid size.
        ? plexArtworkKey(json['grandparentThumb']) ??
              plexArtworkKey(json['parentThumb']) ??
              plexArtworkKey(json['thumb'])
        : plexArtworkKey(json['thumb']) ??
              plexArtworkKey(json['parentThumb']) ??
              plexArtworkKey(json['grandparentThumb']),
    // No `TranscodeSession` at all is the *only* signal Plex gives for a direct
    // play; there is no field that says so.
    playMethod: transcode?.playMethod ?? StreamPlayMethod.directPlay,
    transcodeReasons: transcode?.reasons ?? const [],
    // `Session.bandwidth` is kilobits per second; the model is bits per second.
    // Falls back to the file's own bitrate — also kbps — when the server did not
    // reserve bandwidth for this stream.
    bitrate: _bitsPerSecond(
      plexInt(session?['bandwidth']) ?? plexInt(_firstMedia(json)?['bitrate']),
    ),
    // **Always true on Plex.** `Session.bandwidth` is a reservation made by
    // Plex's streaming brain, not measured egress, and `Media.bitrate` describes
    // the file. Neither is throughput, and labelling either as such — or summing
    // them into a "total" — would be a fabricated claim.
    bitrateIsNominal: true,
    progress: durationMs != null && durationMs > 0 && viewOffsetMs != null
        ? (viewOffsetMs / durationMs).clamp(0.0, 1.0)
        : null,
    isPaused: plexString(player?['state'])?.toLowerCase() == 'paused',
  );
}

/// `S1 · E4 · Title`, skipping whatever the server did not send.
String? _episodeSubtitle(Map<String, dynamic> json, String title) {
  final season = plexInt(json['parentIndex']);
  final episode = plexInt(json['index']);
  final parts = <String>[
    if (season != null) 'S$season',
    if (episode != null) 'E$episode',
    if (title.isNotEmpty) title,
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Plex writes every child element as an array in JSON even when there is one of
/// them — but the container key itself is optional, and some builds send a bare
/// object for the singletons (`User`, `Player`, `Session`).
Map<String, dynamic>? _childObject(dynamic raw) {
  if (raw is Map) return raw.cast<String, dynamic>();
  if (raw is List) {
    final first = raw.whereType<Map>().firstOrNull;
    return first?.cast<String, dynamic>();
  }
  return null;
}

Map<String, dynamic>? _firstMedia(Map<String, dynamic> json) =>
    _childObject(json['Media']);

/// kbps → bits per second. Null in, null out; a zero is not a bitrate.
int? _bitsPerSecond(int? kilobitsPerSecond) {
  if (kilobitsPerSecond == null || kilobitsPerSecond <= 0) return null;
  return kilobitsPerSecond * 1000;
}

extension _NullIfEmpty on String {
  String? get ifEmptyNull => isEmpty ? null : this;
}
