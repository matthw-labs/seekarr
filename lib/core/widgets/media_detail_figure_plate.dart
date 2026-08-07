import 'package:flutter/material.dart';

import 'package:cupola/core/app_gradients.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';

/// The posterless hero lead: the page's own figure, standing in the poster slot.
///
/// Pass it as `MediaDetailPosterRow.posterCard` — the slot keeps its exact
/// 82x123 footprint, so every collapse invariant that depends on the lead's
/// height (`_posterExitFactor`'s clearance math, the staged intervals, the bar
/// reveal) is untouched.
///
/// Bazarr has no poster and no backdrop *by definition*, so its hero was 236pt
/// of gradient framing an absence — a fake poster rendering a film reel above
/// the only question the page answers. This makes the band *contain* the answer:
/// `12` over the eyebrow `MISSING`.
///
/// Silent to assistive technology: the deck's headline says the same thing in
/// words one region below, and a screen reader does not need it twice.
///
/// `headlineSmall` and not `displaySmall`: at the hero band's 1.6x clamp that is
/// 38.4pt, plus a 17.6pt eyebrow and a 4pt gap — 60pt inside a 123pt box, with
/// room to spare. The whole row already lays out on
/// `MediaDetailHeaderMetrics.heroTextScaler`, so it cannot exceed that.
class MediaDetailFigurePlate extends StatelessWidget {
  /// The figure itself, pre-formatted ('12').
  final String value;

  /// What the figure counts ('MISSING'). Uppercased for the eye.
  final String label;

  /// The page's service accent.
  final Color accent;

  const MediaDetailFigurePlate({
    super.key,
    required this.value,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ExcludeSemantics(
      child: DecoratedBox(
        // Two boxes, not one: a `BoxDecoration` carrying both a `color` and a
        // `gradient` paints only the gradient — the base tone is silently
        // dropped and the plate comes out transparent.
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: AppRadius.borderRadiusMd,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: AppRadius.borderRadiusMd,
            gradient: AppGradients.serviceGlow(
              accent,
              center: Alignment.topLeft,
              radius: 1.2,
              alpha: 0.14,
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    style: theme.textTheme.headlineSmall!
                        .weight(FontWeight.w800)
                        .tabular
                        .copyWith(
                          color: ServiceTheme.onTint(
                            accent,
                            surface: colorScheme.surfaceContainerHigh,
                            tintAlpha: 0.14,
                          ),
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    style: AppTheme.eyebrow(colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
