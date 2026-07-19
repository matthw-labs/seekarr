import 'package:flutter/material.dart';

import 'package:seekarr/core/app_spacing.dart';

/// A premium error state with an optional retry affordance.
///
/// Replaces the private, retry-less error widget inside [AsyncValueWidget].
/// When [onRetry] is provided a "Try again" button is shown, wired by callers
/// to their existing `ref.invalidate(...)` refresh path.
class AppErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  const AppErrorState({super.key, required this.error, this.onRetry})
    : compact = false;

  const AppErrorState.compact({super.key, required this.error, this.onRetry})
    : compact = true;

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
                color: colorScheme.errorContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: compact ? 26 : 32,
                color: colorScheme.error,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Something went wrong',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              error.toString(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.xl),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
