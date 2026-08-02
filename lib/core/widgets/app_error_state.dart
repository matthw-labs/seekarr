import 'package:flutter/material.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';

/// A premium error state with an optional retry affordance.
///
/// Replaces the private, retry-less error widget inside [AsyncValueWidget].
/// When [onRetry] is provided a "Try again" button is shown, wired by callers
/// to their existing `ref.invalidate(...)` refresh path.
///
/// ## What the user reads first
///
/// The headline names what failed; [error] is demoted to a detail line beneath
/// it. It used to be the reverse in effect — "Something went wrong" said nothing,
/// so the raw `error.toString()` under it was the message, and on this app's
/// failures that is a Dio exception with a URL and a status code in it. That is
/// diagnostics, not an explanation, and it is the first thing the eye landed on.
/// It stays on screen because a self-hoster genuinely can act on
/// "connection refused" — just not as the sentence that opens the state.
class AppErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  /// What could not be loaded, for the headline: "Couldn't load Radarr".
  ///
  /// Optional because a handful of callers sit on screens where the subject is
  /// already unambiguous; those fall back to naming the surface generically.
  final String? serviceName;

  const AppErrorState({
    super.key,
    required this.error,
    this.onRetry,
    this.serviceName,
  }) : compact = false;

  const AppErrorState.compact({
    super.key,
    required this.error,
    this.onRetry,
    this.serviceName,
  }) : compact = true;

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
              serviceName == null
                  ? "Couldn't load this"
                  : "Couldn't load $serviceName",
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            // The detail, not the message: one step down the type ladder and a
            // step dimmer, so the sentence above it is what gets read.
            Text(
              error.toString(),
              style: theme.textTheme.labelSmall?.copyWith(
                color:
                    theme.extension<SeekarrThemeColors>()?.dimText ??
                    colorScheme.onSurfaceVariant,
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
