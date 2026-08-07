import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/features/import/data/manual_import_service.dart';
import 'package:seekarr/features/import/domain/manual_import_models.dart';
import 'package:seekarr/features/import/presentation/manual_import_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_api_client.dart';

/// Test-only `ManualImportService` that uses a `FakeApiClient`.
class _FakeManualImportService extends ManualImportService {
  _FakeManualImportService(FakeApiClient client, ServiceKey service)
    : super(client: client, service: service);
}

ProviderContainer _container({
  required FakeApiClient client,
  ServiceKey service = ServiceKey.radarr,
  List<dynamic> extra = const [],
}) {
  return ProviderContainer(
    overrides: [
      manualImportServiceProvider(
        service,
      ).overrideWith((ref) => _FakeManualImportService(client, service)),
      ...extra,
    ],
  );
}

ManualImportItem _radarrItem({
  int movieId = 0,
  String path = '/downloads/x.mkv',
}) {
  return ManualImportItem.fromJson({
    'path': path,
    'name': path.split('/').last,
    'movie': movieId > 0 ? {'id': movieId, 'title': 'Some Movie'} : null,
  });
}

ManualImportFixAssignment _radarrAssignment({int movieId = 0}) {
  return ManualImportFixAssignment(
    match: ManualImportLookupResult(
      id: movieId,
      title: 'Some Movie',
      raw: movieId > 0
          ? {'id': movieId, 'title': 'Some Movie'}
          : const <String, dynamic>{},
    ),
  );
}

ManualImportFixAssignment _sonarrAssignment({
  int seriesId = 0,
  List<int> episodeIds = const [],
}) {
  return ManualImportFixAssignment(
    match: ManualImportLookupResult(
      id: seriesId,
      title: 'Some Series',
      raw: seriesId > 0
          ? {'id': seriesId, 'title': 'Some Series'}
          : const <String, dynamic>{},
    ),
    episodes: episodeIds
        .map(
          (id) => ManualImportEpisode(
            id: id,
            seasonNumber: 1,
            episodeNumber: id,
            title: 'E$id',
            raw: {
              'id': id,
              'seasonNumber': 1,
              'episodeNumber': id,
              'title': 'E$id',
            },
          ),
        )
        .toList(growable: false),
  );
}

ManualImportFixAssignment _lidarrAssignment({
  int artistId = 0,
  int? albumId,
  List<int> trackIds = const [],
}) {
  return ManualImportFixAssignment(
    match: ManualImportLookupResult(
      id: artistId,
      title: 'Some Artist',
      raw: artistId > 0
          ? {'id': artistId, 'title': 'Some Artist'}
          : const <String, dynamic>{},
    ),
    album: albumId == null
        ? null
        : ManualImportAlbum(
            id: albumId,
            title: 'Some Album',
            raw: {'id': albumId, 'title': 'Some Album'},
          ),
    tracks: trackIds
        .map(
          (id) => ManualImportTrack(
            id: id,
            title: 'T$id',
            raw: {'id': id, 'title': 'T$id'},
          ),
        )
        .toList(growable: false),
  );
}

void main() {
  group('mapImportError', () {
    test('returns "Couldn\'t reach Radarr" for connectionError', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionError,
      );
      expect(
        mapImportError(err, ServiceKey.radarr),
        startsWith("Couldn't reach Radarr"),
      );
    });

    test('returns "Couldn\'t reach Sonarr" for connectionTimeout', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionTimeout,
      );
      expect(
        mapImportError(err, ServiceKey.sonarr),
        startsWith("Couldn't reach Sonarr"),
      );
    });

    test('a receiveTimeout blames the slow answer, not the URL', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/api/v3/manualimport'),
        type: DioExceptionType.receiveTimeout,
      );
      final msg = mapImportError(err, ServiceKey.sonarr);
      expect(msg, contains('took too long to answer'));
      // The connection succeeded, so pointing at the URL is misleading.
      expect(msg, isNot(contains('Check the URL')));
    });

    test('returns the 500 hint message for statusCode 500 (radarr)', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/api/v3/command'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/v3/command'),
          statusCode: 500,
        ),
        type: DioExceptionType.badResponse,
      );
      final msg = mapImportError(err, ServiceKey.radarr);
      expect(msg, contains('returned 500'));
      expect(
        msg,
        contains('Try moving the file into a folder named after the movie'),
      );
      expect(msg, contains('Check Radarr → System → Logs'));
    });

    test('returns the 500 hint message for sonarr (series/episode naming)', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/api/v3/command'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/v3/command'),
          statusCode: 500,
        ),
        type: DioExceptionType.badResponse,
      );
      final msg = mapImportError(err, ServiceKey.sonarr);
      expect(msg, contains('returned 500'));
      expect(msg, contains("doesn't match a known series/episode pattern"));
      expect(msg, contains('Series Title/S01E01.ext'));
      expect(msg, isNot(contains('movie')));
    });

    test(
      'returns the 500 hint message for lidarr (artist/album/track naming)',
      () {
        final err = DioException(
          requestOptions: RequestOptions(path: '/api/v1/command'),
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: '/api/v1/command'),
            statusCode: 500,
          ),
          type: DioExceptionType.badResponse,
        );
        final msg = mapImportError(err, ServiceKey.lidarr);
        expect(msg, contains('returned 500'));
        expect(
          msg,
          contains("doesn't match a known artist/album/track pattern"),
        );
        expect(msg, contains('Artist/Album/Track.ext'));
        expect(msg, isNot(contains('movie')));
      },
    );

    test('returns "Radarr returned 404: Not Found" for 404 with message', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 404,
          data: {'message': 'Not Found'},
        ),
        type: DioExceptionType.badResponse,
      );
      expect(
        mapImportError(err, ServiceKey.radarr),
        'Radarr returned 404: Not Found',
      );
    });

    test('returns "Radarr returned 401." for 401 with no message', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 401,
        ),
        type: DioExceptionType.badResponse,
      );
      expect(mapImportError(err, ServiceKey.radarr), 'Radarr returned 401.');
    });

    test('returns error.toString() for non-DioException throwables', () {
      expect(mapImportError(Exception('boom'), ServiceKey.radarr), 'boom');
    });

    test(
      'returns "Lidarr request failed..." for DioException with no response and unknown type',
      () {
        final err = DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.unknown,
        );
        expect(
          mapImportError(err, ServiceKey.lidarr),
          contains('Lidarr request failed'),
        );
      },
    );
  });

  group('libraryGuardError', () {
    test('returns null for a valid radarr assignment', () {
      expect(
        libraryGuardError(ServiceKey.radarr, _radarrAssignment(movieId: 123)),
        isNull,
      );
    });

    test(
      'returns non-null containing "library" for radarr with match.id == 0',
      () {
        final msg = libraryGuardError(
          ServiceKey.radarr,
          _radarrAssignment(movieId: 0),
        );
        expect(msg, isNotNull);
        expect(msg, contains('library'));
      },
    );

    test('returns non-null for sonarr with no episodes', () {
      final msg = libraryGuardError(
        ServiceKey.sonarr,
        _sonarrAssignment(seriesId: 10),
      );
      expect(msg, isNotNull);
      expect(msg, contains('library'));
    });

    test('returns non-null for lidarr with no tracks', () {
      final msg = libraryGuardError(
        ServiceKey.lidarr,
        _lidarrAssignment(artistId: 1, albumId: 2),
      );
      expect(msg, isNotNull);
      expect(msg, contains('library'));
    });

    test('returns non-null for lidarr with no album', () {
      final msg = libraryGuardError(
        ServiceKey.lidarr,
        _lidarrAssignment(artistId: 1, trackIds: [4]),
      );
      expect(msg, isNotNull);
      expect(msg, contains('library'));
    });

    test('returns null for a valid sonarr assignment with episodes', () {
      expect(
        libraryGuardError(
          ServiceKey.sonarr,
          _sonarrAssignment(seriesId: 10, episodeIds: [50]),
        ),
        isNull,
      );
    });

    test('returns null for a valid lidarr assignment with album + tracks', () {
      expect(
        libraryGuardError(
          ServiceKey.lidarr,
          _lidarrAssignment(artistId: 1, albumId: 2, trackIds: [4]),
        ),
        isNull,
      );
    });
  });

  group('ManualImportFlowNotifier.applyFixAssignment', () {
    test(
      'guard fails fast for radarr with match.id == 0: no API call, error set',
      () async {
        final client = FakeApiClient();
        final container = _container(
          client: client,
          service: ServiceKey.radarr,
        );
        addTearDown(container.dispose);

        // Seed the flow with a radarr service and one item.
        final notifier = container.read(manualImportFlowProvider.notifier);
        await notifier.start(ServiceKey.radarr, force: true);
        // Reset error from the start() call.
        container.read(manualImportFlowProvider.notifier).state = container
            .read(manualImportFlowProvider)
            .copyWith(error: null);
        client.postCallCount = 0; // ignore any start() side effects

        final item = _radarrItem(movieId: 0, path: '/downloads/Barbie.avi');
        final assignment = _radarrAssignment(movieId: 0);

        final result = await notifier.applyFixAssignment(item, assignment);

        expect(result, isNull);
        expect(client.postCallCount, 0);
        final state = container.read(manualImportFlowProvider);
        expect(state.error, isNotNull);
        expect(state.error, contains('library'));
      },
    );

    test(
      'valid radarr assignment: no API call, item replaced, auto-selected',
      () async {
        final client = FakeApiClient();
        final container = _container(
          client: client,
          service: ServiceKey.radarr,
        );
        addTearDown(container.dispose);

        final notifier = container.read(manualImportFlowProvider.notifier);
        final item = _radarrItem(
          movieId: 123,
          path: '/downloads/Inception.avi',
        );
        final assignment = _radarrAssignment(movieId: 123);

        // Inject the item into state manually (skip folder scan).
        container.read(manualImportFlowProvider.notifier).state = container
            .read(manualImportFlowProvider)
            .copyWith(service: ServiceKey.radarr, items: [item]);

        final result = await notifier.applyFixAssignment(item, assignment);

        expect(result, isNotNull);
        // The fix flow MUST NOT call the import endpoint — the actual import
        // is triggered by confirmImport when the user clicks "Confirm import".
        expect(client.postCallCount, 0);

        final state = container.read(manualImportFlowProvider);
        // Item at the same path should have been replaced with the resolved one.
        expect(state.items.length, 1);
        expect(state.items.first.path, '/downloads/Inception.avi');
        expect(state.items.first.hasMatchFor(ServiceKey.radarr), isTrue);
        // The resolved item should be auto-selected so "Confirm import" picks it.
        expect(state.selectedPaths, contains('/downloads/Inception.avi'));
        expect(state.error, isNull);
      },
    );

    test('resolves only the row at that path, never id twins', () async {
      final container = _container(
        client: FakeApiClient(),
        service: ServiceKey.radarr,
      );
      addTearDown(container.dispose);

      // A service that hands every file the same id — the *arrs hash the path
      // into `Id` so this does not happen in practice, but the match must not
      // depend on that being true.
      final first = ManualImportItem.fromJson({
        'id': 7,
        'path': '/downloads/A.mkv',
        'name': 'A',
      });
      final second = ManualImportItem.fromJson({
        'id': 7,
        'path': '/downloads/B.mkv',
        'name': 'B',
      });
      final notifier = container.read(manualImportFlowProvider.notifier);
      notifier.state = container
          .read(manualImportFlowProvider)
          .copyWith(service: ServiceKey.radarr, items: [first, second]);

      await notifier.applyFixAssignment(first, _radarrAssignment(movieId: 5));

      final state = container.read(manualImportFlowProvider);
      expect(state.items.first.hasMatchFor(ServiceKey.radarr), isTrue);
      // The other file shares the id and nothing else: it is a different file
      // and must stay unmatched.
      expect(state.items[1].path, '/downloads/B.mkv');
      expect(state.items[1].hasMatchFor(ServiceKey.radarr), isFalse);
      expect(state.selectedPaths, {'/downloads/A.mkv'});
    });
  });

  group('launching manual import from a title', () {
    /// The four GETs a `start` + `loadSelectedFolderItems` round makes:
    /// root folders, the file system listing, the scan, then the library.
    FakeApiClient scanClient({
      required List<Map<String, dynamic>> items,
      List<Map<String, dynamic>> library = const [
        {'id': 42, 'title': 'Target Movie', 'year': '2024'},
      ],
    }) {
      final client = FakeApiClient();
      client.getResponseQueue.addAll([
        [
          {'id': 1, 'path': '/downloads', 'accessible': true},
        ],
        {'parent': null, 'directories': <dynamic>[], 'files': <dynamic>[]},
        items,
        library,
      ]);
      return client;
    }

    test('assigns the target only to files Radarr could import', () async {
      final client = scanClient(
        items: const [
          {'path': '/downloads/Target Movie.mkv', 'name': 'Target Movie'},
          {'path': '/downloads/Target Movie.srt', 'name': 'Target Movie'},
          {'path': '/downloads/poster.jpg', 'name': 'poster'},
          {'path': '/downloads/Target Movie.nfo', 'name': 'Target Movie'},
        ],
      );
      final container = _container(client: client, service: ServiceKey.radarr);
      addTearDown(container.dispose);

      final notifier = container.read(manualImportFlowProvider.notifier);
      await notifier.start(ServiceKey.radarr, targetId: 42, force: true);
      await notifier.loadSelectedFolderItems();

      final state = container.read(manualImportFlowProvider);
      final matched = state.items
          .where((item) => item.hasMatchFor(ServiceKey.radarr))
          .map((item) => item.path);
      // Radarr's library guard is satisfied by a movieId alone, so without the
      // supported-file filter the launch target was written into the subtitle,
      // the artwork and the NFO too — one tap from importing them as the movie.
      expect(matched, ['/downloads/Target Movie.mkv']);
    });

    test('never pre-ticks a match the user has not seen', () async {
      final client = scanClient(
        items: const [
          {'path': '/downloads/Target Movie.mkv', 'name': 'Target Movie'},
        ],
      );
      final container = _container(client: client, service: ServiceKey.radarr);
      addTearDown(container.dispose);

      final notifier = container.read(manualImportFlowProvider.notifier);
      await notifier.start(ServiceKey.radarr, targetId: 42, force: true);
      await notifier.loadSelectedFolderItems();

      final state = container.read(manualImportFlowProvider);
      // The file did get the guess, but a guess must not arrive armed: nothing
      // is selected — and so nothing is importable — until the user ticks it.
      expect(state.readyItems, hasLength(1));
      expect(state.selectedPaths, isEmpty);
      expect(state.canImportSelected, isFalse);
    });

    // The other half of the same protection, and the one that survives a tap on
    // "Select all ready files": a file the app has no reason to think is the
    // target never becomes ready in the first place. `targetId` outlives every
    // folder change, and the entry points that carry one carry no path, so
    // without this a scan of the whole downloads root labelled every
    // unidentified rip in it with the movie the user came from.
    test('leaves a file that is not the target alone', () async {
      final client = scanClient(
        items: const [
          {'path': '/downloads/Target Movie.mkv', 'name': 'Target Movie'},
          {'path': '/downloads/Some Other Movie.mkv', 'name': 'Some Other'},
        ],
      );
      final container = _container(client: client, service: ServiceKey.radarr);
      addTearDown(container.dispose);

      final notifier = container.read(manualImportFlowProvider.notifier);
      await notifier.start(ServiceKey.radarr, targetId: 42, force: true);
      await notifier.loadSelectedFolderItems();

      final state = container.read(manualImportFlowProvider);
      expect(
        state.items
            .where((item) => item.hasMatchFor(ServiceKey.radarr))
            .map((item) => item.path),
        ['/downloads/Target Movie.mkv'],
      );

      // And the gesture that arms the batch cannot reach the stranger either.
      notifier.toggleAllReady();
      expect(container.read(manualImportFlowProvider).selectedPaths, {
        '/downloads/Target Movie.mkv',
      });
    });

    test('a release-named file in the target folder still matches', () async {
      // What the launch is actually for: Radarr could not parse the file, but
      // the download is plainly the movie the user came from.
      final client = scanClient(
        items: const [
          {
            'path': '/downloads/Target Movie (2024)/rip-a1.mkv',
            'folderName': 'Target Movie (2024)',
            'relativePath': 'rip-a1.mkv',
            'name': 'rip-a1',
          },
          {
            'path': '/downloads/Target.Movie.2024.1080p.BluRay-GRP.mkv',
            'name': 'Target.Movie.2024.1080p.BluRay-GRP',
          },
        ],
      );
      final container = _container(client: client, service: ServiceKey.radarr);
      addTearDown(container.dispose);

      final notifier = container.read(manualImportFlowProvider.notifier);
      await notifier.start(ServiceKey.radarr, targetId: 42, force: true);
      await notifier.loadSelectedFolderItems();

      final state = container.read(manualImportFlowProvider);
      expect(
        state.items.every((item) => item.hasMatchFor(ServiceKey.radarr)),
        isTrue,
      );
    });

    test('a real match found by the service is still preselected', () async {
      final client = scanClient(
        items: const [
          {
            'path': '/downloads/Known.mkv',
            'name': 'Known',
            'movie': {'id': 42, 'title': 'Target Movie'},
          },
          {'path': '/downloads/Unknown.mkv', 'name': 'Unknown'},
        ],
      );
      final container = _container(client: client, service: ServiceKey.radarr);
      addTearDown(container.dispose);

      final notifier = container.read(manualImportFlowProvider.notifier);
      await notifier.start(ServiceKey.radarr, targetId: 42, force: true);
      await notifier.loadSelectedFolderItems();

      // What the service identified itself is not a guess, so the ordinary
      // ready-file preselection is untouched.
      expect(container.read(manualImportFlowProvider).selectedPaths, {
        '/downloads/Known.mkv',
      });
    });
  });

  group('ManualImportFlowNotifier.loadSelectedFolderItems', () {
    test('preselects only files that are ready for import', () async {
      final client = FakeApiClient();
      client.getResponseQueue.addAll([
        // getRootFolders
        [
          {'id': 1, 'path': '/downloads', 'accessible': true},
        ],
        // getFileSystem for '/'
        {'parent': null, 'directories': <dynamic>[], 'files': <dynamic>[]},
        // getManualImportItems
        [
          {
            'path': '/downloads/Ready.mkv',
            'name': 'Ready.mkv',
            'movie': {'id': 42, 'title': 'Ready Movie'},
          },
          {'path': '/downloads/Unmatched.mkv', 'name': 'Unmatched.mkv'},
          {
            'path': '/downloads/Imported.mkv',
            'name': 'Imported.mkv',
            'movie': {'id': 7, 'title': 'Old Movie'},
            'movieFileId': 99,
          },
        ],
      ]);
      final container = _container(client: client, service: ServiceKey.radarr);
      addTearDown(container.dispose);

      final notifier = container.read(manualImportFlowProvider.notifier);
      await notifier.start(ServiceKey.radarr, force: true);
      await notifier.loadSelectedFolderItems();

      final state = container.read(manualImportFlowProvider);
      expect(state.items.length, 3);
      // Only the fully matched file enters the import selection; the
      // unmatched one waits in the attention group until it is fixed.
      expect(state.selectedPaths, {'/downloads/Ready.mkv'});
      expect(state.readyItems.map((item) => item.path), [
        '/downloads/Ready.mkv',
      ]);
      expect(state.attentionItems.map((item) => item.path), [
        '/downloads/Unmatched.mkv',
      ]);
      expect(state.importedItems.map((item) => item.path), [
        '/downloads/Imported.mkv',
      ]);
      expect(state.canImportSelected, isTrue);
    });

    test('toggleItem refuses a file that is not ready', () {
      final container = _container(
        client: FakeApiClient(),
        service: ServiceKey.radarr,
      );
      addTearDown(container.dispose);

      final notifier = container.read(manualImportFlowProvider.notifier);
      final unmatched = _radarrItem(movieId: 0, path: '/downloads/x.mkv');
      final ready = _radarrItem(movieId: 5, path: '/downloads/y.mkv');
      notifier.state = container
          .read(manualImportFlowProvider)
          .copyWith(service: ServiceKey.radarr, items: [unmatched, ready]);

      notifier.toggleItem(unmatched, true);
      expect(container.read(manualImportFlowProvider).selectedPaths, isEmpty);

      notifier.toggleItem(ready, true);
      expect(container.read(manualImportFlowProvider).selectedPaths, {
        '/downloads/y.mkv',
      });
    });
  });

  group('a submitted batch can never be submitted twice', () {
    FakeApiClient commandClient({String status = 'started'}) {
      final client = FakeApiClient();
      client.postResponseData = {'id': 77, 'status': status};
      return client;
    }

    ProviderContainer seeded(FakeApiClient client, {int fileCount = 2}) {
      final container = _container(client: client, service: ServiceKey.radarr);
      final items = [
        for (var index = 0; index < fileCount; index++)
          _radarrItem(movieId: 100 + index, path: '/downloads/file$index.mkv'),
      ];
      container.read(manualImportFlowProvider.notifier).state = container
          .read(manualImportFlowProvider)
          .copyWith(
            service: ServiceKey.radarr,
            items: items,
            selectedPaths: items.map((item) => item.path).toSet(),
          );
      return container;
    }

    test('the selection is spent once the command is posted', () async {
      final client = commandClient();
      final container = seeded(client);
      addTearDown(container.dispose);
      final notifier = container.read(manualImportFlowProvider.notifier);

      final command = await notifier.confirmImport();
      expect(command, isNotNull);
      expect(client.postCallCount, 1);

      final state = container.read(manualImportFlowProvider);
      // Nothing left selected, nothing left ready: the button behind Track is
      // disabled rather than armed with the same files.
      expect(state.selectedPaths, isEmpty);
      expect(state.readyItems, isEmpty);
      expect(state.canImportSelected, isFalse);
      expect(state.submittedPaths, {
        '/downloads/file0.mkv',
        '/downloads/file1.mkv',
      });
      expect(state.inFlightItems, hasLength(2));
    });

    test('pressing import again while it runs posts nothing', () async {
      final client = commandClient();
      final container = seeded(client);
      addTearDown(container.dispose);
      final notifier = container.read(manualImportFlowProvider.notifier);

      await notifier.confirmImport();
      // Simulate the user going back to Review and hitting the button again —
      // the old flow queued a second identical ManualImport command here.
      final again = await notifier.confirmImport();

      expect(client.postCallCount, 1);
      // Returns the running command so the caller just navigates to Track.
      expect(again?.id, 77);
      expect(container.read(manualImportFlowProvider).error, isNull);
    });

    test('a completed command keeps its files out of reach', () async {
      final client = commandClient(status: 'completed');
      final container = seeded(client);
      addTearDown(container.dispose);
      final notifier = container.read(manualImportFlowProvider.notifier);

      await notifier.confirmImport();
      // This is the FileNotFoundException case: the service already moved these
      // files into the library, so re-posting them can only fail.
      await notifier.confirmImport();

      expect(client.postCallCount, 1);
      final state = container.read(manualImportFlowProvider);
      expect(state.readyItems, isEmpty);
      expect(state.blockedPaths, hasLength(2));
    });

    test('toggling a submitted file back on is refused', () async {
      final client = commandClient();
      final container = seeded(client);
      addTearDown(container.dispose);
      final notifier = container.read(manualImportFlowProvider.notifier);

      await notifier.confirmImport();
      final submitted = container.read(manualImportFlowProvider).items.first;
      notifier.toggleItem(submitted, true);
      notifier.toggleAllReady();

      expect(container.read(manualImportFlowProvider).selectedPaths, isEmpty);
    });

    test(
      'a failed command releases its files so a retry is possible',
      () async {
        final client = commandClient(status: 'failed');
        final container = seeded(client);
        addTearDown(container.dispose);
        final notifier = container.read(manualImportFlowProvider.notifier);

        await notifier.confirmImport();

        final state = container.read(manualImportFlowProvider);
        // The files are still on disk — the import did not happen — so the user
        // must be able to fix the cause and try again.
        expect(state.blockedPaths, isEmpty);
        expect(state.readyItems, hasLength(2));

        notifier.toggleAllReady();
        expect(
          container.read(manualImportFlowProvider).selectedPaths,
          hasLength(2),
        );
        await notifier.confirmImport();
        expect(client.postCallCount, 2);
      },
    );

    test('refreshing after import keeps the command and the block', () async {
      final client = commandClient();
      client.getResponseQueue.add([
        // The service still lists the file: the import is in flight, the move
        // has not happened yet. It must not become selectable again.
        {
          'path': '/downloads/file0.mkv',
          'name': 'file0',
          'movie': {'id': 100, 'title': 'Some Movie'},
        },
      ]);
      final container = seeded(client, fileCount: 1);
      addTearDown(container.dispose);
      container.read(manualImportFlowProvider.notifier).state = container
          .read(manualImportFlowProvider)
          .copyWith(selectedFolder: '/downloads');
      final notifier = container.read(manualImportFlowProvider.notifier);

      await notifier.confirmImport();
      await notifier.refreshAfterImport();

      final state = container.read(manualImportFlowProvider);
      expect(state.command?.id, 77);
      expect(state.blockedPaths, {'/downloads/file0.mkv'});
      expect(state.readyItems, isEmpty);
      expect(state.selectedPaths, isEmpty);
      expect(state.inFlightItems, hasLength(1));
    });
  });

  group('ManualImportFlowNotifier.confirmImport', () {
    test('sets state.error to the mapped message on DioException 500', () async {
      final client = FakeApiClient();
      client.postException = DioException(
        requestOptions: RequestOptions(path: '/api/v3/command'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/v3/command'),
          statusCode: 500,
        ),
        type: DioExceptionType.badResponse,
      );
      final container = _container(client: client, service: ServiceKey.radarr);
      addTearDown(container.dispose);

      final notifier = container.read(manualImportFlowProvider.notifier);
      final item = _radarrItem(movieId: 123, path: '/downloads/Inception.avi');

      // Pre-populate state with a ready, selected item (the post-fix-flow state).
      container.read(manualImportFlowProvider.notifier).state = container
          .read(manualImportFlowProvider)
          .copyWith(
            service: ServiceKey.radarr,
            items: [item],
            selectedPaths: {'/downloads/Inception.avi'},
          );

      final command = await notifier.confirmImport();

      expect(command, isNull);
      final state = container.read(manualImportFlowProvider);
      expect(state.error, isNotNull);
      expect(state.error, contains('returned 500'));
      expect(
        state.error,
        contains('Try moving the file into a folder named after the movie'),
      );
    });
  });
}
