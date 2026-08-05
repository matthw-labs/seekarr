import 'package:flutter/material.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/service_theme.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/pressable_scale.dart';

/// A horizontally scrolling row of pills selecting one value along one axis.
///
/// This replaces two implementations of the same control that had drifted apart
/// inside a single feature: a `SegmentedButton` pinned in a fixed-height
/// `SliverPersistentHeader` on the per-service Activity screen, and a hand-rolled
/// chip on the global one. Between them they had three defects worth naming,
/// because each is a class of mistake rather than a one-off:
///
/// - The chip had **no semantics node at all** — no button role, no accessible
///   name, no selected state — while a service tile 150 lines away in the same
///   file did all three correctly. It also skipped [PressableScale], which is
///   where the press animation, the haptic, the Reduce Motion check and the
///   button role live together; hand-rolling a tap silently drops all four.
/// - The chip hard-coded `BorderRadius.circular(20)` twice instead of taking a
///   token.
/// - The segmented button lived in a 56pt box with `minExtent == maxExtent`, so
///   at an accessibility reading size its label outgrew the header and Flutter
///   painted its overflow stripe across the control. Nothing here has a fixed
///   height; the pill is sized by its label, with a minimum for the touch target.
///
/// The selected pill borrows the navigation bar's treatment — [AppRadius.pill],
/// the accent fill, the accent border — rather than inventing a third "this one
/// is active" language for the app. It is deliberately **not** [AppRadius.full]:
/// full radius means metadata in this system, so an interactive pill at full
/// radius would read as a label.
class SelectionPills<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T value) labelBuilder;
  final ValueChanged<T> onSelected;

  /// Colour of the selected pill. Defaults to the theme primary.
  ///
  /// On an aggregate surface this stays primary: per DESIGN.md's Room Light Rule
  /// one accent lights a screen at a time, and a screen showing several services
  /// at once is lit by primary rather than by whichever service happens to be
  /// first.
  final Color? accent;

  const SelectionPills({
    super.key,
    required this.values,
    required this.selected,
    required this.labelBuilder,
    required this.onSelected,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final tone = accent ?? Theme.of(context).colorScheme.primary;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          for (final value in values)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: _Pill(
                label: labelBuilder(value),
                accent: tone,
                selected: value == selected,
                onTap: () => onSelected(value),
              ),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  /// The stricter of the two platform minimums (48dp Android, 44pt iOS), applied
  /// as a floor rather than a fixed height so the pill can still grow with the
  /// reading size.
  static const double _minTouchTarget = 48;

  final String label;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  const _Pill({
    required this.label,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    final tintAlpha = isDark ? 0.16 : 0.13;
    final background = selected
        ? accent.withValues(alpha: tintAlpha)
        : colorScheme.surfaceContainer;
    final border = selected
        ? accent.withValues(alpha: 0.27)
        : colorScheme.outlineVariant;

    // The Luminance Rule, second half: the raw accent is not a legible label over
    // a low-alpha tint of itself in light theme. [ServiceTheme.onTint] keeps the
    // accent's hue and walks its lightness until it clears AA over the composite
    // of tint-over-surface, so the pill stays accent-coloured in both themes
    // instead of falling back to a neutral in daylight.
    final labelColor = selected
        ? ServiceTheme.onTint(
            accent,
            surface: colorScheme.surface,
            tintAlpha: tintAlpha,
          )
        : colorScheme.onSurfaceVariant;

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: PressableScale(
          onTap: onTap,
          borderRadius: AppRadius.borderRadiusPill,
          child: Container(
            constraints: const BoxConstraints(minHeight: _minTouchTarget),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius: AppRadius.borderRadiusPill,
              border: Border.all(color: border),
            ),
            child: Text(
              label,
              maxLines: 1,
              style: theme.textTheme.labelMedium!
                  .weight(FontWeight.w700)
                  .copyWith(color: labelColor),
            ),
          ),
        ),
      ),
    );
  }
}
