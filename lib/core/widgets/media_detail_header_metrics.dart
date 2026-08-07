import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

import 'package:cupola/core/text_scale.dart';

/// Extent math for the media detail pages' pinned hero header.
///
/// The header collapses from a full backdrop hero into a slim glass title bar.
/// Both extents grow with the reading size via [TextScaleMetrics], but on
/// different clamps: the expanded hero holds a multi-line summary
/// ([heroMaxScaleFactor], 1.6x), the collapsed bar is single-line chrome
/// (1.3x). The `max` guard in [maxExtent]
/// exists because those two clamps could otherwise cross at extreme scales and
/// trip the framework's `minExtent <= maxExtent` assert.
class MediaDetailHeaderMetrics {
  MediaDetailHeaderMetrics._();

  /// Prototype hero height at the default reading size, excluding safe area.
  static const double baseExpandedHeight = 236.0;

  /// Collapsed bar body: a 44pt tap target with breathing room.
  static const double baseCollapsedHeight = 52.0;

  /// The reading-size ceiling the expanded hero is *both* grown by and laid out
  /// at.
  ///
  /// [expandedHeight] buys room for this much text growth and [heroTextScaler]
  /// paints the copy on the same ceiling — one constant, so the two cannot
  /// drift apart again. A box grown at one clamp and painted at another is
  /// normally an overflow stripe; here it was worse than a stripe, because the
  /// hero's copy is bottom-anchored inside the header's `ClipRect`, so the
  /// excess was cut silently off the *top* — and the top of that stack is the
  /// status badge, the one thing this surface exists to answer.
  static const double heroMaxScaleFactor =
      TextScaleMetrics.defaultMaxScaleFactor;

  /// Text scaler for the expanded hero's copy, clamped to [heroMaxScaleFactor].
  ///
  /// Past the ceiling the title ellipsises — it is capped at two lines — rather
  /// than pushing the badge up out of the header.
  static TextScaler heroTextScaler(BuildContext context) =>
      TextScaleMetrics.clampedScalerOf(
        context,
        maxScaleFactor: heroMaxScaleFactor,
      );

  /// Text inside the expanded hero at the default reading size: the status
  /// badge (23) + 4 + two title lines (50) + 4 + the metadata line (20) + 8 +
  /// two runs of genre/tag chips (23 + 4 + 23) = 159.
  ///
  /// Measured, not estimated — and the chip row is budgeted on purpose. The
  /// cheaper fix was to drop the chips above a reading threshold, and it is
  /// wrong here: the hero's tag slot is not uniformly a duplicate of the body.
  /// Radarr/Sonarr/Seerr do repeat their genres further down, but Lidarr passes
  /// album/track counts and Bazarr a subtitle profile, and neither is written
  /// anywhere else on the page. Deleting a fact at exactly the reading size
  /// where hunting for it costs the most is a worse trade than the ~35pt of
  /// extra hero this budget spends at the 1.6x ceiling.
  ///
  /// Two chip runs is the phone case at the default size; the third run a long
  /// genre name buys at 1.6x still clears, because the box grows by
  /// `(s - 1) x 159` while the copy grows by `(s - 1) x 143` — the four gaps
  /// between the runs do not scale — on top of the 61pt of slack the base
  /// height already carries over this stack.
  static const double _heroTextHeight = 159.0;

  /// Text inside the collapsed bar: one titleMedium line.
  ///
  /// Unchanged by the type ramp's new per-role leading, and deliberately so: the
  /// root `DefaultTextHeightBehavior` sets `applyHeightToFirstAscent` and
  /// `applyHeightToLastDescent` to false, so leading opens the gaps *between*
  /// lines while a block's outer edges keep Inter's natural metrics. This bar's
  /// title is one line, so it measures what it always did.
  static const double _barTextHeight = 20.0;

  /// Collapsed bar height at the current reading size.
  static double collapsedHeight(BuildContext context) =>
      TextScaleMetrics.boxHeight(
        context,
        base: baseCollapsedHeight,
        textHeight: _barTextHeight,
        maxScaleFactor: TextScaleMetrics.singleLineChromeMaxScaleFactor,
      );

  /// Expanded hero height at the current reading size.
  static double expandedHeight(BuildContext context) =>
      TextScaleMetrics.boxHeight(
        context,
        base: baseExpandedHeight,
        textHeight: _heroTextHeight,
        maxScaleFactor: heroMaxScaleFactor,
      );

  static double minExtent(BuildContext context) =>
      MediaQuery.paddingOf(context).top + collapsedHeight(context);

  static double maxExtent(BuildContext context) => math.max(
    MediaQuery.paddingOf(context).top + expandedHeight(context),
    minExtent(context) + 1,
  );
}

/// All hero-collapse visuals derived from a single scroll progress [t]
/// (0.0 fully expanded → 1.0 fully collapsed), on staged intervals.
///
/// A curve applied to a scroll-driven `t` is a remap of the user's own finger
/// position, not an animation: there is no animator and no clock, so these
/// stages do NOT need to check Reduce Motion. What Reduce Motion suppresses is
/// only motion that is independent of the finger — the parallax translation,
/// the overscroll stretch, and the poster scale/lift, which read as the scene
/// moving on its own. Those getters flatten when [reduceMotion] is set; the
/// scrim, bar reveal and glow keep working because they are the functional
/// legibility/orientation layer.
class MediaDetailHeroPhase {
  /// Collapse progress: 0.0 fully expanded, 1.0 fully collapsed.
  final double t;

  /// Whether the platform requests reduced motion.
  final bool reduceMotion;

  const MediaDetailHeroPhase({required this.t, this.reduceMotion = false});

  static double _seg(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  /// Hero title/metadata/badge dissolve early — they are about to be replaced
  /// by the collapsed bar's title.
  double get summaryFade => 1 - _seg(t, 0.10, 0.45);

  /// The scrim deepens as art gives way to chrome.
  double get scrimDepth => _seg(t, 0.0, 0.80);

  /// The glass bar materialises well before the poster is fully gone.
  double get barReveal => Curves.easeOutCubic.transform(_seg(t, 0.62, 0.92));

  /// Poster shrink while collapsing. Decorative — flat under Reduce Motion.
  double get posterScale =>
      reduceMotion ? 1 : lerpDouble(1.0, 0.86, _seg(t, 0.20, 0.90))!;

  /// Poster slide progress toward the bar. Decorative.
  double get posterLift => reduceMotion ? 0 : _seg(t, 0.0, 1.0);

  /// Fraction of scroll speed the backdrop moves at. Decorative.
  double get parallaxFactor => reduceMotion ? 0 : 0.35;

  /// The room light dims while collapsing, but never goes out
  /// (Room Light Rule: the accent stays the screen's orientation cue).
  double get glowAlpha => lerpDouble(0.22, 0.12, _seg(t, 0.30, 0.75))!;
}
