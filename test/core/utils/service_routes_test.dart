import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/core/utils/service_routes.dart';

void main() {
  group('ServiceRoutes', () {
    test('builds Radarr detail routes with optional hero tag', () {
      expect(ServiceRoutes.radarrMovie(42), '/services/radarr/movie/42');
      expect(
        ServiceRoutes.radarrMovie(42, heroTag: 'movie hero'),
        '/services/radarr/movie/42?heroTag=movie+hero',
      );
    });

    test('builds Sonarr and Lidarr detail routes', () {
      expect(
        ServiceRoutes.sonarrSeries(7, heroTag: 'series_7'),
        '/services/sonarr/series/7?heroTag=series_7',
      );
      expect(
        ServiceRoutes.lidarrArtist(9, heroTag: 'artist_9'),
        '/services/lidarr/artist/9?heroTag=artist_9',
      );
    });

    test('encodes Seerr detail query values once', () {
      expect(
        ServiceRoutes.seerrDetail(
          mediaType: 'tv',
          id: 123,
          heroTag: 'hero tag',
          posterUrl: 'https://image.tmdb.org/t/p/w500/a/b.jpg',
        ),
        '/services/seerr/tv/123?heroTag=hero+tag&posterUrl=https%3A%2F%2Fimage.tmdb.org%2Ft%2Fp%2Fw500%2Fa%2Fb.jpg',
      );
    });

    test('normalizes non-tv Seerr media types to movie', () {
      expect(
        ServiceRoutes.seerrDetail(mediaType: 'movie', id: 1),
        '/services/seerr/movie/1',
      );
      expect(
        ServiceRoutes.seerrDetail(mediaType: 'person', id: 1),
        '/services/seerr/movie/1',
      );
    });

    test('exposes the Bazarr service root', () {
      expect(ServiceRoutes.bazarr, '/services/bazarr');
    });

    test('builds Prowlarr library and indexer detail routes', () {
      expect(ServiceRoutes.prowlarr, '/services/prowlarr');
      expect(ServiceRoutes.prowlarrLibrary, '/services/prowlarr/library');
      expect(ServiceRoutes.prowlarrIndexer(3), '/services/prowlarr/indexer/3');
    });
  });
}
