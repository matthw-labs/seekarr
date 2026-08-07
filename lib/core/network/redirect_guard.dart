import 'package:dio/dio.dart';

import 'package:cupola/core/network/connection_failure.dart';

/// Status codes that carry a `Location` header we are expected to follow.
const _redirectStatuses = {301, 302, 303, 307, 308};

/// Headers that describe a request body. A redirect that downgrades to GET
/// leaves the body behind, so these stop describing anything.
const _entityHeaders = {Headers.contentLengthHeader, Headers.contentTypeHeader};

/// Accepts exactly the 3xx codes [SameOriginRedirectInterceptor] knows how to
/// follow, so Dio hands them to the interceptor instead of rejecting them
/// before the chain runs.
///
/// Deliberately *not* "any status below 400": the other 3xx codes (300 Multiple
/// Choices, 304 Not Modified, 305, 306) are not followed by anything here, so
/// accepting them would deliver an empty or HTML body to a caller that goes on
/// to read `response.data['results']` and either throws a type error or
/// silently yields nothing. Rejecting them makes them ordinary Dio failures
/// that [classifyConnectionFailure] can report.
bool allowRedirectStatus(int? status) =>
    status != null && (status < 300 || _redirectStatuses.contains(status));

/// A redirect [SameOriginRedirectInterceptor] refused to follow.
///
/// Carries both the verdict and the sentence explaining it, because the enum
/// alone cannot say *which* host a reverse proxy bounced the request to — and
/// that sentence is the only thing that tells the user their proxy, not their
/// address, is the problem.
///
/// [reason] is [ServiceFailureReason.redirected], which is its own cause rather
/// than a borrowed one. It was `notFound` for a while — close, since both mean
/// "the server answered but the API is not here" — but the fixes differ: a
/// missing base path is corrected in the address field, whereas a refused
/// redirect is corrected on the proxy sitting in front of the service, and the
/// address the user typed may be perfectly right. Either way it tells
/// `certProbeWorthwhile` the handshake already succeeded, so no TLS probe is
/// worth running.
///
/// All three refusals — cross-origin target, missing `Location`, redirect loop
/// — share the reason and differ only in [failureDetail], which is the sentence
/// the UI actually shows.
class RedirectRefused implements Exception, HasFailureReason, HasFailureDetail {
  const RedirectRefused(this.message);

  final String message;

  @override
  String get failureDetail => message;

  @override
  ServiceFailureReason get reason => ServiceFailureReason.redirected;

  @override
  String toString() => message;
}

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
  static const _depthKey = 'cupola.redirectDepth';

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
          error: RedirectRefused(
            'The server answered $status without a Location header. '
            'Check the service URL.',
          ),
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
          error: RedirectRefused(
            'The server redirected to ${target.origin}, a different host '
            'than the one configured. The request was not resent so the '
            'API key is not exposed. Point Cupola directly at the '
            'service, or fix the redirect on the server.',
          ),
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
          error: RedirectRefused(
            'The server redirected more than $maxRedirects times.',
          ),
        ),
      );
      return;
    }

    // 303, and 301/302 in practice, downgrade the method to GET and drop the body.
    final becomesGet =
        status == 303 ||
        ((status == 301 || status == 302) &&
            request.method.toUpperCase() != 'HEAD');

    // Dio stamps `content-length` onto the *original* `RequestOptions` while
    // encoding the body, so replaying `request.headers` verbatim after dropping
    // that body sends a GET whose headers still promise N bytes. `dart:io` then
    // throws `HttpException: Content size below specified contentLength` at
    // `request.close()` — the legitimate same-origin redirect this interceptor
    // exists to follow would fail with an opaque transport error (a Radarr
    // `POST /api/v3/command` behind a proxy that normalises a trailing slash).
    // 307/308 keep the body, so they keep the headers that describe it.
    final headers = Map<String, dynamic>.from(request.headers);
    if (becomesGet) {
      headers.removeWhere(
        (key, _) => _entityHeaders.contains(key.toLowerCase()),
      );
    }

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
          headers: headers,
          responseType: request.responseType,
          contentType: becomesGet ? null : request.contentType,
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
