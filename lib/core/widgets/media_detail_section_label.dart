import 'package:flutter/material.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/service_theme.dart';
import 'package:seekarr/core/theme.dart';

/// Reading size past which a label and its action stop sharing a line.
///
/// The Stacking Header Rule's threshold, and deliberately the same number
/// `SectionHeader` uses: two headings on one page must not break at two
/// different reading sizes.
const double _stackAboveScaleFactor = 1.4;

/// The body-role size the threshold is measured at.
const double _stackProbeFontSize = 14.0;

/// The media detail body's region label — an accent eyebrow with an optional
/// tabular count and an optional trailing control.
///
/// Built **only** by `MediaDetailView`'s spine, from `MediaDetailSlot.label`.
/// That is the point: a caller cannot ship a section without a heading, without
/// the page accent, or without `Semantics(header: true)`, because a caller never
/// builds one.
///
/// Why an eyebrow and not [SectionHeader]'s `titleLarge`: on a six-region page
/// the hero title and the collapsed bar's title are the page's voice, and a
/// stack of 22pt bold headings competes with them. An accent kicker repeated
/// five or six times down the page reads as a *rhythm* — which is the same
/// argument the `/services` engraved domain header makes, including the
/// asymmetric 24-above / 8-below proximity the spine applies around it. No
/// fill, no border, and deliberately no leading colour pipe: three pipes of
/// arbitrary length read as tick marks, where five identical kickers read as
/// structure.
class MediaDetailSectionLabel extends StatelessWidget {
  /// The region name, in its original case. Uppercased for the eye only.
  final String label;

  /// The page's service accent. Walked to a legible tone before it is used as
  /// text — see [ServiceTheme.onTint].
  final Color accent;

  /// A count beside the label ('41 of 48 · 5 seasons'), in tabular digits.
  final String? count;

  /// An interactive control at the trailing edge (a jump-to, a refresh).
  ///
  /// Never silenced: this is the `SectionHeader.action` carve-out. A control in
  /// a caller slot has to keep a node of its own or it leaves the accessibility
  /// tree entirely.
  final Widget? action;

  const MediaDetailSectionLabel({
    super.key,
    required this.label,
    required this.accent,
    this.count,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // The accent as *text on the surface*, not as a fill. `tintAlpha: 0` makes
    // the composite the surface itself, so `onTint` walks the accent's
    // lightness — keeping its hue — until it clears 4.5:1. Without it Sonarr's
    // violet on `surface-light` measures about 3.96:1, and an 11pt eyebrow is
    // not large text.
    final litAccent = ServiceTheme.onTint(
      accent,
      surface: colorScheme.surface,
      tintAlpha: 0,
    );
    final dimText =
        theme.extension<SeekarrThemeColors>()?.dimText ??
        colorScheme.onSurfaceVariant;

    final headline = ExcludeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              label.toUpperCase(),
              maxLines: 2,
              softWrap: true,
              style: AppTheme.eyebrow(litAccent),
            ),
          ),
          if (count != null && count!.trim().isNotEmpty) ...[
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              // **This count does not roll, and the reason is the note further
              // down this very file.** It moves when the library does — an
              // episode is grabbed and "41 of 48" becomes "42 of 48" — so it
              // looks like an obvious candidate, and it was tried.
              //
              // `ReelLine` gates itself with a `LayoutBuilder`, because deciding
              // whether a line can roll means knowing the width it has. But a
              // `LayoutBuilder` cannot report intrinsic dimensions, and the
              // stacking note below records that this widget "sits inside callers
              // that ask for them" — which is why the stack threshold here is
              // keyed off the text scaler instead of measuring. Putting a
              // measuring widget inside the one component that documents it must
              // not measure would fail on whichever caller asks first, and the
              // existing `Flexible` + ellipsis is already the correct answer for
              // a count this long.
              child: Text(
                count!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall!.tabular.copyWith(
                  color: dimText,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    // Past this reading size a label and its action stop sharing a line on a
    // phone, and eliding does not rescue either half. Keyed off the scaler
    // rather than a `LayoutBuilder` for the same reason `SectionHeader` is: a
    // `LayoutBuilder` cannot report intrinsics, and this sits inside callers
    // that ask for them.
    final stacked =
        action != null &&
        MediaQuery.textScalerOf(context).scale(_stackProbeFontSize) >
            _stackProbeFontSize * _stackAboveScaleFactor;

    final content = stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              headline,
              const SizedBox(height: AppSpacing.xs),
              // Full width, so a trailing control that wraps internally can.
              SizedBox(width: double.infinity, child: action!),
            ],
          )
        : Row(
            children: [
              Expanded(child: headline),
              if (action != null) ...[
                const SizedBox(width: AppSpacing.sm),
                action!,
              ],
            ],
          );

    return Semantics(
      container: true,
      // Keeps this node's label exactly the composed string, and lets an
      // interactive `action` keep a node of its own.
      explicitChildNodes: true,
      header: true,
      // Original case: uppercase belongs in the eye, not in the ear.
      label: [
        label,
        if (count != null && count!.trim().isNotEmpty) count!,
      ].join(', '),
      child: content,
    );
  }
}
