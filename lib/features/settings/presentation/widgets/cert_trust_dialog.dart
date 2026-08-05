import 'package:flutter/material.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/network/cert_trust.dart';
import 'package:seekarr/core/theme.dart';

/// Prompts the user to trust an untrusted (typically self-signed) TLS
/// certificate for a self-hosted service, mirroring a browser's "this site
/// uses an untrusted certificate — proceed?" exception flow.
///
/// Returns true if the user chose to trust the certificate. The caller is
/// responsible for persisting the pinned fingerprint.
Future<bool> showCertTrustDialog(
  BuildContext context, {
  required String serviceTitle,
  required ServerCertificate certificate,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        icon: Icon(Icons.gpp_maybe_outlined, color: theme.colorScheme.error),
        title: const Text('Untrusted certificate'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$serviceTitle presented a certificate that is not trusted by '
              'your device. This is normal for a self-signed certificate on a '
              'home install, but it also means the connection cannot be '
              'authenticated — only trust it if you recognise this server.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            _CertRow(label: 'Subject', value: certificate.subject),
            _CertRow(label: 'Issuer', value: certificate.issuer),
            if (certificate.validTo != null)
              _CertRow(
                label: 'Valid until',
                value: certificate.validTo!.toLocal().toString(),
              ),
            _CertRow(
              label: 'SHA-256',
              value: certificate.displayFingerprint,
              monospace: true,
            ),
          ],
        ),
        actions: [
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

class _CertRow extends StatelessWidget {
  final String label;
  final String value;
  final bool monospace;

  const _CertRow({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SelectableText(
            value,
            // The SHA-256 fingerprint is read by comparing it, character by
            // character, against the one the server shows. `fontFamily:
            // 'monospace'` only resolves on Android — on iOS and macOS
            // CoreText has no such family, so this hex was rendering in the
            // proportional system face with nothing lining up and 0/O
            // indistinguishable. `.mono` carries a real fallback chain and
            // turns on the slashed zero.
            style: monospace
                ? theme.textTheme.bodySmall!.mono
                : theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
