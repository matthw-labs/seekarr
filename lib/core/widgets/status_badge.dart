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

  /// Suppresses this badge's own semantics node.
  ///
  /// Set it when an enclosing tile already speaks the status — a poster cell
  /// passing `info.semanticLabel` as its `semanticValue`, say. Without it the
  /// tile and the badge are two stops for one piece of information; with it the
  /// badge is decoration, which is what a coloured dot on a poster is.
  final bool excludeFromSemantics;

  const StatusBadge({
    super.key,
    required this.info,
    this.compact = false,
    this.iconOnly = false,
    this.excludeFromSemantics = false,
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

    final accentColor = statusToneColor(colorScheme, info.tone);
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
      return _spoken(
        Container(
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
        ),
      );
    }

    final foreground = compact ? onAccentColor : accentColor;
    final percentText = _percentText;

    return _spoken(
      Container(
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
      ),
    );
  }

  /// One spoken form for all three variants.
  ///
  /// The `iconOnly` dot is pure colour and the `compact` overlay is colour plus
  /// a glyph, so neither has anything to read. Even the full badge paints only
  /// [MediaStatusInfo.label] and a percentage — the warning carried by the tone
  /// is never written down. So the string always comes from
  /// [MediaStatusInfo.semanticLabel] and the painted children are excluded,
  /// which keeps one code path instead of three and stops the full badge
  /// announcing the same pill twice over.
  ///
  /// No `button:` role: in every call site the tap lives on the enclosing tile.
  Widget _spoken(Widget badge) {
    if (excludeFromSemantics) return ExcludeSemantics(child: badge);

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: info.semanticLabel,
      child: badge,
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
    final percent = info.progressPercent;
    return percent == null ? null : '$percent%';
  }
}

/// The single mapping from a semantic [StatusTone] to a real colour.
///
/// Top-level rather than private to the badge because a status is not always
/// drawn *as* a badge: a queue row tints its progress bar by tone so a failed
/// transfer reads red instead of the service accent, and the Activity feed tints
/// its leading icon well the same way. Every one of those was previously a
/// widget-local `switch` on something other than the resolved status — which is
/// how a `downloadFailed` event ended up rendering in the success green.
///
/// Anything that colours by status calls this. Nothing re-derives it.
Color statusToneColor(ColorScheme colorScheme, StatusTone tone) {
  return switch (tone) {
    StatusTone.primary => colorScheme.primary,
    StatusTone.success => AppColors.success,
    StatusTone.warning => AppColors.warning,
    StatusTone.info => AppColors.info,
    StatusTone.error => colorScheme.error,
    StatusTone.neutral => colorScheme.onSurfaceVariant,
  };
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
      // A transfer that should be moving and is not — distinct from a pause,
      // which the user chose.
      MediaPipeline.stalled => Icons.sync_problem_rounded,
      MediaPipeline.importPending => Icons.hourglass_bottom_rounded,
      MediaPipeline.importBlocked => Icons.block_rounded,
      MediaPipeline.importing => Icons.drive_file_move_rounded,
      MediaPipeline.paused => Icons.pause_circle_rounded,
      // `cloud_off` already means "this service did not answer" elsewhere in the
      // app (the Activity health strip and service tiles); an unreachable
      // download client is the same fact one layer down.
      MediaPipeline.clientUnavailable => Icons.cloud_off_rounded,
      MediaPipeline.failed => Icons.error_rounded,
    };
  }

  if (info.unmonitored && !info.isAvailable) {
    return Icons.bookmark_border_rounded;
  }

  // A status can describe an *event* rather than a thing on disk — a history
  // record, a blocked release — in which case it carries a tone override and no
  // availability. Falling through to the availability switch gave all of those
  // the `unknown` question mark, which is the one glyph that tells the user
  // nothing. Read the severity instead.
  if (info.availability == MediaAvailability.unknown && info.pipeline == null) {
    return switch (info.tone) {
      StatusTone.error => Icons.error_rounded,
      StatusTone.warning => Icons.warning_amber_rounded,
      StatusTone.success => Icons.check_circle_rounded,
      StatusTone.info => Icons.info_rounded,
      StatusTone.primary => Icons.add_circle_rounded,
      StatusTone.neutral => Icons.help_outline_rounded,
    };
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
