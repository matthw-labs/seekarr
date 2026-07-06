import 'package:flutter/material.dart';

import 'package:seekarr/core/theme.dart';

/// Centralised gradient tokens for Seekarr.
///
/// Gradients were previously hand-rolled inline across onboarding, media detail
/// backdrops and poster scrims. Routing them through [AppGradients] keeps the
/// premium look consistent and makes the brand language editable in one place.
class AppGradients {
  AppGradients._();

  /// Indigo → violet brand mark (logo tiles, primary accents).
  static const LinearGradient brandMark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.seerr, AppColors.sonarr],
  );

  /// Active progress / selection fill (indigo → light indigo).
  static const LinearGradient progressActive = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [AppColors.primary, AppColors.primaryLight],
  );

  /// Bottom-up scrim laid over a poster/backdrop so foreground text and badges
  /// stay legible. Fades from the given [surface] colour to transparent.
  static LinearGradient heroScrim(Color surface) {
    return LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [
        surface,
        surface.withValues(alpha: 0.85),
        surface.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.35, 1.0],
    );
  }

  /// Lighter top-down scrim for badges pinned to the top corner of a poster.
  static LinearGradient posterScrim(Color shadow) {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [shadow.withValues(alpha: 0.45), shadow.withValues(alpha: 0.0)],
      stops: const [0.0, 0.6],
    );
  }

  /// Ambient background wash: two soft accent radials over the base surface,
  /// used behind headers and the onboarding canvas to add depth.
  static RadialGradient ambientBackground(
    ColorScheme scheme, {
    Color? accent,
    Alignment center = const Alignment(-0.7, -0.9),
  }) {
    final glow = (accent ?? scheme.primary);
    return RadialGradient(
      center: center,
      radius: 1.4,
      colors: [
        glow.withValues(
          alpha: scheme.brightness == Brightness.dark ? 0.16 : 0.10,
        ),
        scheme.surface.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 1.0],
    );
  }

  /// Accent-tinted radial glow used inside signature service cards.
  static RadialGradient serviceGlow(
    Color accent, {
    Alignment center = Alignment.topRight,
    double radius = 1.2,
  }) {
    return RadialGradient(
      center: center,
      radius: radius,
      colors: [accent.withValues(alpha: 0.22), accent.withValues(alpha: 0.0)],
      stops: const [0.0, 1.0],
    );
  }
}
