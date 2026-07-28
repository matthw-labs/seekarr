import 'package:flutter_test/flutter_test.dart';
import 'package:seekarr/core/utils/url_utils.dart';

void main() {
  group('UrlUtils', () {
    group('buildUrl', () {
      test('builds correct URL with trailing slash in baseUrl', () {
        final result = UrlUtils.buildUrl(
          'http://localhost:7878/',
          '/api/v3/image.jpg',
        );
        expect(result, 'http://localhost:7878/api/v3/image.jpg');
      });

      test('builds correct URL without trailing slash in baseUrl', () {
        final result = UrlUtils.buildUrl(
          'http://localhost:7878',
          '/api/v3/image.jpg',
        );
        expect(result, 'http://localhost:7878/api/v3/image.jpg');
      });

      test('handles path without leading slash', () {
        final result = UrlUtils.buildUrl(
          'http://localhost:7878',
          'api/v3/image.jpg',
        );
        expect(result, 'http://localhost:7878/api/v3/image.jpg');
      });

      test('returns empty string when baseUrl is empty', () {
        final result = UrlUtils.buildUrl('', '/api/v3/image.jpg');
        expect(result, '');
      });

      test('returns empty string when path is empty', () {
        final result = UrlUtils.buildUrl('http://localhost:7878', '');
        expect(result, '');
      });
    });

    group('validateServiceUrl', () {
      test('returns required error for null', () {
        expect(UrlUtils.validateServiceUrl(null), 'Server URL is required');
      });

      test('returns required error for empty string', () {
        expect(UrlUtils.validateServiceUrl(''), 'Server URL is required');
      });

      test('returns required error for whitespace only', () {
        expect(UrlUtils.validateServiceUrl('  '), 'Server URL is required');
      });

      test('rejects non-http schemes', () {
        expect(
          UrlUtils.validateServiceUrl('ftp://host.com'),
          'URL must start with http:// or https://',
        );
      });

      test('rejects non-url values', () {
        expect(
          UrlUtils.validateServiceUrl('not-a-url'),
          'URL must start with http:// or https://',
        );
      });

      test('rejects bare http scheme', () {
        expect(
          UrlUtils.validateServiceUrl('http://'),
          'Enter a valid URL (e.g. https://192.168.1.100:7878)',
        );
      });

      test('rejects bare https scheme', () {
        expect(
          UrlUtils.validateServiceUrl('https://'),
          'Enter a valid URL (e.g. https://192.168.1.100:7878)',
        );
      });

      test('accepts localhost with port', () {
        expect(UrlUtils.validateServiceUrl('http://localhost:7878'), isNull);
      });

      test('accepts fqdn over https', () {
        expect(
          UrlUtils.validateServiceUrl('https://radarr.mydomain.com'),
          isNull,
        );
      });

      test('accepts private ip with port', () {
        expect(
          UrlUtils.validateServiceUrl('http://192.168.1.100:8989'),
          isNull,
        );
      });

      test('accepts local hostname with port', () {
        expect(UrlUtils.validateServiceUrl('http://mynas.local:7878'), isNull);
      });

      test('accepts reverse proxy base path', () {
        expect(
          UrlUtils.validateServiceUrl('https://proxy.example.com/radarr'),
          isNull,
        );
      });

      test('accepts trailing slash', () {
        expect(UrlUtils.validateServiceUrl('http://10.0.0.1:7878/'), isNull);
      });

      test('accepts whitespace around valid URL', () {
        expect(
          UrlUtils.validateServiceUrl('  http://localhost:7878  '),
          isNull,
        );
      });

      test('rejects embedded credentials', () {
        expect(
          UrlUtils.validateServiceUrl('https://user:pass@radarr.example.com'),
          contains('Remove the username:password'),
        );
      });

      test('rejects internal whitespace', () {
        expect(
          UrlUtils.validateServiceUrl('https://not a url'),
          'Enter a valid URL (e.g. https://192.168.1.100:7878)',
        );
      });
    });

    group('validateServiceHost', () {
      test('requires a value', () {
        expect(UrlUtils.validateServiceHost(''), 'Server URL is required');
        expect(UrlUtils.validateServiceHost('   '), 'Server URL is required');
        expect(UrlUtils.validateServiceHost(null), 'Server URL is required');
      });

      test('accepts a scheme-less host, matching client normalisation', () {
        expect(UrlUtils.validateServiceHost('radarr.example.com'), isNull);
        expect(UrlUtils.validateServiceHost('192.168.1.10:7878'), isNull);
      });

      test('accepts explicit http and https', () {
        expect(
          UrlUtils.validateServiceHost('http://192.168.1.10:7878'),
          isNull,
        );
        expect(UrlUtils.validateServiceHost('https://radarr.lan'), isNull);
      });

      test('rejects a non-http scheme instead of silently downgrading', () {
        expect(
          UrlUtils.validateServiceHost('wss://dockge.example.com'),
          'Only http:// and https:// addresses are supported',
        );
        expect(
          UrlUtils.validateServiceHost('ftp://host.example.com'),
          'Only http:// and https:// addresses are supported',
        );
      });

      test('rejects a malformed scheme rather than reporting unreachable', () {
        // The exact failure the QA pass hit: a typo reached the client, which
        // reported "Unreachable" and sent the user hunting for network faults.
        expect(UrlUtils.validateServiceHost('htps://not a url'), isNotNull);
        expect(UrlUtils.validateServiceHost('http://'), isNotNull);
        expect(UrlUtils.validateServiceHost('://host'), isNotNull);
      });

      test('rejects embedded credentials', () {
        expect(
          UrlUtils.validateServiceHost('user:pass@host.example.com'),
          contains('Remove the username:password'),
        );
      });
    });

    group('isSecureScheme', () {
      test('only explicit cleartext schemes are insecure', () {
        expect(UrlUtils.isSecureScheme('http://host'), isFalse);
        expect(UrlUtils.isSecureScheme('ws://host'), isFalse);
      });

      test('https and wss are secure', () {
        expect(UrlUtils.isSecureScheme('https://host'), isTrue);
        expect(UrlUtils.isSecureScheme('wss://host'), isTrue);
      });

      test('an unrecognised scheme never downgrades to cleartext', () {
        // Dockge used `scheme == 'https'`, so a typo sent the login credentials
        // over an unencrypted socket.
        expect(UrlUtils.isSecureScheme('htps://host'), isTrue);
        expect(UrlUtils.isSecureScheme('host'), isTrue);
        expect(UrlUtils.isSecureScheme(''), isTrue);
      });
    });

    group('cleartextWarning', () {
      test('does not warn for https', () {
        expect(
          UrlUtils.cleartextWarning('https://anything.example.com'),
          isNull,
        );
      });

      test('does not warn for cleartext on the local network', () {
        for (final host in const [
          'http://192.168.1.10:7878',
          'http://10.0.0.5',
          'http://172.16.4.4',
          'http://172.31.4.4',
          'http://127.0.0.1:8080',
          'http://localhost:8080',
          'http://mynas.local',
          'http://mynas.lan',
        ]) {
          expect(UrlUtils.cleartextWarning(host), isNull, reason: host);
        }
      });

      test('warns for cleartext to a public host', () {
        expect(
          UrlUtils.cleartextWarning('http://radarr.example.com'),
          contains('unencrypted'),
        );
        // 172.32 is outside the 172.16/12 private range.
        expect(UrlUtils.cleartextWarning('http://172.32.0.1'), isNotNull);
      });

      test('ignores empty input', () {
        expect(UrlUtils.cleartextWarning(''), isNull);
        expect(UrlUtils.cleartextWarning(null), isNull);
      });
    });
  });
}
