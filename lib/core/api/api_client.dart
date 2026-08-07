import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:seekarr/core/network/cert_trust.dart';
import 'package:seekarr/core/network/redirect_guard.dart';
import 'package:seekarr/core/utils/url_utils.dart';

/// Timeouts match the newer per-service clients (SABnzbd, NZBGet, Unraid) so a
/// black-holed host fails in seconds instead of hanging on socket defaults.
const _connectTimeout = Duration(seconds: 10);
const _receiveTimeout = Duration(seconds: 15);

/// For endpoints that do real server-side work before answering — Sonarr/Radarr/
/// Lidarr's `manualimport` walks the folder, parses every release name and runs
/// MediaInfo on each file — the default 15s ceiling fires long before a healthy
/// instance replies. Pass this (or another explicit value) per request rather
/// than raising the global default, which would bring back multi-minute hangs on
/// an unreachable host.
const kSlowScanReceiveTimeout = Duration(minutes: 5);

/// For interactive release search, which is synchronous on the server: Sonarr's
/// `/release` builds one task per enabled indexer and awaits them all, so the
/// slowest indexer gates the response and a rate-limited one can hold it for
/// minutes. Under the default 15s ceiling those searches never returned at all.
///
/// Five minutes is chosen to sit *above* every common gateway ceiling — nginx
/// defaults to 60s, Cloudflare caps at 100s and cannot be raised on a free plan
/// — which is what makes a failure attributable: a connection that dies at 62s
/// was cut by something in the middle, not by us, and the UI can say so. A 60s
/// client timeout would make Seekarr indistinguishable from the proxy it is
/// trying to blame.
///
/// Only [ApiClient.get]'s `receiveTimeout` is raised. `connectTimeout` stays at
/// ten seconds, because connecting and waiting are different problems and a host
/// that will not answer should still fail fast.
const kReleaseSearchReceiveTimeout = Duration(minutes: 5);

class ApiClient {
  final Dio _dio;

  /// [baseUrl] may omit the scheme — the onboarding and settings fields both
  /// accept a bare host, and Dio's `baseUrl` setter throws `ArgumentError` on
  /// one. Normalising here (rather than at each of the twelve call sites) means
  /// a bare host can only ever fail as a connection error.
  ///
  /// [pinnedCertFingerprint], when non-empty, is a self-signed certificate the
  /// user explicitly trusted for this origin (trust-on-first-use, ADR-6) — see
  /// [SettingsModel.pinForUrl]. Null or empty leaves this client on the
  /// platform trust store only, exactly as before ADR-6.
  ApiClient({
    required String baseUrl,
    required String apiKey,
    String? pinnedCertFingerprint,
  }) : this._(
         baseUrl: baseUrl,
         authHeaders: {'X-Api-Key': apiKey},
         pinnedCertFingerprint: pinnedCertFingerprint,
       );

  /// For a service whose credential does not travel as `X-Api-Key`.
  ///
  /// Jellyfin wants `Authorization: MediaBrowser Token="…"` and Plex wants
  /// `X-Plex-Token` alongside a persisted `X-Plex-Client-Identifier`, so neither
  /// fits the arr-family header this class was built around. A named constructor
  /// rather than an optional parameter on the default one, because the two are
  /// genuinely different contracts: passing both an `apiKey` and a header map
  /// would leave the caller guessing which one authenticates the request.
  ///
  /// Everything else is deliberately shared — the timeouts, the JSON headers and
  /// above all [SameOriginRedirectInterceptor], which is what stops a credential
  /// being replayed to a host the user never configured. A bespoke `Dio` per
  /// media server would have had to re-earn that guarantee twice.
  ApiClient.authenticatedBy({
    required String baseUrl,
    required Map<String, String> headers,
    String? pinnedCertFingerprint,
  }) : this._(
         baseUrl: baseUrl,
         authHeaders: headers,
         pinnedCertFingerprint: pinnedCertFingerprint,
       );

  ApiClient._({
    required String baseUrl,
    required Map<String, String> authHeaders,
    String? pinnedCertFingerprint,
  }) : _dio = Dio(
         BaseOptions(
           baseUrl: UrlUtils.normalizeBaseUrl(baseUrl),
           connectTimeout: _connectTimeout,
           receiveTimeout: _receiveTimeout,
           // Redirects are followed by SameOriginRedirectInterceptor instead, so
           // the credential can never be replayed to an unconfigured host.
           followRedirects: false,
           validateStatus: allowRedirectStatus,
           headers: {
             ...authHeaders,
             'Content-Type': 'application/json',
             'Accept': 'application/json',
           },
         ),
       ) {
    // A followed same-origin redirect goes out over this same `_dio`, so it
    // inherits the pinned adapter automatically — no extra wiring needed for
    // SameOriginRedirectInterceptor to keep honouring the pin.
    final adapter = pinnedHttpClientAdapterFor(
      _dio.options.baseUrl,
      pinnedFingerprint: pinnedCertFingerprint,
    );
    if (adapter != null) _dio.httpClientAdapter = adapter;
    _dio.interceptors.add(SameOriginRedirectInterceptor(_dio));
  }

  /// Lets a test swap in a stub transport, the way the per-service clients take
  /// an injected `Dio`.
  @visibleForTesting
  Dio get dio => _dio;

  /// The normalised base URL, for a transport that cannot go through this Dio.
  ///
  /// Phase 2's background task is native code with its own HTTP stack, so it has
  /// to be handed a URL and headers rather than a client. Exposed narrowly for
  /// that, and it is worth knowing what such a caller gives up:
  /// [SameOriginRedirectInterceptor] is a credential-replay guard, not a
  /// convenience, so anything bypassing this client owes the same refusal.
  String get baseUrl => _dio.options.baseUrl;

  /// The headers this client sends, auth included.
  Map<String, String> get headers => {
    for (final entry in _dio.options.headers.entries)
      entry.key: '${entry.value}',
  };

  /// [receiveTimeout] overrides the client default for this request only; see
  /// [kSlowScanReceiveTimeout].
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) {
    return _dio.get(
      path,
      queryParameters: queryParameters,
      cancelToken: cancelToken,
      options: receiveTimeout == null
          ? null
          : Options(receiveTimeout: receiveTimeout),
    );
  }

  Future<Response> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Duration? receiveTimeout,
  }) {
    return _dio.post(
      path,
      data: data,
      queryParameters: queryParameters,
      options: receiveTimeout == null
          ? null
          : Options(receiveTimeout: receiveTimeout),
    );
  }

  Future<Response> put(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) {
    return _dio.put(path, data: data, queryParameters: queryParameters);
  }

  Future<Response> patch(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) {
    return _dio.patch(path, data: data, queryParameters: queryParameters);
  }

  Future<Response> delete(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) {
    return _dio.delete(path, data: data, queryParameters: queryParameters);
  }

  void close({bool force = false}) {
    _dio.close(force: force);
  }
}
