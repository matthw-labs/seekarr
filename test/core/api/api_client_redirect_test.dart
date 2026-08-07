import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/api/api_client.dart';
import 'package:seekarr/core/network/connection_failure.dart';

/// Answers the first request with [status] (and a `Location`, unless
/// [location] is empty) and everything after it with 200 + JSON, recording
/// what each request looked like on the wire.
///
/// `CapturingHttpAdapter` cannot express a `Location` header, which is the
/// whole point here, so this is the redirect-shaped sibling of it.
class _RedirectThenOkAdapter implements HttpClientAdapter {
  _RedirectThenOkAdapter({required this.status, this.location = ''});

  final int status;
  final String location;

  final List<Uri> uris = [];
  final List<String> methods = [];
  final List<Map<String, dynamic>> headers = [];
  bool _redirectServed = false;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    uris.add(options.uri);
    methods.add(options.method);
    headers.add(Map<String, dynamic>.from(options.headers));

    if (!_redirectServed) {
      _redirectServed = true;
      return ResponseBody.fromBytes(
        Uint8List(0),
        status,
        headers: {
          if (location.isNotEmpty) 'location': [location],
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

bool _has(Map<String, dynamic> headers, String name) =>
    headers.keys.any((key) => key.toLowerCase() == name.toLowerCase());

ApiClient _clientOn(HttpClientAdapter adapter) {
  final client = ApiClient(baseUrl: 'https://radarr.lan:7878', apiKey: 'k');
  client.dio.httpClientAdapter = adapter;
  return client;
}

void main() {
  group('ApiClient redirect handling', () {
    // The wiring under test is `followRedirects: false` +
    // `allowRedirectStatus` + `SameOriginRedirectInterceptor` together, which
    // only this class assembles. Radarr behind a proxy that normalises a
    // trailing slash answers `POST /api/v3/command` with a 302, and the replay
    // used to inherit the `content-length` Dio had stamped on the original
    // request — a GET promising a body it no longer had, which `dart:io`
    // refuses with `HttpException: Content size below specified contentLength`.
    test(
      'follows a same-origin 302 on a POST without a stale length',
      () async {
        final adapter = _RedirectThenOkAdapter(
          status: 302,
          location: 'https://radarr.lan:7878/api/v3/command/',
        );
        final client = _clientOn(adapter);

        final response = await client.post(
          '/api/v3/command',
          data: {'name': 'RefreshMovie'},
        );

        expect(response.statusCode, 200);
        expect(response.data, {'ok': true});
        expect(adapter.methods, ['POST', 'GET']);
        expect(_has(adapter.headers.first, 'content-length'), isTrue);
        expect(_has(adapter.headers.last, 'content-length'), isFalse);
        expect(adapter.headers.last['X-Api-Key'], 'k');
        client.close();
      },
    );

    test('a 304 fails instead of arriving as an empty success', () async {
      // Nothing in `lib/` sends a conditional validator, so a 304 here means a
      // non-conforming proxy — but delivering it as a 200-shaped success left
      // callers doing `response.data['results'] as List` on an empty body.
      final adapter = _RedirectThenOkAdapter(status: 304);
      final client = _clientOn(adapter);

      await expectLater(
        client.get('/api/v3/movie'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'statusCode',
            304,
          ),
        ),
      );
      expect(adapter.uris, hasLength(1));
      client.close();
    });

    test('refuses a cross-origin redirect and says why', () async {
      final adapter = _RedirectThenOkAdapter(
        status: 302,
        location: 'https://attacker.example.net/collect',
      );
      final client = _clientOn(adapter);

      try {
        await client.get('/api/v3/movie');
        fail('expected the cross-origin redirect to be refused');
      } catch (e) {
        // A refused redirect has its own reason: the address may be perfectly
        // correct and the fix lives on the proxy, so it must not borrow
        // notFound's "check the address" copy.
        expect(classifyConnectionFailure(e), ServiceFailureReason.redirected);
        expect(connectionFailureDetail(e), contains('different host'));
      }

      // The API key never left the configured origin.
      expect(adapter.uris, hasLength(1));
      expect(adapter.uris.single.host, 'radarr.lan');
      client.close();
    });
  });
}
