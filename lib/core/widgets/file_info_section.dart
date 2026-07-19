import 'package:flutter/material.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/widgets/media_detail_view.dart';

/// A reusable widget to display file information (path and filename).
///
/// Uses Material Design 3 styling with proper color tokens.
class FileInfoSection extends StatelessWidget {
  final String? path;
  final String? filename;

  /// Optional per-service accent for the section header pipe.
  final Color? accent;

  const FileInfoSection({super.key, this.path, this.filename, this.accent});

  @override
  Widget build(BuildContext context) {
    if (path == null && filename == null) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MediaDetailSectionHeader(title: 'File', accent: accent),
        _InfoRow(
          title: filename ?? 'Library path',
          subtitle: path,
          icon: Icons.storage_rounded,
          colorScheme: colorScheme,
          theme: theme,
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final ColorScheme colorScheme;
  final ThemeData theme;

  const _InfoRow({
    required this.title,
    required this.icon,
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
            child: Icon(icon, size: 18, color: colorScheme.primary),
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
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
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
