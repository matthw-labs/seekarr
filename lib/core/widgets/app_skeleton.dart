import 'package:flutter/material.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/widgets/shimmer_placeholder.dart';

/// Higher-level skeleton presets, built on [ShimmerPlaceholder], that mirror
/// the real shapes screens render. Using these instead of hand-built shimmer
/// blocks keeps loading states consistent and premium across the app.
class AppSkeleton {
  AppSkeleton._();

  /// Horizontal poster carousel skeleton (matches dashboard poster sections).
  static Widget posterRow({
    double height = 168,
    double aspectRatio = 2 / 3,
    int count = 6,
  }) {
    final width = height * aspectRatio;
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (_, __) =>
            ShimmerPlaceholder.card(width: width, height: height),
      ),
    );
  }

  /// Vertical list of row skeletons (queue, requests, history).
  ///
  /// The default tracks the real row it stands in for: an activity tile is an
  /// icon well beside a title, a subtitle, a status badge and sometimes a
  /// progress bar, which lands near 104pt with its 8pt gap. At the previous 72pt
  /// the content visibly jumped on settle — the one thing a skeleton exists to
  /// prevent.
  static Widget listRows({int count = 5, double rowHeight = 104}) {
    return ShimmerList(itemCount: count, itemHeight: rowHeight);
  }

  /// Poster grid skeleton (search results, library grids).
  static Widget posterGrid({int count = 9, int crossAxisCount = 3}) {
    return ShimmerGrid(itemCount: count, crossAxisCount: crossAxisCount);
  }

  /// Detail-page skeleton: backdrop + poster/title block + body lines.
  static Widget detailBody() {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerPlaceholder(height: 220, borderRadius: BorderRadius.zero),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerPlaceholder(
                      width: 96,
                      height: 144,
                      borderRadius: AppRadius.borderRadiusMd,
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ShimmerPlaceholder.text(width: 200, height: 22),
                          const SizedBox(height: AppSpacing.md),
                          ShimmerPlaceholder.text(width: 120),
                          const SizedBox(height: AppSpacing.sm),
                          ShimmerPlaceholder.text(width: 160),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                ShimmerPlaceholder.text(width: double.infinity),
                const SizedBox(height: AppSpacing.sm),
                ShimmerPlaceholder.text(width: double.infinity),
                const SizedBox(height: AppSpacing.sm),
                ShimmerPlaceholder.text(width: 240),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
