import 'package:flutter/material.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/models/rating_source.dart';
import 'package:seekarr/core/utils/rating_display.dart';
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
        // Each source on its own scale. `toStringAsFixed(1)` for everything is
        // what rendered Metacritic's 53 as `53.0` and Rotten Tomatoes' 57 as
        // `57.0` — a decimal place on an integer scale is most of why five pills
        // read as five comparable numbers.
        final display = ratingDisplayFor(
          icon: rating.icon,
          name: rating.name,
          value: rating.value,
        );
        return RatingChip(
          value: display.value,
          denominator: display.denominator,
          votes: rating.votes,
          sourceName: rating.name,
          sourceIcon: rating.icon,
          accent: accent,
        );
      }).toList(),
    );
  }
}
