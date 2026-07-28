import 'package:flutter/material.dart';

import 'package:seekarr/core/app_gradients.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// The full colour bundle for a single service, derived from its accent.
///
/// Single source of truth for service theming. Screens should read
/// [serviceThemeFor] (or [ServiceTheme.fromAccent]) instead of re-deriving
/// accent containers, gradients and glows locally — a pattern that previously
/// diverged (e.g. the onboarding screen tinted Seerr green instead of indigo).
@immutable
class ServiceTheme {
  /// The saturated brand accent.
  final Color accent;

  /// Foreground colour that reads legibly on top of [accent].
  final Color onAccent;

  /// Low-alpha accent fill for soft containers (icon backgrounds, chips).
  final Color softContainer;

  const ServiceTheme({
    required this.accent,
    required this.onAccent,
    required this.softContainer,
  });

  /// Builds a [ServiceTheme] from any accent colour.
  factory ServiceTheme.fromAccent(Color accent) {
    return ServiceTheme(
      accent: accent,
      onAccent: foregroundOn(accent),
      softContainer: accent.withValues(alpha: 0.14),
    );
  }

  /// The legible foreground for text or icons sitting on [background].
  ///
  /// Hard-coding white was wrong for the bright accents in this palette: white
  /// on the amber used by Radarr and SABnzbd measures 2.15:1 and on the success
  /// green 2.28:1, both far below WCAG AA, while black on the same fills clears
  /// 9:1. Picking by luminance keeps every badge legible without giving up the
  /// brand colour.
  static Color foregroundOn(Color background) {
    // 0.5 relative luminance is the crossover where black overtakes white.
    return background.computeLuminance() > 0.45
        ? const Color(0xFF111827) // gray-900, softer than pure black
        : Colors.white;
  }

  /// Accent-tinted radial glow for signature cards.
  RadialGradient get glow => AppGradients.serviceGlow(accent);
}

/// Resolves the [ServiceTheme] for a given service. The accent still lives on
/// [ServiceKey.accent] (backed by `AppColors`), keeping one authority.
ServiceTheme serviceThemeFor(ServiceKey service) {
  return ServiceTheme.fromAccent(service.accent);
}
