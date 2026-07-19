import 'package:flutter/material.dart';

/// Premium elevation tokens for Seekarr.
///
/// Instead of Material's flat `elevation: n` (which tints the surface), Seekarr
/// uses explicit, layered [BoxShadow] stacks that read as soft, physical depth:
/// a tight *contact* shadow plus a wide, low-opacity *ambient* shadow. Shadows
/// are tuned per brightness — deeper and darker on dark surfaces, softer on
/// light ones — so cards separate cleanly from the background at every level.
///
/// Usage:
/// ```dart
/// Container(
///   decoration: BoxDecoration(
///     color: colorScheme.surfaceContainer,
///     borderRadius: AppRadius.borderRadiusMd,
///     boxShadow: AppElevation.level2(colorScheme),
///   ),
/// );
/// ```
class AppElevation {
  AppElevation._();

  static bool _isDark(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark;

  /// Subtle lift for resting cards and list rows.
  static List<BoxShadow> level1(ColorScheme scheme) {
    final dark = _isDark(scheme);
    return [
      BoxShadow(
        color: scheme.shadow.withValues(alpha: dark ? 0.28 : 0.06),
        blurRadius: 6,
        offset: const Offset(0, 2),
      ),
      BoxShadow(
        color: scheme.shadow.withValues(alpha: dark ? 0.18 : 0.04),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ];
  }

  /// Standard elevation for posters, feature cards and elevated surfaces.
  static List<BoxShadow> level2(ColorScheme scheme) {
    final dark = _isDark(scheme);
    return [
      BoxShadow(
        color: scheme.shadow.withValues(alpha: dark ? 0.34 : 0.08),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
      BoxShadow(
        color: scheme.shadow.withValues(alpha: dark ? 0.22 : 0.05),
        blurRadius: 22,
        offset: const Offset(0, 10),
      ),
    ];
  }

  /// Prominent elevation for sheets, popovers and hero surfaces.
  static List<BoxShadow> level3(ColorScheme scheme) {
    final dark = _isDark(scheme);
    return [
      BoxShadow(
        color: scheme.shadow.withValues(alpha: dark ? 0.40 : 0.10),
        blurRadius: 16,
        offset: const Offset(0, 6),
      ),
      BoxShadow(
        color: scheme.shadow.withValues(alpha: dark ? 0.26 : 0.07),
        blurRadius: 36,
        offset: const Offset(0, 18),
      ),
    ];
  }

  /// Floating-glass elevation: a deep ambient shadow plus a 1px top highlight
  /// that reads as light catching the leading edge of a blurred surface.
  ///
  /// Used by the floating navigation bar and other backdrop-blurred surfaces.
  static List<BoxShadow> glass(ColorScheme scheme) {
    final dark = _isDark(scheme);
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.35 : 0.18),
        blurRadius: 32,
        offset: const Offset(0, 8),
      ),
      BoxShadow(
        color: Colors.white.withValues(alpha: dark ? 0.07 : 0.55),
        blurRadius: 0,
        offset: const Offset(0, 1),
      ),
    ];
  }

  /// Accent-tinted glow, used to make signature cards feel lit from within by
  /// their service colour. Layer *under* a card's own neutral elevation.
  static List<BoxShadow> accentGlow(Color accent, {double alpha = 0.28}) {
    return [
      BoxShadow(
        color: accent.withValues(alpha: alpha),
        blurRadius: 24,
        spreadRadius: -6,
        offset: const Offset(0, 8),
      ),
    ];
  }
}
