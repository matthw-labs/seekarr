import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seekarr/core/network/redirect_guard.dart';

/// Adapter that answers a redirect for the first N requests, then 200, and
/// records every (uri, headers) pair it saw.
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
      expect(adapter.seenHeaders.last['X-Api-Key'], 'secret-key');
    });

    test('passes a normal 200 straight through', () async {
      final adapter = _RedirectingAdapter(location: '', redirectsToServe: 0);
      final response = await _guardedDio(adapter).get('/api/v3/movie');

      expect(response.statusCode, 200);
      expect(adapter.seenUris, hasLength(1));
    });
  });
}
