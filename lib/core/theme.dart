import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cupola/core/app_radius.dart';

/// Builds a [TextStyle] backed by the bundled Inter variable font.
///
/// Every style goes through here so three things are impossible to forget:
/// the `wght` axis (see [AppTheme.interVariations] — a bare [FontWeight] does
/// not reach it), the optical size, and Inter's own tracking.
TextStyle _inter({
  Color? color,
  required double fontSize,
  required FontWeight fontWeight,
  required double height,
  required Brightness brightness,
  double? letterSpacing,
  List<FontFeature>? fontFeatures,
}) {
  return TextStyle(
    fontFamily: AppTheme.fontFamily,
    color: color,
    fontSize: fontSize,
    fontWeight: fontWeight,
    fontVariations: AppTheme.interVariations(fontWeight, fontSize),
    height: height,
    letterSpacing:
        letterSpacing ?? AppTheme.interTracking(fontSize, brightness),
    fontFeatures: fontFeatures,
  );
}

/// Type-level helpers that have to reach Inter's variable axes.
///
/// These exist because [TextStyle.copyWith] is a trap on a variable font: it
/// will happily change [TextStyle.fontWeight] and leave `fontVariations`
/// pointing at the old weight, so the text keeps rendering at the weight it
/// had. Re-weight through [weight] instead.
extension CupolaTextStyle on TextStyle {
  /// Re-weights this style so the change actually reaches Inter's `wght` axis.
  ///
  /// The bundled Inter is a single variable face registered at weight 400.
  /// Flutter resolves `fontWeight: FontWeight.w800` against that one face,
  /// finds it, and never touches the axis — so the glyphs stay Regular and the
  /// only difference is whatever synthetic emboldening Skia decides to add.
  /// Measured: `w400` through `w900` all lay out to the identical advance
  /// width, while an explicit `wght` variation does not.
  ///
  /// The optical size is carried over rather than recomputed, so re-weighting a
  /// display style does not quietly hand it back the text-size drawing.
  TextStyle weight(FontWeight weight) {
    double? opticalSize;
    final variations = fontVariations;
    if (variations != null) {
      for (final variation in variations) {
        if (variation.axis == 'opsz') {
          opticalSize = variation.value;
          break;
        }
      }
    }
    return copyWith(
      fontWeight: weight,
      fontVariations: [
        FontVariation('wght', weight.value.toDouble()),
        FontVariation(
          'opsz',
          opticalSize ?? AppTheme.opticalSize(fontSize ?? 14),
        ),
      ],
    );
  }

  /// Locks digits to a single advance width.
  ///
  /// The Tabular Rule: anything that updates in place — a transfer rate, a
  /// percentage, a queue count — jitters as it counts with proportional digits.
  TextStyle get tabular =>
      copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  /// Switches a style onto the monospaced family, for code, logs and data.
  ///
  /// Keeps the size, colour and line height it already had — a fingerprint or a
  /// log line still belongs to the role it was set in, it just needs columns
  /// that line up. See [AppTheme.monoFontFamily] for why this is not a literal.
  TextStyle get mono => copyWith(
    fontFamily: AppTheme.monoFontFamily,
    fontFamilyFallback: AppTheme.monoFontFamilyFallback,
    // Inter's axes mean nothing to the platform mono face, and a mono face is
    // already spaced on a fixed advance — tracking it fights the grid.
    fontVariations: const [],
    letterSpacing: 0,
    fontFeatures: const [FontFeature.slashedZero()],
  );
}

/// Seerr-inspired color palette for Seekarr
///
/// Colors extracted from Seerr source code (Tailwind config)
/// Provides both dark and light theme variants while maintaining
/// the signature indigo accent color.
class AppColors {
  AppColors._();

  // === SERVICE ACCENTS ===
  static const Color seerr = Color(0xFF6366F1);
  static const Color radarr = Color(0xFFF59E0B);
  static const Color sonarr = Color(0xFF8B5CF6);
  static const Color lidarr = Color(0xFFEC4899);
  static const Color qbittorrent = Color(0xFF2F67BA);
  static const Color bazarr = Color(0xFF25A7DF);
  static const Color truenas = Color(0xFF0095D5); // TrueNAS blue
  static const Color dockge = Color(0xFF058373); // Dockge teal
  static const Color prowlarr = Color(0xFFE66000); // Prowlarr orange
  static const Color readarr = Color(0xFFC0392B); // Readarr red
  static const Color sabnzbd = Color(0xFFF0A800); // SABnzbd amber/gold
  static const Color nzbget = Color(0xFF0F9D58); // NZBGet green
  static const Color unraid = Color(0xFFFF8C2B); // Unraid orange
  static const Color jellyfin = Color(0xFFAA5CC3); // Jellyfin purple

  /// Transmission crimson — the brand's red family, walked off its own hex for
  /// the same reason [plex] is walked off Plex gold.
  ///
  /// Transmission's mark is a plain red that lands ΔE 5.3 from [readarr] and
  /// 6.1 from [error]: three near-identical reds, one of which is the alarm
  /// tone. At the 8pt source dot on the merged Recently Added rail, and at the
  /// 18pt glyph on a folded matrix cell, that is not a distinguishable colour —
  /// it is a red smear that could be a book, a torrent, or a failure. Rotating
  /// toward crimson keeps it unmistakably Transmission red while clearing
  /// ΔE 8.8 from the alarm tone and 10.8 from Readarr. For reference, the
  /// tightest pair already shipping is [radarr]/[sabnzbd] at ΔE 4.8.
  static const Color transmission = Color(0xFFE11D48);

  /// Nginx Proxy Manager vermilion — the brand value, used unchanged.
  ///
  /// Unlike [transmission] and [plex] this one needed no adjustment: it sits
  /// ΔE 9.2 from [prowlarr]'s orange and 8.3 from [error], comfortably above
  /// the palette's existing floor, because it is a *red*-orange and the crowded
  /// band above it ([unraid], [plex], [radarr], [sabnzbd]) is amber.
  static const Color nginxProxyManager = Color(0xFFF15833);

  /// Plex bronze — deliberately **not** Plex's brand gold `#E5A00D`.
  ///
  /// The brand value is unusable here, and measurably so. In CIE Lab it sits
  /// ΔE 5 from [sabnzbd] and ΔE 8 from [warning] — and [warning] and [radarr]
  /// are already the same byte value — so brand gold would have been the fourth
  /// amber in a five-way tie that includes the alarm tone. Two consequences,
  /// both fatal: the 8pt source dot on the merged Recently Added rail could not
  /// distinguish a Plex item from a Radarr or SABnzbd one, and the Stream
  /// dashboard's whole focal moment — a transcoding session lighting its reason
  /// in [warning] — would have been invisible against a room lit by the Plex
  /// accent itself.
  ///
  /// This value keeps the brand's hue family (34° against the brand's 41°, so it
  /// still reads as Plex gold) while clearing ΔE 18 from every existing amber
  /// and 20 from the alarm tone. It resolves to 5.05:1 as a label over its own
  /// 14% tint in dark; light theme still goes through `ServiceTheme.onTint`,
  /// which brand gold also required (it measured 1.84:1 there).
  static const Color plex = Color(0xFFC97A16);

  // === NAV SECTION ACCENTS ===
  //
  // One per canonical tab, so the floating nav bar's selected pill actually
  // differs by section. The bar has always taken a per-destination accent and
  // DESIGN.md has always described the pill as carrying "that destination's
  // accent" — but every `NavTab` passed `primary`, so the mechanism existed and
  // never showed a difference.
  //
  // These are **sections, not services**, and the hues are chosen accordingly:
  //
  // - Nothing here may borrow from the status vocabulary (`success`, `warning`,
  //   `error`, `info`). Status is a closed set, and a green or amber pill in
  //   permanent chrome would read as a health signal (The Closed Tone Rule).
  // - Nothing here should be mistaken for a service's identity, so the set stays
  //   in the cool, instrument-panel end of the palette rather than reaching for
  //   the alarm hues.
  // - Services keeps `primary`: it is the app's own colour and the home tab.
  static const Color navServices = primary;
  static const Color navActivity = Color(0xFF06B6D4); // cyan-500
  static const Color navSearch = Color(0xFFA855F7); // purple-500
  static const Color navSettings = Color(0xFF14B8A6); // teal-500

  // === PRIMARY (Seerr Indigo) ===
  static const Color primary = seerr;
  static const Color primaryDark = Color(0xFF4F46E5); // indigo-600
  static const Color primaryLight = Color(0xFF818CF8); // indigo-400
  static const Color primaryLighter = Color(0xFFA5B4FC); // indigo-300

  // === DARK THEME SURFACES ===
  // Deep, layered near-black ladder so cards separate cleanly once elevation
  // and shadows are applied. Each step is a genuinely distinct tone.
  static const Color surfaceDark = Color(0xFF0A0B11); // scaffold base
  static const Color surfaceContainerLowestDark = Color(0xFF08090F);
  static const Color surfaceContainerLowDark = Color(0xFF11131B);
  static const Color surfaceContainerDark = Color(0xFF161923);
  static const Color surfaceContainerHighDark = Color(0xFF1E2430);
  static const Color surfaceContainerHighestDark = Color(0xFF29303E);

  // === LIGHT THEME SURFACES ===
  static const Color surfaceLight = Color(0xFFF3F4F6);
  static const Color surfaceContainerLight = Color(0xFFFFFFFF);
  static const Color surfaceContainerHighLight = Color(0xFFF0F1F5);
  static const Color surfaceContainerHighestLight = Color(0xFFE2E4EA);

  /// Fill behind a selected segment/chip in light mode.
  ///
  /// Deliberately further from `surfaceLight` than the container tokens: a
  /// selected state has to be visible at a glance, and 1.03:1 was not.
  static const Color selectedContainerLight = Color(0xFFE2E5EE);

  // === TEXT COLORS - DARK ===
  static const Color onSurfaceDark = Color(0xFFF0F2F8);
  static const Color onSurfaceVariantDark = Color(
    0xFFB4BCCB,
  ); // brighter secondary
  static const Color onSurfaceDimDark = Color(0xFF7C8598); // dimmer tertiary

  // === TEXT COLORS - LIGHT ===
  //
  // Both secondary tones are darkened from their Tailwind equivalents to clear
  // WCAG AA (4.5:1) on `surfaceLight`. gray-500 measured 4.39:1 and gray-400 a
  // failing 2.36:1, so secondary and tertiary text was below the line in every
  // light-mode screen. The hierarchy between them is preserved — 5.6:1 vs
  // 4.8:1 reads as two distinct weights — and reinforced by size and weight
  // rather than by contrast alone.
  static const Color onSurfaceLight = Color(0xFF111827); // gray-900
  static const Color onSurfaceVariantLight = Color(0xFF5A6273); // 5.56:1
  static const Color onSurfaceDimLight = Color(0xFF656C7B); // 4.79:1

  // === OUTLINE / BORDER ===
  static const Color outlineDark = Color(0xFF2D3748);
  static const Color outlineVariantDark = Color(0xFF2D3748);
  static const Color outlineLight = Color(0xFFE2E4EA);
  static const Color outlineVariantLight = Color(0xFFE2E4EA);

  // === SEMANTIC COLORS ===
  static const Color success = Color(0xFF22C55E); // green-500
  static const Color successContainer = Color(0xFF166534); // green-800
  static const Color warning = Color(0xFFF59E0B); // amber-500
  static const Color warningContainer = Color(0xFF92400E); // amber-800
  static const Color error = Color(0xFFEF4444); // red-500
  static const Color errorContainer = Color(0xFF991B1B); // red-800
  static const Color info = Color(0xFF3B82F6); // blue-500
  static const Color infoContainer = Color(0xFF1E40AF); // blue-800
}

@immutable
class CupolaThemeColors extends ThemeExtension<CupolaThemeColors> {
  final Color statusBadgeBackground;
  final Color statusBadgeForeground;

  /// Dimmer tertiary text tone for editorial captions / metadata, sitting a
  /// step below [ColorScheme.onSurfaceVariant].
  final Color dimText;

  /// Translucent surface used by backdrop-blurred (glass) elements.
  final Color glassSurface;

  /// Brand gradient endpoints (indigo → violet) for accents and marks.
  final Color brandGradientStart;
  final Color brandGradientEnd;

  const CupolaThemeColors({
    required this.statusBadgeBackground,
    required this.statusBadgeForeground,
    required this.dimText,
    required this.glassSurface,
    required this.brandGradientStart,
    required this.brandGradientEnd,
  });

  factory CupolaThemeColors.defaults({
    required Brightness brightness,
    required ColorScheme colorScheme,
  }) {
    final isDark = brightness == Brightness.dark;
    return CupolaThemeColors(
      statusBadgeBackground: colorScheme.surface.withValues(alpha: 0.8),
      statusBadgeForeground: colorScheme.onSurface,
      dimText: isDark
          ? AppColors.onSurfaceDimDark
          : AppColors.onSurfaceDimLight,
      glassSurface: colorScheme.surfaceContainer.withValues(
        alpha: isDark ? 0.72 : 0.55,
      ),
      brandGradientStart: AppColors.seerr,
      brandGradientEnd: AppColors.sonarr,
    );
  }

  @override
  CupolaThemeColors copyWith({
    Color? statusBadgeBackground,
    Color? statusBadgeForeground,
    Color? dimText,
    Color? glassSurface,
    Color? brandGradientStart,
    Color? brandGradientEnd,
  }) {
    return CupolaThemeColors(
      statusBadgeBackground:
          statusBadgeBackground ?? this.statusBadgeBackground,
      statusBadgeForeground:
          statusBadgeForeground ?? this.statusBadgeForeground,
      dimText: dimText ?? this.dimText,
      glassSurface: glassSurface ?? this.glassSurface,
      brandGradientStart: brandGradientStart ?? this.brandGradientStart,
      brandGradientEnd: brandGradientEnd ?? this.brandGradientEnd,
    );
  }

  @override
  CupolaThemeColors lerp(
    covariant ThemeExtension<CupolaThemeColors>? other,
    double t,
  ) {
    if (other is! CupolaThemeColors) {
      return this;
    }

    return CupolaThemeColors(
      statusBadgeBackground:
          Color.lerp(statusBadgeBackground, other.statusBadgeBackground, t) ??
          statusBadgeBackground,
      statusBadgeForeground:
          Color.lerp(statusBadgeForeground, other.statusBadgeForeground, t) ??
          statusBadgeForeground,
      dimText: Color.lerp(dimText, other.dimText, t) ?? dimText,
      glassSurface:
          Color.lerp(glassSurface, other.glassSurface, t) ?? glassSurface,
      brandGradientStart:
          Color.lerp(brandGradientStart, other.brandGradientStart, t) ??
          brandGradientStart,
      brandGradientEnd:
          Color.lerp(brandGradientEnd, other.brandGradientEnd, t) ??
          brandGradientEnd,
    );
  }
}

/// Material Design 3 Theme configuration for Seekarr
class AppTheme {
  AppTheme._();

  /// Bundled app font family declared in pubspec.yaml.
  static const String fontFamily = 'Inter';

  /// Family for code, logs, hashes and anything read in columns.
  ///
  /// **Not** the string `'monospace'`, which is the mistake this token exists to
  /// stop repeating. `'monospace'` is an Android family alias; CoreText has no
  /// family by that name, so on iOS and macOS Flutter finds nothing and falls
  /// back to the proportional system face. That silently rendered Dockge's YAML
  /// editor, its container logs, TrueNAS' JSON diagnostics and — worst — the
  /// certificate fingerprint a user is asked to *compare by eye* in a
  /// proportional font on two of the three targets, which is also a per-OS
  /// divergence the brand explicitly forbids.
  ///
  /// Menlo leads because it is the mono face reliably present on both Apple
  /// platforms; the fallbacks pick the job up everywhere else, ending at the
  /// Android alias.
  static const String monoFontFamily = 'Menlo';

  /// Fallbacks for [monoFontFamily], in resolution order.
  static const List<String> monoFontFamilyFallback = <String>[
    'SF Mono',
    'Roboto Mono',
    'Droid Sans Mono',
    'Consolas',
    'monospace',
  ];

  // === VARIABLE AXES ===
  //
  // The bundled Inter.ttf is a variable font exposing `wght` (100–900) and
  // `opsz` (14–32). Both are addressed explicitly: Flutter drives neither from
  // a plain `TextStyle`.

  /// Lower bound of Inter's optical-size axis — the text-reading drawing.
  static const double _opticalSizeMin = 14;

  /// Upper bound of Inter's optical-size axis — the display drawing.
  static const double _opticalSizeMax = 32;

  /// The optical size Inter should be *drawn* at for text rendered at [fontSize].
  ///
  /// Inter's `opsz` axis is not a size, it is a drawing: at 14 the letterforms
  /// are opened up and lightly contrasted for small text, at 32 they tighten and
  /// gain contrast for headlines. The app bundles the axis and, until now, spent
  /// every string on the 14pt drawing — so a 57pt title was set in a face
  /// designed to survive being 14pt. Tracking the authored size is the whole
  /// point of the axis.
  static double opticalSize(double fontSize) =>
      fontSize.clamp(_opticalSizeMin, _opticalSizeMax);

  /// The `wght` + `opsz` pair for Inter at a given weight and size.
  static List<FontVariation> interVariations(
    FontWeight weight,
    double fontSize,
  ) => <FontVariation>[
    FontVariation('wght', weight.value.toDouble()),
    FontVariation('opsz', opticalSize(fontSize)),
  ];

  // === TRACKING ===

  /// Inter's own tracking, in logical pixels, for text at [fontSize].
  ///
  /// The ramp used to carry Material's Baseline tracking table — `+0.5` on
  /// `bodyLarge`, `+0.25` on `bodyMedium`, `+0.5` on the labels. Those values
  /// are specified for Roboto, a narrower face with tighter default fit; on
  /// Inter they read spacey, and the display end of the same ramp had already
  /// been hand-tuned negative, so the ladder was half-designed and half
  /// inherited.
  ///
  /// This is instead Inter's published dynamic-metrics curve — tracking in em as
  /// `-0.0223 + 0.185·e^(-0.1745·size)` — which lands near zero at reading sizes
  /// and around -0.022em at display sizes. It replaces fifteen literals with the
  /// curve they were approximating.
  ///
  /// [brightness] adds a hair of positive tracking on the dark theme only.
  /// Light-on-dark type blooms optically and its counters close up; the standard
  /// compensation is a little more air, tapering away by the headline sizes where
  /// the effect stops mattering. Both themes still end up tighter than the
  /// Roboto values they replace, so nothing gets wider than it was.
  static double interTracking(double fontSize, Brightness brightness) {
    final double em =
        -0.0223 +
        0.185 * math.exp(-0.1745 * fontSize) +
        (brightness == Brightness.dark ? _darkTrackingDelta(fontSize) : 0);
    return em * fontSize;
  }

  /// Dark-theme optical compensation, in em: +0.006 up to 16pt, gone by 24pt.
  static double _darkTrackingDelta(double fontSize) {
    const double maxDelta = 0.006;
    final double taper = ((24 - fontSize) / 8).clamp(0.0, 1.0);
    return maxDelta * taper;
  }

  /// Standardised "eyebrow" / overline style: small, uppercase-tracked label
  /// used above section titles and on onboarding steps. Pair with
  /// `Text(label.toUpperCase(), style: AppTheme.eyebrow(...))`.
  ///
  /// The one style whose tracking is authored rather than derived: it is meant
  /// to be a distinct voice, and +1.4 is what uppercasing at 11pt needs to stop
  /// reading as a cramped acronym. Kept off [interTracking] deliberately.
  static TextStyle eyebrow(Color color) => _inter(
    color: color,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 1.4,
    brightness: Brightness.dark,
  );

  // === DARK THEME (Primary) ===
  //
  // Both themes are deliberately fixed. Seekarr's palette is part of its
  // identity — per-service accents have to stay recognisable, and the
  // experience is meant to be identical on every OS — so platform dynamic
  // color (Material You) is not harmonised in. The previous signature took a
  // `dynamicColorScheme` it silently ignored, which read as a wiring bug.
  static ThemeData darkTheme() {
    return _buildTheme(
      brightness: Brightness.dark,
      colorScheme: _darkColorScheme,
      navigationBarBackground: AppColors.surfaceContainerDark,
      bottomSheetBackground: _darkColorScheme.surfaceContainer,
      dialogBackground: _darkColorScheme.surfaceContainer,
    );
  }

  // === LIGHT THEME ===
  static ThemeData lightTheme() {
    return _buildTheme(
      brightness: Brightness.light,
      colorScheme: _lightColorScheme,
      navigationBarBackground: _lightColorScheme.surface,
      bottomSheetBackground: _lightColorScheme.surface,
      dialogBackground: _lightColorScheme.surface,
    );
  }

  static ThemeData _buildTheme({
    required Brightness brightness,
    required ColorScheme colorScheme,
    required Color navigationBarBackground,
    required Color bottomSheetBackground,
    required Color dialogBackground,
  }) {
    final TextTheme textTheme = _buildTextTheme(
      brightness == Brightness.dark
          ? ThemeData.dark().textTheme
          : ThemeData.light().textTheme,
      brightness,
    );
    // Component text comes off the ramp rather than re-declaring sizes: the
    // app-bar title *is* titleLarge at a heavier weight, a button label *is*
    // labelLarge. Restating `fontSize: 22` here is how a component drifts out of
    // the ladder it is supposed to belong to.
    final TextStyle labelLarge = textTheme.labelLarge!;
    final TextStyle labelMedium = textTheme.labelMedium!;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      extensions: [
        CupolaThemeColors.defaults(
          brightness: brightness,
          colorScheme: colorScheme,
        ),
      ],
      textTheme: textTheme,
      scaffoldBackgroundColor: colorScheme.surface,

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge!
            .weight(FontWeight.w800)
            .copyWith(color: colorScheme.onSurface),
        iconTheme: IconThemeData(color: colorScheme.onSurface),
      ),

      // NavigationBar
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: navigationBarBackground,
        indicatorColor: colorScheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return labelMedium
                .weight(FontWeight.w600)
                .copyWith(color: colorScheme.primary);
          }
          return labelMedium.copyWith(color: colorScheme.onSurfaceVariant);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: colorScheme.primary);
          }
          return IconThemeData(color: colorScheme.onSurfaceVariant);
        }),
      ),

      // Card
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusMd),
      ),

      // Chip
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHighest,
        labelStyle: labelMedium.copyWith(color: colorScheme.onSurfaceVariant),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusSm),
      ),

      // FilledButton
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          textStyle: labelLarge.weight(FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusMd),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),

      // OutlinedButton
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: labelLarge.weight(FontWeight.w600),
          side: BorderSide(color: colorScheme.outline),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusMd),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),

      // TextButton
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: labelLarge.weight(FontWeight.w600),
        ),
      ),

      // Input Decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusMd,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusMd,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusMd,
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusMd,
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusMd,
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        hintStyle: textTheme.bodyMedium!.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),

      // BottomSheet
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: bottomSheetBackground,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
      ),

      // Dialog
      dialogTheme: DialogThemeData(
        backgroundColor: dialogBackground,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusLg),
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
      ),

      // SnackBar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium!.copyWith(
          color: colorScheme.onInverseSurface,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusMd),
      ),

      // ListTile
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusMd),
      ),

      // TabBar
      tabBarTheme: TabBarThemeData(
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        indicatorColor: colorScheme.primary,
        labelStyle: labelLarge.weight(FontWeight.w600),
        unselectedLabelStyle: labelLarge,
      ),

      // ProgressIndicator
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
      ),
    );
  }

  // === COLOR SCHEMES ===

  static final ColorScheme _darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    // Primary
    primary: AppColors.primary,
    onPrimary: Colors.white,
    primaryContainer: AppColors.primaryDark,
    onPrimaryContainer: AppColors.primaryLighter,
    // Secondary (same as primary for unified look)
    secondary: AppColors.primaryLight,
    onSecondary: Colors.white,
    secondaryContainer: AppColors.surfaceContainerHighDark,
    onSecondaryContainer: AppColors.onSurfaceVariantDark,
    // Tertiary
    tertiary: AppColors.success,
    onTertiary: Colors.white,
    tertiaryContainer: AppColors.successContainer,
    onTertiaryContainer: Colors.white,
    // Error
    error: AppColors.error,
    onError: Colors.white,
    errorContainer: AppColors.errorContainer,
    onErrorContainer: Colors.white,
    // Surface
    surface: AppColors.surfaceDark,
    onSurface: AppColors.onSurfaceDark,
    surfaceContainerLowest: AppColors.surfaceContainerLowestDark,
    surfaceContainerLow: AppColors.surfaceContainerLowDark,
    surfaceContainer: AppColors.surfaceContainerDark,
    surfaceContainerHigh: AppColors.surfaceContainerHighDark,
    surfaceContainerHighest: AppColors.surfaceContainerHighestDark,
    onSurfaceVariant: AppColors.onSurfaceVariantDark,
    // Outline
    outline: AppColors.outlineDark,
    outlineVariant: AppColors.outlineVariantDark,
    // Other
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: AppColors.surfaceLight,
    onInverseSurface: AppColors.onSurfaceLight,
    inversePrimary: AppColors.primaryDark,
  );

  static final ColorScheme _lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    // Primary
    primary: AppColors.primary,
    onPrimary: Colors.white,
    primaryContainer: AppColors.primaryLighter,
    onPrimaryContainer: AppColors.primaryDark,
    // Secondary
    //
    // `secondaryContainer` is what Material paints behind a selected
    // SegmentedButton segment. It used to be surfaceContainerHigh (#F0F1F5),
    // which sits 1.03:1 from `surface` — the selected segment had no visible
    // fill at all, and with onSurfaceVariant as its foreground it read as
    // *less* prominent than the unselected ones. A distinctly tinted container
    // plus full-strength text makes the selected state unmistakable.
    secondary: AppColors.primary,
    onSecondary: Colors.white,
    secondaryContainer: AppColors.selectedContainerLight,
    onSecondaryContainer: AppColors.onSurfaceLight,
    // Tertiary
    tertiary: AppColors.success,
    onTertiary: Colors.white,
    tertiaryContainer: const Color(0xFFDCFCE7), // green-100
    onTertiaryContainer: AppColors.successContainer,
    // Error
    error: AppColors.error,
    onError: Colors.white,
    errorContainer: const Color(0xFFFEE2E2), // red-100
    onErrorContainer: AppColors.errorContainer,
    // Surface
    surface: AppColors.surfaceLight,
    onSurface: AppColors.onSurfaceLight,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: AppColors.surfaceLight,
    surfaceContainer: AppColors.surfaceContainerLight,
    surfaceContainerHigh: AppColors.surfaceContainerHighLight,
    surfaceContainerHighest: AppColors.surfaceContainerHighestLight,
    onSurfaceVariant: AppColors.onSurfaceVariantLight,
    // Outline
    outline: AppColors.outlineLight,
    outlineVariant: AppColors.outlineVariantLight,
    // Other
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: AppColors.surfaceDark,
    onInverseSurface: AppColors.onSurfaceDark,
    inversePrimary: AppColors.primaryLight,
  );

  // === TEXT THEME ===

  /// The type ramp.
  ///
  /// Sizes and weights are unchanged; what is new is that the weights actually
  /// render (see [CupolaTextStyle.weight]), that tracking comes from Inter's
  /// own curve rather than Roboto's table ([interTracking]), and that line
  /// height is a decision per role instead of the font file's default.
  ///
  /// On that last point: every style in the app used to inherit Inter's own
  /// 1.21 (ascender 1984 + descender 494 over a 2048 em), from the 57pt display
  /// down to 12pt metadata. One ratio across a 5:1 size range cannot be right at
  /// both ends — it is loose for a headline and cramped for a paragraph. So the
  /// ladder now tightens as it climbs and opens as it falls:
  ///
  /// - **Display and headline** tighten toward the 1.10 floor. Large type needs
  ///   less leading, not proportionally more. The floor is not taste: an
  ///   accented capital reaches ~0.89em above its baseline and a descender
  ///   ~0.21em below, so below 1.10 the acute on one line starts touching the
  ///   `y` on the line above. Media titles arrive from TMDB in every language,
  ///   so that case is real; 1.06 was tried and the collision is visible.
  /// - **Body** opens to 1.45–1.55. This is where prose lives — overviews,
  ///   descriptions, empty-state copy — and light-on-dark text at a wide measure
  ///   wants the most air of anything here. `bodyLarge` is the widest measure and
  ///   gets the most.
  /// - **Labels stay at ~1.22**, near the old default, because labels are chrome:
  ///   they sit in fixed-height pills, badges and cells where extra leading buys
  ///   nothing and costs layout.
  static TextTheme _buildTextTheme(TextTheme base, Brightness brightness) {
    TextStyle style({
      required double size,
      required FontWeight weight,
      required double height,
    }) => _inter(
      fontSize: size,
      fontWeight: weight,
      height: height,
      brightness: brightness,
    );

    return base
        .apply(fontFamily: fontFamily)
        .copyWith(
          // Display — editorial: heaviest weights, tightest leading.
          displayLarge: style(size: 57, weight: FontWeight.w800, height: 1.10),
          displayMedium: style(size: 45, weight: FontWeight.w800, height: 1.10),
          displaySmall: style(size: 36, weight: FontWeight.w700, height: 1.10),
          // Headline — screen-level headings.
          headlineLarge: style(size: 32, weight: FontWeight.w800, height: 1.15),
          headlineMedium: style(
            size: 28,
            weight: FontWeight.w700,
            height: 1.18,
          ),
          headlineSmall: style(size: 24, weight: FontWeight.w700, height: 1.20),
          // Title — section headers, card titles, row primaries, KPI values.
          titleLarge: style(size: 22, weight: FontWeight.w700, height: 1.25),
          titleMedium: style(size: 16, weight: FontWeight.w600, height: 1.32),
          titleSmall: style(size: 14, weight: FontWeight.w600, height: 1.34),
          // Body — running text. The only roles set for reading, not for chrome.
          bodyLarge: style(size: 16, weight: FontWeight.w400, height: 1.55),
          bodyMedium: style(size: 14, weight: FontWeight.w400, height: 1.45),
          bodySmall: style(size: 12, weight: FontWeight.w400, height: 1.40),
          // Label — chips, badges, nav, dense metadata. Chrome: leading stays put.
          labelLarge: style(size: 14, weight: FontWeight.w500, height: 1.22),
          labelMedium: style(size: 12, weight: FontWeight.w500, height: 1.22),
          labelSmall: style(size: 11, weight: FontWeight.w500, height: 1.22),
        );
  }
}
