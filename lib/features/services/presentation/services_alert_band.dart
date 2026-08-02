/// The conditional alert band above the stack matrix on `/services`.
///
/// Renders **nothing** while every configured service is answering, which is the
/// whole design: its presence is the signal, so a healthy stack has no alert
/// chrome to learn to ignore. A persistent "13 of 13 online" instrument would be
/// green on almost every open, and a badge that is always green is a badge nobody
/// reads on the day it turns red.
///
/// It replaces an 8pt dot in the app bar whose only affordance was a `Tooltip` —
/// useless on the phone this app is mostly used on — and which counted against
/// all thirteen `ServiceKey.values` rather than the configured ones, so a healthy
/// five-service stack reported "5 online, 8 offline".
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/service_theme.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/features/services/domain/services_semantics.dart';
import 'package:seekarr/features/services/presentation/service_kpi_provider.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

class ServicesAlertBand extends ConsumerWidget {
  const ServicesAlertBand({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);

    // Only configured services can be "not answering". An unconfigured one is
    // not a fault, and treating it as one is what made the old aggregate lie.
    final offline = ServiceKey.values
        .where(settings.isServiceConfigured)
        .where(
          // Strictly `false`, not `!= true`: a summary still loading is neither
          // online nor a fault, and a band that appears during the first second
          // of every cold open is a band that cried wolf.
          (service) =>
              ref
                  .watch(serviceSummaryProvider(service))
                  .asData
                  ?.value
                  .isOnline ==
              false,
        )
        .toList(growable: false);

    if (offline.isEmpty) return const SizedBox.shrink();

    return _AlertBandBody(
      services: offline,
      onRetry: () {
        // Only the offenders. Re-checking the whole stack would throw away
        // twelve good summaries to re-fetch one bad one.
        for (final service in offline) {
          ref.invalidate(serviceSummaryProvider(service));
          ref.invalidate(serviceKpiProvider(service));
          ref.invalidate(serviceSignalProvider(service));
        }
      },
    );
  }
}

class _AlertBandBody extends StatelessWidget {
  const _AlertBandBody({required this.services, required this.onRetry});

  final List<ServiceKey> services;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final message = servicesAlertBandMessage(
      services.map((s) => s.title).toList(growable: false),
    );

    // The band fills with error at 10%, so the label is measured against that
    // composite rather than against the error colour or the surface alone.
    const tintAlpha = 0.10;
    final onTint = ServiceTheme.onTint(
      colorScheme.error,
      surface: colorScheme.surface,
      tintAlpha: tintAlpha,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Semantics(
        key: const ValueKey('services-alert-band'),
        container: true,
        // The retry inside stays reachable as its own control; this node only
        // owns the sentence.
        explicitChildNodes: true,
        // Announced when it appears, which is the moment it matters. It is not
        // routed through `announce()` as well: that double-reads on iOS and is a
        // no-op on Android.
        liveRegion: true,
        // The same string the band paints: see `servicesAlertBandMessage`.
        label: message,
        child: AppCard.outlined(
          backgroundColor: colorScheme.error.withValues(alpha: tintAlpha),
          borderColor: colorScheme.error.withValues(alpha: 0.28),
          borderRadius: AppRadius.borderRadiusMd,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              ExcludeSemantics(
                child: Icon(Icons.cloud_off_rounded, size: 18, color: onTint),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ExcludeSemantics(
                  child: Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: onTint,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: onTint,
                  // 44pt on iOS / 48dp on Android is the floor, and this button
                  // shares its row with body text that would otherwise size it.
                  minimumSize: const Size(64, 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                ),
                child: Text(
                  'Retry',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: onTint,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
