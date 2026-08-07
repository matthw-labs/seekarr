import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/features/music/data/lidarr_service.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_api_client.dart';

void main() {
  group('lidarrServiceProvider', () {
    test('throws when Lidarr is not configured', () {
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
      );
      addTearDown(container.dispose);

      expect(() => container.read(lidarrServiceProvider), throwsException);
    });

    test('returns a service when Lidarr is configured', () {
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => const SettingsModel(
              lidarrUrl: 'https://lidarr.example.com',
              lidarrApiKey: 'key',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(lidarrServiceProvider), isA<LidarrService>());
    });
  });

  group('LidarrService', () {
    late FakeApiClient client;
    late LidarrService service;

    setUp(() {
      client = FakeApiClient();
      service = LidarrService(client);
    });

    test('uses the Lidarr API config', () {
      expect(service.config.apiVersion, 'v1');
      expect(service.config.sortKey, 'releaseDate');
    });

    test('getArtists fetches and maps artists', () async {
      client.getResponseData = [
        _artistJson(id: 1, artistName: 'The National'),
        _artistJson(id: 2, artistName: 'Mogwai'),
      ];

      final artists = await service.getArtists();

      expect(client.lastGetPath, '/api/v1/artist');
      expect(artists, hasLength(2));
      expect(artists.first.artistName, 'The National');
      expect(artists.last.id, 2);
    });

    test('getArtists returns empty list on error', () async {
      client.getException = Exception('boom');

      final artists = await service.getArtists();

      expect(artists, isEmpty);
    });

    test('getArtistById returns a typed artist on success', () async {
      client.getResponseData = _artistJson(id: 5, artistName: 'Band');

      final artist = await service.getArtistById(5);

      expect(client.lastGetPath, '/api/v1/artist/5');
      expect(artist?.id, 5);
      expect(artist?.artistName, 'Band');
    });

    test('getArtistById returns null on error', () async {
      client.getException = Exception('boom');

      final artist = await service.getArtistById(5);

      expect(artist, isNull);
    });

    test('getAlbums fetches albums for the artist', () async {
      client.getResponseData = [
        _albumJson(id: 10, title: 'Album 1', monitored: true),
        _albumJson(id: 11, title: 'Album 2', monitored: false),
      ];

      final albums = await service.getAlbums(7);

      expect(client.lastGetPath, '/api/v1/album');
      expect(client.lastGetQueryParameters, {'artistId': 7});
      expect(albums, hasLength(2));
      expect(albums.first.title, 'Album 1');
      expect(albums.last.monitored, isFalse);
    });

    test('getTracks fetches tracks for the album', () async {
      client.getResponseData = [
        _trackJson(id: 20, title: 'Track 1', duration: 180000),
      ];

      final tracks = await service.getTracks(10);

      expect(client.lastGetPath, '/api/v1/track');
      expect(client.lastGetQueryParameters, {'albumId': 10});
      expect(tracks, hasLength(1));
      expect(tracks.single.title, 'Track 1');
      expect(tracks.single.duration, 180000);
    });

    test('searchArtist posts the ArtistSearch command', () async {
      await service.searchArtist(1);

      expect(client.lastPostPath, '/api/v1/command');
      expect(client.lastPostData, {'name': 'ArtistSearch', 'artistId': 1});
    });

    test('searchAlbums posts the AlbumSearch command', () async {
      await service.searchAlbums([10, 11]);

      expect(client.lastPostPath, '/api/v1/command');
      expect(client.lastPostData, {
        'name': 'AlbumSearch',
        'albumIds': [10, 11],
      });
    });

    test('getReleases passes artistId query params', () async {
      client.getResponseData = [
        {'title': 'Artist Release'},
      ];

      final releases = await service.getReleases(artistId: 1);

      expect(client.lastGetPath, '/api/v1/release');
      expect(client.lastGetQueryParameters, {'artistId': 1});
      expect(releases, hasLength(1));
    });

    test('getReleases passes albumId query params', () async {
      client.getResponseData = const [];

      await service.getReleases(albumId: 10);

      expect(client.lastGetQueryParameters, {'albumId': 10});
    });

    test('getReleases passes both artistId and albumId query params', () async {
      client.getResponseData = const [];

      await service.getReleases(artistId: 1, albumId: 10);

      expect(client.lastGetQueryParameters, {'artistId': 1, 'albumId': 10});
    });

    test('getReleases forwards the cancel token to ApiClient', () async {
      client.getResponseData = const [];
      final cancelToken = CancelToken();

      await service.getReleases(artistId: 1, cancelToken: cancelToken);

      expect(client.lastGetPath, '/api/v1/release');
      expect(client.lastGetQueryParameters, {'artistId': 1});
      expect(client.lastGetCancelToken, same(cancelToken));
    });

    test('grabRelease posts the release payload', () async {
      await service.grabRelease(guid: 'guid-123', indexerId: 9);

      expect(client.lastPostPath, '/api/v1/release');
      expect(client.lastPostData, {'guid': 'guid-123', 'indexerId': 9});
    });

    test('lookupArtists returns empty list for empty terms', () async {
      final artists = await service.lookupArtists('');

      expect(artists, isEmpty);
      expect(client.lastGetPath, isNull);
    });

    test('lookupArtists encodes the term and maps results', () async {
      client.getResponseData = [_artistJson(id: 3, artistName: 'Metallica')];

      final artists = await service.lookupArtists('metallica & friends');

      expect(client.lastGetPath, '/api/v1/artist/lookup');
      expect(client.lastGetQueryParameters, {
        'term': 'metallica%20%26%20friends',
      });
      expect(artists.single.artistName, 'Metallica');
    });

    test('lookupArtists forwards the cancel token to ApiClient', () async {
      client.getResponseData = const [];
      final cancelToken = CancelToken();

      await service.lookupArtists('metallica', cancelToken: cancelToken);

      // Global search re-runs this leg on every debounced keystroke; without a
      // token the superseded request runs to completion.
      expect(client.lastGetCancelToken, same(cancelToken));
    });

    test('getQualityProfiles returns mapped profiles', () async {
      client.getResponseData = [
        {'id': 1, 'name': 'Lossless'},
      ];

      final profiles = await service.getQualityProfiles();

      expect(client.lastGetPath, '/api/v1/qualityprofile');
      expect(profiles, [
        {'id': 1, 'name': 'Lossless'},
      ]);
    });

    test('updateArtistProfile fetches then updates the artist', () async {
      client.getResponseData = _artistJson(
        id: 3,
        artistName: 'Artist',
        qualityProfileId: 1,
      );

      await service.updateArtistProfile(3, 7);

      expect(client.lastGetPath, '/api/v1/artist/3');
      expect(client.lastPutPath, '/api/v1/artist/3');
      expect(client.lastPutData['qualityProfileId'], 7);
      expect(client.lastPutData['artistName'], 'Artist');
    });

    test('deleteArtist sends default delete params', () async {
      await service.deleteArtist(1);

      expect(client.lastDeletePath, '/api/v1/artist/1');
      expect(client.lastDeleteQueryParameters, {
        'deleteFiles': false,
        'addImportListExclusion': false,
      });
    });

    test('deleteArtist sends custom delete params', () async {
      await service.deleteArtist(
        1,
        deleteFiles: true,
        addImportListExclusion: true,
      );

      expect(client.lastDeleteQueryParameters, {
        'deleteFiles': true,
        'addImportListExclusion': true,
      });
    });
  });
}

Map<String, dynamic> _artistJson({
  required int id,
  required String artistName,
  String status = 'active',
  bool monitored = true,
  int? qualityProfileId,
}) {
  return {
    'id': id,
    'artistName': artistName,
    'status': status,
    'monitored': monitored,
    'images': const [],
    'genres': const [],
    if (qualityProfileId != null) 'qualityProfileId': qualityProfileId,
  };
}

Map<String, dynamic> _albumJson({
  required int id,
  required String title,
  required bool monitored,
}) {
  return {'id': id, 'title': title, 'monitored': monitored, 'images': const []};
}

Map<String, dynamic> _trackJson({
  required int id,
  required String title,
  required int duration,
}) {
  return {'id': id, 'title': title, 'hasFile': true, 'duration': duration};
}
