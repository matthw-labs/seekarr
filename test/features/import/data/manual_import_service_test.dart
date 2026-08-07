import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/import/data/manual_import_service.dart';
import 'package:cupola/features/import/domain/manual_import_models.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_api_client.dart';

void main() {
  group('ManualImportService.importItem', () {
    test(
      'radarr posts to /api/v3/command with ManualImport + importMode',
      () async {
        final client = FakeApiClient();
        client.postResponseData = {
          'id': 1,
          'name': 'ManualImport',
          'status': 'queued',
        };
        final service = ManualImportService(
          client: client,
          service: ServiceKey.radarr,
        );
        final item = ManualImportItem.fromJson({
          'path': '/downloads/Inception.2010.mkv',
          'name': 'Inception.2010.mkv',
          'folderName': 'Inception (2010)',
          'quality': {
            'quality': {'id': 7, 'name': 'Bluray-1080p'},
          },
          'languages': [
            {'id': 1, 'name': 'English'},
          ],
          'releaseGroup': 'SPARKS',
          'indexerFlags': 0,
          'downloadId': '',
          'movie': {'id': 123, 'title': 'Inception'},
        });

        final status = await service.importItem(
          item,
          importMode: ManualImportMode.auto,
        );

        expect(client.lastPostPath, '/api/v3/command');
        expect(client.postCallCount, 1);
        expect(client.lastPostData, isA<Map<String, dynamic>>());
        final body = client.lastPostData as Map<String, dynamic>;
        expect(body['name'], 'ManualImport');
        expect(body['importMode'], 'auto');
        expect(body['files'], isA<List>());
        expect((body['files'] as List).length, 1);
        // Radarr should NOT include Lidarr-only replaceExistingFiles.
        expect(body.containsKey('replaceExistingFiles'), isFalse);

        expect(status.id, 1);
        expect(status.name, 'ManualImport');
        expect(status.status, 'queued');
      },
    );

    test(
      'radarr file body contains movieId and excludes other-service keys',
      () async {
        final client = FakeApiClient();
        client.postResponseData = {
          'id': 1,
          'name': 'ManualImport',
          'status': 'queued',
        };
        final service = ManualImportService(
          client: client,
          service: ServiceKey.radarr,
        );
        final item = ManualImportItem.fromJson({
          'path': '/downloads/Inception.2010.mkv',
          'name': 'Inception.2010.mkv',
          'folderName': 'Inception (2010)',
          'quality': {
            'quality': {'id': 7, 'name': 'Bluray-1080p'},
          },
          'languages': [
            {'id': 1, 'name': 'English'},
          ],
          'movie': {'id': 123, 'title': 'Inception'},
          'series': {'id': 999, 'title': 'Inception Series'},
          'artist': {'id': 888, 'title': 'Inception Artist'},
          'episodes': [
            {'id': 50, 'seasonNumber': 1, 'episodeNumber': 1, 'title': 'E1'},
          ],
          'tracks': [
            {'id': 4, 'title': 'Track 1'},
          ],
          'id': 99999,
          'rejections': [
            {'reason': 'old', 'type': 'permanent'},
          ],
          'customFormats': [
            {'id': 1, 'name': 'CF1'},
          ],
          'customFormatScore': 50,
        });

        await service.importItem(item, importMode: ManualImportMode.auto);

        final body = client.lastPostData as Map<String, dynamic>;
        final file = (body['files'] as List).first as Map<String, dynamic>;
        expect(file['movieId'], 123);
        expect(file.containsKey('seriesId'), isFalse);
        expect(file.containsKey('artistId'), isFalse);
        expect(file.containsKey('albumId'), isFalse);
        expect(file.containsKey('albumReleaseId'), isFalse);
        expect(file.containsKey('episodeIds'), isFalse);
        expect(file.containsKey('episodeFileId'), isFalse);
        expect(file.containsKey('trackIds'), isFalse);
        expect(file.containsKey('releaseType'), isFalse);
        expect(file.containsKey('disableReleaseSwitching'), isFalse);
        expect(file.containsKey('episodes'), isFalse);
        expect(file.containsKey('tracks'), isFalse);
        expect(file.containsKey('id'), isFalse);
        expect(file.containsKey('rejections'), isFalse);
        expect(file.containsKey('customFormats'), isFalse);
        expect(file.containsKey('customFormatScore'), isFalse);
        expect(file.containsKey('movie'), isFalse);
        expect(file.containsKey('series'), isFalse);
        expect(file.containsKey('artist'), isFalse);
      },
    );

    test('sonarr file body has seriesId and episodeIds', () async {
      final client = FakeApiClient();
      client.postResponseData = {
        'id': 1,
        'name': 'ManualImport',
        'status': 'queued',
      };
      final service = ManualImportService(
        client: client,
        service: ServiceKey.sonarr,
      );
      final item = ManualImportItem.fromJson({
        'path': '/downloads/Frieren.S02E05.mkv',
        'name': 'Frieren.S02E05.mkv',
        'folderName': 'Frieren (2023) - S02',
        'quality': {
          'quality': {'id': 7, 'name': 'Bluray-1080p'},
        },
        'series': {'id': 10, 'title': 'Frieren'},
        'episodes': [
          {'id': 50, 'seasonNumber': 2, 'episodeNumber': 5, 'title': 'E5'},
        ],
      });

      await service.importItem(item, importMode: ManualImportMode.auto);

      final body = client.lastPostData as Map<String, dynamic>;
      expect(body.containsKey('replaceExistingFiles'), isFalse);
      final file = (body['files'] as List).first as Map<String, dynamic>;
      expect(file['seriesId'], 10);
      expect(file['episodeIds'], [50]);
      expect(file.containsKey('movieId'), isFalse);
      expect(file.containsKey('artistId'), isFalse);
      expect(file.containsKey('trackIds'), isFalse);
    });

    test(
      'lidarr file body has artistId, albumId, albumReleaseId, trackIds',
      () async {
        final client = FakeApiClient();
        client.postResponseData = {
          'id': 1,
          'name': 'ManualImport',
          'status': 'queued',
        };
        final service = ManualImportService(
          client: client,
          service: ServiceKey.lidarr,
        );
        final item = ManualImportItem.fromJson({
          'path': '/downloads/Artist/Album/Track01.flac',
          'name': 'Track01.flac',
          'quality': {
            'quality': {'id': 1, 'name': 'FLAC'},
          },
          'artist': {'id': 1, 'title': 'Artist'},
          'album': {'id': 2, 'title': 'Album'},
          'albumReleaseId': 3,
          'tracks': [
            {'id': 4, 'title': 'Track 1'},
          ],
        });

        await service.importItem(item, importMode: ManualImportMode.auto);

        final body = client.lastPostData as Map<String, dynamic>;
        expect(client.lastPostPath, '/api/v1/command');
        // Lidarr includes replaceExistingFiles=false.
        expect(body['replaceExistingFiles'], false);
        final file = (body['files'] as List).first as Map<String, dynamic>;
        expect(file['artistId'], 1);
        expect(file['albumId'], 2);
        expect(file['albumReleaseId'], 3);
        expect(file['trackIds'], [4]);
        expect(file.containsKey('movieId'), isFalse);
        expect(file.containsKey('seriesId'), isFalse);
        expect(file.containsKey('episodeIds'), isFalse);
      },
    );

    test('rethrows DioException with 500 so the provider can map it', () async {
      final client = FakeApiClient();
      client.postException = DioException(
        requestOptions: RequestOptions(path: '/api/v3/command'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/v3/command'),
          statusCode: 500,
        ),
        type: DioExceptionType.badResponse,
      );
      final service = ManualImportService(
        client: client,
        service: ServiceKey.radarr,
      );
      final item = ManualImportItem.fromJson({
        'path': '/downloads/Inception.2010.mkv',
        'name': 'Inception.2010.mkv',
        'movie': {'id': 123, 'title': 'Inception'},
      });

      await expectLater(
        service.importItem(item, importMode: ManualImportMode.auto),
        throwsA(isA<DioException>()),
      );
    });

    test('importMode is forwarded as the lowercase api value', () async {
      final client = FakeApiClient();
      client.postResponseData = {
        'id': 1,
        'name': 'ManualImport',
        'status': 'queued',
      };
      final service = ManualImportService(
        client: client,
        service: ServiceKey.radarr,
      );
      final item = ManualImportItem.fromJson({
        'path': '/downloads/x.mkv',
        'name': 'x.mkv',
        'movie': {'id': 1, 'title': 'X'},
      });

      await service.importItem(item, importMode: ManualImportMode.move);

      final body = client.lastPostData as Map<String, dynamic>;
      expect(body['importMode'], 'move');
    });
  });

  group('ManualImportService.startManualImport', () {
    test(
      'regression guard: bulk import still posts to /command with files list',
      () async {
        final client = FakeApiClient();
        client.postResponseData = {
          'id': 1,
          'name': 'ManualImport',
          'status': 'queued',
        };
        final service = ManualImportService(
          client: client,
          service: ServiceKey.radarr,
        );
        final itemA = ManualImportItem.fromJson({
          'path': '/downloads/a.mkv',
          'name': 'a.mkv',
          'movie': {'id': 1, 'title': 'A'},
        });
        final itemB = ManualImportItem.fromJson({
          'path': '/downloads/b.mkv',
          'name': 'b.mkv',
          'movie': {'id': 2, 'title': 'B'},
        });

        await service.startManualImport([
          itemA,
          itemB,
        ], importMode: ManualImportMode.auto);

        expect(client.lastPostPath, '/api/v3/command');
        final body = client.lastPostData as Map<String, dynamic>;
        expect(body['name'], 'ManualImport');
        expect(body['importMode'], 'auto');
        expect((body['files'] as List).length, 2);
      },
    );
  });

  group('ManualImportService scan timeouts', () {
    test(
      'getManualImportItems asks for the slow-scan receive timeout',
      () async {
        final client = FakeApiClient();
        client.getResponseData = const [];
        final service = ManualImportService(
          client: client,
          service: ServiceKey.sonarr,
        );

        await service.getManualImportItems(folder: '/downloads/complete');

        expect(client.lastGetPath, '/api/v3/manualimport');
        // The default 15s ceiling fires long before Sonarr finishes walking the
        // folder and probing each file, which surfaced as a bogus
        // "couldn't reach Sonarr" error.
        expect(client.lastGetReceiveTimeout, kSlowScanReceiveTimeout);
      },
    );

    test('getFileSystem asks for the slow-scan receive timeout', () async {
      final client = FakeApiClient();
      client.getResponseData = const {'directories': [], 'files': []};
      final service = ManualImportService(
        client: client,
        service: ServiceKey.radarr,
      );

      await service.getFileSystem('/mnt/media');

      expect(client.lastGetPath, '/api/v3/filesystem');
      expect(client.lastGetReceiveTimeout, kSlowScanReceiveTimeout);
    });

    test('getLibraryMatches asks for the slow-scan receive timeout', () async {
      final client = FakeApiClient();
      client.getResponseData = const [];
      final service = ManualImportService(
        client: client,
        service: ServiceKey.sonarr,
      );

      await service.getLibraryMatches();

      expect(client.lastGetPath, '/api/v3/series');
      expect(client.lastGetReceiveTimeout, kSlowScanReceiveTimeout);
    });
  });
}
