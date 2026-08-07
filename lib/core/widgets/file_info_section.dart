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

  /// Renders the tracked-but-empty hint instead of a real file.
  final bool _isMissingHint;

  const FileInfoSection({super.key, this.path, this.filename, this.accent})
    : _isMissingHint = false;

  /// The same row, for a title the service tracks with nothing on disk yet.
  ///
  /// Deliberately this row and **not** an `AppEmptyState`: a centred well with a
  /// circled glyph cost far more height than the fact deserves, on a page whose
  /// hero already says `No file` and whose consequence sentence already says the
  /// state — and it made the region jump when a file finally arrived. One
  /// footprint in both states is the whole point.
  ///
  /// The copy is a suggestion, and it names the route the promoted button does
  /// not: on this rung the primary directly above already reads "Auto search",
  /// so repeating it would spend the region on nothing.
  const FileInfoSection.missing({super.key, this.accent})
    : path = null,
      filename = null,
      _isMissingHint = true;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    if (_isMissingHint) {
      return _InfoRow(
        title: 'Import a file you already have',
        subtitle: 'Manual import is in the actions menu.',
        icon: Icons.drive_folder_upload_rounded,
        iconColor: accent ?? colorScheme.onSurfaceVariant,
        colorScheme: colorScheme,
        theme: theme,
        // The actionable half must survive a reading size, and this line is the
        // only place the alternative route is named.
        subtitleMaxLines: 2,
      );
    }

    if (path == null && filename == null) {
      return const SizedBox.shrink();
    }

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
  final int subtitleMaxLines;

  const _InfoRow({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.colorScheme,
    required this.theme,
    this.subtitle,
    this.subtitleMaxLines = 1,
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
            // One node, so a screen reader hears a whole thought instead of a
            // filename and then a path as two unrelated fragments.
            child: Semantics(
              container: true,
              label: <String>[title, ?subtitle].join(', '),
              child: ExcludeSemantics(
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
                        maxLines: subtitleMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
