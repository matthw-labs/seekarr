import 'package:flutter/material.dart';

import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/widgets/cert_trust_content.dart';

/// Prompts the user to trust an untrusted (typically self-signed) TLS
/// certificate for a self-hosted service, mirroring a browser's "this site
/// uses an untrusted certificate — proceed?" exception flow.
///
/// Returns true if the user chose to trust the certificate. The caller is
/// responsible for persisting the pinned fingerprint (as the origin's pin,
/// per [SettingsModel.copyWithTrustedCertificate] — ADR-6).
///
/// [probe.rotated] changes more than the copy: a certificate change gets no
/// visually-affirmative default. Both actions render the same weight, so
/// nothing nudges the user toward continuing past what could be an
/// interception rather than a routine renewal.
Future<bool> showCertTrustDialog(
  BuildContext context, {
  required String origin,
  required UntrustedCertificateProbe probe,
  String? previousFingerprint,
  List<ServiceKey> sharedWith = const [],
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final content = CertTrustContent(
        origin: origin,
        probe: probe,
        previousFingerprint: previousFingerprint,
        sharedWith: sharedWith,
      );
      return AlertDialog(
        content: SingleChildScrollView(child: content),
        actions: probe.rotated
            ? [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Trust this certificate anyway'),
                ),
              ]
            : [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Trust this certificate'),
                ),
              ],
      );
    },
  );
  return result ?? false;
}
