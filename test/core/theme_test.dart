import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/theme.dart';

void main() {
  group('AppTheme', () {
    testWidgets('dark theme preserves special-case background colors', (
      tester,
    ) async {
      final theme = AppTheme.darkTheme(null);

      expect(theme.colorScheme.surface, const Color(0xFF0A0B11));
      expect(theme.colorScheme.surfaceContainer, const Color(0xFF161923));
      expect(theme.colorScheme.surfaceContainerHigh, const Color(0xFF1E2430));
      expect(theme.colorScheme.outline, const Color(0xFF2D3748));
      expect(theme.colorScheme.onSurface, const Color(0xFFF0F2F8));
      expect(theme.colorScheme.onSurfaceVariant, const Color(0xFFB4BCCB));
      expect(
        theme.navigationBarTheme.backgroundColor,
        AppColors.surfaceContainerDark,
      );
      expect(
        theme.bottomSheetTheme.backgroundColor,
        theme.colorScheme.surfaceContainer,
      );
      expect(
        theme.dialogTheme.backgroundColor,
        theme.colorScheme.surfaceContainer,
      );
    });

    testWidgets('light theme preserves special-case background colors', (
      tester,
    ) async {
      final theme = AppTheme.lightTheme(null);

      expect(theme.colorScheme.surface, const Color(0xFFF3F4F6));
      expect(theme.colorScheme.surfaceContainer, Colors.white);
      expect(theme.colorScheme.surfaceContainerHigh, const Color(0xFFF0F1F5));
      expect(theme.colorScheme.outline, const Color(0xFFE2E4EA));
      expect(theme.colorScheme.onSurface, const Color(0xFF111827));
      expect(theme.colorScheme.onSurfaceVariant, const Color(0xFF6B7280));
      expect(
        theme.navigationBarTheme.backgroundColor,
        theme.colorScheme.surface,
      );
      expect(theme.bottomSheetTheme.backgroundColor, theme.colorScheme.surface);
      expect(theme.dialogTheme.backgroundColor, theme.colorScheme.surface);
    });

    testWidgets('dark theme attaches SeekarrThemeColors defaults', (
      tester,
    ) async {
      final theme = AppTheme.darkTheme(null);

      final colors = theme.extension<SeekarrThemeColors>();

      expect(colors, isNotNull);
      expect(
        colors!.statusBadgeBackground,
        theme.colorScheme.surface.withValues(alpha: 0.8),
      );
      expect(colors.statusBadgeForeground, theme.colorScheme.onSurface);
    });

    testWidgets('light theme attaches SeekarrThemeColors defaults', (
      tester,
    ) async {
      final theme = AppTheme.lightTheme(null);

      final colors = theme.extension<SeekarrThemeColors>();

      expect(colors, isNotNull);
      expect(
        colors!.statusBadgeBackground,
        theme.colorScheme.surface.withValues(alpha: 0.8),
      );
      expect(colors.statusBadgeForeground, theme.colorScheme.onSurface);
    });

    test('SeekarrThemeColors.defaults uses surface scrim and onSurface', () {
      final colorScheme = AppTheme.lightTheme(null).colorScheme.copyWith(
        surface: const Color(0xFF123456),
        onSurface: const Color(0xFFABCDEF),
      );

      final colors = SeekarrThemeColors.defaults(
        brightness: Brightness.light,
        colorScheme: colorScheme,
      );

      expect(
        colors.statusBadgeBackground,
        colorScheme.surface.withValues(alpha: 0.8),
      );
      expect(colors.statusBadgeForeground, colorScheme.onSurface);
    });

    test('service accent colors match the Open Design prototype', () {
      expect(AppColors.seerr, const Color(0xFF6366F1));
      expect(AppColors.radarr, const Color(0xFFF59E0B));
      expect(AppColors.sonarr, const Color(0xFF8B5CF6));
      expect(AppColors.lidarr, const Color(0xFFEC4899));
    });
  });
}
