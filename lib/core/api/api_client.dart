import 'package:dio/dio.dart';

import 'package:seekarr/core/network/redirect_guard.dart';

/// Timeouts match the newer per-service clients (SABnzbd, NZBGet, Unraid) so a
/// black-holed host fails in seconds instead of hanging on socket defaults.
const _connectTimeout = Duration(seconds: 10);
const _receiveTimeout = Duration(seconds: 15);

class ApiClient {
  final Dio _dio;

  ApiClient({required String baseUrl, required String apiKey})
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
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

  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) {
    return _dio.get(
      path,
      queryParameters: queryParameters,
      cancelToken: cancelToken,
    );
  }

  Future<Response> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) {
    return _dio.post(path, data: data, queryParameters: queryParameters);
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
