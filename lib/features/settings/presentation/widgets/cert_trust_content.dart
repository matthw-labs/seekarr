import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The `host:port` an origin string shows a human, dropping the `https://`
/// every origin carries (every entry in [SettingsModel.trustedCertificates]
/// is built by [UrlUtils.certOrigin], which always returns that scheme).
String displayOrigin(String origin) =>
    origin.startsWith('https://') ? origin.substring(8) : origin;

/// The trust decision for one TLS origin, shared by the modal dialog
/// (settings) and the inline card (onboarding) so the same certificate reads
/// the same way wherever the user meets it — before ADR-6 the two surfaces
/// had drifted into different words, different evidence and two different
/// fingerprint formats for the same two services.
///
/// Content only — no buttons. A modal's action row and a card's single button
/// are different idioms and each host keeps its own; what must not differ
/// between them is the evidence and the words. [probe]'s
/// [UntrustedCertificateProbe.rotated] is exposed as [rotated] so a host can
/// make its own chrome — a dialog's action buttons, a card's border — react
/// to the same signal this content escalates for.
class CertTrustContent extends StatelessWidget {
  const CertTrustContent({
    super.key,
    required this.origin,
    required this.probe,
    this.previousFingerprint,
    this.sharedWith = const [],
  });

  /// The origin (`https://host:port`) this certificate was presented for.
  final String origin;

  /// What the probe found — [rotated] decides which of the two states below
  /// renders.
  final UntrustedCertificateProbe probe;

  /// The fingerprint already pinned for [origin], shown only when [rotated].
  final String? previousFingerprint;

  /// Other configured services reached through [origin] — trusting or
  /// forgetting this certificate covers them too. Excludes the service this
  /// prompt is already about; empty when nothing else shares it.
  final List<ServiceKey> sharedWith;

  /// True when this origin already had a *different* pin — a certificate
  /// change, not a first trust. That is the shape a real interception would
  /// take, so it must read as an escalation, never as a routine prompt.
  bool get rotated => probe.rotated;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cert = probe.certificate;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              rotated ? Icons.gpp_bad_outlined : Icons.gpp_maybe_outlined,
              color: scheme.error,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                rotated
                    ? 'This certificate has changed'
                    : 'Untrusted certificate',
                style: theme.textTheme.titleMedium!
                    .weight(FontWeight.w700)
                    .copyWith(color: rotated ? scheme.error : null),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(_body(), style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.md),
        _CertRow(label: 'Address', value: displayOrigin(origin)),
        if (sharedWith.isNotEmpty)
          _CertRow(
            label: 'Also used by',
            value: sharedWith.map((s) => s.title).join(', '),
          ),
        const SizedBox(height: AppSpacing.sm),
        if (rotated && previousFingerprint != null)
          _CertRow(
            label: 'Previously trusted',
            value: _displayFingerprint(previousFingerprint!),
            monospace: true,
            tone: scheme.onSurfaceVariant,
          ),
        _CertRow(label: 'Subject', value: cert.subject),
        _CertRow(label: 'Issuer', value: cert.issuer),
        if (cert.validFrom != null)
          _CertRow(
            label: 'Valid from',
            value: cert.validFrom!.toLocal().toString(),
          ),
        if (cert.validTo != null)
          _CertRow(
            label: 'Valid until',
            value: cert.validTo!.toLocal().toString(),
          ),
        _CertRow(
          label: 'SHA-256',
          value: cert.displayFingerprint,
          monospace: true,
          tone: rotated ? scheme.error : null,
        ),
      ],
    );
  }

  String _body() {
    final sharedClause = sharedWith.isEmpty
        ? ''
        : ' This address is shared with ${sharedWith.map((s) => s.title).join(', ')} — trusting or forgetting it applies to all of them.';

    if (rotated) {
      return 'The certificate this address presents is not the one you '
          'trusted before. That can happen after a legitimate renewal — or it '
          'can mean something between you and the server is intercepting the '
          'connection. Only continue if you can confirm this exact '
          'fingerprint with the server directly.$sharedClause';
    }
    return 'This address presented a certificate that is not trusted by your '
        'device. That is normal for a self-signed certificate on a home '
        'install, but it also means the connection cannot be authenticated — '
        'only trust it if you recognise this server.$sharedClause';
  }

  /// Uppercased, colon-grouped hex, matching [ServerCertificate.displayFingerprint]
  /// — [previousFingerprint] comes from storage as raw lowercase hex, so it
  /// needs the same formatting to read next to the certificate's own.
  static String _displayFingerprint(String rawHex) {
    final upper = rawHex.toUpperCase();
    final pairs = <String>[
      for (var i = 0; i + 2 <= upper.length; i += 2) upper.substring(i, i + 2),
    ];
    return pairs.join(':');
  }
}

class _CertRow extends StatelessWidget {
  const _CertRow({
    required this.label,
    required this.value,
    this.monospace = false,
    this.tone,
  });

  final String label;
  final String value;
  final bool monospace;
  final Color? tone;

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
            style:
                (monospace
                        ? theme.textTheme.bodySmall!.mono
                        : theme.textTheme.bodySmall)
                    ?.copyWith(color: tone),
          ),
        ],
      ),
    );
  }
}
