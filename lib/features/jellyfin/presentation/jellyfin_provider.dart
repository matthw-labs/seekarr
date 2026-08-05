import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/features/jellyfin/data/jellyfin_client.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/stream/domain/models/stream_item.dart';
import 'package:seekarr/features/stream/domain/models/stream_library.dart';
import 'package:seekarr/features/stream/domain/models/stream_session.dart';
import 'package:seekarr/features/stream/domain/stream_server_client.dart';

/// Jellyfin client bound to the current settings.
///
/// Throws if Jellyfin is not configured; widgets must check
/// `settings.isServiceConfigured(ServiceKey.jellyfin)` before reading. The
/// `'not configured'` substring is load-bearing — `AsyncValueWidget` string-matches
/// it to render `NotConfiguredPlaceholder` instead of an error.
///
/// `jellyfinUserId` is read here rather than passed per call, so choosing a
/// different household member in settings rebuilds this provider and invalidates
/// every dependent lens. That is why the browse family below is keyed by
/// (library, lens, page) and not by viewer: the viewer is part of *which client
/// you are talking to*, not part of a page's identity.
final jellyfinClientProvider = Provider<JellyfinClient>((ref) {
  final settings = ref.watch(currentSettingsProvider);
  if (settings.jellyfinUrl.isEmpty || settings.jellyfinApiKey.isEmpty) {
    throw Exception('Jellyfin not configured');
  }
  final client = JellyfinClient(
    baseUrl: settings.jellyfinUrl,
    apiKey: settings.jellyfinApiKey,
    userId: settings.jellyfinUserId,
  );
  ref.onDispose(client.close);
  return client;
});

/// The same client, seen through the interface the Stream surfaces are written
/// against.
///
/// Widgets should depend on this one: nothing above the data layer has any
/// business knowing whether it is talking to Jellyfin or Plex, and a screen that
/// takes the interface can be reused for both — which is the entire point of
/// having it. `cancelToken` now lives on `StreamServerClient` itself, so even the
/// paged browse below goes through here; the concrete provider stays public only
/// for the Jellyfin-specific extras (`getViewers` filtering, the raw item mapper)
/// that genuinely have no cross-server meaning.
final jellyfinServerProvider = Provider<StreamServerClient>((ref) {
  return ref.watch(jellyfinClientProvider);
});

/// Server version from the credential-free probe, or null when the box is not
/// answering.
///
/// Deliberately separate from a credential check: this failing means the server
/// is unreachable, whereas [jellyfinCredentialAcceptedProvider] failing means the
/// API key is wrong. Collapsing the two is what makes Stream misconfiguration
/// unreadable.
final jellyfinVersionProvider = FutureProvider<String?>((ref) async {
  return ref.watch(jellyfinServerProvider).probeVersion();
});

/// Whether the stored API key is accepted.
final jellyfinCredentialAcceptedProvider = FutureProvider<bool>((ref) async {
  return ref.watch(jellyfinServerProvider).verifyCredential();
});

/// Everything playing right now, most expensive first.
///
/// Not polled from here: the dashboard owns its own refresh cadence the way
/// `torrentDetailPollingProvider` does, and a timer buried in a data provider
/// would keep firing behind a screen nobody is looking at.
final jellyfinSessionsProvider = FutureProvider<List<StreamSession>>((
  ref,
) async {
  return ref.watch(jellyfinServerProvider).getSessions();
});

/// The libraries this server exposes.
final jellyfinLibrariesProvider = FutureProvider<List<StreamLibrary>>((
  ref,
) async {
  return ref.watch(jellyfinServerProvider).getLibraries();
});

/// Household members whose watch state a library can be read through.
///
/// Sourced from `/Users`, which is the only place a user id exists: the API key
/// authenticates as an administrator with no user attached, so this list is what
/// the settings picker fills `jellyfinUserId` from.
final jellyfinViewersProvider = FutureProvider<List<StreamViewer>>((ref) async {
  return ref.watch(jellyfinServerProvider).getViewers();
});

/// Rows per browse page.
///
/// Fifty is a screenful and change on the widest layout, and it stays under the
/// isolate-mapping threshold so a page costs no port round trip.
const int kJellyfinLibraryPageSize = 50;

/// Identifies one page of one library under one lens.
///
/// A record, so the family key gets structural equality for free — the pattern
/// `discoverByGenrePageProvider` already uses. The viewer is *not* part of it; see
/// [jellyfinClientProvider].
typedef JellyfinLibraryPageKey = ({
  String libraryId,
  StreamLibraryLens lens,
  int page,
});

/// One page of a library under one lens.
///
/// [JellyfinLibraryPageKey.page] is zero-based and converted to the API's
/// `startIndex` here, so no widget has to know that Jellyfin pages by offset
/// rather than by page number.
///
/// The request is cancelled if the page is disposed before it lands, which for a
/// list the user is scrolling quickly is most of them.
final jellyfinLibraryItemsProvider =
    FutureProvider.family<List<StreamItem>, JellyfinLibraryPageKey>((
      ref,
      key,
    ) async {
      final client = ref.watch(jellyfinServerProvider);
      final cancelToken = CancelToken();
      ref.onDispose(cancelToken.cancel);
      return client.getLibraryItems(
        libraryId: key.libraryId,
        lens: key.lens,
        startIndex: key.page * kJellyfinLibraryPageSize,
        limit: kJellyfinLibraryPageSize,
        cancelToken: cancelToken,
      );
    });

/// One item at any depth, by id.
///
/// Resolves from the id alone so `ServiceRoutes.jellyfinItem` works as a deep
/// link; `state.extra` stays preload/Hero data only.
final jellyfinItemProvider = FutureProvider.family<StreamItem?, String>((
  ref,
  itemId,
) async {
  final client = ref.watch(jellyfinServerProvider);
  final cancelToken = CancelToken();
  ref.onDispose(cancelToken.cancel);
  return client.getItem(itemId, cancelToken: cancelToken);
});

/// The children of a series, season or album — seasons, episodes or tracks.
///
/// Empty for a leaf item, which the client answers without a request.
final jellyfinItemChildrenProvider =
    FutureProvider.family<List<StreamItem>, String>((ref, itemId) async {
      final client = ref.watch(jellyfinServerProvider);
      final cancelToken = CancelToken();
      ref.onDispose(cancelToken.cancel);
      return client.getChildren(itemId, cancelToken: cancelToken);
    });
