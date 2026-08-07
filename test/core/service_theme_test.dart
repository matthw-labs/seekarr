import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The alphas the selected nav pill and the Activity segment pills actually use.
const _darkTintAlpha = 0.16;
const _lightTintAlpha = 0.13;

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  final lighter = a > b ? a : b;
  final darker = a > b ? b : a;
  return (lighter + 0.05) / (darker + 0.05);
}

/// The background a label is really drawn on: the tint composited over the
/// surface, not the accent on its own.
///
/// Measuring against the accent alone is the mistake that makes this class of bug
/// invisible — it passes combinations that fail on screen.
Color _tintOverSurface(Color accent, double alpha, Color surface) =>
    Color.alphaBlend(accent.withValues(alpha: alpha), surface);

void main() {
  group('ServiceTheme.onTint', () {
    test('every service accent clears AA over its own tint, in both themes', () {
      for (final service in ServiceKey.values) {
        for (final (surface, alpha) in const [
          (AppColors.surfaceLight, _lightTintAlpha),
          (AppColors.surfaceDark, _darkTintAlpha),
        ]) {
          final background = _tintOverSurface(service.accent, alpha, surface);
          final label = ServiceTheme.onTint(
            service.accent,
            surface: surface,
            tintAlpha: alpha,
          );

          expect(
            _contrast(label, background),
            greaterThanOrEqualTo(4.5),
            reason:
                '${service.name} on ${surface == AppColors.surfaceLight ? 'light' : 'dark'}',
          );
        }
      }
    });

    test('every nav section accent clears AA over its own tint', () {
      for (final tab in NavTab.values) {
        for (final (surface, alpha) in const [
          (AppColors.surfaceLight, _lightTintAlpha),
          (AppColors.surfaceDark, _darkTintAlpha),
        ]) {
          final background = _tintOverSurface(tab.accentColor, alpha, surface);
          final label = ServiceTheme.onTint(
            tab.accentColor,
            surface: surface,
            tintAlpha: alpha,
          );

          expect(
            _contrast(label, background),
            greaterThanOrEqualTo(4.5),
            reason:
                '${tab.name} on ${surface == AppColors.surfaceLight ? 'light' : 'dark'}',
          );
        }
      }
    });

    test('an accent that already passes is returned untouched', () {
      // Dark theme is the case that always worked. The helper must not "correct"
      // it, or every pill in the app shifts colour for no reason.
      expect(
        ServiceTheme.onTint(
          AppColors.radarr,
          surface: AppColors.surfaceDark,
          tintAlpha: _darkTintAlpha,
        ),
        AppColors.radarr,
      );
    });

    test(
      'the light-theme amber that used to ship was nowhere near the line',
      () {
        // The concrete defect: the nav bar painted this exact combination.
        final background = _tintOverSurface(
          AppColors.radarr,
          _lightTintAlpha,
          AppColors.surfaceLight,
        );

        expect(_contrast(AppColors.radarr, background), lessThan(2.5));
        expect(
          ServiceTheme.onTint(
            AppColors.radarr,
            surface: AppColors.surfaceLight,
            tintAlpha: _lightTintAlpha,
          ),
          isNot(AppColors.radarr),
        );
      },
    );

    test('the accent hue survives the adjustment', () {
      // This is the whole reason for deriving a tone instead of dropping the
      // label to a neutral: the pill has to stay recognisably that colour.
      for (final accent in [
        AppColors.radarr,
        AppColors.nzbget,
        AppColors.navSettings,
      ]) {
        final tuned = ServiceTheme.onTint(
          accent,
          surface: AppColors.surfaceLight,
          tintAlpha: _lightTintAlpha,
        );

        expect(
          HSLColor.fromColor(tuned).hue,
          closeTo(HSLColor.fromColor(accent).hue, 1.0),
          reason: '$accent should keep its hue',
        );
      }
    });
  });

  group('NavTab accents', () {
    test('each section carries its own accent', () {
      // All four used to be `AppColors.primary`, so the nav bar's
      // per-destination accent mechanism could never show a difference.
      final accents = NavTab.values.map((tab) => tab.accentColor).toSet();

      expect(accents, hasLength(NavTab.values.length));
    });

    test('no section borrows the closed status vocabulary', () {
      // A green or amber pill in permanent chrome would read as a health signal.
      const statusTones = [
        AppColors.success,
        AppColors.warning,
        AppColors.error,
        AppColors.info,
      ];

      for (final tab in NavTab.values) {
        expect(statusTones, isNot(contains(tab.accentColor)), reason: tab.name);
      }
    });
  });
}
