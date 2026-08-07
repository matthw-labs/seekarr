import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/plex/data/plex_client.dart';
import 'package:cupola/features/plex/domain/models/plex_models.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';

/// Plex client bound to the current settings.
///
/// Throws if Plex is not configured; widgets must check
/// `settings.isServiceConfigured(ServiceKey.plex)` before reading. The exact
/// `'not configured'` wording is load-bearing — `AsyncValueWidget` matches on it
/// to render `NotConfiguredPlaceholder` instead of an error.
///
/// `plexClientId` is read but never generated here: `SettingsService` mints it
/// once and persists it, because Plex registers a new device row against the
/// user's server for every distinct `X-Plex-Client-Identifier` it sees.
///
/// Field-by-field `select` rather than a bare watch of the whole
/// `SettingsModel`, for the same reason `jellyfinClientProvider` does it: this
/// provider closes a live `Dio` in `onDispose`, so any rebuild kills in-flight
/// requests and cascades an invalidation through every Stream surface. Watching
/// the whole settings object meant a theme-mode toggle did that.
final plexClientProvider = Provider<PlexClient>((ref) {
  final url = ref.watch(currentSettingsProvider.select((s) => s.plexUrl));
  final token = ref.watch(currentSettingsProvider.select((s) => s.plexToken));
  final clientId = ref.watch(
    currentSettingsProvider.select((s) => s.plexClientId),
  );
  final certFingerprint = ref.watch(
    currentSettingsProvider.select((s) => s.pinForUrl(s.plexUrl)),
  );
  if (url.isEmpty || token.isEmpty) {
    throw Exception('Plex not configured');
  }
  final client = PlexClient(
    url: url,
    token: token,
    clientIdentifier: clientId,
    pinnedCertFingerprint: certFingerprint,
  );
  ref.onDispose(client.close);
  return client;
});

/// The same client, seen through the interface the Stream surfaces are written
/// against.
///
/// The Jellyfin side has always had this; Plex was missing it, which meant a
/// screen meant to serve both servers had to name one of them. Nothing above the
/// data layer should know which media server it is talking to — that is the whole
/// reason `StreamServerClient` exists.
final plexServerProvider = Provider<StreamServerClient>((ref) {
  return ref.watch(plexClientProvider);
});

/// `GET /` — friendly name, version, and the Plex Pass flag that decides whether
/// a "stop stream" affordance is offered at all.
final plexCapabilitiesProvider = FutureProvider<PlexServerCapabilities?>((
  ref,
) async {
  return ref.watch(plexClientProvider).getCapabilities();
});

/// Everything playing right now, most expensive first.
///
/// Not self-polling: the Stream board owns its own refresh cadence, and a timer
/// here would keep hitting `/status/sessions` while the user is three screens
/// away. `ref.invalidate(plexSessionsProvider)` is the refresh.
final plexSessionsProvider = FutureProvider<List<StreamSession>>((ref) async {
  return ref.watch(plexClientProvider).getSessions();
});

/// The libraries ("sections") this server exposes.
final plexLibrariesProvider = FutureProvider<List<StreamLibrary>>((ref) async {
  return ref.watch(plexClientProvider).getLibraries();
});

/// Identifies one page of one library under one lens.
///
/// A record rather than a hand-written key class: records have structural
/// equality, which is what a `family` needs to reuse a cached page instead of
/// refetching it, and this is the same shape `discoverByGenrePageProvider`
/// already uses.
typedef PlexLibraryPageKey = ({
  String libraryId,
  StreamLibraryLens lens,
  int page,
});

/// One zero-indexed page of a library.
///
/// Returns the whole [PlexPage] rather than a bare list because Plex requires
/// the caller to read `MediaContainer.offset`/`size`/`totalSize` back — a pager
/// that counted the rows it received would either stop early on a page the
/// server trimmed or never stop at all.
///
/// No viewer is passed. On Plex the token *is* the user: `/library/*` takes no
/// impersonation parameter, so every lens answers for the token's owner and a
/// viewer key would be a parameter with no effect. See `PlexClient.getViewers`.
///
/// Null when the request failed, which an empty page is not: see
/// `StreamLibraryPage`. A caller that only wants rows should say
/// `?.items ?? const []` and be explicit about flattening the two.
///
/// `autoDispose`, like every per-page and per-item family here: a browse the
/// user has left holds fifty `StreamItem`s per page, and a family entry that is
/// never disposed keeps every one of them for the life of the app.
final plexLibraryItemsProvider = FutureProvider.autoDispose
    .family<PlexPage<StreamItem>?, PlexLibraryPageKey>((ref, key) async {
      return ref
          .watch(plexClientProvider)
          .getLibraryItemsPage(
            libraryId: key.libraryId,
            lens: key.lens,
            startIndex: key.page * kPlexLibraryPageSize,
            limit: kPlexLibraryPageSize,
          );
    });

/// How many items a library holds.
///
/// Separate from [plexLibrariesProvider] because Plex puts no count on a
/// section: the number costs one extra request per library, so it is fetched
/// where it is shown rather than N times on every dashboard load.
final plexLibraryItemCountProvider = FutureProvider.autoDispose
    .family<int?, String>((ref, libraryId) async {
      return ref.watch(plexClientProvider).getLibraryItemCount(libraryId);
    });

/// One item at any depth — film, show, season, episode, album or track.
final plexItemProvider = FutureProvider.autoDispose.family<StreamItem?, String>(
  (ref, ratingKey) async {
    return ref.watch(plexClientProvider).getItem(ratingKey);
  },
);

/// The children of a show, season or album.
final plexChildrenProvider = FutureProvider.autoDispose
    .family<List<StreamItem>, String>((ref, ratingKey) async {
      return ref.watch(plexClientProvider).getChildren(ratingKey);
    });

/// In-progress playback across every library.
final plexContinueWatchingProvider = FutureProvider<List<StreamItem>>((
  ref,
) async {
  return ref.watch(plexClientProvider).getContinueWatching();
});

/// The household members whose watch state can be read — always exactly one on
/// Plex. See `PlexClient.getViewers` for why that is structural.
final plexViewersProvider = FutureProvider<List<StreamViewer>>((ref) async {
  return ref.watch(plexClientProvider).getViewers();
});
