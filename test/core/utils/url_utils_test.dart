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

    group('normalizeBaseUrl', () {
      test('qualifies a scheme-less host with https', () {
        // Dio's `baseUrl` setter throws ArgumentError on a bare host, and both
        // address fields accept one — so this is what keeps a plausible address
        // from wedging its caller.
        expect(
          UrlUtils.normalizeBaseUrl('192.168.1.10:7878'),
          'https://192.168.1.10:7878',
        );
        expect(UrlUtils.normalizeBaseUrl('radarr.lan'), 'https://radarr.lan');
      });

      test('honours an explicit scheme, whatever its case', () {
        expect(
          UrlUtils.normalizeBaseUrl('http://10.0.0.5:8989'),
          'http://10.0.0.5:8989',
        );
        expect(
          UrlUtils.normalizeBaseUrl('HTTP://10.0.0.5:8989'),
          'HTTP://10.0.0.5:8989',
        );
      });

      test('trims surrounding space and trailing slashes', () {
        expect(
          UrlUtils.normalizeBaseUrl('  https://nas.local:7878//  '),
          'https://nas.local:7878',
        );
      });

      test('leaves an empty value empty', () {
        expect(UrlUtils.normalizeBaseUrl(''), '');
        expect(UrlUtils.normalizeBaseUrl('   '), '');
      });

      test('preserves a reverse-proxy base path', () {
        expect(
          UrlUtils.normalizeBaseUrl('https://proxy.example.com/radarr'),
          'https://proxy.example.com/radarr',
        );
      });
    });

    group('validateServiceHost', () {
      test('accepts a reverse-proxy base path', () {
        expect(
          UrlUtils.validateServiceHost('https://proxy.example.com/radarr'),
          isNull,
        );
      });

      test('accepts a trailing slash and surrounding whitespace', () {
        expect(UrlUtils.validateServiceHost('http://10.0.0.1:7878/'), isNull);
        expect(
          UrlUtils.validateServiceHost('  http://localhost:7878  '),
          isNull,
        );
      });

      test('rejects internal whitespace', () {
        expect(
          UrlUtils.validateServiceHost('https://not a url'),
          'Enter a valid URL (e.g. https://192.168.1.100:7878)',
        );
      });

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

      // `Uri.tryParse` is far looser than DNS — it reports `hello!world` and
      // `a,b.com` as hosts — so free text used to sail through the form and
      // come back as "couldn't reach it", sending the user hunting for a
      // network fault that was never there.
      test('rejects free text that cannot be a host', () {
        for (final value in const [
          'not a url',
          'hello!world',
          'radarr,example.com',
          'what is this?!',
          '{{RADARR_URL}}',
          'nas..local',
          '-nas.local',
          'nas-.local',
          'radarr(prod).example.com',
        ]) {
          expect(
            UrlUtils.validateServiceHost(value),
            'Enter a valid URL (e.g. https://192.168.1.100:7878)',
            reason: '"$value" is not a host',
          );
        }
      });

      // The other direction, and the reason the check is a character rule and
      // not a "must contain a dot" rule: single-label names resolve on a home
      // network, and a Compose service name is a normal way to reach a
      // container.
      test('still accepts the terse addresses a home lab actually uses', () {
        for (final value in const [
          'nas',
          'nas:7878',
          'radarr_prod',
          'radarr-prod.lan',
          'nas.local.',
          'http://[::1]:8080',
          'https://[fd00::1]:7878',
          '[2001:db8::1]',
        ]) {
          expect(
            UrlUtils.validateServiceHost(value),
            isNull,
            reason: '"$value" is a legitimate address',
          );
        }
      });

      // `Uri.host` percent-encodes anything non-ASCII, and `%` is not in any
      // host's alphabet — so a character rule applied to the raw host rejected
      // every internationalised name and told the user their address was
      // malformed. It is the same class of input as the single-label and
      // underscore hosts the rule deliberately keeps.
      test('accepts internationalised domain names', () {
        for (final value in const [
          'münchen.de',
          'https://münchen.de:8096',
          'https://пример.рф',
          'ドメイン.テスト',
          // The punycode form of the same address must keep working too.
          'https://xn--mnchen-3ya.de',
        ]) {
          expect(
            UrlUtils.validateServiceHost(value),
            isNull,
            reason: '"$value" is a legitimate address',
          );
        }
      });

      // Decoding happens per label and only to character-check it, so an escape
      // cannot smuggle a separator or a stray `%` past the rule.
      test('a percent-escape is still checked as one label', () {
        expect(UrlUtils.validateServiceHost('https://a%2Fb.com'), isNotNull);
        expect(UrlUtils.validateServiceHost('https://a%zzb.com'), isNotNull);
      });

      test('rejects a malformed IPv6 literal', () {
        expect(UrlUtils.validateServiceHost('http://[::zz]'), isNotNull);
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

      test('does not warn for cleartext to a private IPv6 address', () {
        for (final host in const [
          'http://[::1]:8080',
          'http://[fd00::1]',
          'http://[fdff:1234::abcd]:7878',
          'http://[fc00::1]',
          'http://[fe80::1]',
          'http://[fe80::1%25en0]',
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
        // A public IPv6 address is not in fc00::/7 or fe80::/10.
        expect(UrlUtils.cleartextWarning('http://[2001:db8::1]'), isNotNull);
      });

      // The bug: `host.startsWith('fd') || host.startsWith('fe80')` was applied
      // to *any* host, DNS names included, so a public domain that happened to
      // start with those letters was silently treated as local and the user was
      // never told their API key was travelling in the clear.
      test('does not mistake a DNS name for an IPv6 range', () {
        for (final host in const [
          'http://fdn.example.com',
          'http://fd.example.com',
          'http://fe80s.example.com',
          'http://fe80.example.com',
          'http://fdisk.io',
        ]) {
          expect(
            UrlUtils.cleartextWarning(host),
            contains('unencrypted'),
            reason: '$host is a public hostname, not a ULA',
          );
        }
      });

      test('ignores empty input', () {
        expect(UrlUtils.cleartextWarning(''), isNull);
        expect(UrlUtils.cleartextWarning(null), isNull);
      });
    });

    group('certOrigin', () {
      // The single normaliser trusted-certificate pins are keyed on (ADR-6):
      // two services on the same host:port must resolve to the same string.
      test('normalises a scheme-less host to https with the default port', () {
        expect(UrlUtils.certOrigin('nas.local'), 'https://nas.local:443');
      });

      test('keeps an explicit port', () {
        expect(
          UrlUtils.certOrigin('https://nas.local:8443'),
          'https://nas.local:8443',
        );
      });

      test('two URLs on the same host:port are the same origin', () {
        expect(
          UrlUtils.certOrigin('https://nas.local:8443/'),
          UrlUtils.certOrigin('nas.local:8443'),
        );
      });

      test('a different port is a different origin', () {
        expect(
          UrlUtils.certOrigin('https://nas.local:8443'),
          isNot(UrlUtils.certOrigin('https://nas.local:9443')),
        );
      });

      test('http and ws cannot carry a certificate', () {
        expect(UrlUtils.certOrigin('http://nas.local:8080'), isNull);
        expect(UrlUtils.certOrigin('ws://nas.local:8080'), isNull);
      });

      test('an unparseable or empty URL has no origin', () {
        expect(UrlUtils.certOrigin(''), isNull);
        expect(UrlUtils.certOrigin('   '), isNull);
      });
    });

    // Moved here from discover_detail_model_test.dart when the identical guard
    // in the TrueNAS app-portal screen was collapsed onto this one. Both callers
    // launch a string a *server* chose, so the allowlist is one rule with one
    // set of cases rather than two that can drift apart.
    group('isLaunchableWebUrl', () {
      test('accepts http and https with a host', () {
        expect(UrlUtils.isLaunchableWebUrl('https://vimeo.com/1'), isTrue);
        expect(UrlUtils.isLaunchableWebUrl('http://vimeo.com/1'), isTrue);
        expect(
          UrlUtils.isLaunchableWebUrl('  https://nas.local:9000/  '),
          isTrue,
        );
      });

      test('refuses every other scheme, and scheme-less input', () {
        expect(UrlUtils.isLaunchableWebUrl('javascript:alert(1)'), isFalse);
        expect(UrlUtils.isLaunchableWebUrl('data:text/html,x'), isFalse);
        expect(UrlUtils.isLaunchableWebUrl('file:///etc/passwd'), isFalse);
        expect(UrlUtils.isLaunchableWebUrl('intent://x#Intent;end'), isFalse);
        expect(UrlUtils.isLaunchableWebUrl('tel:+15551234'), isFalse);
        expect(UrlUtils.isLaunchableWebUrl('vimeo.com/1'), isFalse);
        expect(UrlUtils.isLaunchableWebUrl(''), isFalse);
        expect(UrlUtils.isLaunchableWebUrl('https://'), isFalse);
      });

      test('the scheme test is case-insensitive', () {
        // `Uri` lower-cases the scheme on parse, but the rule is stated as
        // "http or https" and a caller should not have to know that.
        expect(UrlUtils.isLaunchableWebUrl('HTTPS://vimeo.com/1'), isTrue);
        expect(UrlUtils.isLaunchableWebUrl('JavaScript:alert(1)'), isFalse);
      });

      test('the Uri overload agrees with the String one', () {
        for (final raw in const [
          'https://vimeo.com/1',
          'intent://x#Intent;end',
          'file:///etc/passwd',
          'nas.local:9000',
        ]) {
          expect(
            UrlUtils.isLaunchableWebUri(Uri.tryParse(raw)),
            UrlUtils.isLaunchableWebUrl(raw),
            reason: 'disagreed on $raw',
          );
        }
      });

      test('a null Uri is not launchable', () {
        // The overload exists for callers that used `Uri.tryParse` to keep a
        // FormatException out of a tap handler, so null is its normal input.
        expect(UrlUtils.isLaunchableWebUri(null), isFalse);
      });
    });
  });
}
