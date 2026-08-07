import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/core/utils/image_utils.dart';

void main() {
  group('ImageUtils', () {
    group('extractPosterUrl', () {
      test('returns remoteUrl when it starts with http', () {
        final images = [
          {
            'coverType': 'poster',
            'remoteUrl': 'https://image.tmdb.org/t/p/w500/abc.jpg',
            'url': '/local/abc.jpg',
          },
        ];

        final result = ImageUtils.extractPosterUrl(
          images,
          baseUrl: 'http://localhost:7878',
          apiKey: 'test-key',
        );

        expect(result.url, 'https://image.tmdb.org/t/p/w500/abc.jpg');
        expect(result.headers, isNull);
      });

      test('builds URL with auth headers when remoteUrl is relative', () {
        final images = [
          {
            'coverType': 'poster',
            'remoteUrl': '/MediaCover/1/poster.jpg',
            'url': '/MediaCover/1/poster.jpg',
          },
        ];

        final result = ImageUtils.extractPosterUrl(
          images,
          baseUrl: 'http://localhost:7878',
          apiKey: 'test-key',
        );

        expect(result.url, 'http://localhost:7878/MediaCover/1/poster.jpg');
        expect(result.headers, {'X-Api-Key': 'test-key'});
      });

      test('uses url when remoteUrl is null', () {
        final images = [
          {'coverType': 'poster', 'url': '/MediaCover/1/poster.jpg'},
        ];

        final result = ImageUtils.extractPosterUrl(
          images,
          baseUrl: 'http://localhost:7878',
          apiKey: 'test-key',
        );

        expect(result.url, 'http://localhost:7878/MediaCover/1/poster.jpg');
        expect(result.headers, {'X-Api-Key': 'test-key'});
      });

      test('returns empty string when images is null', () {
        final result = ImageUtils.extractPosterUrl(
          null,
          baseUrl: 'http://localhost:7878',
          apiKey: 'test-key',
        );

        expect(result.url, '');
        expect(result.headers, isNull);
      });

      test('returns empty string when images is empty', () {
        final result = ImageUtils.extractPosterUrl(
          [],
          baseUrl: 'http://localhost:7878',
          apiKey: 'test-key',
        );

        expect(result.url, '');
        expect(result.headers, isNull);
      });

      test('finds cover type from custom coverTypes list', () {
        final images = [
          {'coverType': 'cover', 'remoteUrl': 'https://example.com/cover.jpg'},
        ];

        final result = ImageUtils.extractPosterUrl(
          images,
          baseUrl: 'http://localhost:7878',
          apiKey: 'test-key',
          coverTypes: ['poster', 'cover'],
        );

        expect(result.url, 'https://example.com/cover.jpg');
        expect(result.headers, isNull);
      });

      test('returns empty string when no matching cover type found', () {
        final images = [
          {
            'coverType': 'banner',
            'remoteUrl': 'https://example.com/banner.jpg',
          },
        ];

        final result = ImageUtils.extractPosterUrl(
          images,
          baseUrl: 'http://localhost:7878',
          apiKey: 'test-key',
          coverTypes: ['poster'],
        );

        expect(result.url, '');
        expect(result.headers, isNull);
      });

      test('returns empty image source for local images without api key', () {
        final images = [
          {'coverType': 'poster', 'url': '/MediaCover/1/poster.jpg'},
        ];

        final result = ImageUtils.extractPosterUrl(
          images,
          baseUrl: 'http://localhost:7878',
          apiKey: '',
        );

        expect(result.url, '');
        expect(result.headers, isNull);
      });
    });

    group('buildTmdbPosterUrl', () {
      test('builds correct TMDB URL with default size', () {
        final result = ImageUtils.buildTmdbPosterUrl('/abc123.jpg');
        expect(result, 'https://image.tmdb.org/t/p/w500/abc123.jpg');
      });

      test('builds correct TMDB URL with custom size', () {
        final result = ImageUtils.buildTmdbPosterUrl(
          '/abc123.jpg',
          size: 'original',
        );
        expect(result, 'https://image.tmdb.org/t/p/original/abc123.jpg');
      });

      test('returns empty string when posterPath is null', () {
        final result = ImageUtils.buildTmdbPosterUrl(null);
        expect(result, '');
      });

      test('returns empty string when posterPath is empty', () {
        final result = ImageUtils.buildTmdbPosterUrl('');
        expect(result, '');
      });
    });
  });
}
