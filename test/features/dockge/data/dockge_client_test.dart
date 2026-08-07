import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/dockge/data/dockge_client.dart';

DockgeClient _client(String url) => DockgeClient(baseUrl: url);

void main() {
  group('DockgeClient.resolveEndpoint', () {
    test('defaults a scheme-less URL to secure wss/https (443)', () {
      // Security §10.3: credentials must not be sent over an unencrypted
      // socket when the user omits the scheme.
      final uri = _client('dockge.local:5001').resolveEndpoint();
      expect(uri.scheme, 'https');
      expect(uri.host, 'dockge.local');
      expect(uri.port, 5001);
    });

    test('defaults a scheme-less host without a port to 443', () {
      final uri = _client('dockge.local').resolveEndpoint();
      expect(uri.scheme, 'https');
      expect(uri.port, 443);
    });

    test('honours an explicit http:// scheme (port 80)', () {
      final uri = _client('http://dockge.local').resolveEndpoint();
      expect(uri.scheme, 'http');
      expect(uri.port, 80);
    });

    test('preserves an explicit https URL with a custom port', () {
      final uri = _client('https://dockge.local:8443').resolveEndpoint();
      expect(uri.scheme, 'https');
      expect(uri.port, 8443);
    });

    test('throws on an empty URL', () {
      expect(_client('  ').resolveEndpoint, throwsA(isA<DockgeException>()));
    });
  });

  // The editor screen refuses this too, but the call that actually destroys the
  // file is here: Dockge takes the YAML it is handed as the stack's new truth,
  // so an empty string replaces docker-compose.yaml with nothing — and for
  // deployStack, then runs `compose up` on the result.
  group('DockgeClient empty-compose guard', () {
    // An unreachable URL, so anything that gets *past* the guard fails on the
    // endpoint instead of opening a socket — which is what distinguishes
    // "refused" from "allowed through" without going near the network.
    DockgeClient client() => _client('');

    test('refuses to save or deploy an empty compose over a stack', () async {
      for (final yaml in const ['', '   ', '\n\t \n']) {
        await expectLater(
          client().deployStack(name: 'immich', composeYAML: yaml, isAdd: false),
          throwsA(
            isA<DockgeException>().having(
              (e) => e.message,
              'message',
              contains('Refusing to deploy an empty compose file'),
            ),
          ),
          reason: 'deployStack accepted ${jsonEncode(yaml)}',
        );
        await expectLater(
          client().saveStack(name: 'immich', composeYAML: yaml, isAdd: false),
          throwsA(
            isA<DockgeException>().having(
              (e) => e.message,
              'message',
              contains('Refusing to save an empty compose file'),
            ),
          ),
          reason: 'saveStack accepted ${jsonEncode(yaml)}',
        );
      }
    });

    test('creating a stack from a blank editor is not blocked', () async {
      // `isAdd` overwrites nothing, so the guard must not fire — it gets as far
      // as the transport, which is what fails here.
      await expectLater(
        client().deployStack(name: 'new', composeYAML: '', isAdd: true),
        throwsA(
          isA<DockgeException>().having(
            (e) => e.message,
            'message',
            isNot(contains('Refusing')),
          ),
        ),
      );
    });

    test('a real compose file is not blocked', () async {
      await expectLater(
        client().saveStack(
          name: 'immich',
          composeYAML: 'services:\n  web:\n    image: nginx\n',
          isAdd: false,
        ),
        throwsA(
          isA<DockgeException>().having(
            (e) => e.message,
            'message',
            isNot(contains('Refusing')),
          ),
        ),
      );
    });
  });

  group('DockgeClient.combinedTerminalName', () {
    test('builds the aggregated-logs terminal name for a stack', () {
      expect(
        _client('https://dockge.local').combinedTerminalName('immich'),
        'combined--immich',
      );
    });
  });
}
