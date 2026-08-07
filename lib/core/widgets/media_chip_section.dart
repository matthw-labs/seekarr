import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/widgets/tag_chip.dart';

/// A wrapped run of catalogue chips for a detail page's region 5.
///
/// Label-less by design — the slot owns the heading, so the same list can never
/// reach two differently-titled sections.
class MediaChipSection extends StatelessWidget {
  final List<String> values;

  /// Non-null only for [MediaChipSection.accented].
  final Color? accent;

  /// Neutral pills, for **genres and TMDB keywords**.
  ///
  /// The pill DESIGN.md describes as "used where a colour would over-signal": a
  /// genre is a fact about the title, not a state of the user's copy of it, and
  /// an accent here would put the page's service colour on something the
  /// service has no opinion about.
  const MediaChipSection.neutral({super.key, required this.values})
    : accent = null;

  /// Accent pills, for **real Radarr / Sonarr / Bazarr tags only**.
  ///
  /// The slot's label must be `TAGS`, and this constructor must not be used for
  /// anything else. In this domain a tag targets release profiles and import
  /// lists — it is a thing the user configured on their server — so labelling
  /// genres "Tags" asserts something false about that server. Three screens
  /// used to do exactly that.
  const MediaChipSection.accented({
    super.key,
    required this.values,
    required this.accent,
  }) : assert(accent != null, 'MediaChipSection.accented needs an accent');

  @override
  Widget build(BuildContext context) {
    final visible = values
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
    if (visible.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    // The accent as a chip *label on its own 12% tint* — the second half of the
    // Luminance Rule, and a different sum from a foreground on an opaque fill.
    // Measured over its own tint on `surface-light`, Radarr's amber lands near
    // 1.80:1 untreated; `onTint` keeps the hue and walks the lightness until it
    // clears AA, and the fill follows the walked colour so the recipe stays
    // self-consistent.
    final chipColor = accent == null
        ? null
        : ServiceTheme.onTint(
            accent!,
            surface: colorScheme.surface,
            tintAlpha: 0.12,
          );

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final value in visible)
          if (chipColor == null)
            GenreChip(genre: value)
          else
            TagChip(text: value, color: chipColor),
      ],
    );
  }
}
