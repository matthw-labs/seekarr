import 'package:flutter/material.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';

class RatingChip extends StatelessWidget {
  final String value;

  /// The scale [value] is measured on: `/10`, `/100` or `%`.
  ///
  /// Without it a row of pills reads as one comparable set of numbers when it is
  /// nothing of the kind — Metacritic's 53 and IMDb's 8.4 are the same opinion.
  /// Empty for a source whose scale this app does not know; see
  /// `ratingDisplayFor`, which is where the scale is decided.
  ///
  /// Rendered inside the value run for the eye, and spoken as words — "out of
  /// 100", "percent" — because a screen reader reading "53 slash 100" is worse
  /// than the ambiguity this fixes.
  final String denominator;

  final int votes;
  final String sourceName;
  final String sourceIcon;

  /// Accent for the chip. Defaults to the app primary; detail screens pass their
  /// service accent so the ratings row matches the rest of the page.
  final Color? accent;

  const RatingChip({
    super.key,
    required this.value,
    this.denominator = '',
    required this.votes,
    required this.sourceName,
    required this.sourceIcon,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final formattedVotes = _formatVoteCount(votes);
    final score = '$value$denominator';
    final displayText = formattedVotes.isEmpty
        ? score
        : '$score ($formattedVotes)';
    final color = accent ?? Theme.of(context).colorScheme.primary;

    // No `onTap`: the parameter existed, was never passed by any of the four
    // construction sites, and was the only reason this metadata pill carried a
    // hand-rolled `GestureDetector` and claimed a button role it never had. A
    // rating is a fact, not an action — it keeps the full radius its `GenreChip`
    // and `TagChip` neighbours use for exactly that reason.
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$sourceName rating $value${_spokenScale(denominator)}',
      value: votes > 0 ? '$votes votes' : null,
      child: Tooltip(
        message: sourceName,
        preferBelow: true,
        triggerMode: TooltipTriggerMode.tap,
        // The pill itself stays compact; the constraint keeps the tooltip's own
        // trigger area comfortable without growing the ratings row.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            widthFactor: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: AppRadius.borderRadiusFull,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    sourceIcon,
                    style: Theme.of(context).textTheme.labelSmall!
                        .weight(FontWeight.bold)
                        .copyWith(color: color),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    displayText,
                    // Score plus vote count — digits that differ per card and
                    // stack in a ratings row, so they get a shared advance.
                    style: Theme.of(context).textTheme.labelSmall!
                        .weight(FontWeight.w700)
                        .tabular
                        .copyWith(color: color),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The scale as words, for the ear.
  ///
  /// `/100` reads aloud as "53 slash 100" or "53 divided by 100" depending on
  /// the reader — both worse than the ambiguity the denominator exists to fix.
  /// Empty stays empty, so an unknown scale is not narrated into existence.
  String _spokenScale(String denominator) {
    if (denominator.isEmpty) return '';
    if (denominator == '%') return ' percent';
    if (denominator.startsWith('/')) {
      return ' out of ${denominator.substring(1)}';
    }
    return ' $denominator';
  }

  /// Formats a vote count, or returns empty when there is nothing to report.
  ///
  /// Zero is empty rather than `"0"`: a rating annotated "(0)" claims a score
  /// backed by no votes, which is a contradiction the user has to decode. The
  /// score alone is the honest presentation.
  String _formatVoteCount(int count) {
    if (count <= 0) return '';
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return count.toString();
  }
}
