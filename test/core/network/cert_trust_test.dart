import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/cert_trust.dart';
import 'package:cupola/core/utils/url_utils.dart';

/// The trust *record* has been covered since ADR-6 by
/// `test/features/settings/cert_pinning_scope_test.dart`. Nothing covered its
/// *enforcement* — a client could accept a `certFingerprint`, store it, drop it
/// on the floor, and every existing test still passed green.
///
/// This is that missing half. `X509Certificate` is an abstract interface, so a
/// fake satisfies it with no socket, no HTTP override and no fixture server.
class _FakeCert implements X509Certificate {
  _FakeCert(List<int> bytes) : der = Uint8List.fromList(bytes);

  @override
  final Uint8List der;

  @override
  String get pem => '';

  @override
  Uint8List get sha1 => Uint8List(0);

  @override
  String get subject => 'CN=nas.local';

  @override
  String get issuer => 'CN=nas.local';

  @override
  DateTime get startValidity => DateTime(2026);

  @override
  DateTime get endValidity => DateTime(2027);
}

void main() {
  group('buildPinnedHttpClient', () {
    test('binds a pin to its host and port, not to the fingerprint alone', () {
      final cert = _FakeCert(const [1, 2, 3]);
      bool accepts(X509Certificate c, String host, int port) =>
          pinnedCertificateIsTrusted(
            c,
            host: host,
            port: port,
            pinnedFingerprint: certificateFingerprint(cert),
            pinnedHost: 'nas.local',
            pinnedPort: 9091,
          );

      expect(accepts(cert, 'nas.local', 9091), isTrue);

      // Under ADR-6 one process holds many pinned clients across services that
      // share an origin, so the fingerprint alone is no longer enough to keep a
      // pin scoped to the host it was granted for.
      expect(accepts(cert, 'evil.example.com', 9091), isFalse);
      expect(accepts(cert, 'nas.local', 443), isFalse);
      expect(accepts(_FakeCert(const [9]), 'nas.local', 9091), isFalse);
    });

    test('is case-insensitive about the stored fingerprint', () {
      final cert = _FakeCert(const [4, 5, 6]);
      expect(
        pinnedCertificateIsTrusted(
          cert,
          host: 'nas.local',
          port: 443,
          pinnedFingerprint: certificateFingerprint(cert).toUpperCase(),
          pinnedHost: 'nas.local',
          pinnedPort: 443,
        ),
        isTrue,
      );
    });

    test('an empty pin trusts nothing', () {
      // The secure default: without a stored fingerprint the platform trust
      // store is the sole authority, exactly like a browser with no exception.
      // `buildPinnedHttpClient` expresses that by installing no callback at all
      // — which a test cannot observe, because `badCertificateCallback` is a
      // setter only. The predicate has to agree independently, so neither route
      // can drift into accepting.
      final cert = _FakeCert(const [1, 2, 3]);
      for (final pin in ['', '   ']) {
        expect(
          pinnedCertificateIsTrusted(
            cert,
            host: 'nas.local',
            port: 443,
            pinnedFingerprint: pin,
          ),
          isFalse,
          reason: 'pin="$pin"',
        );
      }
    });
  });

  group('pinnedHttpClientAdapterFor', () {
    test('returns null when there is nothing pinned', () {
      expect(pinnedHttpClientAdapterFor('https://nas.local:9091'), isNull);
      expect(
        pinnedHttpClientAdapterFor(
          'https://nas.local:9091',
          pinnedFingerprint: '  ',
        ),
        isNull,
      );
    });

    test('a scheme-less base URL must be normalised first', () {
      // The silent failure this guards: `Uri.parse('nas.local:9091')` yields
      // `scheme: 'nas.local'` and an EMPTY host, so `pinnedHost` becomes `''`
      // and the callback refuses every certificate — a pin the user explicitly
      // granted, dead on arrival. Every client must pass the *normalised* URL,
      // which is why they all build it before touching this.
      final raw = Uri.parse('nas.local:9091');
      expect(raw.host, isEmpty, reason: 'the trap this test exists for');

      final normalised = Uri.parse(UrlUtils.normalizeBaseUrl('nas.local:9091'));
      expect(normalised.host, 'nas.local');
      expect(normalised.port, 9091);

      expect(
        pinnedHttpClientAdapterFor(
          UrlUtils.normalizeBaseUrl('nas.local:9091'),
          pinnedFingerprint: 'ab12cd34',
        ),
        isNotNull,
      );
    });
  });

  group('certificateFingerprint', () {
    test('is the SHA-256 of the DER encoding, as lowercase hex', () {
      final fingerprint = certificateFingerprint(_FakeCert(const [1, 2, 3]));
      expect(fingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(
        certificateFingerprint(_FakeCert(const [1, 2, 3])),
        fingerprint,
        reason: 'the same certificate must always hash the same',
      );
      expect(
        certificateFingerprint(_FakeCert(const [1, 2, 4])),
        isNot(fingerprint),
      );
    });
  });

  group('normalizeBaseUrl', () {
    test('strips embedded credentials before they can reach a request URI', () {
      // Transmission's ecosystem writes addresses as
      // `http://user:pass@host:9091/`, and this is the function whose output
      // becomes `BaseOptions.baseUrl`. A credential left here would be
      // interpolated into every request URI, land in `HttpException`'s
      // `uri = …` text, and be persisted in plain SharedPreferences.
      expect(
        UrlUtils.normalizeBaseUrl('http://matt:hunter2@nas.local:9091'),
        'http://nas.local:9091',
      );
      expect(
        UrlUtils.normalizeBaseUrl('https://matt:hunter2@nas.local'),
        isNot(contains('hunter2')),
      );
    });

    test('still defaults a scheme-less address to https', () {
      expect(
        UrlUtils.normalizeBaseUrl('nas.local:9091'),
        'https://nas.local:9091',
      );
    });
  });
}
