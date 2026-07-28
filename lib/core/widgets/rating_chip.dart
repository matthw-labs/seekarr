import 'package:flutter/material.dart';
import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';

class RatingChip extends StatelessWidget {
  final String value;
  final int votes;
  final String sourceName;
  final String sourceIcon;
  final VoidCallback? onTap;

  /// Accent for the chip. Defaults to the app primary; detail screens pass their
  /// service accent so the ratings row matches the rest of the page.
  final Color? accent;

  const RatingChip({
    super.key,
    required this.value,
    required this.votes,
    required this.sourceName,
    required this.sourceIcon,
    this.onTap,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final formattedVotes = _formatVoteCount(votes);
    final displayText = formattedVotes.isEmpty
        ? value
        : '$value ($formattedVotes)';
    final color = accent ?? Theme.of(context).colorScheme.primary;

    return Semantics(
      button: onTap != null,
      container: true,
      excludeSemantics: true,
      label: '$sourceName rating $value',
      value: votes > 0 ? '$votes votes' : null,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: Tooltip(
          message: sourceName,
          preferBelow: true,
          triggerMode: TooltipTriggerMode.tap,
          // The pill itself stays compact; the constraint only enlarges the
          // touch area to the 44pt minimum.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Center(
              widthFactor: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
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
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      displayText,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
