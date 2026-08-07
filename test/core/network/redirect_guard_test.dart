import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/network/redirect_guard.dart';

/// Adapter that answers a redirect for the first N requests, then 200, and
/// records every (uri, method, headers) triple it saw.
class _RedirectingAdapter implements HttpClientAdapter {
  _RedirectingAdapter({
    required this.location,
    this.status = 302,
    this.redirectsToServe = 1,
    this.omitLocation = false,
  });

  final String location;
  final int status;
  int redirectsToServe;
  final bool omitLocation;

  final List<Uri> seenUris = [];
  final List<String> seenMethods = [];
  final List<Map<String, dynamic>> seenHeaders = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seenUris.add(options.uri);
    seenMethods.add(options.method);
    seenHeaders.add(Map<String, dynamic>.from(options.headers));

    if (redirectsToServe > 0) {
      redirectsToServe--;
      return ResponseBody.fromBytes(
        Uint8List(0),
        status,
        headers: {
          if (!omitLocation) 'location': [location],
        },
      );
    }
    return ResponseBody.fromBytes(
      Uint8List.fromList(utf8.encode('{"ok":true}')),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }
}

/// Header lookup that does not care how the sending layer cased the key.
bool _hasHeader(Map<String, dynamic> headers, String name) =>
    headers.keys.any((key) => key.toLowerCase() == name.toLowerCase());

Dio _guardedDio(HttpClientAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://radarr.example.com',
      followRedirects: false,
      validateStatus: allowRedirectStatus,
      headers: {'X-Api-Key': 'secret-key'},
    ),
  );
  dio.httpClientAdapter = adapter;
  dio.interceptors.add(SameOriginRedirectInterceptor(dio));
  return dio;
}

void main() {
  group('SameOriginRedirectInterceptor', () {
    test('follows a same-origin redirect and keeps the API key', () async {
      final adapter = _RedirectingAdapter(
        location: 'https://radarr.example.com/api/v3/movie/',
      );
      final response = await _guardedDio(adapter).get('/api/v3/movie');

      expect(response.statusCode, 200);
      expect(adapter.seenUris, hasLength(2));
      expect(adapter.seenUris.last.path, '/api/v3/movie/');
      // Same origin, so re-sending the credential is safe and required.
      expect(adapter.seenHeaders.last['X-Api-Key'], 'secret-key');
    });

    test('follows a relative Location against the request URI', () async {
      final adapter = _RedirectingAdapter(location: '/api/v3/movie/');
      await _guardedDio(adapter).get('/api/v3/movie');

      expect(adapter.seenUris.last.host, 'radarr.example.com');
      expect(adapter.seenUris.last.path, '/api/v3/movie/');
    });

    test('refuses a cross-origin redirect without resending the key', () async {
      final adapter = _RedirectingAdapter(
        location: 'https://attacker.example.net/collect',
      );

      await expectLater(
        _guardedDio(adapter).get('/api/v3/movie'),
        throwsA(
          isA<DioException>().having(
            (e) => e.error.toString(),
            'error',
            contains('different host'),
          ),
        ),
      );

      // The attacker host was never contacted, so the key never left.
      expect(adapter.seenUris, hasLength(1));
      expect(
        adapter.seenUris.every((u) => u.host == 'radarr.example.com'),
        isTrue,
      );
    });

    test('treats a scheme downgrade as cross-origin', () async {
      final adapter = _RedirectingAdapter(
        location: 'http://radarr.example.com/api/v3/movie',
      );

      await expectLater(
        _guardedDio(adapter).get('/api/v3/movie'),
        throwsA(isA<DioException>()),
      );
      expect(adapter.seenUris, hasLength(1));
    });

    test('treats a port change as cross-origin', () async {
      final adapter = _RedirectingAdapter(
        location: 'https://radarr.example.com:8443/api/v3/movie',
      );

      await expectLater(
        _guardedDio(adapter).get('/api/v3/movie'),
        throwsA(isA<DioException>()),
      );
      expect(adapter.seenUris, hasLength(1));
    });

    test('rejects a redirect with no Location header', () async {
      final adapter = _RedirectingAdapter(location: '', omitLocation: true);

      await expectLater(
        _guardedDio(adapter).get('/api/v3/movie'),
        throwsA(
          isA<DioException>().having(
            (e) => e.error.toString(),
            'error',
            contains('without a Location header'),
          ),
        ),
      );
    });

    test('stops after maxRedirects on a same-origin loop', () async {
      final adapter = _RedirectingAdapter(
        location: 'https://radarr.example.com/loop',
        redirectsToServe: 100,
      );
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://radarr.example.com',
          followRedirects: false,
          validateStatus: allowRedirectStatus,
        ),
      );
      dio.httpClientAdapter = adapter;
      dio.interceptors.add(SameOriginRedirectInterceptor(dio, maxRedirects: 3));

      await expectLater(
        dio.get('/loop'),
        throwsA(
          isA<DioException>().having(
            (e) => e.error.toString(),
            'error',
            contains('more than 3 times'),
          ),
        ),
      );
      // Initial request plus 3 followed hops.
      expect(adapter.seenUris, hasLength(4));
    });

    test('a 303 downgrades the followed request to GET', () async {
      final adapter = _RedirectingAdapter(
        location: 'https://radarr.example.com/graphql/',
        status: 303,
      );
      await _guardedDio(adapter).post('/graphql', data: {'query': '{ x }'});

      expect(adapter.seenUris, hasLength(2));
      expect(adapter.seenMethods, ['POST', 'GET']);
      expect(adapter.seenHeaders.last['X-Api-Key'], 'secret-key');
    });

    // The bug this asserts against: Dio writes `content-length` onto the
    // *original* `RequestOptions` while encoding the body, so replaying those
    // headers on a body-less GET sent a request that still promised N bytes.
    // `dart:io` answers that with `HttpException: Content size below specified
    // contentLength` — i.e. the legitimate same-origin redirect this whole
    // interceptor exists to follow failed with an opaque transport error.
    for (final status in const [301, 302, 303]) {
      test('a $status that drops the body drops its entity headers', () async {
        final adapter = _RedirectingAdapter(
          location: 'https://radarr.example.com/api/v3/command/',
          status: status,
        );
        await _guardedDio(
          adapter,
        ).post('/api/v3/command', data: {'name': 'RefreshMovie'});

        expect(adapter.seenHeaders, hasLength(2));
        expect(
          _hasHeader(adapter.seenHeaders.first, 'content-length'),
          isTrue,
          reason: 'Dio stamps it on the original POST — that is the premise',
        );
        expect(adapter.seenMethods.last, 'GET');
        expect(
          _hasHeader(adapter.seenHeaders.last, 'content-length'),
          isFalse,
          reason: 'a GET with no body must not claim a body length',
        );
        expect(
          _hasHeader(adapter.seenHeaders.last, 'content-type'),
          isFalse,
          reason: 'nor a body type',
        );
      });
    }

    test('a 307 keeps the body, and the headers describing it', () async {
      final adapter = _RedirectingAdapter(
        location: 'https://radarr.example.com/api/v3/command/',
        status: 307,
      );
      await _guardedDio(
        adapter,
      ).post('/api/v3/command', data: {'name': 'RefreshMovie'});

      expect(adapter.seenMethods, ['POST', 'POST']);
      expect(_hasHeader(adapter.seenHeaders.last, 'content-length'), isTrue);
    });

    test('passes a normal 200 straight through', () async {
      final adapter = _RedirectingAdapter(location: '', redirectsToServe: 0);
      final response = await _guardedDio(adapter).get('/api/v3/movie');

      expect(response.statusCode, 200);
      expect(adapter.seenUris, hasLength(1));
    });
  });

  group('allowRedirectStatus', () {
    test('accepts 1xx and 2xx', () {
      for (final status in const [100, 200, 201, 204, 299]) {
        expect(allowRedirectStatus(status), isTrue, reason: '$status');
      }
    });

    test('accepts exactly the redirects the interceptor follows', () {
      for (final status in const [301, 302, 303, 307, 308]) {
        expect(allowRedirectStatus(status), isTrue, reason: '$status');
      }
    });

    // Nothing follows these, so letting them through delivered an empty or
    // HTML body to a caller that then read `response.data['results']` and
    // either threw a type error or silently yielded nothing.
    test('rejects the 3xx codes nothing here handles', () {
      for (final status in const [300, 304, 305, 306]) {
        expect(allowRedirectStatus(status), isFalse, reason: '$status');
      }
    });

    test('rejects 4xx, 5xx and a missing status', () {
      expect(allowRedirectStatus(400), isFalse);
      expect(allowRedirectStatus(500), isFalse);
      expect(allowRedirectStatus(null), isFalse);
    });

    test('an unhandled 3xx surfaces as a Dio error, not as data', () async {
      final adapter = _RedirectingAdapter(
        location: 'https://radarr.example.com/api/v3/movie/',
        status: 304,
      );

      await expectLater(
        _guardedDio(adapter).get('/api/v3/movie'),
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.badResponse,
          ),
        ),
      );
    });
  });

  group('a refused redirect keeps its explanation', () {
    // `ServiceDiagnosis` keeps only the enum, so a refusal classified as
    // `unknown` reached the user as "Could not verify the instance" — the one
    // message that names the actual cause was thrown away. `redirected` is its
    // own cause rather than a borrowed `notFound`, because the thing to fix is
    // the proxy, not the address in the form.
    test('classifies as redirected, not unknown or notFound', () async {
      final adapter = _RedirectingAdapter(
        location: 'https://attacker.example.net/collect',
      );

      try {
        await _guardedDio(adapter).get('/api/v3/movie');
        fail('expected the cross-origin redirect to be refused');
      } catch (e) {
        expect(
          classifyConnectionFailure(e),
          ServiceFailureReason.redirected,
          reason: 'the server answered, so this is not "could not verify"',
        );
        expect(connectionFailureDetail(e), contains('different host'));
      }
    });

    // The fallback must not paper over the verdict either: onboarding passes
    // `unreachable` for the clients that report failures as untyped strings.
    test('the verdict survives a caller fallback', () async {
      final adapter = _RedirectingAdapter(
        location: 'https://attacker.example.net/collect',
      );

      try {
        await _guardedDio(adapter).get('/api/v3/movie');
        fail('expected the cross-origin redirect to be refused');
      } catch (e) {
        expect(
          classifyConnectionFailure(
            e,
            fallback: ServiceFailureReason.unreachable,
          ),
          ServiceFailureReason.redirected,
        );
      }
    });

    test('the no-Location and loop refusals share the verdict', () async {
      final noLocation = _RedirectingAdapter(location: '', omitLocation: true);
      try {
        await _guardedDio(noLocation).get('/api/v3/movie');
        fail('expected a refusal');
      } catch (e) {
        expect(connectionFailureDetail(e), contains('Location header'));
        expect(classifyConnectionFailure(e), ServiceFailureReason.redirected);
      }

      final loop = _RedirectingAdapter(
        location: 'https://radarr.example.com/loop',
        redirectsToServe: 100,
      );
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://radarr.example.com',
          followRedirects: false,
          validateStatus: allowRedirectStatus,
        ),
      );
      dio.httpClientAdapter = loop;
      dio.interceptors.add(SameOriginRedirectInterceptor(dio, maxRedirects: 2));

      try {
        await dio.get('/loop');
        fail('expected a refusal');
      } catch (e) {
        expect(connectionFailureDetail(e), contains('more than 2 times'));
        expect(classifyConnectionFailure(e), ServiceFailureReason.redirected);
      }
    });

    // 300/304/305/306 never reach the interceptor — `allowRedirectStatus`
    // rejects them, so Dio throws before the chain runs and there is no
    // `RedirectRefused` to read a verdict off. The status code has to carry it.
    test('a 3xx nobody follows is still a redirect', () async {
      final adapter = _RedirectingAdapter(
        location: 'https://radarr.example.com/api/v3/movie/',
        status: 300,
      );

      try {
        await _guardedDio(adapter).get('/api/v3/movie');
        fail('expected a 300 to surface as an error');
      } catch (e) {
        expect(classifyConnectionFailure(e), ServiceFailureReason.redirected);
        expect(connectionFailureDetail(e), isNull);
      }
    });
  });
}
