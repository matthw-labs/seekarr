import 'package:flutter/material.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';

/// A reusable widget to display file information (path and filename).
///
/// Headless: the heading comes from the `MediaDetailSlot` that hosts it, so
/// every heading on a detail page is built by the spine and cannot lose its
/// accent, its `Semantics(header: true)` or its place in the region order.
class FileInfoSection extends StatelessWidget {
  final String? path;
  final String? filename;

  /// Optional per-service accent for the storage glyph.
  ///
  /// It used to feed a section-header pipe; now that the spine owns headings it
  /// tints the glyph, which is what stopped that glyph being a second accent
  /// (`colorScheme.primary` indigo) on a Radarr amber or Sonarr violet page.
  final Color? accent;

  const FileInfoSection({super.key, this.path, this.filename, this.accent});

  @override
  Widget build(BuildContext context) {
    if (path == null && filename == null) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return _InfoRow(
      title: filename ?? 'Library path',
      subtitle: path,
      icon: Icons.storage_rounded,
      iconColor: accent ?? colorScheme.onSurfaceVariant,
      colorScheme: colorScheme,
      theme: theme,
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color iconColor;
  final ColorScheme colorScheme;
  final ThemeData theme;

  const _InfoRow({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.colorScheme,
    required this.theme,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 54,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall!
                      .weight(FontWeight.w600)
                      .copyWith(color: colorScheme.onSurface),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
