import 'package:flutter/material.dart';

import 'package:cupola/core/app_gradients.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

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
  /// 9:1. So the two candidate inks are *measured* against the fill and the
  /// winner is returned. A plain luminance threshold is not enough: the
  /// contrast crossover sits near 0.18 relative luminance, so a mid-luminance
  /// accent (Radarr's 0.44 amber, the 0.41 success green) passes any intuitive
  /// cutoff while white on it still fails — which is exactly how a 0.45
  /// threshold shipped white-on-amber buttons at 2.15:1.
  static Color foregroundOn(Color background) {
    const darkInk = Color(0xFF111827); // gray-900, softer than pure black
    final luminance = background.computeLuminance();
    final whiteContrast = 1.05 / (luminance + 0.05);
    final darkContrast =
        (luminance + 0.05) / (darkInk.computeLuminance() + 0.05);
    return darkContrast >= whiteContrast ? darkInk : Colors.white;
  }

  /// A legible label colour for text drawn **on a low-alpha tint of its own
  /// accent** — a selected nav pill, an accent chip, a segment pill.
  ///
  /// This is the second half of DESIGN.md's Luminance Rule, and it is a different
  /// problem from [foregroundOn]. There the accent is an opaque *fill* and the
  /// question is which foreground survives on top of it. Here the accent is the
  /// *text* and the background is a translucent tint of that same accent, so the
  /// surface underneath is part of the contrast calculation: the composite, not
  /// the accent, is what the label is measured against.
  ///
  /// Getting this wrong is invisible in development. Measured against
  /// `surface-light`, Radarr's amber on its own 12% tint comes out around 1.80:1
  /// and the success green around 1.88:1, against a 4.5:1 requirement — while the
  /// identical chips in dark theme measure about 7.7:1 and pass comfortably. A
  /// pill that reads perfectly at night can be effectively invisible in daylight,
  /// which is why checking the dark theme proves nothing about the light one.
  ///
  /// So: keep the accent's hue, and walk its lightness away from the composite
  /// until it clears AA. One code path covers both themes, and it has to —
  /// measured over their own pill tints, the Seerr indigo lands at 3.48:1 in light
  /// **and 3.80:1 in dark**, and the section purple at 3.08:1 and 4.26:1. Dark
  /// theme is more forgiving, not safe: a mid-luminance accent fails there too,
  /// so a "light theme only" fix would have left half the palette failing.
  ///
  /// Bright accents (Radarr's amber, the section cyan) do pass on the first check
  /// in dark and are returned untouched.
  static Color onTint(
    Color accent, {
    required Color surface,
    required double tintAlpha,
  }) {
    final background = Color.alphaBlend(
      accent.withValues(alpha: tintAlpha),
      surface,
    );

    if (_contrastRatio(accent, background) >= _minBodyContrast) return accent;

    // Direction is derived, not assumed: the same accent has to escape a
    // near-white composite in light theme and a near-black one in dark.
    final darken = background.computeLuminance() > 0.5;
    final hsl = HSLColor.fromColor(accent);

    for (var step = 1; step <= _lightnessSteps; step++) {
      final progress = step / _lightnessSteps;
      final lightness = darken
          ? hsl.lightness * (1 - progress)
          : hsl.lightness + (1 - hsl.lightness) * progress;
      final candidate = hsl.withLightness(lightness.clamp(0.0, 1.0)).toColor();

      if (_contrastRatio(candidate, background) >= _minBodyContrast) {
        return candidate;
      }
    }

    // No point on this hue clears it — a very light tint under a very light
    // accent. Better a legible neutral than a brand-coloured smudge.
    return foregroundOn(background);
  }

  /// WCAG AA for body-sized text.
  static const double _minBodyContrast = 4.5;

  /// Granularity of the lightness walk. Fine enough to keep the result close to
  /// the original accent, coarse enough to stay cheap in a build method.
  static const int _lightnessSteps = 24;

  static double _contrastRatio(Color foreground, Color background) {
    final a = foreground.computeLuminance();
    final b = background.computeLuminance();
    final lighter = a > b ? a : b;
    final darker = a > b ? b : a;
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Accent-tinted radial glow for signature cards.
  RadialGradient get glow => AppGradients.serviceGlow(accent);
}

/// Resolves the [ServiceTheme] for a given service. The accent still lives on
/// [ServiceKey.accent] (backed by `AppColors`), keeping one authority.
ServiceTheme serviceThemeFor(ServiceKey service) {
  return ServiceTheme.fromAccent(service.accent);
}
