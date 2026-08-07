import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/media_detail_header_metrics.dart';

/// The media detail pages' back affordance, in one of two poses.
///
/// [reveal] interpolates between them: `0` sits over backdrop artwork (a plate
/// floating on the photograph), `1` sits on chrome (no plate — the collapsed
/// glass bar is the ground by then). The collapsing hero drives it
/// continuously; the placeholder and error pages pin it at `1`, because they
/// have no artwork for a plate to float on.
///
/// Extracted so those two hosts cannot drift apart: the plate schedule, the
/// foreground rule, the [discSize]-inside-[targetSize] target and the tooltip
/// all live here.
///
/// ## Why the plate is `surface`-toned and the glyph never inverts
///
/// The previous pose was a black wash carrying a white glyph, morphing to an
/// `onSurface` glyph with no wash. Both endpoints read, but nothing in between
/// did, and the endpoint over artwork was thin:
///
/// * Thin endpoint. `black@0.45` over a *bright* backdrop composites to
///   `#8C8C8C`, which gives a white glyph 3.35:1 — over WCAG 1.4.11's 3:1 floor
///   for a graphical object by a hair, and visibly washed out on a 22pt
///   chevron. That is the reported defect: legible over a night sky, near
///   invisible over a lit wall.
/// * Impossible middle. In light theme the two poses are *inverted* (light
///   glyph on dark ground → dark glyph on light ground). Any continuous path
///   between an inverted pair passes through the point where foreground and
///   background luminance are equal, i.e. 1:1. Measured on the old lerp at
///   `reveal` 0.5 over a bright backdrop: 2.07:1. No amount of retiming fixes
///   a crossing — only removing the inversion does.
///
/// So the polarity is fixed for the whole range: the glyph is always
/// [ColorScheme.onSurface] and the plate is always [ColorScheme.surface], the
/// one pair the theme guarantees. In dark theme that is visually the pose it
/// already was (near-black plate, near-white glyph). In light theme the plate
/// becomes light and the chevron dark — the light theme's own chrome language,
/// and the same treatment a light-mode map or photo viewer uses over imagery.
/// It also retires this file's `Colors.black`/`Colors.white` exception: every
/// colour here now comes from the scheme.
///
/// [plateAlpha] is not a taste value. It is the smallest opacity at which the
/// plate composited over the *worst possible* artwork — pure white in dark
/// theme, pure black in light theme, with no credit for the hero's scrim — still
/// clears 4.5:1 against `onSurface`. Solving the sRGB relative-luminance
/// equation for that bound gives 0.528 (light) and 0.594 (dark); 0.62 carries
/// headroom over both. Ratios below are *measured off the painted pixels* by
/// `media_detail_back_button_test.dart`, at zero scrim credit — the widget over
/// a synthetic solid backdrop, nothing else in the stack:
///
/// | theme | artwork  | plate composite | ratio to `onSurface` |
/// |-------|----------|-----------------|----------------------|
/// | dark  | #FFFFFF  | ~#67686E        | 4.98:1               |
/// | dark  | #000000  | ~#07070A        | 17.99:1              |
/// | light | #000000  | ~#979798        | 6.08:1               |
/// | light | #FFFFFF  | ~#F8F8F9        | 16.71:1              |
///
/// The two failure modes are complementary, which is why one number covers
/// arbitrary photography: artwork that tones *toward* the plate makes the plate
/// itself disappear, and that is exactly the artwork against which the glyph is
/// at its most legible.
class MediaDetailBackButton extends StatelessWidget {
  /// 0 = over artwork, 1 = on chrome.
  final double reveal;

  /// Overrides the default `Navigator.maybePop`.
  ///
  /// Rarely needed: the detail routes are nested under their service
  /// dashboards, so go_router builds a poppable parent stack even for a cold
  /// deep link.
  final VoidCallback? onBack;

  const MediaDetailBackButton({super.key, this.reveal = 1, this.onBack});

  /// Visual plate size; the tap target is padded out around it.
  ///
  /// 36 is a *painted* size, deliberately smaller than the target: a 48pt disc
  /// over artwork reads as a button competing with the poster, where a 36pt one
  /// reads as chrome. The target grows around it instead — see [targetSize] —
  /// and [gutterAlignedLeftInset] keeps the plate's leading edge on the content
  /// gutter whatever the target does.
  static const double discSize = 36;

  /// The minimum touch target this button always occupies.
  ///
  /// 48, matching [HeaderActionRow.buttonHeight]: one cross-platform constant
  /// has to satisfy the larger of iOS' 44pt and Android's 48dp, and the app had
  /// been carrying two different answers (44 here, 48 on the action band) for
  /// the same floor. Raising it changes nothing that is painted — the plate is
  /// still [discSize] — only the hit box and, through
  /// [gutterAlignedLeftInset], the inset that keeps the plate on the gutter.
  static const double targetSize = 48;

  /// Left inset that lands the *plate's* leading edge on the content gutter.
  ///
  /// The target is centred on the plate, so the plate starts
  /// `(targetSize - discSize) / 2` inside the target's own box. Deriving the
  /// inset from both constants means [targetSize] can move again without the
  /// chevron drifting off the [AppSpacing.lg] column the hero copy and every
  /// body slot align to — which is exactly the coupling that made the old 44
  /// unraisable.
  static const double gutterAlignedLeftInset =
      AppSpacing.lg - (targetSize - discSize) / 2;

  /// Horizontal room the collapsed bar must reserve on each side so its centred
  /// title never collides with this button.
  static const double barClearance =
      gutterAlignedLeftInset + targetSize + AppSpacing.md;

  /// Plate opacity while the plate is the ground. See the class doc for the
  /// derivation — this is a computed floor, not a taste value.
  static const double plateAlpha = 0.62;

  /// Where the plate starts handing the ground back to the chrome.
  ///
  /// Held at full strength until here, then released to nothing by `reveal` 1,
  /// because that window is the only part of the range where the chrome can
  /// take over: `barReveal` 0.82 corresponds to collapse `t` 0.75, where
  /// `AppGradients.heroScrim` measures ~95% opaque behind the button (the
  /// header is short by then, so the button sits in the scrim's deep end
  /// rather than its transparent top). A plate that faded linearly from
  /// `reveal` 0 would be at half strength around `reveal` 0.5, where the scrim
  /// behind the button is still thin enough for bright artwork to read through.
  static const double plateReleaseStart = 0.82;

  /// Plate fill at [reveal], over whatever is behind it.
  ///
  /// Public and pure so the contrast guarantee in the class doc is asserted
  /// arithmetically rather than eyeballed: the test composites this over
  /// synthetic bright and dark artwork and measures the real WCAG ratio.
  static Color plateColorFor(ColorScheme scheme, double reveal) {
    final release = ((reveal - plateReleaseStart) / (1 - plateReleaseStart))
        .clamp(0.0, 1.0);
    return scheme.surface.withValues(alpha: plateAlpha * (1 - release));
  }

  /// Glyph colour. Deliberately independent of [reveal] — see the class doc:
  /// an inverting foreground cannot clear AA at every point in the morph.
  static Color glyphColorFor(ColorScheme scheme) => scheme.onSurface;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox.square(
      dimension: targetSize,
      // Loosens the constraints so the button can hold its 36pt plate while
      // `MaterialTapTargetSize.padded` grows the *hit box* out to fill this
      // square. A tight inner `SizedBox(36)` — what this used to be — capped
      // the padded hit box at 36 too, so 8pt of the documented target was
      // decoration: a tap 2pt inside the corner missed the button entirely.
      child: Center(
        child: IconButton.filled(
          onPressed: onBack ?? () => Navigator.of(context).maybePop(),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          style: IconButton.styleFrom(
            backgroundColor: plateColorFor(colorScheme, reveal),
            foregroundColor: glyphColorFor(colorScheme),
            padding: EdgeInsets.zero,
            // `minimumSize` as well as `fixedSize`: `fixedSize` is clamped
            // *into* the resolved minimum, and `IconButton`'s M3 default
            // minimum is 48 — so on its own it would paint a 48pt plate (40 on
            // a desktop's compact density). Pinning the density too keeps the
            // plate's leading edge on the content gutter on every platform
            // rather than letting it drift 2pt with `VisualDensity`.
            minimumSize: const Size.square(discSize),
            fixedSize: const Size.square(discSize),
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          icon: const Icon(Icons.chevron_left_rounded, size: 22),
        ),
      ),
    );
  }

  /// Top inset that lands the button over artwork ([reveal] 0) or centred in
  /// the collapsed glass bar ([reveal] 1).
  static double topOffsetFor(BuildContext context, double reveal) {
    final topPadding = MediaQuery.paddingOf(context).top;
    return lerpDouble(
      topPadding + AppSpacing.md,
      topPadding +
          math.max(
            0,
            (MediaDetailHeaderMetrics.collapsedHeight(context) - targetSize) /
                2,
          ),
      reveal,
    )!;
  }
}
