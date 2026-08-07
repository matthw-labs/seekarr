import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/models/stream_library_page.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';
import 'package:cupola/features/stream/presentation/stream_library_screen.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_poster_tile.dart';

import '../../test_helpers/fake_secure_settings_store.dart';

/// A media server that answers whatever the test scripted, page by page.
///
/// Scripted by *start index* rather than by call order, because the thing under
/// test is precisely that the screen asks for the offset the server told it to.
class _ScriptedServer implements StreamServerClient {
  _ScriptedServer(
    this.pages, {
    this.lensPages = const {},
    this.gates = const {},
  });

  final Map<int, StreamLibraryPage> pages;

  /// Per-lens overrides, for the cases where two lenses must answer differently
  /// at the same offset.
  final Map<StreamLibraryLens, Map<int, StreamLibraryPage>> lensPages;

  /// Lenses whose requests hang until the test says otherwise.
  ///
  /// The only way to have a request still in flight while the screen does
  /// something else, which is what a stale fetch outliving its controller needs.
  final Map<StreamLibraryLens, Completer<void>> gates;

  final List<int> requested = [];
  final List<StreamLibraryLens> requestedLenses = [];

  @override
  Future<StreamLibraryPage> getLibraryPage({
    required String libraryId,
    required StreamLibraryLens lens,
    String? viewerId,
    int startIndex = 0,
    int limit = 50,
    CancelToken? cancelToken,
  }) async {
    requested.add(startIndex);
    requestedLenses.add(lens);
    final gate = gates[lens];
    if (gate != null) await gate.future;
    return lensPages[lens]?[startIndex] ??
        pages[startIndex] ??
        StreamLibraryPage.empty(startIndex: startIndex);
  }

  @override
  Future<List<StreamItem>> getLibraryItems({
    required String libraryId,
    required StreamLibraryLens lens,
    String? viewerId,
    int startIndex = 0,
    int limit = 50,
    CancelToken? cancelToken,
  }) async => (await getLibraryPage(
    libraryId: libraryId,
    lens: lens,
    startIndex: startIndex,
    limit: limit,
  )).items;

  @override
  StreamImageSource? imageFor(String posterPath, {int? width}) => null;

  @override
  Future<List<StreamItem>> getChildren(
    String itemId, {
    String? viewerId,
    CancelToken? cancelToken,
  }) async => const [];

  @override
  Future<StreamItem?> getItem(
    String itemId, {
    String? viewerId,
    CancelToken? cancelToken,
  }) async => null;

  @override
  Future<StreamItem?> findByExternalId({
    String? tmdbId,
    String? tvdbId,
    String? imdbId,
    CancelToken? cancelToken,
  }) async => null;

  @override
  Future<List<StreamLibrary>> getLibraries() async => const [];

  @override
  Future<List<StreamSession>> getSessions() async => const [];

  @override
  Future<List<StreamViewer>> getViewers() async => const [];

  @override
  Future<String?> probeVersion() async => '10.11.0';

  @override
  Future<bool> verifyCredential() async => true;

  @override
  Future<void> refreshLibrary(String libraryId) async {}

  @override
  Future<void> stopSession(String sessionId) async {}

  @override
  void close() {}
}

StreamItem _item(String id, String title) => StreamItem(
  id: id,
  title: title,
  subtitle: null,
  kind: StreamItemKind.movie,
  posterPath: null,
  year: 2016,
  runtimeMs: 7200000,
  isPlayed: false,
  resumeOffsetMs: null,
  unplayedChildCount: null,
);

StreamLibraryPage _page(
  List<StreamItem> items, {
  required int nextStartIndex,
  required bool hasMore,
}) => StreamLibraryPage(
  items: items,
  nextStartIndex: nextStartIndex,
  hasMore: hasMore,
);

Future<void> _pumpLibrary(
  WidgetTester tester,
  _ScriptedServer server, {
  ServiceKey service = ServiceKey.jellyfin,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [jellyfinServerProvider.overrideWithValue(server)],
      child: MaterialApp(
        home: StreamLibraryScreen(
          service: service,
          libraryId: 'lib-1',
          libraryTitle: 'Films',
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // A gated request leaves a spinner on screen, and a spinner never settles.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }
}

/// The library screen over a real `settingsProvider`, so a case can change a
/// setting the way the settings screen does and watch what the screen makes of
/// it. Returns the container so the test can drive that change.
Future<ProviderContainer> _pumpLibraryWithSettings(
  WidgetTester tester,
  _ScriptedServer server, {
  required SettingsModel settings,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
      initialSettingsProvider.overrideWith((ref) => settings),
      jellyfinServerProvider.overrideWithValue(server),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: StreamLibraryScreen(
          service: ServiceKey.jellyfin,
          libraryId: 'lib-1',
          libraryTitle: 'Films',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('the Stream library browse', () {
    testWidgets('starts at offset zero, not one page in', (tester) async {
      // `nextIntPageKey` starts at 1, so multiplying it by the page size made
      // the very first request skip the first fifty rows of every lens.
      final server = _ScriptedServer({
        0: _page([_item('a', 'Arrival')], nextStartIndex: 1, hasMore: false),
      });

      await _pumpLibrary(tester, server);

      expect(server.requested.first, 0);
      expect(find.byType(StreamPosterTile), findsOneWidget);
    });

    testWidgets('walks past a page the lens filtered down to nothing', (
      tester,
    ) async {
      // Plex has no separate continue/next-up endpoints, so one `onDeck`
      // response is split after mapping and a mid-list page can come back with
      // no rows while the next one is full. Stopping there — which is what
      // `lastPageIsEmpty` did — rendered "Nothing in progress" over a library
      // that had plenty, and `PagedLayoutBuilder` never asks again once the
      // accumulated count is zero.
      final server = _ScriptedServer({
        0: _page(const [], nextStartIndex: 50, hasMore: true),
        50: _page([_item('b', 'Solaris')], nextStartIndex: 100, hasMore: false),
      });

      await _pumpLibrary(tester, server);

      expect(server.requested, [0, 50]);
      expect(find.byType(StreamPosterTile), findsOneWidget);
      expect(find.text('Nothing in progress'), findsNothing);
    });

    testWidgets('advances by the offset the server reported', (tester) async {
      // Not `pageIndex * pageSize`: both servers are explicit that a response
      // may hold a different number of rows than was asked for.
      final server = _ScriptedServer({
        0: _page([_item('a', 'Arrival')], nextStartIndex: 37, hasMore: true),
        37: _page([_item('b', 'Solaris')], nextStartIndex: 74, hasMore: false),
      });

      await _pumpLibrary(tester, server);
      await tester.pumpAndSettle();

      expect(server.requested, [0, 37]);
    });

    testWidgets('stops when the server says "more" without moving on', (
      tester,
    ) async {
      // Jellyfin computes `nextStartIndex` from the rows it sent while
      // `hasMore` compares it against `TotalRecordCount`, so an endpoint that
      // filters rows away server-side answers zero rows, an unmoved offset and
      // `hasMore: true`. Taking that at its word re-requested the same offset
      // forever: the fetch burnt its attempts, the controller appended an empty
      // page, and `PagedLayoutBuilder` fired the next fetch straight back while
      // the user sat at the bottom of the grid.
      final server = _ScriptedServer({
        0: _page([_item('a', 'Arrival')], nextStartIndex: 50, hasMore: true),
        50: _page(const [], nextStartIndex: 50, hasMore: true),
      });

      await _pumpLibrary(tester, server);
      await tester.pumpAndSettle();

      expect(server.requested, [0, 50]);
      expect(find.byType(StreamPosterTile), findsOneWidget);
    });

    testWidgets('a fetch left behind by a lens change is abandoned', (
      tester,
    ) async {
      // The offset lives on the State now, which means it is shared across a
      // controller rebuild in a way `PagingState` never was — and
      // `PagingController.dispose` only detaches the result, it does not stop
      // the fetch. So the fetch has to be fenced: a stale one must not issue a
      // second request (under the *new* lens, since it read the field fresh)
      // and must not write the new lens's offset.
      final gate = Completer<void>();
      final server = _ScriptedServer(
        const {},
        lensPages: {
          // Empty but "there is more", so an unfenced fetch walks on to a
          // second request — the observable symptom.
          StreamLibraryLens.continueWatching: {
            0: _page(const [], nextStartIndex: 50, hasMore: true),
          },
          StreamLibraryLens.all: {
            0: _page(
              [_item('a', 'Arrival')],
              nextStartIndex: 50,
              hasMore: false,
            ),
          },
        },
        gates: {StreamLibraryLens.continueWatching: gate},
      );

      await _pumpLibrary(tester, server, settle: false);
      expect(server.requestedLenses, [StreamLibraryLens.continueWatching]);

      // Switch lens while Continue's first page is still in flight. A–Z is not
      // gated, so it answers straight away.
      await tester.tap(find.text('A–Z'));
      await tester.pumpAndSettle();

      gate.complete();
      await tester.pumpAndSettle();

      expect(server.requested, [0, 0]);
      expect(server.requestedLenses, [
        StreamLibraryLens.continueWatching,
        StreamLibraryLens.all,
      ]);
      expect(find.byType(StreamPosterTile), findsOneWidget);
    });

    testWidgets('a failed first page offers a retry, never "empty"', (
      tester,
    ) async {
      // Both clients degrade a remote failure to an empty list, so a browse that
      // only saw rows told the user "This library is empty · The server reports
      // no items here" about a server that had not answered at all.
      final server = _ScriptedServer({
        0: const StreamLibraryPage.failed(startIndex: 0),
      });

      await _pumpLibrary(tester, server);

      expect(find.text('This library is empty'), findsNothing);
      expect(find.text('The server reports no items here'), findsNothing);
      expect(find.text('Nothing in progress'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('a mid-list failure keeps the rows and offers a retry', (
      tester,
    ) async {
      // The old behaviour was a silent truncation: no spinner, no message, no
      // way to ask for the rest.
      final server = _ScriptedServer({
        0: _page([_item('a', 'Arrival')], nextStartIndex: 50, hasMore: true),
        50: const StreamLibraryPage.failed(startIndex: 50),
      });

      await _pumpLibrary(tester, server);
      await tester.pumpAndSettle();

      expect(find.byType(StreamPosterTile), findsOneWidget);
      expect(find.textContaining('Couldn’t load more'), findsOneWidget);
    });

    testWidgets('no viewer names the setting instead of claiming empty', (
      tester,
    ) async {
      // A Jellyfin API key is an administrator with no user attached, so
      // "continue watching" has no subject until one is chosen — and the picker
      // lives in settings, which this screen offers no path to on its own.
      final server = _ScriptedServer({
        0: const StreamLibraryPage.viewerRequired(),
      });

      await _pumpLibrary(tester, server);

      expect(find.text('Nothing in progress'), findsNothing);
      expect(find.text('Choose whose watch state to show'), findsOneWidget);
      expect(find.text('Pick a viewer'), findsOneWidget);
    });

    testWidgets('choosing a viewer resolves the panel that asked for one', (
      tester,
    ) async {
      // The panel's whole point is that the user has something to act on. The
      // action lives on another route, nothing else here reads settings, and
      // `PagedLayoutBuilder` never retries a first-page error — so coming back
      // used to find the same "Choose whose watch state to show", with the
      // viewer already chosen.
      final server = _ScriptedServer({
        0: const StreamLibraryPage.viewerRequired(),
      });

      final container = await _pumpLibraryWithSettings(
        tester,
        server,
        settings: const SettingsModel(
          jellyfinUrl: 'https://jellyfin.lan:8096',
          jellyfinApiKey: 'abcdef1234567890',
        ),
      );
      expect(find.text('Choose whose watch state to show'), findsOneWidget);

      // What the settings screen does when a household member is picked.
      server.pages[0] = _page(
        [_item('a', 'Arrival')],
        nextStartIndex: 1,
        hasMore: false,
      );
      await container
          .read(settingsProvider.notifier)
          .updateSettings(
            container.read(settingsProvider).copyWith(jellyfinUserId: 'u-1'),
          );
      await tester.pumpAndSettle();

      expect(find.text('Choose whose watch state to show'), findsNothing);
      expect(find.byType(StreamPosterTile), findsOneWidget);
    });

    testWidgets('a genuinely empty lens still reads as empty', (tester) async {
      // The distinction has to cut both ways: an answered request with nothing
      // in it is an empty state, and offering a retry there would be noise.
      final server = _ScriptedServer({0: const StreamLibraryPage.empty()});

      await _pumpLibrary(tester, server);

      expect(find.text('Nothing in progress'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });
  });
}
