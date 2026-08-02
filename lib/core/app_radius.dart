import 'package:flutter/material.dart';

/// Material Design 3 Border Radius Scale
///
/// Following M3 shape system with consistent corner radii.
/// Use these values for all rounded corners.
class AppRadius {
  AppRadius._();

  /// 0dp - No rounding (sharp corners)
  static const double none = 0;

  /// 4dp - Extra small rounding for subtle curves
  static const double xs = 4;

  /// 8dp - Small rounding for chips, badges
  static const double sm = 8;

  /// 12dp - Medium rounding for cards, containers
  static const double md = 12;

  /// 16dp - Large rounding for dialogs, sheets
  static const double lg = 16;

  /// 20dp - The selected-affordance radius
  ///
  /// Deliberately off the 4/8/12/16/28 ladder, and the one exception to it: this
  /// is the navigation bar's selection indicator, which DESIGN.md pins at 20dp as
  /// the `nav-pill` component. It exists as a token because a second control —
  /// the Activity segment pills — now shares that vocabulary, and "this one is
  /// active" should look the same everywhere. Reach for it only for a selected
  /// state, never as a general corner.
  static const double pill = 20;

  /// 28dp - Extra large rounding for FAB
  static const double xl = 28;

  /// 50dp - Full/circular rounding
  static const double full = 50;

  // --- Pre-built BorderRadius ---

  /// BorderRadius for extra small elements
  static final BorderRadius borderRadiusXs = BorderRadius.circular(xs);

  /// BorderRadius for small elements (chips, badges)
  static final BorderRadius borderRadiusSm = BorderRadius.circular(sm);

  /// BorderRadius for medium elements (cards)
  static final BorderRadius borderRadiusMd = BorderRadius.circular(md);

  /// BorderRadius for large elements (dialogs, sheets)
  static final BorderRadius borderRadiusLg = BorderRadius.circular(lg);

  /// BorderRadius for a selected affordance (nav indicator, segment pills)
  static final BorderRadius borderRadiusPill = BorderRadius.circular(pill);

  /// BorderRadius for extra large elements (FAB)
  static final BorderRadius borderRadiusXl = BorderRadius.circular(xl);

  /// BorderRadius for fully rounded elements
  static final BorderRadius borderRadiusFull = BorderRadius.circular(full);
}
