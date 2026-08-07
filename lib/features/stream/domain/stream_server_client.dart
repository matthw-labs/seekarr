/// What the Stream feature needs from a media server, regardless of which one.
///
/// The dashboard, the library browse and the item detail are written against this
/// and never against Jellyfin or Plex directly, so the two implementations can
/// keep their genuinely different mechanics — ticks against milliseconds, one
/// `PlayMethod` against three independent `*Decision` fields, an impersonating
/// admin key against a single-perspective token — without leaking either into a
/// widget.
///
/// Errors follow the project convention: a missing configuration throws
/// `Exception('<Service> not configured')`, which `AsyncValueWidget` detects to
/// render `NotConfiguredPlaceholder`. Read paths degrade to `[]`/`null` on a
/// remote failure; write actions surface theirs so the UI can report them.
library;

import 'package:dio/dio.dart' show CancelToken;

import 'package:seekarr/features/stream/domain/models/stream_item.dart';
import 'package:seekarr/features/stream/domain/models/stream_library.dart';
import 'package:seekarr/features/stream/domain/models/stream_library_page.dart';
import 'package:seekarr/features/stream/domain/models/stream_session.dart';

/// A viewer whose watch state a library can be read through.
class StreamViewer {
  final String id;
  final String name;

  const StreamViewer({required this.id, required this.name});
}

/// Resolved artwork: the URL plus whatever headers authenticate it.
///
/// A record rather than a bare URL because the credential must stay in a header
/// wherever it can. `ImageUtils.extractPosterUrl` can only emit `X-Api-Key`, and
/// putting a token in the query string leaks it into `CachedNetworkImage`'s cache
/// key — which is also the reason Plex's `/photo/:/transcode` proxy is only used
/// where its `url=` parameter genuinely forces the issue, and then with a
/// 48-hour delegation token rather than the user's own.
typedef StreamImageSource = ({String url, Map<String, String>? headers});

abstract interface class StreamServerClient {
  /// Reachability probe returning the server version.
  ///
  /// Deliberately the endpoint that does not *require* a credential on either
  /// server (`/System/Info/Public`, `/identity`), so that "the box is down" and
  /// "the token is wrong" cannot arrive as the same error — the single most
  /// common Stream misconfiguration, and the one a generic timeout hides.
  ///
  /// Note the precise claim: not that no credential is *sent*. Both clients set
  /// their auth header in `BaseOptions`, so it travels here too. What makes the
  /// separation hold is the server side — Jellyfin marks the endpoint
  /// `[AllowAnonymous]`, so a rejected token cannot turn this into a failure —
  /// and [verifyCredential] is the call that answers the credential question.
  Future<String?> probeVersion();

  /// Whether the stored credential is accepted. Separate from [probeVersion].
  Future<bool> verifyCredential();

  /// Everything playing right now, most expensive first.
  Future<List<StreamSession>> getSessions();

  /// Stop one playback.
  ///
  /// Both servers only *dispatch* this — Jellyfin returns 204 meaning "sent to
  /// the client", which may ignore it, and Plex returns an empty body. Callers
  /// must re-read [getSessions] to confirm rather than trusting the status code.
  Future<void> stopSession(String sessionId);

  /// The libraries this server exposes.
  Future<List<StreamLibrary>> getLibraries();

  /// Queue a scan for one library.
  Future<void> refreshLibrary(String libraryId);

  /// One page of a library under one lens.
  ///
  /// [viewerId] is required by Jellyfin for every per-viewer lens and ignored by
  /// Plex, which has only the token's own perspective.
  /// [cancelToken] is part of the interface rather than an implementation extra:
  /// the project's convention is that list and search fetches are cancellable,
  /// and both clients had independently widened their overrides to add it. Left
  /// off here, every provider that wanted cancellation had to depend on the
  /// concrete `JellyfinClient` or `PlexClient` — which forfeits the one thing
  /// this interface exists for.
  Future<List<StreamItem>> getLibraryItems({
    required String libraryId,
    required StreamLibraryLens lens,
    String? viewerId,
    int startIndex = 0,
    int limit = 50,
    CancelToken? cancelToken,
  });

  /// [getLibraryItems] with the paging envelope kept.
  ///
  /// **What a paged browse must call.** [getLibraryItems] throws the rows away
  /// from around the rows: it cannot say whether an empty result means the
  /// library is empty, the request failed, or this particular page happened to
  /// be filtered down to nothing — and each of those needs a different thing on
  /// screen. See [StreamLibraryPage] for the two false claims that came out of
  /// collapsing them.
  ///
  /// Never throws. A failure is [StreamPageOutcome.failed], for the same reason
  /// [getLibraryItems] degrades to `[]`: the caller decides whether this is a
  /// retry affordance or a quiet gap.
  Future<StreamLibraryPage> getLibraryPage({
    required String libraryId,
    required StreamLibraryLens lens,
    String? viewerId,
    int startIndex = 0,
    int limit = 50,
    CancelToken? cancelToken,
  });

  // Deliberately no `hasViewer` here. "A per-viewer lens has no subject" is
  // already carried by [StreamLibraryPage.needsViewer] — per request, where the
  // browse actually needs it — so a second, connection-wide spelling of the same
  // fact bought nothing and forced every implementer and test fake to declare a
  // member no caller read.

  /// One item at any depth.
  Future<StreamItem?> getItem(
    String itemId, {
    String? viewerId,
    CancelToken? cancelToken,
  });

  /// The children of a series, season or album.
  Future<List<StreamItem>> getChildren(
    String itemId, {
    String? viewerId,
    CancelToken? cancelToken,
  });

  /// Whether an item the *arrs* know about is on this server, and where the
  /// viewer stopped in it.
  ///
  /// This is what lets a Radarr or Sonarr detail page say "On Jellyfin · 34 min
  /// in" instead of Seekarr shipping a second, near-identical catalogue. The join
  /// is on an external database id rather than on a title, because a title match
  /// across two catalogues is a guess and this has to be a fact: Radarr carries
  /// `tmdbId`, Sonarr `tvdbId`, and both servers index the same ids
  /// (Jellyfin as `ProviderIds`, Plex as `Guid[]` entries like `tmdb://1234`).
  ///
  /// Returns null when the item is not there or when the server is too old to
  /// filter by provider id — both are "we cannot say it is watchable", and the
  /// caller renders nothing rather than a wrong claim.
  ///
  /// A missing viewer is **not** one of those cases. It costs the *watch state*
  /// — the slot reads "Ready to watch" instead of "34 min in" — but presence and
  /// a route to open the item are still facts, and they are the media server's
  /// facts rather than a restatement of the arr's: the arr knows a file is on
  /// disk, the server knows it is in the library and playable. Refusing to
  /// answer without a viewer made this slot Plex-only in practice.
  Future<StreamItem?> findByExternalId({
    String? tmdbId,
    String? tvdbId,
    String? imdbId,
    CancelToken? cancelToken,
  });

  /// Household members whose watch state can be read.
  ///
  /// Returns a single-entry list on Plex — see [StreamLibraryLens.isPerViewer].
  Future<List<StreamViewer>> getViewers();

  /// Resolve artwork for an item or session poster path.
  ///
  /// **Synchronous, and that is a requirement rather than an optimisation.** A
  /// poster grid calls this once per tile during `build`; a `Future` would force
  /// every cell through a `FutureBuilder` and hand the grid a frame of empty boxes
  /// on every scroll. Both servers can answer it by string manipulation alone —
  /// Jellyfin composes `/Items/{id}/Images/Primary`, Plex either resolves a
  /// relative key or builds a `/photo/:/transcode` URL — so nothing here needs a
  /// round trip. If a future server ever does (a signed URL, say), it belongs
  /// behind a cache the client owns, not in this signature.
  StreamImageSource? imageFor(String posterPath, {int? width});

  void close();
}
