import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/features/qbittorrent/data/qbittorrent_client.dart';

/// In-memory [HttpClientAdapter] that returns a canned response and
/// records the last request for assertions.
class _MockAdapter implements HttpClientAdapter {
  _MockAdapter({this.response});

  dynamic response;

  RequestOptions? lastRequest;
  Map<String, dynamic>? lastHeaders;
  dynamic lastData;

  int callCount = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    callCount++;
    lastRequest = options;
    lastHeaders = options.headers;
    lastData = options.data;
    final body = response;
    final bytes = body is String
        ? utf8.encode(body)
        : Uint8List.fromList(utf8.encode(jsonEncode(body)));
    return ResponseBody.fromBytes(
      bytes,
      200,
      headers: {
        Headers.contentTypeHeader: ['text/plain; charset=utf-8'],
      },
    );
  }
}

QbittorrentClient _client(
  HttpClientAdapter adapter, {
  String url = 'http://localhost:8080',
  String? user,
  String? pw,
}) {
  final dio = Dio(BaseOptions(baseUrl: url));
  dio.httpClientAdapter = adapter;
  return QbittorrentClient(url: url, username: user, password: pw, dio: dio);
}

/// Scriptable adapter that returns a different status code per call.
/// Used to verify the retry-on-403 interceptor never loops infinitely.
class _ScriptableAdapter implements HttpClientAdapter {
  _ScriptableAdapter({required this.script});

  final List<int> script;
  int callIndex = 0;
  final List<RequestOptions> requests = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final status = callIndex < script.length ? script[callIndex] : script.last;
    callIndex++;
    final isLogin = options.path == '/api/v2/auth/login';
    final body = isLogin ? (status == 200 ? 'Ok.' : 'Fails.') : 'v4.6.5';
    final bytes = utf8.encode(body);
    return ResponseBody.fromBytes(
      bytes,
      status,
      headers: {
        Headers.contentTypeHeader: ['text/plain; charset=utf-8'],
      },
    );
  }
}

void main() {
  group('QbittorrentClient baseUrl normalization', () {
    test('trims trailing slash', () {
      final c = QbittorrentClient(url: 'http://localhost:8080/');
      expect(c.baseUrl, 'http://localhost:8080');
      c.close();
    });

    test('prepends https:// when scheme missing (secure default)', () {
      final c = QbittorrentClient(url: 'localhost:8080');
      expect(c.baseUrl, 'https://localhost:8080');
      c.close();
    });

    test('honours an explicit http:// scheme', () {
      final c = QbittorrentClient(url: 'http://localhost:8080');
      expect(c.baseUrl, 'http://localhost:8080');
      c.close();
    });

    test('preserves https scheme', () {
      final c = QbittorrentClient(url: 'https://qb.example/');
      expect(c.baseUrl, 'https://qb.example');
      c.close();
    });

    test('returns empty string for blank input', () {
      final c = QbittorrentClient(url: '   ');
      expect(c.baseUrl, '');
      c.close();
    });
  });

  group('QbittorrentClient.hasCredentials', () {
    test('false when no username', () {
      final c = QbittorrentClient(url: 'http://localhost', password: 'p');
      expect(c.hasCredentials, isFalse);
      c.close();
    });

    test('false when empty password', () {
      final c = QbittorrentClient(url: 'http://localhost', username: 'u');
      expect(c.hasCredentials, isFalse);
      c.close();
    });

    test('true when both non-empty', () {
      final c = QbittorrentClient(
        url: 'http://localhost',
        username: 'admin',
        password: 'adminadmin',
      );
      expect(c.hasCredentials, isTrue);
      c.close();
    });
  });

  group('QbittorrentClient.authenticate', () {
    test('returns true when no credentials (no auth required)', () async {
      final c = QbittorrentClient(url: 'http://localhost');
      expect(await c.authenticate(), isTrue);
      c.close();
    });

    test('returns true on Ok. response', () async {
      final adapter = _MockAdapter(response: 'Ok.');
      final c = _client(adapter, user: 'admin', pw: 'adminadmin');
      expect(await c.authenticate(), isTrue);
      expect(adapter.lastRequest?.path, '/api/v2/auth/login');
      c.close();
    });

    test('returns false on Fails. response', () async {
      final adapter = _MockAdapter(response: 'Fails.');
      final c = _client(adapter, user: 'admin', pw: 'wrong');
      expect(await c.authenticate(), isFalse);
      c.close();
    });

    test('shares inflight future across concurrent calls', () async {
      final adapter = _MockAdapter(response: 'Ok.');
      final c = _client(adapter, user: 'admin', pw: 'adminadmin');
      final results = await Future.wait([
        c.authenticate(),
        c.authenticate(),
        c.authenticate(),
      ]);
      expect(results, [true, true, true]);
      expect(
        adapter.callCount,
        1,
        reason: 'concurrent authenticate() calls should dedupe',
      );
      c.close();
    });
  });

  group('QbittorrentClient.getVersion', () {
    test('returns trimmed version string', () async {
      final adapter = _MockAdapter(response: 'v4.6.5');
      final c = _client(adapter);
      expect(await c.getVersion(), 'v4.6.5');
      c.close();
    });

    test('trims whitespace around response', () async {
      final adapter = _MockAdapter(response: '  v5.0.4\n');
      final c = _client(adapter);
      expect(await c.getVersion(), 'v5.0.4');
      c.close();
    });
  });

  group('QbittorrentClient 403 retry interceptor', () {
    test(
      'retries exactly once on 403 then surfaces error if still failing',
      () async {
        // 1st call: data fetch → 403.
        // 2nd call: login (forced by interceptor) → 200 Ok.
        // 3rd call: data retry → 403 → surfaced.
        // No further calls — the interceptor must stop after one retry.
        final adapter = _ScriptableAdapter(script: [403, 200, 403, 403, 403]);
        final c = _client(adapter, user: 'admin', pw: 'adminadmin');

        await expectLater(c.getVersion(), throwsA(isA<DioException>()));

        final dataCalls = adapter.requests
            .where((r) => r.path == '/api/v2/app/version')
            .toList();
        expect(
          dataCalls.length,
          2,
          reason: 'interceptor should retry the data call exactly once',
        );
        final loginCalls = adapter.requests
            .where((r) => r.path == '/api/v2/auth/login')
            .toList();
        expect(
          loginCalls.length,
          1,
          reason: 'interceptor should not loop on auth retries',
        );
        expect(
          adapter.callIndex,
          3,
          reason: 'no further network activity after the single retry',
        );
        c.close();
      },
    );

    test('retries once on 403, succeeds when retry returns 200', () async {
      // 1st call: data → 403; 2nd call: login → 200; 3rd call: data → 200.
      final adapter = _ScriptableAdapter(script: [403, 200, 200]);
      final c = _client(adapter, user: 'admin', pw: 'adminadmin');

      final version = await c.getVersion();
      expect(version, 'v4.6.5');
      expect(adapter.callIndex, 3);
      c.close();
    });

    test('does not retry on 403 when no credentials are configured', () async {
      // Without credentials authenticate() short-circuits to true, so
      // the interceptor must not even attempt a retry.
      final adapter = _ScriptableAdapter(script: [403, 200, 200]);
      final c = _client(adapter);

      await expectLater(c.getVersion(), throwsA(isA<DioException>()));
      expect(adapter.callIndex, 1);
      c.close();
    });

    test('does not loop when login itself returns 403', () async {
      // 1st call: data → 403; 2nd call: login → 403.
      // The interceptor should call login once, see failure, and surface
      // the original 403 without retrying the data call.
      final adapter = _ScriptableAdapter(script: [403, 403, 403, 403]);
      final c = _client(adapter, user: 'admin', pw: 'wrong');

      await expectLater(c.getVersion(), throwsA(isA<DioException>()));
      final dataCalls = adapter.requests
          .where((r) => r.path == '/api/v2/app/version')
          .toList();
      final loginCalls = adapter.requests
          .where((r) => r.path == '/api/v2/auth/login')
          .toList();
      expect(
        dataCalls.length,
        1,
        reason: 'must not retry the data call when login itself fails',
      );
      expect(loginCalls.length, 1);
      c.close();
    });
  });
}
