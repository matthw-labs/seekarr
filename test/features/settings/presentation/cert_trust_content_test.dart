import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/cert_trust.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/widgets/cert_trust_content.dart';

const _cert = ServerCertificate(
  fingerprint:
      'ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab1',
  subject: 'CN=nas.local',
  issuer: 'CN=nas.local',
);

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.darkTheme(),
  home: Scaffold(body: child),
);

void main() {
  group('displayOrigin', () {
    test('drops the https:// prefix, since every origin carries one', () {
      expect(displayOrigin('https://nas.local:8443'), 'nas.local:8443');
    });
  });

  group('CertTrustContent', () {
    testWidgets('first trust reads as a normal prompt, not an escalation', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const CertTrustContent(
            origin: 'https://nas.local:8443',
            probe: (certificate: _cert, rotated: false),
          ),
        ),
      );

      expect(find.text('Untrusted certificate'), findsOneWidget);
      expect(find.text('This certificate has changed'), findsNothing);
      expect(find.textContaining('nas.local:8443'), findsOneWidget);
      expect(find.text('Subject'), findsOneWidget);
      expect(find.text('SHA-256'), findsOneWidget);
      // Nothing to compare against on a first trust.
      expect(find.text('Previously trusted'), findsNothing);
    });

    testWidgets('a rotated certificate escalates the headline and shows both '
        'fingerprints', (tester) async {
      const previous =
          '11aa22bb33cc11aa22bb33cc11aa22bb33cc11aa22bb33cc11aa22bb33cc11a';

      await tester.pumpWidget(
        _host(
          const CertTrustContent(
            origin: 'https://nas.local:8443',
            probe: (certificate: _cert, rotated: true),
            previousFingerprint: previous,
          ),
        ),
      );

      expect(find.text('This certificate has changed'), findsOneWidget);
      expect(find.text('Untrusted certificate'), findsNothing);
      expect(find.text('Previously trusted'), findsOneWidget);
      // Both fingerprints render, uppercased and colon-grouped — the
      // previously-trusted one and the one presented now must both be
      // visible for the user to actually compare them.
      expect(find.textContaining('11:AA:22:BB'), findsOneWidget);
      expect(find.textContaining('AB:12:CD:34'), findsOneWidget);
    });

    testWidgets('names every other service the trust decision covers', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const CertTrustContent(
            origin: 'https://nas.local:8443',
            probe: (certificate: _cert, rotated: false),
            sharedWith: [ServiceKey.sonarr, ServiceKey.prowlarr],
          ),
        ),
      );

      expect(find.textContaining('Sonarr'), findsWidgets);
      expect(find.textContaining('Prowlarr'), findsWidgets);
    });

    testWidgets('says nothing about sharing when nothing else uses it', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const CertTrustContent(
            origin: 'https://nas.local:8443',
            probe: (certificate: _cert, rotated: false),
          ),
        ),
      );

      expect(find.text('Also used by'), findsNothing);
    });
  });
}
