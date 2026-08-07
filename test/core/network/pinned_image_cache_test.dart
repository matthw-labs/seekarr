import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show Client;

import 'package:cupola/core/network/pinned_image_cache.dart';

/// Stands in for a real [CacheManager], which opens a sqflite store in its
/// constructor and so cannot be built in a unit test.
class _FakeCacheManager implements BaseCacheManager {
  int emptied = 0;
  int disposed = 0;

  @override
  Future<void> emptyCache() async => emptied++;

  @override
  Future<void> dispose() async => disposed++;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

class _FakeTransport implements Client {
  int closed = 0;

  @override
  void close() => closed++;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

class _Built {
  _Built(this.cacheKey, this.fingerprint, this.host, this.port, this.cache);
  final String cacheKey;
  final String fingerprint;
  final String host;
  final int port;
  final PinnedImageCache cache;

  _FakeCacheManager get manager => cache.manager as _FakeCacheManager;
  _FakeTransport get transport => cache.transport as _FakeTransport;
}

void main() {
  late List<_Built> built;

  setUp(() {
    built = [];
    pinnedImageCacheBuilder =
        ({
          required String cacheKey,
          required String fingerprint,
          required String host,
          required int port,
        }) {
          final PinnedImageCache cache = (
            manager: _FakeCacheManager(),
            transport: _FakeTransport(),
          );
          built.add(_Built(cacheKey, fingerprint, host, port, cache));
          return cache;
        };
  });

  tearDown(() {
    resetPinnedImageCaches();
    CertTrustRegistry.reset();
    pinnedImageCacheBuilder = defaultPinnedImageCacheBuilder;
  });

  group('pinnedImageCacheKey', () {
    // The bug: collapsing every non-alphanumeric to `_` made these two the
    // same key, and a cache key is the name of a sqflite store — so two live
    // managers shared one database.
    test('two origins that differ only in punctuation get different keys', () {
      expect(
        pinnedImageCacheKey('https://nas.local:443', 'aa'),
        isNot(pinnedImageCacheKey('https://nas-local:443', 'aa')),
      );
    });

    test('re-trusting an origin changes its key', () {
      expect(
        pinnedImageCacheKey('https://nas.local:443', 'aa'),
        isNot(pinnedImageCacheKey('https://nas.local:443', 'bb')),
      );
    });

    test('the same origin and pin always produce the same key', () {
      expect(
        pinnedImageCacheKey('https://nas.local:8443', 'ab12'),
        pinnedImageCacheKey('https://nas.local:8443', 'ab12'),
      );
    });

    test('is a filesystem-safe name under a recognisable prefix', () {
      final key = pinnedImageCacheKey('https://nas.local:443', 'aa');
      expect(key, startsWith('cupola_pinned_'));
      expect(RegExp(r'^[a-z0-9_]+$').hasMatch(key), isTrue, reason: key);
    });
  });

  group('pinnedImageCacheFor', () {
    test('is null when nothing is pinned for the origin', () {
      CertTrustRegistry.update(const {'https://nas.local:443': 'aa'});

      expect(pinnedImageCacheFor(null), isNull);
      expect(pinnedImageCacheFor(''), isNull);
      // A different origin, and a cleartext URL that cannot carry a cert.
      expect(pinnedImageCacheFor('https://tmdb.org/poster.jpg'), isNull);
      expect(pinnedImageCacheFor('http://nas.local/poster.jpg'), isNull);
      expect(built, isEmpty);
    });

    test('builds one cache per pinned origin and reuses it', () {
      CertTrustRegistry.update(const {'https://nas.local:443': 'aa'});

      final first = pinnedImageCacheFor('https://nas.local/poster.jpg');
      final second = pinnedImageCacheFor('https://nas.local/fanart.jpg');

      expect(first, isNotNull);
      expect(identical(first, second), isTrue);
      expect(built, hasLength(1));
      expect(built.single.fingerprint, 'aa');
      expect(built.single.host, 'nas.local');
      expect(built.single.port, 443);
    });

    test('pins to the origin the image is actually served from', () {
      CertTrustRegistry.update(const {'https://nas.local:8443': 'aa'});

      pinnedImageCacheFor('https://nas.local:8443/poster.jpg');

      expect(built.single.port, 8443);
    });

    // The leak: the memo entry was overwritten with a new manager built on the
    // *same* cache key, so the superseded one kept its sqlite store and its
    // pinned HttpClient open for the life of the process — and images fetched
    // under the old certificate kept being served.
    test('retires the superseded cache when the fingerprint changes', () async {
      CertTrustRegistry.update(const {'https://nas.local:443': 'aa'});
      final first = pinnedImageCacheFor('https://nas.local/poster.jpg');

      CertTrustRegistry.update(const {'https://nas.local:443': 'bb'});
      final second = pinnedImageCacheFor('https://nas.local/poster.jpg');

      expect(identical(first, second), isFalse);
      expect(built, hasLength(2));
      expect(
        built.last.cacheKey,
        isNot(built.first.cacheKey),
        reason: 'a new pin must not reuse the old store',
      );

      // Retirement is fire-and-forget, so let its microtasks run.
      await Future<void>.delayed(Duration.zero);
      expect(built.first.manager.emptied, 1);
      expect(built.first.manager.disposed, 1);
      expect(built.first.transport.closed, 1);
      expect(built.last.manager.disposed, 0, reason: 'the live one stays open');
    });

    test('an unchanged fingerprint retires nothing', () async {
      CertTrustRegistry.update(const {'https://nas.local:443': 'aa'});
      pinnedImageCacheFor('https://nas.local/poster.jpg');
      pinnedImageCacheFor('https://nas.local/poster.jpg');

      await Future<void>.delayed(Duration.zero);
      expect(built, hasLength(1));
      expect(built.single.manager.disposed, 0);
      expect(built.single.transport.closed, 0);
    });

    test('two pinned origins each get their own cache', () {
      CertTrustRegistry.update(const {
        'https://nas.local:443': 'aa',
        'https://other.local:443': 'bb',
      });

      final a = pinnedImageCacheFor('https://nas.local/poster.jpg');
      final b = pinnedImageCacheFor('https://other.local/poster.jpg');

      expect(identical(a, b), isFalse);
      expect(built, hasLength(2));
      expect(built.first.cacheKey, isNot(built.last.cacheKey));
    });
  });

  group('CertTrustRegistry', () {
    test('reads the pin through the shared origin normaliser', () {
      CertTrustRegistry.update(const {'https://nas.local:8443': 'aa'});

      expect(CertTrustRegistry.pinFor('https://nas.local:8443/x.jpg'), 'aa');
      expect(CertTrustRegistry.pinFor('nas.local:8443'), 'aa');
      expect(CertTrustRegistry.pinFor('https://nas.local:9443/x.jpg'), isNull);
    });

    test('an empty stored pin is no pin at all', () {
      CertTrustRegistry.update(const {'https://nas.local:443': ''});
      expect(CertTrustRegistry.pinFor('https://nas.local/x.jpg'), isNull);
    });

    test('reset clears the process-wide snapshot', () {
      CertTrustRegistry.update(const {'https://nas.local:443': 'aa'});
      CertTrustRegistry.reset();
      expect(CertTrustRegistry.pinFor('https://nas.local/x.jpg'), isNull);
    });
  });
}
