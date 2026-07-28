import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/network/connection_failure.dart';

DioException _badResponse(int code) => DioException(
  requestOptions: RequestOptions(path: '/'),
  type: DioExceptionType.badResponse,
  response: Response(
    requestOptions: RequestOptions(path: '/'),
    statusCode: code,
  ),
);

DioException _wrapping(Object? inner, DioExceptionType type) => DioException(
  requestOptions: RequestOptions(path: '/'),
  type: type,
  error: inner,
);

class _KnowsWhy implements Exception, HasFailureReason {
  const _KnowsWhy(this.reason);
  @override
  final ServiceFailureReason reason;
}

void main() {
  group('classifyConnectionFailure', () {
    test('trusts an exception that already knows why it failed', () {
      expect(
        classifyConnectionFailure(
          const _KnowsWhy(ServiceFailureReason.unauthorized),
        ),
        ServiceFailureReason.unauthorized,
      );
    });

    test('401 and 403 are rejected credentials, not unreachability', () {
      expect(
        classifyConnectionFailure(_badResponse(401)),
        ServiceFailureReason.unauthorized,
      );
      expect(
        classifyConnectionFailure(_badResponse(403)),
        ServiceFailureReason.unauthorized,
      );
    });

    test('404 points at the wrong base path', () {
      expect(
        classifyConnectionFailure(_badResponse(404)),
        ServiceFailureReason.notFound,
      );
    });

    test('5xx is the server, not the client config', () {
      expect(
        classifyConnectionFailure(_badResponse(503)),
        ServiceFailureReason.serverError,
      );
    });

    test('an unmapped status stays unknown', () {
      expect(
        classifyConnectionFailure(_badResponse(418)),
        ServiceFailureReason.unknown,
      );
    });

    test('Dio timeouts map to timeout', () {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        expect(
          classifyConnectionFailure(_wrapping(null, type)),
          ServiceFailureReason.timeout,
          reason: '$type should be a timeout',
        );
      }
    });

    test('badCertificate is a TLS problem', () {
      expect(
        classifyConnectionFailure(
          _wrapping(null, DioExceptionType.badCertificate),
        ),
        ServiceFailureReason.tls,
      );
    });

    test('unwraps the cause Dio buries in connectionError', () {
      expect(
        classifyConnectionFailure(
          _wrapping(
            const SocketException('refused'),
            DioExceptionType.connectionError,
          ),
        ),
        ServiceFailureReason.unreachable,
      );
      expect(
        classifyConnectionFailure(
          _wrapping(
            const HandshakeException('bad cert'),
            DioExceptionType.connectionError,
          ),
        ),
        ServiceFailureReason.tls,
      );
    });

    test('a connectionError with no inner cause is still unreachable', () {
      expect(
        classifyConnectionFailure(
          _wrapping(null, DioExceptionType.connectionError),
        ),
        ServiceFailureReason.unreachable,
      );
    });

    test('bare socket, TLS and timeout errors are classified', () {
      expect(
        classifyConnectionFailure(const SocketException('no route')),
        ServiceFailureReason.unreachable,
      );
      expect(
        classifyConnectionFailure(const HandshakeException('expired')),
        ServiceFailureReason.tls,
      );
      expect(
        classifyConnectionFailure(TimeoutException('slow')),
        ServiceFailureReason.timeout,
      );
    });

    test('an unattributable error returns the caller fallback', () {
      // Socket.IO reports connect failures as an untyped string.
      expect(classifyConnectionFailure('boom'), ServiceFailureReason.unknown);
      expect(
        classifyConnectionFailure(
          'boom',
          fallback: ServiceFailureReason.unreachable,
        ),
        ServiceFailureReason.unreachable,
      );
      expect(
        classifyConnectionFailure(
          null,
          fallback: ServiceFailureReason.unreachable,
        ),
        ServiceFailureReason.unreachable,
      );
    });

    test('the fallback never overrides an attributed cause', () {
      expect(
        classifyConnectionFailure(
          _badResponse(401),
          fallback: ServiceFailureReason.unreachable,
        ),
        ServiceFailureReason.unauthorized,
      );
    });
  });

  group('looksUnauthorizedMessage', () {
    test('matches the wording SABnzbd and Unraid actually use', () {
      for (final message in [
        'API Key Incorrect',
        'Unauthorized',
        'Forbidden',
        'Access denied',
        'Not logged in',
      ]) {
        expect(
          looksUnauthorizedMessage(message),
          isTrue,
          reason: '"$message" should read as an auth failure',
        );
      }
    });

    test('does not claim auth failure for unrelated errors', () {
      expect(looksUnauthorizedMessage('Queue is empty'), isFalse);
      expect(looksUnauthorizedMessage('Disk full'), isFalse);
    });
  });

  group('reasonForStatusCode', () {
    test('maps the statuses the UI can act on', () {
      expect(reasonForStatusCode(401), ServiceFailureReason.unauthorized);
      expect(reasonForStatusCode(404), ServiceFailureReason.notFound);
      expect(reasonForStatusCode(500), ServiceFailureReason.serverError);
      expect(reasonForStatusCode(302), ServiceFailureReason.unknown);
    });
  });
}
