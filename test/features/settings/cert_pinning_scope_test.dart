/// The inverse of the tripwire this file used to be (ADR-5 → ADR-6).
///
/// Under ADR-5, certificate pinning reached exactly two of fifteen services,
/// and `SettingsModel.copyWithCertFingerprint` silently dropped a fingerprint
/// for every other one — a trap for the day someone widened the gate without
/// making `ApiClient` pin-aware first. ADR-6 removed the gate: every service
/// now reaches a pin-aware transport — `ApiClient`, one of the four
/// per-service `Dio` clients (qBittorrent, SABnzbd, NZBGet, Unraid), or its
/// own WebSocket/Socket.IO client — and trust is keyed by TLS origin
/// (`UrlUtils.certOrigin`) rather than by service. See ADR-6 in
/// `context/decisions.md`.
///
/// This file is the tripwire for *that* invariant instead: no service can be
/// silently unpinnable, and two services sharing an origin must share one
/// pin rather than diverging. If a change makes this file fail, the fix is
/// almost never to carve a per-service exception back into `SettingsModel` —
/// check instead that whatever new construction site was added actually
/// threads `pinForUrl`/a pinned adapter through, the way every existing one
/// does.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';

void main() {
  const fakeFingerprint =
      'ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab1';
  const otherFingerprint =
      '11aa22bb33cc11aa22bb33cc11aa22bb33cc11aa22bb33cc11aa22bb33cc11a';
  const url = 'https://nas.local:8443';

  group('SettingsModel trusted-certificate origin scope', () {
    test('every service can round-trip a pin for its own URL', () {
      for (final service in ServiceKey.values) {
        final settings = const SettingsModel().copyWithService(
          service,
          url: url,
          apiKey: 'key',
        );
        final updated = settings.copyWithTrustedCertificate(
          url: settings.urlFor(service),
          fingerprint: fakeFingerprint,
        );
        expect(
          updated.pinForUrl(updated.urlFor(service)),
          fakeFingerprint,
          reason:
              '${service.name} could not round-trip a certificate pin. '
              'Every service must be able to — trust is scoped to the TLS '
              'origin, not to a hand-picked list of services (ADR-6).',
        );
      }
    });

    test('two services on the same origin share one pin', () {
      var settings = const SettingsModel()
          .copyWithService(ServiceKey.radarr, url: url, apiKey: 'key')
          .copyWithService(ServiceKey.sonarr, url: url, apiKey: 'key');

      settings = settings.copyWithTrustedCertificate(
        url: url,
        fingerprint: fakeFingerprint,
      );

      expect(
        settings.pinForUrl(settings.urlFor(ServiceKey.radarr)),
        fakeFingerprint,
      );
      expect(
        settings.pinForUrl(settings.urlFor(ServiceKey.sonarr)),
        fakeFingerprint,
        reason:
            'A certificate belongs to the host, not to one service reached '
            'through it — trusting it for Radarr must also trust it for '
            'Sonarr on the same origin (ADR-6).',
      );
      expect(
        settings.servicesSharingOriginOf(url),
        containsAll(<ServiceKey>[ServiceKey.radarr, ServiceKey.sonarr]),
      );
    });

    test('a different port is a different origin, not the same pin', () {
      final settings = const SettingsModel()
          .copyWithService(ServiceKey.radarr, url: url, apiKey: 'key')
          .copyWithTrustedCertificate(url: url, fingerprint: fakeFingerprint);

      expect(
        settings.pinForUrl('https://nas.local:9443'),
        isNull,
        reason:
            'A different port is a different service on the host and must '
            'not inherit a pin granted to a different origin.',
      );
    });

    test('an empty fingerprint forgets the origin rather than storing one', () {
      var settings = const SettingsModel().copyWithTrustedCertificate(
        url: url,
        fingerprint: fakeFingerprint,
      );
      expect(settings.pinForUrl(url), fakeFingerprint);

      settings = settings.copyWithTrustedCertificate(url: url, fingerprint: '');
      expect(
        settings.pinForUrl(url),
        isNull,
        reason:
            '"Forget" must remove the entry, not store an empty string — '
            'pinForUrl treats a missing key and an empty value the same, but '
            'only removal actually shrinks trustedCertificates, which is '
            'what lets an origin with nothing pinned stay absent from '
            'storage entirely.',
      );
      expect(settings.trustedCertificates, isEmpty);
    });

    test('trusting a new fingerprint replaces the old one for that origin', () {
      var settings = const SettingsModel().copyWithTrustedCertificate(
        url: url,
        fingerprint: fakeFingerprint,
      );
      settings = settings.copyWithTrustedCertificate(
        url: url,
        fingerprint: otherFingerprint,
      );
      expect(settings.pinForUrl(url), otherFingerprint);
    });

    test('a non-TLS URL cannot carry a pin', () {
      final settings = const SettingsModel().copyWithTrustedCertificate(
        url: 'http://nas.local:8080',
        fingerprint: fakeFingerprint,
      );
      expect(
        settings.trustedCertificates,
        isEmpty,
        reason:
            'copyWithTrustedCertificate must be a no-op for a URL that '
            'cannot resolve to a TLS origin (UrlUtils.certOrigin returns '
            'null for http://) — otherwise a garbage key with no matching '
            'origin would sit in storage forever.',
      );
    });
  });
}
