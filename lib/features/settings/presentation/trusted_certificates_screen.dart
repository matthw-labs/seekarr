import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/snack_bar_helper.dart';
import 'package:seekarr/core/widgets/ambient_scaffold.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/app_dialog.dart';
import 'package:seekarr/core/widgets/app_empty_state.dart';
import 'package:seekarr/core/widgets/floating_bottom_nav_bar.dart';
import 'package:seekarr/core/widgets/glass_app_bar.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/settings/presentation/widgets/cert_trust_content.dart';

/// Every self-signed certificate trusted inside Seekarr (ADR-6), independent
/// of any one service's settings screen.
///
/// Trust is scoped to an origin, not to a service — the per-service form
/// shows the pin for *its own* address and can forget it, but nothing there
/// finds a pin whose services have all since been removed, or shows the one
/// decision covering three services at once. This screen is that one place.
class TrustedCertificatesScreen extends ConsumerWidget {
  const TrustedCertificatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final origins = settings.trustedCertificates.keys.toList()..sort();

    return AmbientScaffold(
      appBar: const GlassAppBar(title: Text('Trusted certificates')),
      body: origins.isEmpty
          ? const AppEmptyState(
              icon: Icons.verified_user_outlined,
              title: 'Nothing trusted yet',
              message:
                  'A self-signed certificate you choose to trust — for a '
                  'service behind a home-made reverse proxy, say — shows up '
                  'here, and can be revoked from here even after every '
                  'service that used it is gone.',
            )
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                FloatingNavBarMetrics.getScrollViewBottomPadding(context),
              ),
              itemCount: origins.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, index) {
                final origin = origins[index];
                return _TrustedOriginCard(
                  origin: origin,
                  fingerprint: settings.trustedCertificates[origin]!,
                  services: settings.servicesSharingOriginOf(origin),
                );
              },
            ),
    );
  }
}

class _TrustedOriginCard extends ConsumerWidget {
  const _TrustedOriginCard({
    required this.origin,
    required this.fingerprint,
    required this.services,
  });

  final String origin;
  final String fingerprint;

  /// Every configured service currently reaching [origin]. Empty is a real,
  /// expected state: it means every service that once used this pin has
  /// been removed, and this card is the only remaining way to find it.
  final List<ServiceKey> services;

  Future<void> _forget(BuildContext context, WidgetRef ref) async {
    final result = await showAppConfirmDialog(
      context: context,
      icon: Icons.gpp_bad_outlined,
      title: 'Forget this certificate?',
      message: services.isEmpty
          ? 'No service currently uses this address. Forgetting it just '
                'clears the record.'
          : 'The next connection from '
                '${services.map((s) => s.title).join(', ')} will need to be '
                'trusted again.',
      confirmLabel: 'Forget',
      destructive: true,
      // Reversible — the next connection re-offers the trust prompt.
      dangerNote: '',
    );
    if (!result.confirmed || !context.mounted) return;

    final updated = ref
        .read(currentSettingsProvider)
        .copyWithTrustedCertificate(url: origin, fingerprint: '');
    await ref.read(settingsProvider.notifier).updateSettings(updated);
    if (!context.mounted) return;
    SnackBarHelper.info(context, 'Certificate forgotten');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AppCard.surfaceOutlined(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  displayOrigin(origin),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              TextButton(
                onPressed: () => _forget(context, ref),
                child: const Text('Forget'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'SHA-256',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          SelectableText(
            _displayFingerprint(fingerprint),
            style: theme.textTheme.bodySmall?.mono,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            services.isEmpty
                ? 'No configured service currently uses this address.'
                : 'Used by ${services.map((s) => s.title).join(', ')}.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Uppercased, colon-grouped hex, matching
  /// [ServerCertificate.displayFingerprint] — storage keeps the raw lowercase
  /// hex, so it needs the same formatting to read the way the trust prompt
  /// that created it did.
  static String _displayFingerprint(String rawHex) {
    final upper = rawHex.toUpperCase();
    final pairs = <String>[
      for (var i = 0; i + 2 <= upper.length; i += 2) upper.substring(i, i + 2),
    ];
    return pairs.join(':');
  }
}
