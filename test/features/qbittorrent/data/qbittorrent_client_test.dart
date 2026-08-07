import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client.dart';

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
    final body = isLogin
        ? (status == 200
              ? 'Ok.'
              : status == 204
              ? '' // qBittorrent 5.1+ answers 204 with an empty body.
              : 'Fails.')
        : 'v4.6.5';
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

/// Answers the login with `200 Fails.` — qBittorrent ≤ 5.0's way of saying the
/// credentials are wrong — and 200 for anything else.
class _LoginFailsAdapter implements HttpClientAdapter {
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
    final isLogin = options.path == '/api/v2/auth/login';
    return ResponseBody.fromBytes(
      utf8.encode(isLogin ? 'Fails.' : 'v4.6.5'),
      200,
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

    // This client used to prepend `http://`. It now shares
    // `UrlUtils.normalizeBaseUrl` with every other client, whose default is
    // `https://` so an omitted scheme can never downgrade a WebUI password to
    // cleartext. Configurations saved before there was a validator stored the
    // scheme-less form verbatim; those are rewritten to `http://` by the
    // one-shot settings migration, not by guessing here.
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

    // The landing zone for the migrated legacy configs: once a stored URL says
    // `http://`, this client must carry it through untouched, or every
    // construction would undo the migration and take the TLS handshake failure
    // all over again.
    test('never upgrades an explicit http:// address', () {
      for (final url in const [
        'http://192.168.1.5:8080',
        'http://qb.lan:8080/',
        'http://proxy.example.com/qbittorrent/',
      ]) {
        final c = QbittorrentClient(url: url);
        expect(c.baseUrl, startsWith('http://'), reason: url);
        expect(c.baseUrl, isNot(contains('https://')), reason: url);
        c.close();
      }
    });

    test('preserves https scheme', () {
      final c = QbittorrentClient(url: 'https://qb.example/');
      expect(c.baseUrl, 'https://qb.example');
      c.close();
    });

    test('preserves a reverse-proxy base path', () {
      final c = QbittorrentClient(url: 'https://proxy.example.com/qb/');
      expect(c.baseUrl, 'https://proxy.example.com/qb');
      c.close();
    });

    test('returns empty string for blank input', () {
      final c = QbittorrentClient(url: '   ');
      expect(c.baseUrl, '');
      c.close();
    });

    // The WebUI rejects a request whose Referer/Origin does not match the host
    // it is served from, so these have to be the *normalised* URL — the raw
    // scheme-less string would produce `Referer: localhost:8080`.
    test('sends Referer and Origin as the normalised base URL', () async {
      final adapter = _MockAdapter(response: 'v4.6.5');
      final dio = Dio(BaseOptions(baseUrl: 'https://qb.example:8080'));
      dio.httpClientAdapter = adapter;
      final c = QbittorrentClient(url: 'qb.example:8080/', dio: dio);

      await c.getVersion();

      expect(c.baseUrl, 'https://qb.example:8080');
      expect(adapter.lastHeaders?['Referer'], 'https://qb.example:8080');
      expect(adapter.lastHeaders?['Origin'], 'https://qb.example:8080');
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

    test('returns true on 204 with empty body (qBittorrent 5.1+)', () async {
      // Observed against qBittorrent v5.2.3: a successful login answers
      // 204 No Content and sets the SID cookie — there is no "Ok." body.
      final adapter = _ScriptableAdapter(script: [204]);
      final c = _client(adapter, user: 'admin', pw: 'adminadmin');
      expect(await c.authenticate(), isTrue);
      c.close();
    });

    test('returns false on 401 (qBittorrent 5.1+ bad credentials)', () async {
      final adapter = _ScriptableAdapter(script: [401]);
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
        // 1st call: upfront login → 200 Ok.
        // 2nd call: data fetch → 403 (session rejected).
        // 3rd call: login (forced by interceptor) → 200 Ok.
        // 4th call: data retry → 403 → surfaced.
        // No further calls — the interceptor must stop after one retry.
        final adapter = _ScriptableAdapter(script: [200, 403, 200, 403, 403]);
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
          2,
          reason: 'upfront login plus one interceptor re-auth, and no more',
        );
        expect(
          adapter.callIndex,
          4,
          reason: 'no further network activity after the single retry',
        );
        c.close();
      },
    );

    test('retries once on 403, succeeds when retry returns 200', () async {
      // login → 200; data → 403; re-login → 200; data retry → 200.
      final adapter = _ScriptableAdapter(script: [200, 403, 200, 200]);
      final c = _client(adapter, user: 'admin', pw: 'adminadmin');

      final version = await c.getVersion();
      expect(version, 'v4.6.5');
      expect(adapter.callIndex, 4);
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

    // The QA finding: a wrong password cost three round trips (login → data 403
    // → re-login) before the failure surfaced, and on a slow link that ran past
    // the 8s verify budget and was reported as a timeout, i.e. "check the
    // address". An unambiguous rejection now fails immediately and carries
    // `unauthorized` so the UI can name the real cause.
    group('credential rejection fails fast', () {
      test('200 Fails. stops before the data call', () async {
        // Login → 200 "Fails.". Nothing else should be attempted.
        final adapter = _ScriptableAdapter(script: [200, 200, 200]);
        // Force the login to report failure while keeping a 200 status.
        final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080'));
        dio.httpClientAdapter = _LoginFailsAdapter();
        final c = QbittorrentClient(
          url: 'http://localhost:8080',
          username: 'admin',
          password: 'wrong',
          dio: dio,
        );

        await expectLater(
          c.getVersion(),
          throwsA(
            isA<QbittorrentException>().having(
              (e) => e.reason,
              'reason',
              ServiceFailureReason.unauthorized,
            ),
          ),
        );
        expect(adapter.callIndex, 0);
        c.close();
      });

      test('401 stops before the data call', () async {
        final adapter = _ScriptableAdapter(script: [401, 200, 200]);
        final c = _client(adapter, user: 'admin', pw: 'wrong');

        await expectLater(
          c.getVersion(),
          throwsA(
            isA<QbittorrentException>().having(
              (e) => e.reason,
              'reason',
              ServiceFailureReason.unauthorized,
            ),
          ),
        );
        final dataCalls = adapter.requests
            .where((r) => r.path == '/api/v2/app/version')
            .toList();
        expect(dataCalls, isEmpty, reason: 'no point asking after a 401');
        expect(adapter.callIndex, 1, reason: 'one login attempt, then stop');
        c.close();
      });
    });

    test('does not loop when login itself returns 403', () async {
      // Every call → 403: the upfront login fails, the data call fails, and
      // the interceptor's re-auth fails too. The original 403 is surfaced
      // without ever retrying the data call.
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
      expect(loginCalls.length, 2, reason: 'upfront login plus one re-auth');
      c.close();
    });
  });
}
