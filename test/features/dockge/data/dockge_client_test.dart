import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/features/dockge/data/dockge_client.dart';

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

  group('DockgeClient.combinedTerminalName', () {
    test('builds the aggregated-logs terminal name for a stack', () {
      expect(
        _client('https://dockge.local').combinedTerminalName('immich'),
        'combined--immich',
      );
    });
  });
}
