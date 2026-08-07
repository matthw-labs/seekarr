import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/truenas/domain/truenas_version.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';

/// A warning banner shown when the connected TrueNAS is older than the minimum
/// supported version. Renders nothing while loading, on error, or when the
/// version is supported/unknown.
class TrueNasVersionBanner extends ConsumerWidget {
  const TrueNasVersionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(truenasVersionProvider);
    final parsed = version.asData?.value;
    if (parsed == null || parsed.isSupported) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        0,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.12),
          borderRadius: AppRadius.borderRadiusMd,
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: AppColors.warning,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'TrueNAS $parsed detected. Cupola supports SCALE '
                '$kTrueNasMinVersion or newer — some sections may be '
                'unavailable.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
