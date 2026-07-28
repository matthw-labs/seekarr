import 'package:dio/dio.dart';

/// Status codes that carry a `Location` header we are expected to follow.
const _redirectStatuses = {301, 302, 303, 307, 308};

/// Accepts 3xx so [SameOriginRedirectInterceptor] can inspect them instead of
/// Dio rejecting them before the interceptor chain runs.
bool allowRedirectStatus(int? status) => status != null && status < 400;

/// Follows redirects by hand so a credential header is never replayed to a host
/// the user did not configure.
///
/// `dart:io` strips only `authorization`, `www-authenticate`, `cookie` and
/// `cookie2` when a redirect crosses origins; custom headers such as
/// `X-Api-Key` are copied to *any* target. A compromised instance, a
/// misconfigured reverse proxy, or an on-path attacker on a cleartext base URL
/// could therefore harvest the key with a single 302.
///
/// Same-origin redirects (trailing slashes, base-path normalisation) are the
/// legitimate case and keep working; cross-origin ones fail with an explanatory
/// error rather than leaking the credential.
///
/// Requires the owning [Dio] to be configured with `followRedirects: false` and
/// [allowRedirectStatus] as its `validateStatus`.
class SameOriginRedirectInterceptor extends Interceptor {
  SameOriginRedirectInterceptor(this._dio, {this.maxRedirects = 5});

  final Dio _dio;
  final int maxRedirects;

  /// Redirect depth so far, threaded through `RequestOptions.extra`.
  static const _depthKey = 'seekarr.redirectDepth';

  @override
  Future<void> onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    final status = response.statusCode;
    if (status == null || !_redirectStatuses.contains(status)) {
      handler.next(response);
      return;
    }

    final request = response.requestOptions;
    final location = response.headers.value('location');
    if (location == null || location.isEmpty) {
      handler.reject(
        DioException(
          requestOptions: request,
          response: response,
          type: DioExceptionType.badResponse,
          error:
              'The server answered $status without a Location header. '
              'Check the service URL.',
        ),
      );
      return;
    }

    final target = request.uri.resolve(location);
    if (!_isSameOrigin(request.uri, target)) {
      handler.reject(
        DioException(
          requestOptions: request,
          response: response,
          type: DioExceptionType.badResponse,
          error:
              'The server redirected to ${target.origin}, a different host '
              'than the one configured. The request was not resent so the '
              'API key is not exposed. Point Seekarr directly at the '
              'service, or fix the redirect on the server.',
        ),
      );
      return;
    }

    final depth = (request.extra[_depthKey] as int?) ?? 0;
    if (depth >= maxRedirects) {
      handler.reject(
        DioException(
          requestOptions: request,
          response: response,
          type: DioExceptionType.badResponse,
          error: 'The server redirected more than $maxRedirects times.',
        ),
      );
      return;
    }

    // 303, and 301/302 in practice, downgrade the method to GET and drop the body.
    final becomesGet =
        status == 303 ||
        ((status == 301 || status == 302) &&
            request.method.toUpperCase() != 'HEAD');

    try {
      final followed = await _dio.request(
        target.toString(),
        data: becomesGet ? null : request.data,
        queryParameters: const {}, // already baked into `target`
        cancelToken: request.cancelToken,
        onReceiveProgress: request.onReceiveProgress,
        onSendProgress: request.onSendProgress,
        options: Options(
          method: becomesGet ? 'GET' : request.method,
          headers: request.headers,
          responseType: request.responseType,
          contentType: request.contentType,
          sendTimeout: request.sendTimeout,
          receiveTimeout: request.receiveTimeout,
          followRedirects: false,
          validateStatus: request.validateStatus,
          extra: {...request.extra, _depthKey: depth + 1},
        ),
      );
      handler.resolve(followed);
    } on DioException catch (e) {
      handler.reject(e);
    }
  }

  static bool _isSameOrigin(Uri a, Uri b) =>
      a.scheme == b.scheme && a.host == b.host && a.port == b.port;
}
