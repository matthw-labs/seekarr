import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' show Client;
import 'package:http/io_client.dart';

import 'package:cupola/core/network/cert_trust.dart';
import 'package:cupola/core/utils/url_utils.dart';

/// Bridges the Riverpod-held trust map to the leaf image widgets
/// (`ContentCard`, `MediaPosterCard`, …) that predate Riverpod and stay off
/// it deliberately — see `lib/core/widgets/AGENTS.md`: the overwhelming
/// majority of that directory takes plain constructor parameters, and giving
/// every poster widget a `ref` to cover the rare pinned case would cut
/// against that grain for all of them, not just the one that needs it.
///
/// [update] is called from exactly one place, a `ref.listen` on
/// `currentSettingsProvider` in `CupolaApp` — the only spot in the widget
/// tree that both sees Riverpod and sits above every image. Everything
/// downstream, including [pinnedImageCacheFor], reads the snapshot as a pure
/// function of a URL.
class CertTrustRegistry {
  const CertTrustRegistry._();

  static Map<String, String> _trusted = const {};

  static void update(Map<String, String> trustedCertificates) {
    _trusted = trustedCertificates;
  }

  /// Test-only: clears the snapshot so one test's pins cannot leak into the
  /// next — this is process-wide state, not scoped to a `ProviderContainer`.
  @visibleForTesting
  static void reset() => _trusted = const {};

  /// The trusted fingerprint for [rawUrl]'s origin, or null.
  static String? pinFor(String rawUrl) {
    final origin = UrlUtils.certOrigin(rawUrl);
    if (origin == null) return null;
    final pin = _trusted[origin];
    return (pin == null || pin.isEmpty) ? null : pin;
  }
}

/// A pinned [CacheManager] together with the transport it owns.
///
/// The transport travels with the manager because nothing else can close it:
/// `CacheManager.dispose()` closes the sqlite store but knows nothing about the
/// `HttpClient` inside its `FileService`, so a superseded manager would keep
/// its sockets open for the life of the process.
typedef PinnedImageCache = ({BaseCacheManager manager, Client transport});

/// How a pinned cache is built. A seam rather than a hard-coded constructor so
/// the memoisation and retirement contract below can be tested without a real
/// sqflite store — a [CacheManager] opens one in its constructor.
@visibleForTesting
typedef PinnedImageCacheBuilder =
    PinnedImageCache Function({
      required String cacheKey,
      required String fingerprint,
      required String host,
      required int port,
    });

/// The real builder — kept reachable so a test that swapped
/// [pinnedImageCacheBuilder] can put it back.
@visibleForTesting
PinnedImageCache defaultPinnedImageCacheBuilder({
  required String cacheKey,
  required String fingerprint,
  required String host,
  required int port,
}) {
  final transport = IOClient(
    buildPinnedHttpClient(
      pinnedFingerprint: fingerprint,
      pinnedHost: host,
      pinnedPort: port,
    ),
  );
  return (
    manager: CacheManager(
      Config(cacheKey, fileService: HttpFileService(httpClient: transport)),
    ),
    transport: transport,
  );
}

@visibleForTesting
PinnedImageCacheBuilder pinnedImageCacheBuilder =
    defaultPinnedImageCacheBuilder;

/// One cache per pinned origin, rebuilt only when that origin's fingerprint
/// actually changes.
///
/// Memoisation matters here for a reason beyond the usual "don't rebuild
/// widgets": a [CacheManager] opens its own on-disk cache (sqflite on most
/// platforms), so a fresh instance per build would duplicate that store and
/// its I/O on every rebuild rather than just its `HttpClient`.
final Map<String, ({PinnedImageCache cache, String fingerprint})>
_pinnedCaches = {};

/// Test-only: retires every memoised cache so one test cannot see another's.
@visibleForTesting
void resetPinnedImageCaches() {
  final entries = _pinnedCaches.values.toList();
  _pinnedCaches.clear();
  for (final entry in entries) {
    unawaited(_retire(entry.cache));
  }
}

/// A [CacheManager] pinned to [imageUrl]'s trusted certificate, or null when
/// nothing is pinned for it.
///
/// Null is the answer for the overwhelming majority of images — anything on
/// a certificate the OS already trusts, a plain `http://` LAN address, or a
/// public host like TMDB — and it means exactly "use `CachedNetworkImage`'s
/// own default manager", so passing this straight through as `cacheManager:`
/// is safe everywhere, pinned or not.
BaseCacheManager? pinnedImageCacheFor(String? imageUrl) {
  if (imageUrl == null || imageUrl.isEmpty) return null;
  final pin = CertTrustRegistry.pinFor(imageUrl);
  if (pin == null) return null;
  final origin = UrlUtils.certOrigin(imageUrl)!;

  final cached = _pinnedCaches[origin];
  if (cached != null && cached.fingerprint == pin) return cached.cache.manager;

  if (cached != null) {
    // A changed fingerprint means the user re-trusted this origin, so the
    // certificate everything in the old store was fetched under is no longer
    // the one they approved. Retiring it closes the sqlite store and the
    // pinned `HttpClient` — flutter_cache_manager documents one instance per
    // cache key, and simply overwriting the memo entry left the previous
    // manager holding both open for the life of the process.
    unawaited(_retire(cached.cache));
  }

  final endpoint = Uri.parse(origin);
  final cache = pinnedImageCacheBuilder(
    cacheKey: pinnedImageCacheKey(origin, pin),
    fingerprint: pin,
    host: endpoint.host,
    port: endpoint.port,
  );
  _pinnedCaches[origin] = (cache: cache, fingerprint: pin);
  return cache.manager;
}

Future<void> _retire(PinnedImageCache cache) async {
  try {
    // The new pin gets a new cache key and therefore a new store, so the old
    // one would otherwise sit on disk holding images fetched under a
    // certificate the user has since replaced.
    await cache.manager.emptyCache();
  } catch (_) {
    // A store that never opened has nothing to empty; retirement is
    // best-effort housekeeping and must not take a caller down with it.
  }
  try {
    await cache.manager.dispose();
  } catch (_) {
    // Same.
  }
  cache.transport.close();
}

/// [Config]'s cache key becomes a directory and a database name, so it has to
/// be filesystem-safe, unique per cache, and stable for as long as the cache
/// is.
///
/// Hashed rather than sanitised: replacing every non-alphanumeric character
/// with `_` made `https://nas.local:443` and `https://nas-local:443` the same
/// key, which is two live [CacheManager]s sharing one sqflite store. The
/// fingerprint is part of the input so re-trusting an origin starts a clean
/// store instead of re-serving images fetched under the old certificate.
@visibleForTesting
String pinnedImageCacheKey(String origin, String fingerprint) {
  final digest = sha256.convert(utf8.encode('$origin\x00$fingerprint'));
  return 'cupola_pinned_${digest.toString().substring(0, 32)}';
}
