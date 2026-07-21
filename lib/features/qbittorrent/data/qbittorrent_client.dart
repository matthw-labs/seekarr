import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

class QbittorrentClient {
  final String baseUrl;
  final String? username;
  final String? password;
  late final Dio _dio;
  final CookieJar _cookieJar;
  bool _authenticated = false;
  Future<bool>? _authInFlight;

  QbittorrentClient({
    required String url,
    this.username,
    this.password,
    Dio? dio,
    CookieJar? cookieJar,
  }) : baseUrl = _normalizeBaseUrl(url),
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

  static String _normalizeBaseUrl(String url) {
    var normalized = url.trim();
    if (normalized.isEmpty) return '';
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      // Default a scheme-less URL to HTTPS so credentials are not sent in the
      // clear when the user omits the scheme. An explicit http:// is honoured.
      normalized = 'https://$normalized';
    }
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
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
    try {
      final response = await _dio.post(
        '/api/v2/auth/login',
        data: {'username': username, 'password': password},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          extra: {'skipAuthRetry': true},
        ),
      );
      _authenticated = response.data?.toString().trim() == 'Ok.';
    } catch (_) {
      _authenticated = false;
    }
    return _authenticated;
  }

  Future<String> getVersion() async {
    final response = await _dio.get('/api/v2/app/version');
    return response.data?.toString().trim() ?? '';
  }

  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    if (hasCredentials && !_authenticated) {
      await authenticate();
    }
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
    if (hasCredentials && !_authenticated) {
      await authenticate();
    }
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
