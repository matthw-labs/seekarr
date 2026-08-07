import 'package:flutter/material.dart';
import 'package:seekarr/core/app_animation.dart';
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

  /// Whether status changes animate (tone cross-tween, icon/label switcher,
  /// swept progress ring). Only the `.animated` constructor sets this — the
  /// default badge stays static because it appears on twenty-odd surfaces
  /// (poster overlays, queue rows, activity feeds) where a per-cell animation
  /// would be noise.
  final bool _animated;

  const StatusBadge({
    super.key,
    required this.info,
    this.compact = false,
    this.iconOnly = false,
    this.excludeFromSemantics = false,
  }) : _animated = false;

  /// Full badge whose tone, glyph and progress ring animate between resolved
  /// statuses. Used on the media detail hero, where a single badge changing
  /// state (missing → downloading → available) is the point of the surface.
  /// Renders identically to the default under Reduce Motion.
  const StatusBadge.animated({
    super.key,
    required this.info,
    this.excludeFromSemantics = false,
  }) : compact = false,
       iconOnly = false,
       _animated = true;

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
            // A separator ring, not a depth level — this is why it is a single
            // `BoxShadow` rather than an `AppElevation` stack. An 8px mark sits
            // directly on arbitrary poster artwork in a dense row, and without a
            // ring a tone-coloured dot can land on artwork of its own tone and
            // vanish. `colorScheme.shadow` is the token for exactly this ink
            // (`Colors.black` in both schemes, so nothing painted changes) and
            // keeps the file inside the no-raw-`Colors` rule; the back button
            // that used to be cited as the earned exception here no longer holds
            // one.
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.35),
                spreadRadius: 1.5,
              ),
            ],
          ),
        ),
      );
    }

    final foreground = compact ? onAccentColor : accentColor;
    final percentText = _percentText;
    final animate = _animated && !MediaQuery.disableAnimationsOf(context);

    // **Nothing in this badge rolls, and that is a decision rather than an
    // omission** — it is the one surface in the app where a state word genuinely
    // changes and is deliberately left alone.
    //
    // The label was rolled on `.animated` and reverted. This badge is the only
    // reel candidate whose surface *already* had a considered animation: a tone
    // cross-tween, a keyed glyph switcher and a swept progress ring, tuned
    // together for a badge whose changing state is the point of the page. A roll
    // on top of those is a fourth treatment competing with three that work —
    // motion added because it was available, not because anything was missing.
    // It also does not pay for itself: `ReelText` renders one `Text` per
    // grapheme, so rolling the label scattered single-letter `Text` widgets over
    // every detail page, enough to make `find.text('R')` match a slot inside a
    // test asserting a certification is *not* drawn as its own text.
    //
    // The percentage is a separate and firmer no. It updates on every poll while
    // bytes move, so rolling it would leave a queue of eight rows permanently in
    // motion on a two-second clock. A state word changes when the thing it names
    // changes; digits change because time passed. `.tabular` is the right fix for
    // a live number, and it is already applied.
    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      // Keyed by the resolved state (not the live percentage) so the switcher
      // fires on a status change without restarting every progress tick.
      key: animate
          ? ValueKey('${info.availability}-${info.pipeline}-${info.label}')
          : null,
      children: [
        _leading(size: compact ? 10 : 12, color: foreground, animate: animate),
        if (!compact) ...[
          const SizedBox(width: AppSpacing.xs),
          Text(
            info.label,
            style: theme.textTheme.labelSmall!
                .weight(FontWeight.w600)
                .copyWith(color: textColor),
          ),
        ],
        if (percentText != null) ...[
          SizedBox(width: compact ? 2 : AppSpacing.xs),
          Text(
            percentText,
            style: theme.textTheme.labelSmall!
                .weight(FontWeight.w700)
                .tabular
                .copyWith(color: textColor),
          ),
        ],
      ],
    );
    if (animate) {
      content = AnimatedSwitcher(
        duration: AppAnimation.durationSm,
        switchInCurve: AppAnimation.emphasizedCurve,
        child: content,
      );
    }

    Widget badge = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.xs : AppSpacing.sm,
        vertical: compact ? 2 : AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: AppRadius.borderRadiusSm,
        border: Border.all(color: borderColor, width: 1),
      ),
      child: content,
    );

    return _spoken(badge);
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
  ///
  /// When [animate] is set, the ring sweeps to each new value instead of
  /// snapping — the digits beside it stay live and honest, only the arc
  /// eases. A count-up on the numbers themselves was considered and
  /// rejected: a percentage that lags the actual transfer is briefly wrong
  /// on purpose.
  Widget _leading({
    required double size,
    required Color color,
    bool animate = false,
  }) {
    if (info.isActive && info.progress != null) {
      final ring = animate
          ? TweenAnimationBuilder<double>(
              tween: Tween<double>(end: info.progress),
              duration: AppAnimation.durationMd,
              curve: AppAnimation.standardCurve,
              builder: (context, value, _) => CircularProgressIndicator(
                value: value,
                strokeWidth: 2,
                color: color,
                backgroundColor: color.withValues(alpha: 0.25),
              ),
            )
          : CircularProgressIndicator(
              value: info.progress,
              strokeWidth: 2,
              color: color,
              backgroundColor: color.withValues(alpha: 0.25),
            );
      return SizedBox(width: size, height: size, child: ring);
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
