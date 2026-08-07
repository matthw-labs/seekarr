import 'package:flutter/material.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';

/// A reusable section header with title and optional "See All" action.
///
/// Follows Material Design 3 styling with consistent typography
/// and tap feedback for the entire header area.
///
/// Publishes itself as one heading to assistive technology. Title, subtitle and
/// the chevron are three visual pieces of one label, so the header silences its
/// own subtree and speaks a composed string instead — otherwise a screen reader
/// stops on each fragment and the "see all" affordance, being a bare chevron,
/// has no name at all.
class SectionHeader extends StatelessWidget {
  /// The title text for the section
  final String title;

  /// Optional callback when the header is tapped (e.g., "See All" action)
  final VoidCallback? onTap;

  /// Whether to show the chevron icon indicating more content
  final bool showChevron;

  /// Optional trailing widget (alternative to chevron)
  final Widget? trailing;

  /// Optional subtitle text
  final String? subtitle;

  /// Overrides the spoken name of the header.
  ///
  /// Defaults to [title], plus [subtitle] when there is one. Pass it when the
  /// visible title folds a count into brackets ("Alerts (3)"), or when a
  /// non-interactive [trailing] carries information the sentence needs — this
  /// header silences its own subtree, so a trailing count is not spoken unless
  /// it is in here.
  final String? semanticLabel;

  /// What tapping the header does, e.g. 'opens the Readarr library'.
  ///
  /// The chevron is the only visual affordance and a chevron has no name, so
  /// without this a screen reader offers "Authors, heading, button" and no clue
  /// where the button leads. Read out after the label, as a hint.
  final String? semanticHint;

  /// Whether [trailing] is a control in its own right.
  ///
  /// Set by the constructors rather than by callers — [SectionHeader.action] is
  /// how you ask for it. It keeps [trailing] outside the region this header
  /// silences, so a nested button stays reachable.
  final bool trailingIsInteractive;

  const SectionHeader({
    super.key,
    required this.title,
    this.onTap,
    this.showChevron = true,
    this.trailing,
    this.subtitle,
    this.semanticLabel,
    this.semanticHint,
  }) : trailingIsInteractive = false;

  /// A header whose [trailing] is its own control — a "New" button, say.
  ///
  /// Not tappable itself: two tap targets in one row, one of them the whole row,
  /// is exactly the ambiguity a screen-reader user would have to resolve by
  /// guessing.
  const SectionHeader.action({
    super.key,
    required this.title,
    required this.trailing,
    this.subtitle,
    this.semanticLabel,
  }) : onTap = null,
       showChevron = false,
       semanticHint = null,
       trailingIsInteractive = true,
       assert(
         trailing != null,
         'SectionHeader.action needs a trailing control',
       );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final spokenLabel =
        semanticLabel ?? [title, if (subtitle != null) subtitle!].join(', ');

    // Title and optional subtitle, as one label rather than two stops: a
    // subtitle read on its own has no context.
    //
    // Clamped because this is chrome, and follows the reading size only so far —
    // the same contract `TextScaleMetrics` states for a compact box and the
    // floating nav bar applies at 1.3x. Unclamped, `titleLarge` at 2x is 44pt
    // bold, wider than the room a header row leaves beside its action, and
    // Flutter's answer to a single word that cannot fit a line is to break it
    // mid-word: "Downloadi/ng", "Req/uest". A clamped title wraps between words
    // instead, which is a failure mode a heading survives.
    final titleBlock = ExcludeSemantics(
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: TextScaleMetrics.defaultMaxScaleFactor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleLarge!.weight(FontWeight.bold),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                // Tabular: callers use the subtitle for live progress counts
                // ("3 of 12 selected", "2 of 9 being re-imported") that change
                // under the user's finger, and proportional digits make the
                // whole line shuffle sideways on every tap.
                style: theme.textTheme.bodySmall!.tabular.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    final Widget? end = trailing != null
        ? (trailingIsInteractive
              ? trailing!
              : ExcludeSemantics(child: trailing))
        : (showChevron && onTap != null
              ? ExcludeSemantics(
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.primary,
                  ),
                )
              : null);

    // Past this reading size a title and its action stop fitting one line on a
    // phone, and no amount of eliding fixes that — a truncated "See a…" is worse
    // than a second line. So the row becomes a stack, which is the same answer
    // iOS gives its own controls at accessibility sizes. Keyed off the scaler
    // rather than a `LayoutBuilder` on purpose: a `LayoutBuilder` cannot report
    // intrinsic dimensions, and this widget sits inside callers that ask for
    // them.
    final stacked =
        end != null && MediaQuery.textScalerOf(context).scale(14) > 14 * 1.4;

    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleBlock,
                const SizedBox(height: AppSpacing.xs),
                // Full width now, so a trailing that wraps internally has room
                // to do it.
                SizedBox(width: double.infinity, child: end),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: titleBlock),
                if (end != null) end,
              ],
            ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Semantics(
        container: true,
        // Guarantees this node's label stays exactly `spokenLabel`, and that an
        // interactive `trailing` keeps a node of its own.
        explicitChildNodes: true,
        header: true,
        button: onTap != null,
        label: spokenLabel,
        hint: onTap == null ? null : semanticHint,
        onTap: onTap,
        child: onTap == null
            ? content
            : InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(AppSpacing.sm),
                // The name and the tap action are published above; without this
                // the ink response adds a second, unnamed actionable node.
                excludeFromSemantics: true,
                child: content,
              ),
      ),
    );
  }
}
