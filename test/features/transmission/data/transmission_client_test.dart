import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/network/redirect_guard.dart';
import 'package:cupola/features/transmission/data/transmission_client.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';

import '../../../test_helpers/scripted_http_adapter.dart';

/// A Dio shaped exactly like the one [TransmissionClient] builds for itself, so
/// an injected transport still exercises the redirect/status contract the real
/// one runs under.
Dio _dio(
  ScriptedHttpAdapter adapter, {
  String base = 'https://nas.local:9091',
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: base,
      followRedirects: false,
      validateStatus: allowRedirectStatus,
    ),
  );
  dio.httpClientAdapter = adapter;
  return dio;
}

ScriptedReply _ok(Map<String, dynamic> arguments) =>
    ScriptedReply(body: {'result': 'success', 'arguments': arguments});

void main() {
  group('resolveRpcPath', () {
    // The daemon's `rpc-url` setting and any reverse proxy in front of it both
    // move this endpoint, so a hardcoded path is the most common reason a
    // working Transmission looks unreachable.
    test('appends the default path when the URL carries none', () {
      expect(
        TransmissionClient.resolveRpcPath('https://nas.local:9091'),
        '/transmission/rpc',
      );
      expect(
        TransmissionClient.resolveRpcPath('nas.local:9091/'),
        '/transmission/rpc',
      );
    });

    test('appends /rpc to a relocated rpc-url', () {
      expect(
        TransmissionClient.resolveRpcPath('https://nas.local/tr'),
        '/tr/rpc',
      );
      expect(
        TransmissionClient.resolveRpcPath('https://nas.local/tr/'),
        '/tr/rpc',
      );
    });

    test('uses a full endpoint verbatim', () {
      expect(
        TransmissionClient.resolveRpcPath('https://nas.local/tr/rpc'),
        '/tr/rpc',
      );
    });
  });

  group('transport contract', () {
    test('installs the redirect guard and refuses to auto-follow', () {
      final client = TransmissionClient(url: 'https://nas.local:9091');
      addTearDown(client.close);

      // `dart:io` copies `Authorization` on a redirect to a *parent* domain, so
      // without this guard `transmission.homelab.net` → `homelab.net` hands the
      // Basic password to the apex host.
      expect(
        client.dio.interceptors.whereType<SameOriginRedirectInterceptor>(),
        isNotEmpty,
      );
      expect(client.dio.options.followRedirects, isFalse);
    });

    test('installs a pinned adapter only when a fingerprint is given', () {
      final unpinned = TransmissionClient(url: 'https://nas.local:9091');
      final pinned = TransmissionClient(
        url: 'https://nas.local:9091',
        certFingerprint: 'ab12cd34',
      );
      addTearDown(unpinned.close);
      addTearDown(pinned.close);

      expect(
        pinned.dio.httpClientAdapter,
        isNot(unpinned.dio.httpClientAdapter),
      );
    });
  });

  group('authentication', () {
    test(
      'sends HTTP Basic credentials in the header, never in the URL',
      () async {
        final adapter = ScriptedHttpAdapter([
          _ok({'version': '4.0.6', 'rpc-version': 17}),
        ]);
        final client = TransmissionClient(
          url: 'https://nas.local:9091',
          username: 'matt',
          password: 'hunter2',
          dio: _dio(adapter),
        );

        await client.session();

        final auth = adapter.lastRequest.headers['Authorization'] as String;
        expect(auth, 'Basic ${base64Encode(utf8.encode('matt:hunter2'))}');
        expect(adapter.lastRequest.uri.toString(), isNot(contains('hunter2')));
        expect(adapter.lastRequest.uri.userInfo, isEmpty);
      },
    );

    test('sends no Authorization header when there is no username', () async {
      final adapter = ScriptedHttpAdapter([
        _ok({'version': '4.0.6'}),
      ]);
      final client = TransmissionClient(
        url: 'https://nas.local:9091',
        dio: _dio(adapter),
      );

      await client.session();

      expect(adapter.lastRequest.headers.containsKey('Authorization'), isFalse);
    });

    test('a 401 is terminal and is not retried on the next call', () async {
      // Transmission's anti-brute-force guard flips to a 403 lockout that
      // survives until the daemon restarts, so a polling client that re-sends a
      // wrong password locks the user out of their own box.
      final adapter = ScriptedHttpAdapter([
        const ScriptedReply(statusCode: 401),
      ]);
      final client = TransmissionClient(
        url: 'https://nas.local:9091',
        username: 'matt',
        password: 'wrong',
        dio: _dio(adapter),
      );

      await expectLater(
        client.session(),
        throwsA(
          isA<TransmissionException>().having(
            (e) => e.reason,
            'reason',
            ServiceFailureReason.unauthorized,
          ),
        ),
      );
      final afterFirst = adapter.callCount;

      await expectLater(
        client.session(),
        throwsA(isA<TransmissionException>()),
      );
      expect(
        adapter.callCount,
        afterFirst,
        reason: 'a rejected credential must not reach the network again',
      );
    });

    test(
      '403 and 421 are reported as configuration, not bad credentials',
      () async {
        for (final status in [403, 421]) {
          final client = TransmissionClient(
            url: 'https://nas.local:9091',
            username: 'matt',
            password: 'hunter2',
            dio: _dio(ScriptedHttpAdapter([ScriptedReply(statusCode: status)])),
          );
          await expectLater(
            client.session(),
            throwsA(
              isA<TransmissionException>().having(
                (e) => e.message,
                'message',
                contains('whitelist'),
              ),
            ),
          );
        }
      },
    );
  });

  group('CSRF session-id handshake', () {
    test('replays once with the id from the 409 response headers', () async {
      final adapter = ScriptedHttpAdapter([
        const ScriptedReply(
          statusCode: 409,
          headers: {
            'x-transmission-session-id': ['abc123'],
          },
        ),
        _ok({'version': '4.0.6', 'rpc-version': 17}),
      ]);
      final client = TransmissionClient(
        url: 'https://nas.local:9091',
        dio: _dio(adapter),
      );

      final session = await client.session();

      expect(session.version, '4.0.6');
      expect(adapter.callCount, 2);
      expect(
        adapter.requests.first.headers.containsKey(
          TransmissionClient.sessionIdHeader,
        ),
        isFalse,
      );
      expect(
        adapter.requests[1].headers[TransmissionClient.sessionIdHeader],
        'abc123',
      );
    });

    test('reuses the learned id on the next call', () async {
      final adapter = ScriptedHttpAdapter([
        const ScriptedReply(
          statusCode: 409,
          headers: {
            'x-transmission-session-id': ['abc123'],
          },
        ),
        _ok({'version': '4.0.6'}),
      ]);
      final client = TransmissionClient(
        url: 'https://nas.local:9091',
        dio: _dio(adapter),
      );

      await client.session();
      await client.session();

      expect(adapter.callCount, 3);
      expect(
        adapter.requests.last.headers[TransmissionClient.sessionIdHeader],
        'abc123',
      );
    });

    test('a second 409 fails instead of looping forever', () async {
      // The id rotates hourly with **no grace window**, so this path is hit in
      // normal operation — and retrying without a usable id is the classic way
      // clients against this API hang.
      final adapter = ScriptedHttpAdapter([
        const ScriptedReply(
          statusCode: 409,
          headers: {
            'x-transmission-session-id': ['abc123'],
          },
        ),
        const ScriptedReply(
          statusCode: 409,
          headers: {
            'x-transmission-session-id': ['def456'],
          },
        ),
      ]);
      final client = TransmissionClient(
        url: 'https://nas.local:9091',
        dio: _dio(adapter),
      );

      await expectLater(
        client.session(),
        throwsA(isA<TransmissionException>()),
      );
      expect(
        adapter.callCount,
        2,
        reason: 'exactly one replay, never recursive',
      );
    });

    test(
      'a 409 with no session-id header fails rather than replaying',
      () async {
        final adapter = ScriptedHttpAdapter([
          const ScriptedReply(statusCode: 409),
        ]);
        final client = TransmissionClient(
          url: 'https://nas.local:9091',
          dio: _dio(adapter),
        );

        await expectLater(
          client.session(),
          throwsA(
            isA<TransmissionException>().having(
              (e) => e.message,
              'message',
              contains('reverse proxy'),
            ),
          ),
        );
        expect(adapter.callCount, 1);
      },
    );
  });

  group('the RPC envelope', () {
    test('HTTP 200 with a non-success result is a failure', () async {
      final adapter = ScriptedHttpAdapter([
        const ScriptedReply(body: {'result': 'invalid argument'}),
      ]);
      final client = TransmissionClient(
        url: 'https://nas.local:9091',
        dio: _dio(adapter),
      );

      await expectLater(
        client.session(),
        throwsA(
          isA<TransmissionException>().having(
            (e) => e.message,
            'message',
            'invalid argument',
          ),
        ),
      );
    });

    test('HTML on a 200 is reported as "the API is not here"', () async {
      final adapter = ScriptedHttpAdapter([
        const ScriptedReply(body: '<html>Transmission Web UI</html>'),
      ]);
      final client = TransmissionClient(
        url: 'https://nas.local:9091',
        dio: _dio(adapter),
      );

      await expectLater(
        client.session(),
        throwsA(
          isA<TransmissionException>().having(
            (e) => e.reason,
            'reason',
            ServiceFailureReason.notFound,
          ),
        ),
      );
    });
  });

  group('writes', () {
    test('every write sends an ids key, and an empty selection throws', () async {
      // An **absent** `ids` means "all torrents" to this API, so a write
      // assembled with `if (ids.isNotEmpty)` would escalate an empty selection
      // into the whole library — with `delete-local-data` that is the files too.
      final adapter = ScriptedHttpAdapter([_ok(const {})]);
      final client = TransmissionClient(
        url: 'https://nas.local:9091',
        dio: _dio(adapter),
      );

      await client.removeTorrents(['abc'], deleteLocalData: true);
      final body = adapter.lastRequest.body as Map<String, dynamic>;
      expect(body['method'], 'torrent-remove');
      expect(body['arguments']['ids'], ['abc']);
      expect(body['arguments']['delete-local-data'], isTrue);

      await expectLater(
        client.removeTorrents(const [], deleteLocalData: true),
        throwsA(isA<TransmissionException>()),
      );
      expect(
        adapter.callCount,
        1,
        reason: 'an empty selection must never reach the daemon',
      );
    });

    test('remove defaults to keeping the downloaded files', () async {
      final adapter = ScriptedHttpAdapter([_ok(const {})]);
      final client = TransmissionClient(
        url: 'https://nas.local:9091',
        dio: _dio(adapter),
      );

      await client.removeTorrents(['abc']);

      final body = adapter.lastRequest.body as Map<String, dynamic>;
      expect(body['arguments']['delete-local-data'], isFalse);
    });

    test('a duplicate add is reported as duplicate, not as added', () async {
      // Transmission answers `result: "success"` with a `torrent-duplicate`
      // key, so a client checking only `result` claims it added something it
      // did not.
      final adapter = ScriptedHttpAdapter([
        _ok({
          'torrent-duplicate': {'id': 4, 'hashString': 'aa', 'name': 'Dune'},
        }),
      ]);
      final client = TransmissionClient(
        url: 'https://nas.local:9091',
        dio: _dio(adapter),
      );

      final outcome = await client.addTorrent('magnet:?xt=urn:btih:aa');

      expect(outcome.isDuplicate, isTrue);
      expect(outcome.torrent?.name, 'Dune');
    });

    test('speed limits are sent with their matching enabled flag', () async {
      final adapter = ScriptedHttpAdapter([_ok(const {})]);
      final client = TransmissionClient(
        url: 'https://nas.local:9091',
        dio: _dio(adapter),
      );

      await client.setSpeedLimits(['abc'], downloadKbPerSec: 0);

      final args =
          (adapter.lastRequest.body as Map<String, dynamic>)['arguments']
              as Map<String, dynamic>;
      // A limit without its `*Limited` flag stores a value that never applies,
      // which reads on screen as a broken toggle.
      expect(args['downloadLimit'], 0);
      expect(args['downloadLimited'], isFalse);
      expect(args.containsKey('uploadLimit'), isFalse);
    });
  });

  group('model parsing', () {
    test('reads the sentinels Transmission actually uses', () {
      final torrent = TransmissionTorrent.fromJson(const {
        'id': 7,
        'hashString': 'deadbeef',
        'name': 'Arrival',
        'status': 4,
        'percentDone': 0.5,
        'eta': -1,
        'uploadRatio': -1,
        'isStalled': true,
        'error': 3,
        'errorString': 'No data found',
        'doneDate': 0,
      });

      expect(torrent.status, TransmissionStatus.download);
      expect(torrent.status.isIncoming, isTrue);
      expect(torrent.etaLabel, 'Unknown');
      expect(torrent.ratioLabel, '—');
      expect(torrent.errorKind, TransmissionErrorKind.localError);
      // A local error outranks the stalled flag: it is the reason.
      expect(torrent.warning, 'No data found');
      expect(torrent.rpcId, 'deadbeef');
    });

    test('falls back to the session id only when there is no hash', () {
      final torrent = TransmissionTorrent.fromJson(const {'id': 7});
      expect(torrent.rpcId, '7');
    });

    test('an absent eta reads as unknown rather than "arriving now"', () {
      final torrent = TransmissionTorrent.fromJson(const {'id': 1});
      expect(torrent.eta, -1);
      expect(torrent.etaLabel, 'Unknown');
    });
  });
}
