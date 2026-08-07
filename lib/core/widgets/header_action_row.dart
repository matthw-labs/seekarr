import 'package:flutter/material.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';

/// A shared row layout for media detail header actions.
///
/// Displays an [expanded] widget that fills remaining space, with an
/// optional [trailing] widget (typically an icon-only button) on the right.
class HeaderActionRow extends StatelessWidget {
  /// The primary widget that fills available horizontal space.
  final Widget expanded;

  /// Optional trailing widget, shown to the right of [expanded].
  final Widget? trailing;

  /// How [expanded] and [trailing] line up when they are different heights.
  ///
  /// Centred by default, because the common case is two controls of the same
  /// height. A row whose trailing carries a caption underneath it passes
  /// [CrossAxisAlignment.start] so the two controls' *tops* align and the
  /// caption hangs below, rather than the caption pushing its button up.
  final CrossAxisAlignment crossAxisAlignment;

  const HeaderActionRow({
    super.key,
    required this.expanded,
    this.trailing,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  /// Minimum touch target for every detail action control.
  ///
  /// 48, not the 42 this used to be. 42 is under *both* platform minimums, and
  /// the app already documents 44 as its floor on the detail back button
  /// (`MediaDetailBackButton.targetSize`) — so the shared constant was two
  /// points below a number the codebase writes down for itself, on a row that
  /// includes Delete. One cross-platform constant has to satisfy the larger of
  /// iOS' 44pt and Android's 48dp, which is 48; and 48 is also the height the
  /// promoted primary action takes, so an action band has one height rather
  /// than two.
  ///
  /// Adjacent targets are separated by [AppSpacing.sm] (8dp) or more, at every
  /// reading size — a captioned button's column grows *wider* than its own
  /// square as the caption grows, so the gap between two targets only ever
  /// opens up. Locked by `header_action_row_test.dart`.
  static const double buttonHeight = 48.0;

  /// Shared rounded shape for all detail header action buttons.
  static final _buttonShape = RoundedRectangleBorder(
    borderRadius: AppRadius.borderRadiusXl,
  );

  static ButtonStyle _filledButtonStyle({
    EdgeInsetsGeometry? padding,
    Size? minimumSize,
    Size? fixedSize,
    Color? foregroundColor,
    Color? backgroundColor,
  }) => FilledButton.styleFrom(
    padding: padding,
    minimumSize: minimumSize,
    fixedSize: fixedSize,
    foregroundColor: foregroundColor,
    backgroundColor: backgroundColor,
    shape: _buttonShape,
  );

  /// Creates a [ButtonStyle] for icon-only [FilledButton] trailing widgets.
  ///
  /// Produces a [buttonHeight]×[buttonHeight] square button. Pass
  /// [backgroundColor] and [foregroundColor] for variants like error/delete.
  static ButtonStyle iconOnlyButtonStyle({
    Color? foregroundColor,
    Color? backgroundColor,
  }) => _filledButtonStyle(
    padding: EdgeInsets.zero,
    minimumSize: const Size(buttonHeight, buttonHeight),
    fixedSize: const Size(buttonHeight, buttonHeight),
    foregroundColor: foregroundColor,
    backgroundColor: backgroundColor,
  );

  /// Creates a [ButtonStyle] for expanded [FilledButton.icon] widgets.
  ///
  /// [minimumSize], never `fixedSize`: a fixed height cannot grow, so a label
  /// that no longer fits is broken *inside the word* — which is how the request
  /// button came to read "Requeste / d" at an accessibility reading size. The
  /// button grows instead.
  static ButtonStyle expandedButtonStyle({
    Color? foregroundColor,
    Color? backgroundColor,
    Color? disabledForegroundColor,
    Color? disabledBackgroundColor,
  }) => FilledButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    minimumSize: const Size(double.infinity, buttonHeight),
    foregroundColor: foregroundColor,
    backgroundColor: backgroundColor,
    disabledForegroundColor: disabledForegroundColor,
    disabledBackgroundColor: disabledBackgroundColor,
    shape: _buttonShape,
  );

  static ButtonStyle tonalIconButtonStyle({
    required Color foregroundColor,
    required Color backgroundColor,
    required Color borderColor,
  }) => OutlinedButton.styleFrom(
    padding: EdgeInsets.zero,
    minimumSize: const Size(buttonHeight, buttonHeight),
    fixedSize: const Size(buttonHeight, buttonHeight),
    foregroundColor: foregroundColor,
    backgroundColor: backgroundColor,
    side: BorderSide(color: borderColor),
    shape: _buttonShape,
  );

  static ButtonStyle tonalExpandedButtonStyle({
    required Color foregroundColor,
    required Color backgroundColor,
    required Color borderColor,
  }) => OutlinedButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    minimumSize: const Size(double.infinity, buttonHeight),
    foregroundColor: foregroundColor,
    backgroundColor: backgroundColor,
    side: BorderSide(color: borderColor),
    shape: _buttonShape,
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Expanded(child: expanded),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.sm),
          trailing!,
        ],
      ],
    );
  }
}

/// The idle → busy → held-confirmation glyph for a detail action control.
///
/// One implementation, so the morph cannot drift between the promoted primary
/// action and a captioned icon button. The confirmation is the best interaction
/// on this surface and it has three moving parts that are easy to lose
/// separately: the spinner has to spin for *this* control's work only, the
/// check has to be held long enough to be seen after the eye comes back from
/// the snackbar ([AppAnimation.confirmationHold], owned by the host's timer),
/// and the check has to say "complete" out loud rather than just being green.
class ActionStateGlyph extends StatelessWidget {
  /// The resting glyph.
  final IconData icon;

  /// Accessible name of the control this glyph fronts. The confirmed state
  /// announces '<label> complete'.
  final String label;

  /// Work for this control is in flight: the glyph becomes a spinner.
  final bool isBusy;

  /// The work just landed: the glyph holds a success check.
  final bool isConfirmed;

  /// Foreground for the idle glyph and the spinner.
  ///
  /// Null inherits the enclosing button's `IconTheme`, which is what keeps a
  /// disabled control's glyph dimmed by Material instead of painted at full
  /// strength.
  final Color? color;

  /// The colour this glyph is drawn *on top of*.
  ///
  /// Only the confirmed state needs it. A success green that reads cleanly on
  /// the near-black surface measures around 1.3:1 on Radarr's amber, so on a
  /// filled accent control the check is resolved through
  /// [ServiceTheme.onTint] — which keeps the green's hue and walks its
  /// lightness until it clears AA — rather than shipping a tone that is
  /// invisible on a third of the palette. Defaults to `colorScheme.surface`.
  final Color? fill;

  const ActionStateGlyph({
    super.key,
    required this.icon,
    required this.label,
    this.isBusy = false,
    this.isConfirmed = false,
    this.color,
    this.fill,
  });

  /// Glyph size shared by every detail action control.
  static const double glyphSize = 18;

  /// Spinner diameter, two points under [glyphSize] so the stroke's outer edge
  /// lands roughly where the icon's box did and the control does not jump.
  static const double spinnerSize = 16;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final spinnerColor =
        color ?? IconTheme.of(context).color ?? colorScheme.onSurfaceVariant;

    Widget face;
    if (isBusy) {
      face = Semantics(
        key: const ValueKey('busy'),
        label: label,
        child: SizedBox.square(
          dimension: spinnerSize,
          child: CircularProgressIndicator(strokeWidth: 2, color: spinnerColor),
        ),
      );
    } else if (isConfirmed) {
      face = Icon(
        Icons.check_rounded,
        key: const ValueKey('confirmed'),
        size: glyphSize,
        // tertiary is the theme's success signal green.
        color: ServiceTheme.onTint(
          colorScheme.tertiary,
          surface: fill ?? colorScheme.surface,
          tintAlpha: 0,
        ),
        semanticLabel: '$label complete',
      );
    } else {
      face = Icon(
        icon,
        key: const ValueKey('idle'),
        size: glyphSize,
        color: color,
        semanticLabel: label,
      );
    }

    if (reduceMotion) return face;

    return AnimatedSwitcher(
      duration: AppAnimation.durationSm,
      switchInCurve: AppAnimation.emphasizedCurve,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.7, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      child: face,
    );
  }
}

/// A captioned icon action button for a detail action band.
///
/// The caption is the whole point of the widget. The column this replaces was a
/// hard `SizedBox(width: 58)` holding a `fontSize: 9` label at `maxLines: 1`
/// with an ellipsis, so at an accessibility reading size "Interactive" and
/// "Auto Search" both rendered as "Inter…" / "Auto…" — while "Delete", the one
/// control that should be hardest to hit, kept its full label. And because the
/// caption is `ExcludeSemantics`'d while the icon carries the accessible name,
/// VoiceOver stayed perfectly correct: the low-vision *sighted* user was the
/// only one who lost the disambiguator.
///
/// So the caption is `labelSmall` at the 11pt floor, two lines, **wrapping**
/// rather than eliding, in a measure that grows with the reading size on the
/// same clamp the caption is painted at.
class HeaderActionButton extends StatelessWidget {
  /// The resting glyph.
  final IconData icon;

  /// The visible caption, and the accessible name unless [semanticLabel]
  /// overrides it. Keep it to one or two short words.
  final String label;

  /// A richer spoken name, when the caption has to stay short.
  final String? semanticLabel;

  final VoidCallback? onPressed;

  /// Work for this button is in flight.
  final bool isBusy;

  /// The work just landed; holds a success check.
  final bool isConfirmed;

  const HeaderActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.semanticLabel,
    this.onPressed,
    this.isBusy = false,
    this.isConfirmed = false,
  });

  /// Measure the caption wraps inside.
  ///
  /// The square plus one `xl` step. Wide enough for a single word of a dozen
  /// characters at the 11pt floor, so a one-word caption sits on one line rather
  /// than being broken mid-word — Flutter's answer to a word too wide for its
  /// line is to split it, and "Trailer / s" is worse than a second line.
  ///
  /// **Deliberately not grown by the reading size.** Three of these in a row
  /// alongside an expanded primary is a fixed horizontal budget on a 360dp
  /// phone; letting each column widen 1.6× would take 90pt off the primary and
  /// squeeze *its* label into breaking instead. The caption takes a second line
  /// instead, which is the same trade the Column Floor Rule makes — give up
  /// density, never legibility. Its growth is bounded by the clamped scaler
  /// below rather than by this number.
  static const double captionMeasure =
      HeaderActionRow.buttonHeight + AppSpacing.xl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // Compact chrome cannot usefully track a 3x reading size. There is no fixed
    // height here to grow — the column is free — so the clamp is all that is
    // needed: past 1.6x the caption stops growing and keeps both of its lines
    // instead of eliding one.
    final scaler = TextScaleMetrics.clampedScalerOf(context);
    final foreground = colorScheme.onSurfaceVariant;

    return SizedBox(
      width: captionMeasure,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: HeaderActionRow.buttonHeight,
            child: OutlinedButton(
              onPressed: isBusy ? null : onPressed,
              style: HeaderActionRow.tonalIconButtonStyle(
                foregroundColor: foreground,
                backgroundColor: colorScheme.onSurface.withValues(alpha: 0.06),
                borderColor: colorScheme.outlineVariant,
              ),
              child: ActionStateGlyph(
                icon: icon,
                label: semanticLabel ?? label,
                isBusy: isBusy,
                isConfirmed: isConfirmed,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // The button node above already carries the spoken name, so the
          // caption is excluded rather than announced twice. It exists for the
          // eye — which is exactly the reader the old 9pt ellipsised label
          // failed.
          ExcludeSemantics(
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: scaler),
              child: Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                // Ellipsis is the floor, not the behaviour: two lines in a
                // measure that grows to 1.6x holds every caption this app
                // ships.
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall!
                    .weight(FontWeight.w600)
                    .copyWith(color: foreground),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
