import 'package:flutter/material.dart';
import 'package:seekarr/core/app_radius.dart';

/// Builds a [TextStyle] backed by the bundled Inter variable font.
TextStyle _inter({
  Color? color,
  double? fontSize,
  FontWeight? fontWeight,
  double? letterSpacing,
}) {
  return TextStyle(
    fontFamily: AppTheme.fontFamily,
    color: color,
    fontSize: fontSize,
    fontWeight: fontWeight,
    letterSpacing: letterSpacing,
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
class SeekarrThemeColors extends ThemeExtension<SeekarrThemeColors> {
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

  const SeekarrThemeColors({
    required this.statusBadgeBackground,
    required this.statusBadgeForeground,
    required this.dimText,
    required this.glassSurface,
    required this.brandGradientStart,
    required this.brandGradientEnd,
  });

  factory SeekarrThemeColors.defaults({
    required Brightness brightness,
    required ColorScheme colorScheme,
  }) {
    final isDark = brightness == Brightness.dark;
    return SeekarrThemeColors(
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
  SeekarrThemeColors copyWith({
    Color? statusBadgeBackground,
    Color? statusBadgeForeground,
    Color? dimText,
    Color? glassSurface,
    Color? brandGradientStart,
    Color? brandGradientEnd,
  }) {
    return SeekarrThemeColors(
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
  SeekarrThemeColors lerp(
    covariant ThemeExtension<SeekarrThemeColors>? other,
    double t,
  ) {
    if (other is! SeekarrThemeColors) {
      return this;
    }

    return SeekarrThemeColors(
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

  /// Standardised "eyebrow" / overline style: small, uppercase-tracked label
  /// used above section titles and on onboarding steps. Pair with
  /// `Text(label.toUpperCase(), style: AppTheme.eyebrow(...))`.
  static TextStyle eyebrow(Color color) => _inter(
    color: color,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.4,
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
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      extensions: [
        SeekarrThemeColors.defaults(
          brightness: brightness,
          colorScheme: colorScheme,
        ),
      ],
      textTheme: _buildTextTheme(
        brightness == Brightness.dark
            ? ThemeData.dark().textTheme
            : ThemeData.light().textTheme,
      ),
      scaffoldBackgroundColor: colorScheme.surface,

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: _inter(
          color: colorScheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
        iconTheme: IconThemeData(color: colorScheme.onSurface),
      ),

      // NavigationBar
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: navigationBarBackground,
        indicatorColor: colorScheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return _inter(
              color: colorScheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            );
          }
          return _inter(
            color: colorScheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          );
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
        labelStyle: _inter(color: colorScheme.onSurfaceVariant, fontSize: 12),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusSm),
      ),

      // FilledButton
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          textStyle: _inter(fontSize: 14, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusMd),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),

      // OutlinedButton
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: _inter(fontSize: 14, fontWeight: FontWeight.w600),
          side: BorderSide(color: colorScheme.outline),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusMd),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),

      // TextButton
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: _inter(fontSize: 14, fontWeight: FontWeight.w600),
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
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
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
        contentTextStyle: _inter(color: colorScheme.onInverseSurface),
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
        labelStyle: _inter(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: _inter(fontSize: 14, fontWeight: FontWeight.w500),
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

  static TextTheme _buildTextTheme(TextTheme base) {
    return base
        .apply(fontFamily: fontFamily)
        .copyWith(
          // Display — editorial: heavier weight, tight negative tracking
          displayLarge: _inter(
            fontSize: 57,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.0,
          ),
          displayMedium: _inter(
            fontSize: 45,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.75,
          ),
          displaySmall: _inter(
            fontSize: 36,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
          // Headline
          headlineLarge: _inter(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
          headlineMedium: _inter(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
          headlineSmall: _inter(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          // Title
          titleLarge: _inter(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          titleMedium: _inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.15,
          ),
          titleSmall: _inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
          // Body
          bodyLarge: _inter(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.5,
          ),
          bodyMedium: _inter(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.25,
          ),
          bodySmall: _inter(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.4,
          ),
          // Label
          labelLarge: _inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.1,
          ),
          labelMedium: _inter(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
          labelSmall: _inter(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        );
  }
}
