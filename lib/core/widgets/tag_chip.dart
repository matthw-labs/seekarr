import 'package:flutter/material.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';

/// A reusable tag/chip widget for displaying metadata labels.
///
/// Used in detail screens to show year, status, runtime, etc.
/// Follows Material Design 3 styling guidelines.
class TagChip extends StatelessWidget {
  final String text;
  final Color? color;
  final IconData? icon;

  const TagChip({super.key, required this.text, this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveColor = color ?? colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: 0.12),
        borderRadius: AppRadius.borderRadiusFull,
        border: Border.all(color: effectiveColor.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: effectiveColor),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            text,
            style: Theme.of(context).textTheme.labelSmall!
                .weight(FontWeight.w600)
                .copyWith(color: effectiveColor),
          ),
        ],
      ),
    );
  }
}

/// A genre chip specifically styled for movie/TV genres.
class GenreChip extends StatelessWidget {
  final String genre;

  const GenreChip({super.key, required this.genre});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusFull,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Text(
        genre,
        style: Theme.of(context).textTheme.labelSmall!
            .weight(FontWeight.w500)
            .copyWith(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}
