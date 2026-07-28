import 'package:flutter/material.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/models/rating_source.dart';
import 'package:seekarr/core/widgets/rating_chip.dart';

/// Displays a horizontal wrap of [RatingChip] widgets from a list of
/// [RatingSource].
class RatingChipsRow extends StatelessWidget {
  final List<RatingSource> ratings;

  /// Accent for the chips, so the row matches the host screen's service colour.
  final Color? accent;

  const RatingChipsRow({super.key, required this.ratings, this.accent});

  @override
  Widget build(BuildContext context) {
    // Drop sources that have no score to report. An unreleased title comes back
    // from the *arr APIs as 0.0 with 0 votes, and rendering "TMDB 0.0" as a
    // rating states something false about the title.
    final scored = ratings
        .where((rating) => rating.value > 0 || rating.votes > 0)
        .toList(growable: false);

    if (scored.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: scored.map((rating) {
        return RatingChip(
          value: rating.value.toStringAsFixed(1),
          votes: rating.votes,
          sourceName: rating.name,
          sourceIcon: rating.icon,
          accent: accent,
        );
      }).toList(),
    );
  }
}
