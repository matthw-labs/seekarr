import 'package:flutter/material.dart';
import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/service_theme.dart';
import 'package:seekarr/core/status/media_status.dart';
import 'package:seekarr/core/theme.dart';

export 'package:seekarr/core/status/media_status.dart';

/// Renders a resolved [MediaStatusInfo].
///
/// The badge no longer derives anything: the status arrives fully resolved from
/// a per-service resolver in the feature's `domain/` layer. That is deliberate —
/// when the derivation lived here, each caller passed a different `status`
/// string and an item being downloaded rendered as `Missing`.
class StatusBadge extends StatelessWidget {
  final MediaStatusInfo info;

  /// Poster-overlay variant: filled with the tone colour, icon only (plus the
  /// download percentage when known).
  final bool compact;

  /// An 8px tone-coloured dot, for dense poster rails.
  final bool iconOnly;

  const StatusBadge({
    super.key,
    required this.info,
    this.compact = false,
    this.iconOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final seekarrColors =
        theme.extension<SeekarrThemeColors>() ??
        SeekarrThemeColors.defaults(
          brightness: theme.brightness,
          colorScheme: colorScheme,
        );

    final accentColor = _resolveToneColor(colorScheme, info.tone);
    final backgroundColor = compact
        ? accentColor.withValues(alpha: 0.9)
        : seekarrColors.statusBadgeBackground;
    final borderColor = compact
        ? accentColor
        : seekarrColors.statusBadgeForeground.withValues(alpha: 0.12);
    // A compact badge fills with the tone colour, so its foreground must be
    // chosen from that colour's luminance: white on the success green or the
    // warning amber measures ~2.2:1, well below AA.
    final onAccentColor = ServiceTheme.foregroundOn(
      accentColor.withValues(alpha: 1),
    );
    final textColor = compact
        ? onAccentColor
        : seekarrColors.statusBadgeForeground;

    if (iconOnly) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: accentColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              spreadRadius: 1.5,
            ),
          ],
        ),
      );
    }

    final foreground = compact ? onAccentColor : accentColor;
    final percentText = _percentText;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.xs : AppSpacing.sm,
        vertical: compact ? 2 : AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: AppRadius.borderRadiusSm,
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _leading(size: compact ? 10 : 12, color: foreground),
          if (!compact) ...[
            const SizedBox(width: AppSpacing.xs),
            Text(
              info.label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
          if (percentText != null) ...[
            SizedBox(width: compact ? 2 : AppSpacing.xs),
            Text(
              percentText,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: textColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// A determinate ring while bytes are moving, the state icon otherwise.
  Widget _leading({required double size, required Color color}) {
    if (info.isActive && info.progress != null) {
      return SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          value: info.progress,
          strokeWidth: 2,
          color: color,
          backgroundColor: color.withValues(alpha: 0.25),
        ),
      );
    }

    return Icon(statusIconFor(info), size: size, color: color);
  }

  String? get _percentText {
    final progress = info.progress;
    if (progress == null || !info.isActive) return null;
    return '${(progress * 100).round()}%';
  }

  Color _resolveToneColor(ColorScheme colorScheme, StatusTone tone) {
    return switch (tone) {
      StatusTone.primary => colorScheme.primary,
      StatusTone.success => AppColors.success,
      StatusTone.warning => AppColors.warning,
      StatusTone.info => AppColors.info,
      StatusTone.error => colorScheme.error,
      StatusTone.neutral => colorScheme.onSurfaceVariant,
    };
  }
}

/// Maps a resolved status onto its icon.
///
/// Lives with the badge rather than on [MediaStatusInfo] so the status
/// vocabulary stays pure Dart.
IconData statusIconFor(MediaStatusInfo info) {
  final pipeline = info.pipeline;
  if (pipeline != null) {
    return switch (pipeline) {
      MediaPipeline.queued => Icons.schedule_rounded,
      MediaPipeline.downloading => Icons.downloading_rounded,
      MediaPipeline.importPending => Icons.hourglass_bottom_rounded,
      MediaPipeline.importing => Icons.drive_file_move_rounded,
      MediaPipeline.paused => Icons.pause_circle_rounded,
      MediaPipeline.failed => Icons.error_rounded,
    };
  }

  if (info.unmonitored && !info.isAvailable) {
    return Icons.bookmark_border_rounded;
  }

  return switch (info.availability) {
    MediaAvailability.notTracked => Icons.add_circle_rounded,
    MediaAvailability.available => Icons.check_circle_rounded,
    MediaAvailability.upgradable => Icons.upgrade_rounded,
    MediaAvailability.partial => Icons.donut_large_rounded,
    MediaAvailability.missing => Icons.cancel_rounded,
    MediaAvailability.unavailable => Icons.event_rounded,
    MediaAvailability.deleted => Icons.delete_rounded,
    MediaAvailability.unknown => Icons.help_outline_rounded,
  };
}
