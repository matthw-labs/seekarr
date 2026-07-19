import 'package:flutter/material.dart';

import 'package:seekarr/core/app_spacing.dart';

/// A single, premium empty-state widget used across the app.
///
/// Replaces the several bespoke empty states (dashboard sections, services
/// screen, not-configured placeholder) with one consistent visual language:
/// an icon in a soft circle, a title, an optional body and an optional action.
///
/// Two modes:
/// - [AppEmptyState] (full): screen-centred, larger, for whole pages.
/// - [AppEmptyState.compact]: inline, smaller, for carousels/sections.
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool compact;

  /// Optional accent for the icon (defaults to a neutral variant tone).
  final Color? accentColor;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.accentColor,
  }) : compact = false;

  const AppEmptyState.compact({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.accentColor,
  }) : compact = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = accentColor ?? colorScheme.onSurfaceVariant;
    final circleSize = compact ? 52.0 : 72.0;
    final iconSize = compact ? 26.0 : 34.0;

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: circleSize,
          height: circleSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accentColor != null
                ? accent.withValues(alpha: 0.14)
                : colorScheme.surfaceContainerHigh,
          ),
          child: Icon(icon, size: iconSize, color: accent),
        ),
        SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
        Text(
          title,
          style:
              (compact
                      ? theme.textTheme.titleSmall
                      : theme.textTheme.titleMedium)
                  ?.copyWith(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        if (message != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            message!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        if (action != null) ...[
          SizedBox(height: compact ? AppSpacing.lg : AppSpacing.xl),
          action!,
        ],
      ],
    );

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? AppSpacing.xl : 40,
          vertical: compact ? AppSpacing.xl : AppSpacing.xxl,
        ),
        child: column,
      ),
    );
  }
}
