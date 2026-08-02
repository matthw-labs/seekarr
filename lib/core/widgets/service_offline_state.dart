import 'package:flutter/material.dart';

import 'package:seekarr/core/app_spacing.dart';

/// Full-page state shown when a service is configured but unreachable.
///
/// Distinct from [NotConfiguredPlaceholder] (no URL/API key set) — this is
/// for a configured service whose [serviceSummaryProvider] health check
/// failed, so per-section retry banners on zeroed-out stats would be
/// misleading. Replaces that with a single coherent "can't reach it" page.
class ServiceOfflineState extends StatelessWidget {
  const ServiceOfflineState({
    super.key,
    required this.serviceName,
    required this.accent,
    required this.onRetry,
  });

  final String serviceName;
  final Color accent;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cloud_off_rounded, size: 32, color: accent),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '$serviceName is offline',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              "Seekarr can't reach the server. Check that $serviceName is "
              'running and that the URL in Settings is reachable.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
