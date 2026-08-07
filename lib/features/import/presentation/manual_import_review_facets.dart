import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/import/domain/manual_import_status.dart';

/// The scan verdict at a glance — and the control that acts on it.
///
/// This row used to be four read-only [StatusBadge]es stating counts, while the
/// two things a user actually wanted to do with those counts lived elsewhere:
/// "hide what I already imported" was an icon toggle in the app bar, and "put
/// the files this service can't import out of the way" was a collapsed section
/// header halfway down the list. Three controls, three places, one question.
///
/// So the counts became the control. A filled chip is showing; a hollow one with
/// a struck-through eye is hidden. Nothing is buried in a menu, the counts stay
/// legible either way, and what is currently hidden is visible *as* a count
/// rather than as an absence the user has to notice.
class ManualImportFacetBar extends StatelessWidget {
  /// How many files fell into each facet, whole-scan.
  ///
  /// Facets with no files at all are simply absent from the row: a chip reading
  /// "0 other" is chrome describing nothing.
  final Map<ManualImportFacet, int> counts;

  /// Facets the user has switched off. Everything else is shown.
  final Set<ManualImportFacet> hidden;

  final ValueChanged<ManualImportFacet> onToggle;

  const ManualImportFacetBar({
    super.key,
    required this.counts,
    required this.hidden,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final facets = [
      for (final facet in ManualImportFacet.values)
        if ((counts[facet] ?? 0) > 0) facet,
    ];
    if (facets.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      // Wrap rather than a horizontal scroller: a filter the user cannot see is
      // a filter they will not remember setting, and these four have to be
      // readable together for the row to read as a verdict.
      child: Wrap(
        spacing: AppSpacing.sm,
        children: [
          for (final facet in facets)
            _FacetChip(
              facet: facet,
              count: counts[facet]!,
              shown: !hidden.contains(facet),
              onTap: () => onToggle(facet),
            ),
        ],
      ),
    );
  }
}

class _FacetChip extends StatelessWidget {
  /// The stricter of the two platform minimums (48dp Android, 44pt iOS).
  ///
  /// Applied to the *hit box*, not to the pill: the visual chip keeps the badge
  /// proportions this row has always had, and the extra height is transparent
  /// padding around it. A 48pt-tall filled pill four times over would turn a
  /// summary line into a toolbar.
  static const double _minTouchTarget = 48;

  final ManualImportFacet facet;
  final int count;
  final bool shown;
  final VoidCallback onTap;

  const _FacetChip({
    required this.facet,
    required this.count,
    required this.shown,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final info = manualImportFacetStatus(facet, count);
    final tone = statusToneColor(colorScheme, info.tone);
    final tintAlpha = colorScheme.brightness == Brightness.dark ? 0.16 : 0.13;

    // The Luminance Rule, second half: a saturated tone is not a legible label
    // over a low-alpha tint of itself, least of all in light theme.
    final foreground = shown
        ? ServiceTheme.onTint(
            tone,
            surface: colorScheme.surface,
            tintAlpha: tintAlpha,
          )
        : colorScheme.onSurfaceVariant;

    return Semantics(
      container: true,
      button: true,
      // `selected` rather than prose, so the platform speaks the state in the
      // user's own language and the label stays the count.
      selected: shown,
      label: manualImportFacetSpokenLabel(facet, count),
      hint: shown ? 'hides them from the list' : 'shows them in the list',
      onTap: onTap,
      child: ExcludeSemantics(
        child: PressableScale(
          onTap: onTap,
          borderRadius: AppRadius.borderRadiusPill,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _minTouchTarget),
            // `widthFactor: 1` is load-bearing, not a tweak: an `Align` (or a
            // `Container` with an `alignment`) expands to the widest constraint
            // it is given, and inside a `Wrap` that constraint is the full row —
            // so every chip took a line of its own, centred, and the row read as
            // a stack of buttons. With the factor set, the box is as wide as its
            // pill and only its *height* grows to the touch target.
            child: Align(
              alignment: Alignment.center,
              widthFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: shown
                      ? tone.withValues(alpha: tintAlpha)
                      : Colors.transparent,
                  borderRadius: AppRadius.borderRadiusPill,
                  border: Border.all(
                    color: shown
                        ? tone.withValues(alpha: 0.27)
                        : colorScheme.outlineVariant,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs + 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        // Hidden state is carried by a glyph as well as by fill
                        // and colour, so it survives greyscale and colour
                        // blindness — and so a struck eye, not a missing chip,
                        // is what says "these are out of the list".
                        shown ? _iconFor(facet) : Icons.visibility_off_rounded,
                        size: 14,
                        color: foreground,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        info.label,
                        maxLines: 1,
                        style: theme.textTheme.labelSmall!
                            .weight(FontWeight.w700)
                            .tabular
                            .copyWith(color: foreground),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One glyph per facet.
  ///
  /// Deliberately not `statusIconFor(info)`: two of the four facets share the
  /// neutral tone, so a tone-derived icon would give "imported" and "other" the
  /// same glyph — and these chips are the one place where the four classes have
  /// to be told apart at a glance.
  IconData _iconFor(ManualImportFacet facet) {
    return switch (facet) {
      ManualImportFacet.ready => Icons.check_circle_rounded,
      ManualImportFacet.attention => Icons.warning_amber_rounded,
      ManualImportFacet.imported => Icons.library_add_check_rounded,
      ManualImportFacet.other => Icons.insert_drive_file_outlined,
    };
  }
}
