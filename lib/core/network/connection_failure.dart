import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// Why a connection attempt failed.
///
/// A bare "disconnected" cannot tell a wrong address apart from rejected
/// credentials, which leaves the user with a single generic "could not
/// connect" message and nothing to act on. This classifies the failure so the
/// UI can name the actual cause.
enum ServiceFailureReason {
  /// The host never answered: DNS failure, connection refused, no route.
  unreachable,

  /// Reached the host, but it did not answer within the timeout.
  timeout,

  /// The TLS handshake failed — untrusted, expired or mismatched certificate.
  tls,

  /// Reached the service, which rejected the credentials or the API key.
  unauthorized,

  /// Reached a server, but the API is not at this URL — typically a base URL
  /// pointing at the wrong app, or a missing reverse-proxy subpath.
  notFound,

  /// Reached a server that answered with a redirect nothing here may follow:
  /// a `Location` pointing at another origin (following it would replay the
  /// API key to a host the user never configured), a 3xx with no `Location` at
  /// all, or a redirect loop.
  ///
  /// Distinct from [notFound] because the fix is different — the address is
  /// plausible and the server is answering, but something in front of the
  /// service is bouncing the request — and because it must never trigger a TLS
  /// probe: the handshake already succeeded.
  redirected,

  /// The service answered with a 5xx.
  serverError,

  /// Reached, failed, and the cause cannot be attributed.
  unknown,
}

/// Implemented by client exceptions that already know why they failed, so
/// [classifyConnectionFailure] can use their verdict instead of guessing from
/// a wrapped error it can no longer see.
abstract interface class HasFailureReason {
  ServiceFailureReason get reason;
}

/// Implemented by failures that carry a sentence worth showing verbatim,
/// because [ServiceFailureReason] cannot express it.
///
/// The enum is a closed vocabulary on purpose — the UI resolves a tone, a glyph
/// and a label from it — but a handful of failures know something specific and
/// actionable that the vocabulary flattens away: *which* host a reverse proxy
/// redirected to, for instance. Those implement this so the sentence survives
/// the trip to the UI instead of collapsing into the generic copy.
abstract interface class HasFailureDetail {
  String get failureDetail;
}

/// The verbatim explanation [error] carries, or null when it has none — which
/// is the common case, and means "use the message for the reason instead".
///
/// Unwraps one [DioException] level the same way [classifyConnectionFailure]
/// does, because an interceptor's rejection reaches the caller wrapped.
String? connectionFailureDetail(Object? error) {
  if (error is HasFailureDetail) return error.failureDetail;
  if (error is DioException) {
    final inner = error.error;
    if (inner is HasFailureDetail) return inner.failureDetail;
  }
  return null;
}

/// Maps a thrown [error] onto the cause the UI should report.
///
/// [fallback] is returned only when the error carries nothing to attribute it
/// with — Socket.IO, for instance, reports connect failures as an untyped
/// string, and there `unreachable` is a better guess than `unknown`.
ServiceFailureReason classifyConnectionFailure(
  Object? error, {
  ServiceFailureReason fallback = ServiceFailureReason.unknown,
}) {
  if (error is HasFailureReason) return error.reason;
  if (error is DioException) return _fromDio(error, fallback);
  if (error is TimeoutException) return ServiceFailureReason.timeout;
  // HandshakeException extends TlsException, so this covers both.
  if (error is TlsException) return ServiceFailureReason.tls;
  if (error is SocketException) return ServiceFailureReason.unreachable;
  return fallback;
}

/// Heuristic for the services that report an auth failure inside a 200 body
/// instead of an HTTP status — SABnzbd's `{"status": false, "error": …}` and
/// Unraid's GraphQL `errors` array. Matches the wording those APIs use; a
/// miss only costs the generic message, never a wrong verdict on reachability.
bool looksUnauthorizedMessage(String message) {
  final text = message.toLowerCase();
  return text.contains('unauthor') ||
      text.contains('api key') ||
      text.contains('apikey') ||
      text.contains('forbidden') ||
      text.contains('access denied') ||
      text.contains('not logged in');
}

/// Maps a non-2xx HTTP status onto a cause, for callers that inspect the
/// status themselves instead of letting the client throw.
ServiceFailureReason reasonForStatusCode(int code) {
  if (code == 401 || code == 403) return ServiceFailureReason.unauthorized;
  if (code == 404) return ServiceFailureReason.notFound;
  if (code >= 500) return ServiceFailureReason.serverError;
  // Any 3xx that reaches here is one nothing followed — the codes
  // `allowRedirectStatus` rejects outright (300, 304, 305, 306), or a redirect
  // on a client that does not follow them. Left as `unknown` these produced
  // "Could not verify the instance", which sends the user to re-check
  // credentials that were never the problem.
  if (code >= 300 && code < 400) return ServiceFailureReason.redirected;
  return ServiceFailureReason.unknown;
}

ServiceFailureReason _fromDio(
  DioException error,
  ServiceFailureReason fallback,
) {
  // An interceptor that refused the request already reached a verdict; Dio only
  // wrapped it. Reading it here is what keeps that verdict from being re-derived
  // — wrongly — from the status code Dio happened to attach. Without this a
  // refused redirect is classified from its 3xx, which `reasonForStatusCode`
  // does not map, so every one of them landed on `unknown`.
  final wrapped = error.error;
  if (wrapped is HasFailureReason) return wrapped.reason;

  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return ServiceFailureReason.timeout;
    case DioExceptionType.badCertificate:
      return ServiceFailureReason.tls;
    case DioExceptionType.badResponse:
      return reasonForStatusCode(error.response?.statusCode ?? 0);
    case DioExceptionType.cancel:
      return ServiceFailureReason.unknown;
    case DioExceptionType.connectionError:
    case DioExceptionType.unknown:
      // Dio buries the real cause here; unwrap one level.
      final inner = error.error;
      if (inner is TlsException) return ServiceFailureReason.tls;
      if (inner is SocketException) return ServiceFailureReason.unreachable;
      if (inner is TimeoutException) return ServiceFailureReason.timeout;
      return error.type == DioExceptionType.connectionError
          ? ServiceFailureReason.unreachable
          : fallback;
  }
}
