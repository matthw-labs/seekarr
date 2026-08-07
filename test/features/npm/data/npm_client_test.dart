import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/network/connection_failure.dart';
import 'package:seekarr/core/network/redirect_guard.dart';
import 'package:seekarr/features/npm/data/npm_client.dart';
import 'package:seekarr/features/npm/domain/models/npm_models.dart';

import '../../../test_helpers/scripted_http_adapter.dart';

Dio _dio(ScriptedHttpAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://npm.local:81',
      followRedirects: false,
      validateStatus: allowRedirectStatus,
    ),
  );
  dio.httpClientAdapter = adapter;
  return dio;
}

const _health = ScriptedReply(
  body: {
    'status': 'OK',
    'setup': true,
    'version': {'major': 2, 'minor': 15, 'revision': 1},
  },
);

const _token = ScriptedReply(
  body: {
    'token': 'eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxIn0.c2lnbmF0dXJl',
    'expires': '2099-01-01T00:00:00.000Z',
  },
);

/// NPM's failure envelope. It never returns 401 for anything.
ScriptedReply _error(int status, String message) => ScriptedReply(
  statusCode: status,
  body: {
    'error': {'code': status, 'message': message},
  },
);

NpmClient _client(ScriptedHttpAdapter adapter, {bool credentials = true}) {
  return NpmClient(
    url: 'https://npm.local:81',
    identity: credentials ? 'me@example.com' : null,
    secret: credentials ? 'hunter2' : null,
    dio: _dio(adapter),
  );
}

void main() {
  group('transport contract', () {
    test('installs the redirect guard and a pinned adapter when asked', () {
      final plain = NpmClient(url: 'https://npm.local:81');
      final pinned = NpmClient(
        url: 'https://npm.local:81',
        certFingerprint: 'ab12cd34',
      );
      addTearDown(plain.close);
      addTearDown(pinned.close);

      // The bearer token *is* the account — no scoping, no revocation — so a
      // cross-origin redirect must never carry it.
      expect(
        plain.dio.interceptors.whereType<SameOriginRedirectInterceptor>(),
        isNotEmpty,
      );
      expect(plain.dio.options.followRedirects, isFalse);
      expect(pinned.dio.httpClientAdapter, isNot(plain.dio.httpClientAdapter));
    });
  });

  group('health probe', () {
    test('reads the version from GET /api/ with the trailing slash', () async {
      final adapter = ScriptedHttpAdapter([_health]);
      final info = await _client(adapter).serverInfo();

      expect(info.version, '2.15.1');
      expect(info.isHealthy, isTrue);
      // `GET /api` without the slash is a 302; asking for `/api/` skips it.
      expect(adapter.lastRequest.uri.path, '/api/');
      // Unauthenticated — no login round trip is spent on reachability.
      expect(adapter.callCount, 1);
      expect(adapter.lastRequest.headers.containsKey('Authorization'), isFalse);
    });

    test('refuses a 200 that is not the NPM API', () async {
      // The admin port answers almost any path 200 with its single-page app, so
      // a status-code-only health check would report "connected" against a
      // wrong port or an entirely different web server.
      final adapter = ScriptedHttpAdapter([
        const ScriptedReply(body: {'hello': 'world'}),
      ]);

      await expectLater(
        _client(adapter).serverInfo(),
        throwsA(
          isA<NpmException>().having(
            (e) => e.reason,
            'reason',
            ServiceFailureReason.notFound,
          ),
        ),
      );
    });

    test('flags versions that still ship the default administrator', () {
      expect(
        NpmServerInfo.fromJson(const {
          'status': 'OK',
          'version': {'major': 2, 'minor': 12, 'revision': 6},
        }).hasDefaultAdminRisk,
        isTrue,
      );
      expect(
        NpmServerInfo.fromJson(const {
          'status': 'OK',
          'version': {'major': 2, 'minor': 13, 'revision': 0},
        }).hasDefaultAdminRisk,
        isFalse,
      );
    });
  });

  group('login', () {
    test('posts identity and secret, and never an expiry', () async {
      final adapter = ScriptedHttpAdapter([_health, _token, _health]);
      final client = _client(adapter);

      await client.testConnection();

      final login = adapter.requests[1];
      expect(login.uri.path, '/api/tokens');
      final body = login.body as Map<String, dynamic>;
      expect(body['identity'], 'me@example.com');
      expect(body['secret'], 'hunter2');
      // The login schema is `additionalProperties: false`, so an `expiry` field
      // is rejected outright rather than ignored.
      expect(body.containsKey('expiry'), isFalse);
      // The password must never reach the URL.
      expect(login.uri.toString(), isNot(contains('hunter2')));
    });

    test('a wrong password is a 400, and it sticks', () async {
      final adapter = ScriptedHttpAdapter([
        _health,
        _error(400, 'Invalid email or password'),
      ]);
      final client = _client(adapter);

      await expectLater(
        client.testConnection(),
        throwsA(
          isA<NpmException>().having(
            (e) => e.reason,
            'reason',
            ServiceFailureReason.unauthorized,
          ),
        ),
      );
      final afterFirst = adapter.callCount;

      // NPM has no rate limiting at all, so nothing on the server stops this
      // client from hammering the user's own account. The back-off is ours.
      await expectLater(client.proxyHosts(), throwsA(isA<NpmException>()));
      expect(adapter.callCount, afterFirst);
    });

    test(
      'two-factor is reported as such rather than as a broken login',
      () async {
        // NPM answers 200 with a *different shape* when TOTP is on; reading
        // `token` blindly yields null and an incomprehensible error.
        final adapter = ScriptedHttpAdapter([
          _health,
          const ScriptedReply(
            body: {'requires_2fa': true, 'challenge_token': 'eyJa.eyJb.c2ln'},
          ),
        ]);

        await expectLater(
          _client(adapter).testConnection(),
          throwsA(
            isA<NpmException>().having(
              (e) => e.message,
              'message',
              contains('two-factor'),
            ),
          ),
        );
      },
    );

    test('says what is missing when no credentials are configured', () async {
      final adapter = ScriptedHttpAdapter([_health]);
      final client = _client(adapter, credentials: false);

      // Reachability still works without a credential…
      await client.serverInfo();
      // …but anything authenticated must say so plainly.
      await expectLater(
        client.proxyHosts(),
        throwsA(
          isA<NpmException>().having(
            (e) => e.reason,
            'reason',
            ServiceFailureReason.unauthorized,
          ),
        ),
      );
    });
  });

  group('authenticated requests', () {
    test('sends the token as a Bearer header, never in the query', () async {
      final adapter = ScriptedHttpAdapter([
        _token,
        const ScriptedReply(body: []),
      ]);
      final client = _client(adapter);

      await client.proxyHosts();

      final call = adapter.requests[1];
      expect(call.headers['Authorization'], startsWith('Bearer eyJ'));
      expect(call.uri.query, isNot(contains('eyJ')));
      expect(
        call.uri.queryParameters['expand'],
        'owner,access_list,certificate',
      );
      // `items` is deliberately absent: expanding an access list returns the
      // basic-auth credentials of the sites it protects.
      expect(call.uri.queryParameters['expand'], isNot(contains('items')));
    });

    test('an expired token triggers exactly one re-login', () async {
      final adapter = ScriptedHttpAdapter([
        _token,
        _error(400, 'Token has expired'),
        _token,
        const ScriptedReply(body: []),
      ]);
      final client = _client(adapter);

      await client.proxyHosts();

      expect(adapter.callCount, 4);
      expect(adapter.requests[2].uri.path, '/api/tokens');
    });

    test('a persistent expiry fails instead of looping', () async {
      final adapter = ScriptedHttpAdapter([
        _token,
        _error(400, 'Token has expired'),
        _token,
        _error(400, 'Token has expired'),
      ]);

      await expectLater(
        _client(adapter).proxyHosts(),
        throwsA(isA<NpmException>()),
      );
      expect(adapter.callCount, 4, reason: 'one retry, not a loop');
    });

    test('403 reads as a permissions problem, not a broken server', () async {
      final adapter = ScriptedHttpAdapter([
        _token,
        _error(403, 'Permission Denied'),
      ]);

      await expectLater(
        _client(adapter).proxyHosts(),
        throwsA(
          isA<NpmException>()
              .having(
                (e) => e.reason,
                'reason',
                ServiceFailureReason.unauthorized,
              )
              .having((e) => e.message, 'message', contains('view-only')),
        ),
      );
    });

    test('a 500 drops the token so the next call re-mints', () async {
      // A malformed token is a 500 in NPM, not a 401 — so a token gone bad
      // would otherwise look like a permanent server outage.
      final adapter = ScriptedHttpAdapter([
        _token,
        _error(500, 'Internal Error'),
        _token,
        const ScriptedReply(body: []),
      ]);
      final client = _client(adapter);

      await expectLater(client.proxyHosts(), throwsA(isA<NpmException>()));
      await client.proxyHosts();

      expect(adapter.requests[2].uri.path, '/api/tokens');
    });
  });

  group('writes', () {
    test('a forward change sends only the three changed keys', () async {
      // NPM's PUT body is `additionalProperties: false`, so round-tripping an
      // object read from GET is rejected outright — and `meta` or
      // `certificate_id` slipping in would wipe TLS settings or trigger a real
      // Let's Encrypt request.
      final adapter = ScriptedHttpAdapter([
        _token,
        const ScriptedReply(body: {'id': 3}),
        const ScriptedReply(body: {'id': 3, 'domain_names': []}),
      ]);
      final client = _client(adapter);

      await client.updateProxyForward(
        3,
        scheme: 'HTTP',
        host: ' backend.local ',
        port: 8080,
      );

      final put = adapter.requests[1];
      expect(put.method, 'PUT');
      final body = put.body as Map<String, dynamic>;
      expect(body.keys.toSet(), {
        'forward_scheme',
        'forward_host',
        'forward_port',
      });
      expect(body['forward_scheme'], 'http');
      expect(body['forward_host'], 'backend.local');
    });

    test('rejects a forward target that cannot be valid', () async {
      final client = _client(ScriptedHttpAdapter([_token]));

      await expectLater(
        client.updateProxyForward(1, scheme: 'ftp', host: 'a', port: 80),
        throwsA(isA<NpmException>()),
      );
      await expectLater(
        client.updateProxyForward(1, scheme: 'http', host: '  ', port: 80),
        throwsA(isA<NpmException>()),
      );
      await expectLater(
        client.updateProxyForward(1, scheme: 'http', host: 'a', port: 0),
        throwsA(isA<NpmException>()),
      );
    });

    test(
      'enable re-reads the host rather than trusting the bare true',
      () async {
        // NPM answers `true` as soon as the row is written; `nginx -t` runs
        // afterwards and only sets meta.nginx_online false when it fails.
        final adapter = ScriptedHttpAdapter([
          _token,
          const ScriptedReply(body: true),
          const ScriptedReply(
            body: {
              'id': 3,
              'domain_names': ['app.example.com'],
              'enabled': true,
              'meta': {'nginx_online': false, 'nginx_err': 'bad config'},
            },
          ),
        ]);

        final host = await _client(adapter).setProxyHostEnabled(3, true);

        expect(adapter.requests[1].uri.path, '/api/nginx/proxy-hosts/3/enable');
        expect(host?.hasConfigError, isTrue);
        expect(host?.errorText, 'bad config');
      },
    );
  });

  group('secrets never reach a message', () {
    test('redactJwt masks anything token-shaped', () {
      const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abc-DEF_123';
      expect(redactJwt('failed with $jwt here'), 'failed with *** here');
    });

    test('the exception string carries no credential', () async {
      final adapter = ScriptedHttpAdapter([
        _health,
        _error(400, 'Invalid email or password'),
      ]);

      try {
        await _client(adapter).testConnection();
        fail('expected a refusal');
      } on NpmException catch (e) {
        // `AppErrorState` renders `toString()` verbatim.
        expect(e.toString(), isNot(contains('hunter2')));
        expect(e.toString(), isNot(contains('me@example.com')));
        expect(e.toString(), isNot(contains('eyJ')));
      }
    });
  });

  group('model parsing', () {
    test('an absent nginx_online reads as loaded, not as broken', () {
      final host = NpmProxyHost.fromJson(const {
        'id': 1,
        'domain_names': ['app.example.com'],
        'enabled': true,
      });
      expect(host.configLoaded, isTrue);
      expect(host.hasConfigError, isFalse);
      expect(host.primaryDomain, 'app.example.com');
    });

    test('a disabled host is never a config error', () {
      final host = NpmProxyHost.fromJson(const {
        'id': 1,
        'enabled': false,
        'meta': {'nginx_online': false},
      });
      expect(host.hasConfigError, isFalse);
    });

    test('certificates expose expiry without ever modelling meta', () {
      final cert = NpmCertificate.fromJson({
        'id': 2,
        'provider': 'letsencrypt',
        'nice_name': 'example.com',
        'domain_names': ['example.com'],
        'expires_on': DateTime.now()
            .add(const Duration(days: 10))
            .toIso8601String(),
        // Private key material for uploaded certificates lives here; nothing
        // reads it, so nothing can cache or export it.
        'meta': {'certificate_key': 'SUPER SECRET'},
      });

      expect(cert.isLetsEncrypt, isTrue);
      expect(cert.isExpiringSoon(DateTime.now()), isTrue);
      expect(cert.toString(), isNot(contains('SUPER SECRET')));
    });
  });
}
