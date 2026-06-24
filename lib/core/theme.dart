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

  // === PRIMARY (Seerr Indigo) ===
  static const Color primary = seerr;
  static const Color primaryDark = Color(0xFF4F46E5); // indigo-600
  static const Color primaryLight = Color(0xFF818CF8); // indigo-400
  static const Color primaryLighter = Color(0xFFA5B4FC); // indigo-300

  // === DARK THEME SURFACES ===
  static const Color surfaceDark = Color(0xFF0F1117);
  static const Color surfaceContainerDark = Color(0xFF1C2130);
  static const Color surfaceContainerHighDark = Color(0xFF252D3D);
  static const Color surfaceContainerHighestDark = Color(0xFF2D3748);

  // === LIGHT THEME SURFACES ===
  static const Color surfaceLight = Color(0xFFF3F4F6);
  static const Color surfaceContainerLight = Color(0xFFFFFFFF);
  static const Color surfaceContainerHighLight = Color(0xFFF0F1F5);
  static const Color surfaceContainerHighestLight = Color(0xFFE2E4EA);

  // === TEXT COLORS - DARK ===
  static const Color onSurfaceDark = Color(0xFFF0F2F8);
  static const Color onSurfaceVariantDark = Color(0xFF9CA3AF);
  static const Color onSurfaceDimDark = Color(0xFF9CA3AF);

  // === TEXT COLORS - LIGHT ===
  static const Color onSurfaceLight = Color(0xFF111827); // gray-900
  static const Color onSurfaceVariantLight = Color(0xFF6B7280); // gray-500
  static const Color onSurfaceDimLight = Color(0xFF6B7280); // gray-500

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

  const SeekarrThemeColors({
    required this.statusBadgeBackground,
    required this.statusBadgeForeground,
  });

  factory SeekarrThemeColors.defaults({
    required Brightness brightness,
    required ColorScheme colorScheme,
  }) {
    return SeekarrThemeColors(
      statusBadgeBackground: colorScheme.surface.withValues(alpha: 0.8),
      statusBadgeForeground: colorScheme.onSurface,
    );
  }

  @override
  SeekarrThemeColors copyWith({
    Color? statusBadgeBackground,
    Color? statusBadgeForeground,
  }) {
    return SeekarrThemeColors(
      statusBadgeBackground:
          statusBadgeBackground ?? this.statusBadgeBackground,
      statusBadgeForeground:
          statusBadgeForeground ?? this.statusBadgeForeground,
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
    );
  }
}

/// Material Design 3 Theme configuration for Seekarr
class AppTheme {
  AppTheme._();

  /// Bundled app font family declared in pubspec.yaml.
  static const String fontFamily = 'Inter';

  // === DARK THEME (Primary) ===
  static ThemeData darkTheme(ColorScheme? dynamicColorScheme) {
    return _buildTheme(
      brightness: Brightness.dark,
      colorScheme: _darkColorScheme,
      navigationBarBackground: AppColors.surfaceContainerDark,
      bottomSheetBackground: _darkColorScheme.surfaceContainer,
      dialogBackground: _darkColorScheme.surfaceContainer,
    );
  }

  // === LIGHT THEME ===
  static ThemeData lightTheme(ColorScheme? dynamicColorScheme) {
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
    surfaceContainerLowest: AppColors.surfaceDark,
    surfaceContainerLow: AppColors.surfaceDark,
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
    secondary: AppColors.primary,
    onSecondary: Colors.white,
    secondaryContainer: AppColors.surfaceContainerHighLight,
    onSecondaryContainer: AppColors.onSurfaceVariantLight,
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
          // Display
          displayLarge: _inter(
            fontSize: 57,
            fontWeight: FontWeight.w400,
            letterSpacing: -0.25,
          ),
          displayMedium: _inter(fontSize: 45, fontWeight: FontWeight.w400),
          displaySmall: _inter(fontSize: 36, fontWeight: FontWeight.w400),
          // Headline
          headlineLarge: _inter(fontSize: 32, fontWeight: FontWeight.w600),
          headlineMedium: _inter(fontSize: 28, fontWeight: FontWeight.w600),
          headlineSmall: _inter(fontSize: 24, fontWeight: FontWeight.w600),
          // Title
          titleLarge: _inter(fontSize: 22, fontWeight: FontWeight.w600),
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
