import 'package:flutter/material.dart';

/// Material Design 3 Animation Constants
///
/// Following M3 motion guidelines for consistent, fluid animations.
/// Use these durations and curves for all animations.
class AppAnimation {
  AppAnimation._();

  // === DURATIONS ===

  /// 100ms - Extra short for micro-interactions (ripples, highlights)
  static const Duration durationXs = Duration(milliseconds: 100);

  /// 200ms - Short for simple state changes
  static const Duration durationSm = Duration(milliseconds: 200);

  /// 300ms - Medium for standard transitions
  static const Duration durationMd = Duration(milliseconds: 300);

  /// 400ms - Long for complex transitions
  static const Duration durationLg = Duration(milliseconds: 400);

  /// 500ms - Extra long for dramatic effects
  static const Duration durationXl = Duration(milliseconds: 500);

  // === M3 EASING CURVES ===

  /// Standard easing for most animations
  /// Use for elements that move across the screen
  static const Curve standardCurve = Curves.easeInOutCubicEmphasized;

  /// Emphasized easing for entering elements
  /// Use for elements appearing on screen
  static const Curve emphasizedCurve = Curves.easeOutCubic;

  /// Emphasized decelerate for elements coming to rest
  static const Curve decelerateCurve = Curves.easeOutQuart;

  /// Emphasized accelerate for elements leaving screen
  static const Curve accelerateCurve = Curves.easeInQuart;

  /// Linear for continuous animations (progress, loading)
  static const Curve linearCurve = Curves.linear;

  // === COMMON ANIMATION CONFIGS ===

  /// Quick fade in/out
  static const Duration fadeDuration = durationSm;

  /// Page transition duration
  static const Duration pageTransitionDuration = durationMd;

  /// Bottom sheet animation
  static const Duration sheetDuration = durationMd;

  /// Shimmer animation cycle
  static const Duration shimmerDuration = Duration(milliseconds: 1500);

  /// How long a transient success confirmation (a check that replaces a
  /// button's icon after an action lands) stays visible before reverting.
  /// Long enough to be seen after the eye returns from the snackbar, short
  /// enough that the control is back to normal by the next glance.
  static const Duration confirmationHold = Duration(milliseconds: 1600);

  // === HELPER METHODS ===

  /// Create a standard curved animation
  static Animation<double> createStandardAnimation(
    AnimationController controller,
  ) {
    return CurvedAnimation(parent: controller, curve: standardCurve);
  }

  /// Create an emphasized animation for entering elements
  static Animation<double> createEnterAnimation(
    AnimationController controller,
  ) {
    return CurvedAnimation(parent: controller, curve: emphasizedCurve);
  }

  /// Create an animation for exiting elements
  static Animation<double> createExitAnimation(AnimationController controller) {
    return CurvedAnimation(parent: controller, curve: accelerateCurve);
  }
}
