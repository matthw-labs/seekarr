import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import 'package:seekarr/core/network/connection_failure.dart';
import 'package:seekarr/core/utils/url_utils.dart';

/// Error thrown by [QbittorrentClient], carrying the [reason] so a caller
/// verifying the connection can tell rejected credentials from an unreachable
/// host — matching the contract the other service clients use.
class QbittorrentException implements Exception, HasFailureReason {
  const QbittorrentException(
    this.message, {
    this.reason = ServiceFailureReason.unknown,
  });
  final String message;
  @override
  final ServiceFailureReason reason;
  @override
  String toString() => 'QbittorrentException: $message';
}

class QbittorrentClient {
  final String baseUrl;
  final String? username;
  final String? password;
  late final Dio _dio;
  final CookieJar _cookieJar;
  bool _authenticated = false;
  Future<bool>? _authInFlight;

  /// Set when the WebUI answered the login with an unambiguous rejection —
  /// `200 Fails.` (qB ≤ 5.0) or `401` (5.1+).
  bool _credentialsRejected = false;

  QbittorrentClient({
    required String url,
    this.username,
    this.password,
    Dio? dio,
    CookieJar? cookieJar,
  }) : baseUrl = UrlUtils.normalizeBaseUrl(url),
       _cookieJar = cookieJar ?? CookieJar() {
    _dio =
        dio ??
        Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
            sendTimeout: const Duration(seconds: 10),
          ),
        );

    _dio.interceptors.add(CookieManager(_cookieJar));
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers['Referer'] = baseUrl;
          options.headers['Origin'] = baseUrl;
          handler.next(options);
        },
        onError: (error, handler) async {
          final isAuthFailure = error.response?.statusCode == 403;
          final alreadyRetried =
              error.requestOptions.extra['skipAuthRetry'] == true;
          if (!isAuthFailure || !hasCredentials || alreadyRetried) {
            handler.next(error);
            return;
          }
          final ok = await authenticate();
          if (!ok) {
            handler.next(error);
            return;
          }
          error.requestOptions.extra['skipAuthRetry'] = true;
          try {
            final response = await _dio.fetch(error.requestOptions);
            handler.resolve(response);
          } catch (_) {
            handler.next(error);
          }
        },
      ),
    );
  }

  bool get hasCredentials =>
      username != null &&
      username!.isNotEmpty &&
      password != null &&
      password!.isNotEmpty;

  Future<bool> authenticate() {
    if (!hasCredentials) return Future.value(true);
    final inflight = _authInFlight;
    if (inflight != null) return inflight;
    final future = _doAuthenticate();
    _authInFlight = future;
    future.whenComplete(() => _authInFlight = null);
    return future;
  }

  Future<bool> _doAuthenticate() async {
    _credentialsRejected = false;
    try {
      final response = await _dio.post(
        '/api/v2/auth/login',
        data: {'username': username, 'password': password},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          extra: {'skipAuthRetry': true},
        ),
      );
      _authenticated = _isLoginSuccess(response);
      _credentialsRejected = _isCredentialRejection(
        response.statusCode,
        response.data,
      );
    } on DioException catch (e) {
      _authenticated = false;
      // A 401 arrives as an error rather than a response, so read it here too.
      _credentialsRejected = _isCredentialRejection(
        e.response?.statusCode,
        e.response?.data,
      );
    } catch (_) {
      _authenticated = false;
    }
    return _authenticated;
  }

  /// qBittorrent <= 5.0 answers `200 Ok.` on success and `200 Fails.` on bad
  /// credentials; 5.1+ answers `204` with an empty body on success and `401`
  /// on bad credentials. Accept any 2xx that is not an explicit failure.
  static bool _isLoginSuccess(Response response) {
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) return false;
    final body = response.data?.toString().trim().toLowerCase() ?? '';
    return body != 'fails.';
  }

  /// Whether the login response is an unambiguous "wrong credentials".
  ///
  /// Deliberately narrow: only `200 Fails.` and `401`. A 403 on the login route
  /// means something else (a proxy, a banned IP) and keeps the previous flow,
  /// where the interceptor re-authenticates once and the real status surfaces.
  static bool _isCredentialRejection(int? status, dynamic body) {
    if (status == 401) return true;
    if (status == 200) {
      return body?.toString().trim().toLowerCase() == 'fails.';
    }
    return false;
  }

  /// Authenticates when credentials are configured, failing fast on a rejection.
  ///
  /// Without this the client pressed on to the data call, took a 403, let the
  /// interceptor re-authenticate, and only then surfaced the failure — three
  /// round trips to learn the password was wrong, which on a slow link ran past
  /// the verify timeout and reported "check the address" instead.
  Future<void> _ensureAuthenticated() async {
    if (!hasCredentials || _authenticated) return;
    await authenticate();
    if (!_authenticated && _credentialsRejected) {
      throw const QbittorrentException(
        'qBittorrent rejected the username or password',
        reason: ServiceFailureReason.unauthorized,
      );
    }
  }

  Future<String> getVersion() async {
    await _ensureAuthenticated();
    final response = await _dio.get('/api/v2/app/version');
    return response.data?.toString().trim() ?? '';
  }

  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    await _ensureAuthenticated();
    return _dio.get(
      path,
      queryParameters: queryParameters,
      cancelToken: cancelToken,
    );
  }

  Future<Response> post(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? data,
    FormData? formData,
  }) async {
    await _ensureAuthenticated();
    return _dio.post(
      path,
      queryParameters: queryParameters,
      data: formData ?? data,
      options: Options(
        contentType: formData != null
            ? Headers.multipartFormDataContentType
            : Headers.formUrlEncodedContentType,
      ),
    );
  }

  void close({bool force = false}) {
    _dio.close(force: force);
  }
}
