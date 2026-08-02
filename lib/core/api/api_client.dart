import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

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

class ApiClient {
  final Dio _dio;

  /// [baseUrl] may omit the scheme — the onboarding and settings fields both
  /// accept a bare host, and Dio's `baseUrl` setter throws `ArgumentError` on
  /// one. Normalising here (rather than at each of the twelve call sites) means
  /// a bare host can only ever fail as a connection error.
  ApiClient({required String baseUrl, required String apiKey})
    : _dio = Dio(
        BaseOptions(
          baseUrl: UrlUtils.normalizeBaseUrl(baseUrl),
          connectTimeout: _connectTimeout,
          receiveTimeout: _receiveTimeout,
          // Redirects are followed by SameOriginRedirectInterceptor instead, so
          // `X-Api-Key` can never be replayed to an unconfigured host.
          followRedirects: false,
          validateStatus: allowRedirectStatus,
          headers: {
            'X-Api-Key': apiKey,
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      ) {
    _dio.interceptors.add(SameOriginRedirectInterceptor(_dio));
  }

  /// Lets a test swap in a stub transport, the way the per-service clients take
  /// an injected `Dio`.
  @visibleForTesting
  Dio get dio => _dio;

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
