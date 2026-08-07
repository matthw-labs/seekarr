import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/features/jellyfin/data/jellyfin_client.dart';
import 'package:seekarr/features/stream/domain/models/stream_item.dart';
import 'package:seekarr/features/stream/domain/models/stream_library.dart';
import 'package:seekarr/features/stream/domain/models/stream_library_page.dart';
import 'package:seekarr/features/stream/domain/models/stream_session.dart';

import '../../../test_helpers/capturing_http_adapter.dart';
import '../../../test_helpers/fixtures.dart';

/// Ids from the fixtures, named so an assertion reads as the thing it is about.
const _moviesLibraryId = 'f137a2dd21bbc1b99aa5c0f6bf02a805';
const _showsLibraryId = 'a656b907eb3a73532e40e44b968d0225';
const _seriesId = '0f4b8d2a6c1e39574a8b2c6d0e4f8192';
const _seasonId = '6d2a8c4e0b1f39578a3c7e1b5d9f0246';
const _albumId = '5c9e3a7d1f5b9c3e7a1d5f9b3c7e1a50';
const _movieId = '3ca7ff1e0d9b4e2f8a6c5b4d3e2f1a09';
const _viewerId = '8c4f2a1e9b7d4c3a8f5e2d1c9b8a7f6e';

/// [CapturingHttpAdapter] records only the last request; a few of these tests
/// need the whole conversation (how many round trips, and in what order).
class _ConversationAdapter extends CapturingHttpAdapter {
  _ConversationAdapter({super.response, super.statusCode, super.byPath});

  final List<Uri> uris = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    uris.add(options.uri);
    return super.fetch(options, requestStream, cancelFuture);
  }

  Iterable<Uri> matching(String fragment) =>
      uris.where((uri) => uri.path.contains(fragment));
}

/// A client whose transport is stubbed but whose request building — base URL,
/// headers, query parameters — is entirely its own.
JellyfinClient _client(
  CapturingHttpAdapter adapter, {
  String apiKey = 'SECRET-KEY',
  String userId = _viewerId,
  String clientName = 'Seekarr',
}) {
  final client = JellyfinClient(
    baseUrl: 'https://jf.test',
    apiKey: apiKey,
    userId: userId,
    clientName: clientName,
    // Pinned rather than derived, so the expected header is the same on every
    // machine that runs this suite.
    deviceName: 'macos',
    deviceId: 'DEVICE-ID-1',
    appVersion: '0.8.0',
  );
  client.dio.httpClientAdapter = adapter;
  addTearDown(client.close);
  return client;
}

/// Dio keeps request headers in a case-insensitive map, but not every version
/// agrees on the stored casing — so look the header up without assuming.
String? _authorization(CapturingHttpAdapter adapter) {
  for (final entry in (adapter.lastHeaders ?? const {}).entries) {
    if (entry.key.toLowerCase() == 'authorization') {
      return entry.value?.toString();
    }
  }
  return null;
}

void main() {
  group('authorization header', () {
    test('is the exact MediaBrowser form 10.11 accepts', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('jellyfin/system_info_public.json'),
      );
      await _client(adapter).probeVersion();

      // Scheme word, then comma-separated Key="Value" pairs. The keys are
      // case-sensitive server-side and the values must be double-quoted; drop
      // either and `AuthorizationContext` reads no token at all.
      expect(
        _authorization(adapter),
        'MediaBrowser Token="SECRET-KEY", Client="Seekarr", Device="macos", '
        'DeviceId="DEVICE-ID-1", Version="0.8.0"',
      );
    });

    test('URL-encodes a comma so the pair after it cannot be swallowed', () async {
      final adapter = CapturingHttpAdapter(response: const {});
      // The server URL-decodes each value, so a literal comma inside one would
      // split the pair and silently drop everything after it — including, for a
      // differently ordered header, the token itself.
      await _client(adapter, clientName: 'Seekarr, Ltd "beta"').probeVersion();

      final header = _authorization(adapter)!;
      expect(header, contains('Client="Seekarr%2C%20Ltd%20%22beta%22"'));
      expect(header, contains('Token="SECRET-KEY"'));
      // Exactly five pairs: the encoded comma did not create a sixth.
      expect(header.split(', '), hasLength(5));
    });

    test('travels on every request, not just the first', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureList('jellyfin/users.json'),
      );
      final client = _client(adapter);
      await client.getViewers();
      expect(_authorization(adapter), startsWith('MediaBrowser Token='));
    });

    test('the default DeviceId is stable and opaque', () {
      // Jellyfin registers a device row per distinct id, so this must not change
      // between launches. Derived rather than random precisely so it survives
      // without being persisted anywhere.
      final first = defaultJellyfinDeviceId('macos');
      expect(first, defaultJellyfinDeviceId('macos'));
      expect(first, hasLength(32));
      expect(first, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(first, isNot(defaultJellyfinDeviceId('android')));
    });
  });

  group('probeVersion', () {
    test('reads the credential-free public endpoint', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('jellyfin/system_info_public.json'),
      );

      expect(await _client(adapter).probeVersion(), '10.11.11');
      expect(adapter.lastUri!.path, '/System/Info/Public');
    });

    test('returns null when the address answers but is not a Jellyfin', () async {
      // A reverse-proxy landing page returns 200 with a body that decodes fine.
      // Reporting a version here would tell the user the server is healthy.
      final adapter = CapturingHttpAdapter(response: const {'app': 'nginx'});
      expect(await _client(adapter).probeVersion(), isNull);
    });

    test(
      'a 503 during server startup is "no version yet", not a throw',
      () async {
        final adapter = CapturingHttpAdapter(
          response: const {'error': 'starting'},
          statusCode: 503,
        );
        expect(await _client(adapter).probeVersion(), isNull);
      },
    );
  });

  group('verifyCredential', () {
    test('uses the authenticated twin of the probe', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('jellyfin/system_info_public.json'),
      );
      expect(await _client(adapter).verifyCredential(), isTrue);
      expect(adapter.lastUri!.path, '/System/Info');
    });

    test('a rejected token is false, not an exception', () async {
      final adapter = CapturingHttpAdapter(response: '', statusCode: 401);
      expect(await _client(adapter).verifyCredential(), isFalse);
    });

    test('a valid but under-privileged key is also false', () async {
      final adapter = CapturingHttpAdapter(response: '', statusCode: 403);
      expect(await _client(adapter).verifyCredential(), isFalse);
    });
  });

  group('getSessions', () {
    test('an idle server is connected clients with nothing playing', () async {
      // Jellyfin's idle shape is the trap: `/Sessions` returns every *connected*
      // client, so the array is full while nobody is watching. Only
      // `NowPlayingItem` separates the two.
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureList('jellyfin/sessions_idle.json'),
      );

      final sessions = await _client(adapter).getSessions();

      expect(sessions, isEmpty);
      expect(
        adapter.lastUri!.queryParameters['activeWithinSeconds'],
        '${JellyfinClient.kActiveWithinSeconds}',
      );
    });

    test('a direct play reports the file bitrate, flagged as nominal', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureList('jellyfin/sessions_active.json'),
      );
      final sessions = await _client(adapter).getSessions();

      final directPlay = sessions.firstWhere(
        (session) => session.playMethod == StreamPlayMethod.directPlay,
      );
      expect(directPlay.id, '7c1e4b9d3a6f42508d2b7e1c5a9f3d60');
      expect(directPlay.userName, 'flatmate');
      expect(directPlay.title, 'Dune: Part Two');
      expect(directPlay.subtitle, '2024');
      expect(directPlay.deviceLabel, 'Infuse-Library · Apple TV');
      // No rate field exists for a direct play, so this is the source file's own
      // bitrate and must never be presented as measured throughput.
      //
      // The fixture keeps two versions of this film — a 24 Mbps encode and a
      // 60 Mbps remux — and `PlayState.MediaSourceId` names the encode. Reading
      // the largest, or the first, `MediaSources` entry would put 60 Mbps on the
      // one row the whole board exists to make trustworthy.
      expect(directPlay.bitrate, 24305112);
      expect(directPlay.bitrateIsNominal, isTrue);
      expect(directPlay.transcodeReasons, isEmpty);
      expect(directPlay.needsAttention, isFalse);
      expect(directPlay.progress, 0.25);
      expect(directPlay.isPaused, isFalse);
      expect(
        directPlay.posterPath,
        '/Items/b4d8f2a6c1e34957ba0d6f8e2c4a1b39/Images/Primary'
        '?tag=e91f6a0c4d7b2e8f5a3c1b9d0e2f4a68',
      );
    });

    test('a transcode explains itself and reports the encoder target', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureList('jellyfin/sessions_active.json'),
      );
      final sessions = await _client(adapter).getSessions();

      // Most expensive first: the transcode is second in the payload and has the
      // *lower* bitrate of the two, and still sorts to the top.
      final transcode = sessions.first;
      expect(transcode.playMethod, StreamPlayMethod.transcode);
      expect(transcode.needsAttention, isTrue);
      expect(transcode.id, '2a8f6d4b0c1e49735f9a2c6b8d0e1f37');
      expect(transcode.transcodeReasons, [
        'Client cannot decode this video codec',
        'Client cannot decode this audio codec',
        'Subtitles have to be burned in',
      ]);
      expect(
        transcode.transcodeReasonLabel,
        'Client cannot decode this video codec · '
        'Client cannot decode this audio codec · '
        'Subtitles have to be burned in',
      );
      // TranscodingInfo.Bitrate is the encoder's actual target, so this one is
      // real rather than nominal.
      expect(transcode.bitrate, 5616000);
      expect(transcode.bitrateIsNominal, isFalse);
      // An episode leads with the series; the episode is the detail line.
      expect(transcode.title, 'Severance');
      expect(transcode.subtitle, "S2E4 · Woe's Hollow");
      expect(transcode.deviceLabel, 'Jellyfin Web · Chrome');
      expect(transcode.progress, 0.5);
      expect(transcode.isPaused, isTrue);
      // This episode carries no image of its own at all (`ImageTags: {}`), so the
      // poster falls back to the series rather than leaving a grey rectangle.
      expect(
        transcode.posterPath,
        '/Items/$_seriesId/Images/Primary'
        '?tag=77aa11bb22cc33dd44ee55ff66009988',
      );
    });

    test('idle clients are dropped from a mixed payload', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureList('jellyfin/sessions_active.json'),
      );
      // Three connected clients, two of them playing.
      expect(await _client(adapter).getSessions(), hasLength(2));
    });
  });

  group('stopSession', () {
    test('posts to the session id', () async {
      final adapter = CapturingHttpAdapter(response: '', statusCode: 204);
      await _client(adapter).stopSession('2a8f6d4b0c1e49735f9a2c6b8d0e1f37');

      expect(
        adapter.lastUri!.path,
        '/Sessions/2a8f6d4b0c1e49735f9a2c6b8d0e1f37/Playing/Stop',
      );
      expect(adapter.lastRequest!.method, 'POST');
    });

    test('surfaces its failure — a write action, unlike the read paths', () {
      final adapter = CapturingHttpAdapter(response: '', statusCode: 500);
      expect(_client(adapter).stopSession('abc'), throwsA(isA<DioException>()));
    });
  });

  group('getLibraries', () {
    test('maps virtual folders, and skips one that cannot be browsed', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureList('jellyfin/virtual_folders.json'),
      );

      final libraries = await _client(adapter).getLibraries();

      expect(adapter.lastUri!.path, '/Library/VirtualFolders');
      // The fixture's fifth entry has an empty ItemId — nothing to pass as
      // parentId, so listing it would only offer a dead end.
      expect(libraries, hasLength(4));

      final films = libraries.first;
      // `ItemId`, not `Id` and not the name: this is the value /Items scopes on.
      expect(films.id, _moviesLibraryId);
      expect(films.name, 'Films');
      expect(films.kind, StreamLibraryKind.movies);
      expect(films.isRefreshing, isFalse);
      // No per-library count exists on VirtualFolderInfo.
      expect(films.itemCount, isNull);
      // **Always null on Jellyfin**: scanning is one global scheduled task and no
      // per-library completion time is exposed anywhere in the API.
      expect(films.lastScannedAt, isNull);

      expect(libraries[1].kind, StreamLibraryKind.shows);
      expect(libraries[1].isRefreshing, isTrue);
      expect(libraries[2].kind, StreamLibraryKind.music);
      // No CollectionType at all — a mixed library, which must still render.
      expect(libraries[3].kind, StreamLibraryKind.other);
      expect(libraries[3].isRefreshing, isFalse);
    });
  });

  group('refreshLibrary', () {
    test('passes both refresh modes, which default to None', () async {
      final adapter = CapturingHttpAdapter(response: '', statusCode: 204);
      await _client(adapter).refreshLibrary(_moviesLibraryId);

      expect(adapter.lastUri!.path, '/Items/$_moviesLibraryId/Refresh');
      expect(adapter.lastRequest!.method, 'POST');
      // Omit either and the endpoint queues a task that does nothing, then
      // answers 204 as though it worked.
      final query = adapter.lastUri!.queryParameters;
      expect(query['metadataRefreshMode'], 'Default');
      expect(query['imageRefreshMode'], 'Default');
      // Not FullRefresh: "rescan this library" must not re-download every
      // provider's metadata for every item.
      expect(query['replaceAllMetadata'], 'false');
      expect(query['replaceAllImages'], 'false');
    });
  });

  group('getLibraryItems', () {
    _ConversationAdapter browseAdapter({Object? items, int statusCode = 200}) =>
        _ConversationAdapter(
          statusCode: statusCode,
          byPath: {
            'Library/VirtualFolders': jsonFixtureList(
              'jellyfin/virtual_folders.json',
            ),
            'UserItems/Resume': jsonFixtureMap('jellyfin/resume_items.json'),
            'Shows/NextUp': jsonFixtureMap('jellyfin/next_up.json'),
            'Items': items ?? jsonFixtureMap('jellyfin/items_movies_page.json'),
          },
        );

    test('recentlyAdded sorts by DateCreated inside the library', () async {
      final adapter = browseAdapter();
      final items = await _client(adapter).getLibraryItems(
        libraryId: _moviesLibraryId,
        lens: StreamLibraryLens.recentlyAdded,
      );

      final query = adapter.matching('/Items').last.queryParameters;
      expect(query['parentId'], _moviesLibraryId);
      expect(query['sortBy'], 'DateCreated');
      expect(query['sortOrder'], 'Descending');
      // Without `recursive` the endpoint returns the library's folders rather
      // than what is in them.
      expect(query['recursive'], 'true');
      expect(query['includeItemTypes'], 'Movie');
      expect(query['startIndex'], '0');
      expect(query['limit'], '50');
      expect(items, hasLength(3));
    });

    test('maps a page: runtime in ms, resume point, watched state', () async {
      final items = await _client(browseAdapter()).getLibraryItems(
        libraryId: _moviesLibraryId,
        lens: StreamLibraryLens.all,
      );

      final partWatched = items.first;
      expect(partWatched.id, _movieId);
      expect(partWatched.title, 'Arrival');
      expect(partWatched.subtitle, '2016');
      expect(partWatched.kind, StreamItemKind.movie);
      expect(partWatched.year, 2016);
      // 72e9 ticks is two hours: 7 200 000 ms.
      expect(partWatched.runtimeMs, 7200000);
      expect(partWatched.resumeOffsetMs, 1800000);
      expect(partWatched.resumeProgress, 0.25);
      expect(partWatched.isInProgress, isTrue);
      expect(partWatched.isPlayed, isFalse);
      expect(
        partWatched.posterPath,
        '/Items/$_movieId/Images/Primary?tag=1f2e3d4c5b6a70819283a4b5c6d7e8f9',
      );

      final finished = items[1];
      expect(finished.isPlayed, isTrue);
      // `PlaybackPositionTicks: 0` is "never started", not "0 ms in".
      expect(finished.resumeOffsetMs, isNull);
      expect(finished.resumeProgress, isNull);

      final unprobed = items[2];
      // `RunTimeTicks: 0` must not render as a zero-length film.
      expect(unprobed.runtimeMs, isNull);
      expect(unprobed.posterPath, isNull);
      expect(unprobed.isPlayed, isFalse);
    });

    test('unplayed filters server-side and names the viewer', () async {
      final adapter = browseAdapter();
      await _client(adapter).getLibraryItems(
        libraryId: _moviesLibraryId,
        lens: StreamLibraryLens.unplayed,
      );

      final query = adapter.matching('/Items').last.queryParameters;
      expect(query['isPlayed'], 'false');
      expect(query['sortBy'], 'SortName');
      // An API key has an empty UserId claim, so the watch state has to be asked
      // for on someone's behalf explicitly.
      expect(query['userId'], _viewerId);
      expect(query['enableUserData'], 'true');
    });

    test('continueWatching uses the non-deprecated resume endpoint', () async {
      final adapter = browseAdapter();
      final items = await _client(adapter).getLibraryItems(
        libraryId: _showsLibraryId,
        lens: StreamLibraryLens.continueWatching,
      );

      final request = adapter.matching('/UserItems/Resume').single;
      expect(request.queryParameters['userId'], _viewerId);
      expect(request.queryParameters['parentId'], _showsLibraryId);
      // What somebody is watching right now belongs on the session board, not
      // duplicated into their own continue-watching row.
      expect(request.queryParameters['excludeActiveSessions'], 'true');
      // No `sortBy`: this endpoint is always DatePlayed desc.
      expect(request.queryParameters.containsKey('sortBy'), isFalse);
      // The `/Items` lenses were not consulted, so no library lookup happened.
      expect(adapter.matching('Library/VirtualFolders'), isEmpty);

      final episode = items.first;
      expect(episode.kind, StreamItemKind.episode);
      expect(episode.title, "Woe's Hollow");
      expect(episode.subtitle, 'Severance · S2E4');
      // This item reports `PlayedPercentage: 40.0` and no position ticks — a
      // 0-100 double, so 40% of 2 700 000 ms.
      expect(episode.runtimeMs, 2700000);
      expect(episode.resumeOffsetMs, 1080000);
      expect(episode.resumeProgress, closeTo(0.4, 0.0001));
    });

    test('nextUp asks the Shows endpoint for the viewer', () async {
      final adapter = browseAdapter();
      final items = await _client(adapter).getLibraryItems(
        libraryId: _showsLibraryId,
        lens: StreamLibraryLens.nextUp,
      );

      final request = adapter.matching('/Shows/NextUp').single;
      // 404s outright without a userId.
      expect(request.queryParameters['userId'], _viewerId);
      expect(request.queryParameters['parentId'], _showsLibraryId);
      expect(request.queryParameters['enableRewatching'], 'false');
      expect(items.single.title, 'Sweet Vitriol');
      // Thumb-only episode: asking for a Primary image that does not exist would
      // 404, so the tag that is actually there is used — and the item's own art
      // beats the `SeriesPrimaryImageTag` this fixture also carries, so an
      // episode list does not mix stills with series posters row by row.
      expect(
        items.single.posterPath,
        '/Items/e2b6d0a4c8f13957b1d5f9a3c7e1b502/Images/Thumb'
        '?tag=3c5e7a9b1d3f5709a1c3e5b7d9f10204',
      );
    });

    test('a per-viewer lens with no viewer asks nothing at all', () async {
      final adapter = browseAdapter();
      // No `jellyfinUserId` configured and no override: the endpoint would 404,
      // so the lens degrades to empty without spending a round trip.
      final items = await _client(adapter, userId: '').getLibraryItems(
        libraryId: _showsLibraryId,
        lens: StreamLibraryLens.nextUp,
      );

      expect(items, isEmpty);
      expect(adapter.callCount, 0);
    });

    test(
      'a per-viewer lens with no viewer says so rather than "empty"',
      () async {
        // The envelope is the whole point: `[]` and "we never asked" are the same
        // list, and a browse that could not tell them apart told the user their
        // library was empty when they had simply not chosen a household member.
        final page = await _client(browseAdapter(), userId: '').getLibraryPage(
          libraryId: _showsLibraryId,
          lens: StreamLibraryLens.nextUp,
        );

        expect(page.outcome, StreamPageOutcome.viewerRequired);
        expect(page.needsViewer, isTrue);
        expect(page.failed, isFalse);
      },
    );

    test(
      'A–Z is answered without a viewer, being the same wall for everyone',
      () async {
        // `/Items?parentId=…&sortBy=SortName` takes `userId` as strictly optional
        // and only loses `UserData` without it. Scoping A–Z to a viewer made the
        // client refuse a request that works, and told a connected-but-unpicked
        // user their library was empty.
        final adapter = browseAdapter();
        final items = await _client(adapter, userId: '').getLibraryItems(
          libraryId: _moviesLibraryId,
          lens: StreamLibraryLens.all,
        );

        expect(items, isNotEmpty);
        final query = adapter.matching('/Items').last.queryParameters;
        expect(query['sortBy'], 'SortName');
        expect(query.containsKey('userId'), isFalse);
        expect(query.containsKey('enableUserData'), isFalse);
      },
    );

    test('a page carries the server’s own offset and total', () async {
      // A pager may not advance by the page size it asked for, nor stop because
      // the rows it received were empty: both are inferences, and
      // `TotalRecordCount` is the fact.
      final page = await _client(browseAdapter()).getLibraryPage(
        libraryId: _moviesLibraryId,
        lens: StreamLibraryLens.all,
      );

      expect(page.outcome, StreamPageOutcome.ok);
      expect(page.items, hasLength(3));
      // Three rows from offset zero, against a TotalRecordCount of three.
      expect(page.nextStartIndex, 3);
      expect(page.hasMore, isFalse);
    });

    test('a failed page is a failure, not an empty library', () async {
      // The read path still degrades to `[]` for callers that only want rows;
      // the envelope is what lets a browse offer a retry instead of stating
      // that the server reports no items.
      final client = _client(browseAdapter(statusCode: 503));

      final page = await client.getLibraryPage(
        libraryId: _moviesLibraryId,
        lens: StreamLibraryLens.all,
        startIndex: 100,
      );

      expect(page.failed, isTrue);
      expect(page.items, isEmpty);
      // Echoed back so a retry resumes where it stopped.
      expect(page.nextStartIndex, 100);
      expect(
        await client.getLibraryItems(
          libraryId: _moviesLibraryId,
          lens: StreamLibraryLens.all,
        ),
        isEmpty,
      );
    });

    test('recentlyAdded still works with no viewer configured', () async {
      final adapter = browseAdapter();
      final items = await _client(adapter, userId: '').getLibraryItems(
        libraryId: _moviesLibraryId,
        lens: StreamLibraryLens.recentlyAdded,
      );

      expect(items, isNotEmpty);
      final query = adapter.matching('/Items').last.queryParameters;
      expect(query.containsKey('userId'), isFalse);
      expect(query.containsKey('enableUserData'), isFalse);
    });

    test('an explicit viewerId overrides the configured one', () async {
      final adapter = browseAdapter();
      await _client(adapter).getLibraryItems(
        libraryId: _showsLibraryId,
        lens: StreamLibraryLens.nextUp,
        viewerId: 'OTHER-VIEWER',
      );
      expect(
        adapter.matching('/Shows/NextUp').single.queryParameters['userId'],
        'OTHER-VIEWER',
      );
    });

    test('a deep link looks the library kind up once, then caches it', () async {
      // `/services/jellyfin/library/<id>` can be opened cold, with no library
      // list ever loaded, so the type filter has to be recoverable from the id.
      final adapter = browseAdapter();
      final client = _client(adapter);

      await client.getLibraryItems(
        libraryId: _showsLibraryId,
        lens: StreamLibraryLens.all,
      );
      await client.getLibraryItems(
        libraryId: _showsLibraryId,
        lens: StreamLibraryLens.all,
        startIndex: 50,
      );

      expect(adapter.matching('Library/VirtualFolders'), hasLength(1));
      final requests = adapter.matching('/Items').toList();
      // A TV library browses as shows; without this the A-Z page would interleave
      // series, seasons and every episode.
      expect(requests.first.queryParameters['includeItemTypes'], 'Series');
      expect(requests.last.queryParameters['startIndex'], '50');
    });

    test('a failed library lookup is not cached, so the next page retries', () async {
      // The lookup degrades to `[]` rather than throwing, so "it failed" and "this
      // server has no libraries" arrive identically. Caching that would leave
      // every later page of this library unfiltered for the life of the client —
      // an A-Z page interleaving series, seasons and episodes, with no way back
      // short of restarting the app.
      final adapter = browseAdapter(statusCode: 500);
      final client = _client(adapter);

      expect(
        await client.getLibraryItems(
          libraryId: _showsLibraryId,
          lens: StreamLibraryLens.all,
        ),
        isEmpty,
      );
      expect(adapter.matching('Library/VirtualFolders'), hasLength(1));

      adapter.statusCode = 200;
      final items = await client.getLibraryItems(
        libraryId: _showsLibraryId,
        lens: StreamLibraryLens.all,
      );

      // Asked again, and this time the filter is recovered.
      expect(adapter.matching('Library/VirtualFolders'), hasLength(2));
      expect(
        adapter.matching('/Items').last.queryParameters['includeItemTypes'],
        'Series',
      );
      expect(items, isNotEmpty);
    });

    test('pages by startIndex rather than page number', () async {
      final adapter = browseAdapter();
      await _client(adapter).getLibraryItems(
        libraryId: _moviesLibraryId,
        lens: StreamLibraryLens.all,
        startIndex: 100,
        limit: 25,
      );
      final query = adapter.matching('/Items').last.queryParameters;
      expect(query['startIndex'], '100');
      expect(query['limit'], '25');
    });

    test('a large page is mapped without dropping anything', () async {
      // Past the isolate threshold, so this exercises the `Isolate.run` path
      // rather than the inline one — and proves the mapper is sendable.
      final page = jsonFixtureMap('jellyfin/items_movies_page.json');
      final template = (page['Items'] as List).first;
      final items =
          await _client(
            browseAdapter(
              items: {
                'Items': List.generate(400, (_) => template),
                'TotalRecordCount': 400,
                'StartIndex': 0,
              },
            ),
          ).getLibraryItems(
            libraryId: _moviesLibraryId,
            lens: StreamLibraryLens.all,
            limit: 400,
          );

      expect(items, hasLength(400));
      expect(items.last.runtimeMs, 7200000);
    });
  });

  group('getItem', () {
    test('passes the viewer as a query parameter and maps the item', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('jellyfin/item_movie.json'),
      );
      final item = await _client(adapter).getItem(_movieId);

      expect(adapter.lastUri!.path, '/Items/$_movieId');
      expect(adapter.lastUri!.queryParameters['userId'], _viewerId);
      // This endpoint ignores `fields`, so sending any would be noise.
      expect(adapter.lastUri!.queryParameters.containsKey('fields'), isFalse);
      expect(item!.title, 'Arrival');
      expect(item.runtimeMs, 7200000);
      expect(item.resumeOffsetMs, 1800000);
    });

    test('resolves without a viewer, losing only the watch state', () async {
      // `userId` is a `Guid?` on this endpoint: omitting it costs the `UserData`
      // block and nothing else. Refusing to call at all without one is what made
      // a deep link into `/services/jellyfin/item/<id>` render "Not on the
      // server" on an install where the item plainly was.
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('jellyfin/item_movie.json'),
      );
      final item = await _client(adapter, userId: '').getItem(_movieId);

      expect(item, isNotNull);
      expect(item!.title, 'Arrival');
      expect(adapter.callCount, 1);
      expect(adapter.lastUri!.queryParameters.containsKey('userId'), isFalse);
    });
  });

  group('getChildren', () {
    test('a series lists its seasons', () async {
      final adapter = _ConversationAdapter(
        byPath: {
          'Seasons': jsonFixtureMap('jellyfin/seasons.json'),
          'Items/': jsonFixtureMap('jellyfin/item_series.json'),
        },
      );
      final seasons = await _client(adapter).getChildren(_seriesId);

      // The type is not in the id, so the item is probed first.
      expect(adapter.uris.first.path, '/Items/$_seriesId');
      expect(adapter.uris.last.path, '/Shows/$_seriesId/Seasons');
      expect(seasons, hasLength(3));
      expect(seasons.first.kind, StreamItemKind.season);
      expect(seasons.first.title, 'Specials');
      expect(seasons.first.subtitle, 'Severance');
      expect(seasons[1].isPlayed, isTrue);
      expect(seasons[1].unplayedChildCount, 0);
      expect(seasons[2].unplayedChildCount, 6);
    });

    test('a season asks the SERIES for episodes, filtered by season', () async {
      final adapter = _ConversationAdapter(
        byPath: {
          'Episodes': jsonFixtureMap('jellyfin/episodes.json'),
          'Items/': jsonFixtureMap('jellyfin/item_season.json'),
        },
      );
      final episodes = await _client(adapter).getChildren(_seasonId);

      // The whole reason the probe exists: `/Shows/{id}/Episodes` takes the
      // *series* id even when listing one season, and a season id does not
      // contain its parent's.
      final request = adapter.uris.last;
      expect(request.path, '/Shows/$_seriesId/Episodes');
      expect(request.queryParameters['seasonId'], _seasonId);
      expect(request.queryParameters['sortBy'], 'AiredEpisodeOrder');
      expect(request.queryParameters['userId'], _viewerId);

      expect(episodes, hasLength(3));
      expect(episodes.first.kind, StreamItemKind.episode);
      expect(episodes.first.title, 'Hello, Ms. Cobel');
      expect(episodes.first.subtitle, 'Severance · S2E1');
      expect(episodes.first.isPlayed, isTrue);
      // 30 600 000 000 ticks → 51 minutes.
      expect(episodes.first.runtimeMs, 3060000);
      expect(episodes.last.resumeOffsetMs, 468000);
    });

    test('an album lists its tracks in disc/track order', () async {
      final adapter = _ConversationAdapter(
        byPath: {
          'Items?': jsonFixtureMap('jellyfin/tracks.json'),
          'Items/': jsonFixtureMap('jellyfin/item_album.json'),
        },
        response: jsonFixtureMap('jellyfin/tracks.json'),
      );
      final tracks = await _client(adapter).getChildren(_albumId);

      final request = adapter.uris.last;
      expect(request.queryParameters['parentId'], _albumId);
      expect(
        request.queryParameters['sortBy'],
        'ParentIndexNumber,IndexNumber,SortName',
      );
      expect(tracks, hasLength(2));
      expect(tracks.first.kind, StreamItemKind.track);
      expect(tracks.first.title, 'Intro');
      // The artist credit contains a comma, which is fine in a payload — only a
      // header value has to escape one.
      expect(tracks.first.subtitle, 'Black Country, New Road');
      expect(
        tracks.first.posterPath,
        '/Items/$_albumId/Images/Primary?tag=4d6f8a0c2e4557799bbddff113355779',
      );
    });

    test('a leaf item spends one request, not two', () async {
      final adapter = _ConversationAdapter(
        response: jsonFixtureMap('jellyfin/item_movie.json'),
      );
      expect(await _client(adapter).getChildren(_movieId), isEmpty);
      expect(adapter.uris, hasLength(1));
    });
  });

  group('getViewers', () {
    test('lists household members and drops disabled accounts', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureList('jellyfin/users.json'),
      );
      final viewers = await _client(adapter).getViewers();

      expect(adapter.lastUri!.path, '/Users');
      // /Users is the only source of a user id, because the API key has none.
      expect(viewers.map((viewer) => viewer.name), ['matt', 'flatmate']);
      expect(viewers.first.id, _viewerId);
    });
  });

  group('imageFor', () {
    test('keeps the credential in a header and out of the URL', () async {
      final source = await _client(
        CapturingHttpAdapter(response: const {}),
      ).imageFor('/Items/$_movieId/Images/Primary?tag=abc123');

      expect(
        source!.url,
        'https://jf.test/Items/$_movieId/Images/Primary?tag=abc123',
      );
      // A token in the URL becomes part of CachedNetworkImage's cache key, which
      // puts it in a filename on disk and in every request log.
      expect(source.url, isNot(contains('SECRET-KEY')));
      expect(source.headers!['Authorization'], startsWith('MediaBrowser '));
    });

    test('adds maxWidth while preserving the cache-busting tag', () async {
      final source = await _client(
        CapturingHttpAdapter(response: const {}),
      ).imageFor('/Items/$_movieId/Images/Primary?tag=abc123', width: 400);

      expect(source!.url, contains('tag=abc123'));
      expect(source.url, contains('maxWidth=400'));
    });

    test('treats a bare id as that item primary image', () async {
      // A deep-linked detail screen has the id before it has any image tag.
      final source = await _client(
        CapturingHttpAdapter(response: const {}),
      ).imageFor(_movieId);

      expect(source!.url, 'https://jf.test/Items/$_movieId/Images/Primary');
    });

    test('an absolute URL is handed back without the credential', () async {
      // Jellyfin never produces one of these, but a poster path is data from the
      // server and an admin API key must not be attached to a host the user never
      // configured — the same guarantee `SameOriginRedirectInterceptor` gives the
      // API calls.
      final source = await _client(
        CapturingHttpAdapter(response: const {}),
      ).imageFor('https://images.example.com/poster.jpg');

      expect(source!.url, 'https://images.example.com/poster.jpg');
      expect(source.headers, isNull);
    });

    test('an empty path resolves to nothing', () async {
      expect(
        await _client(CapturingHttpAdapter(response: const {})).imageFor('  '),
        isNull,
      );
    });
  });

  group('remote failure', () {
    test('every read path degrades instead of throwing', () async {
      final adapter = CapturingHttpAdapter(response: '', statusCode: 500);
      final client = _client(adapter);

      expect(await client.probeVersion(), isNull);
      expect(await client.verifyCredential(), isFalse);
      expect(await client.getSessions(), isEmpty);
      expect(await client.getLibraries(), isEmpty);
      expect(await client.getViewers(), isEmpty);
      expect(await client.getItem(_movieId), isNull);
      expect(await client.getChildren(_seriesId), isEmpty);
      expect(
        await client.getLibraryItems(
          libraryId: _moviesLibraryId,
          lens: StreamLibraryLens.all,
        ),
        isEmpty,
      );
      expect(
        await client.getLibraryItems(
          libraryId: _showsLibraryId,
          lens: StreamLibraryLens.continueWatching,
        ),
        isEmpty,
      );
    });

    test('a body that is not the documented shape degrades too', () async {
      // An HTML error page from a reverse proxy decodes to a String, not a Map.
      final adapter = CapturingHttpAdapter(response: '<html>nope</html>');
      final client = _client(adapter);

      expect(await client.getSessions(), isEmpty);
      expect(await client.getLibraries(), isEmpty);
      expect(await client.getItem(_movieId), isNull);
    });
  });
}
