import 'package:flutter/material.dart';

import 'package:seekarr/core/widgets/shimmer_placeholder.dart';

/// Loading placeholder for Prowlarr list sections.
///
/// [count] controls how many shimmer rows are rendered (the dashboard shows a
/// short preview, the library a fuller list).
class ProwlarrListShimmer extends StatelessWidget {
  const ProwlarrListShimmer({
    super.key,
    this.count = 3,
    this.verticalPadding = 0,
  });

  final int count;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: verticalPadding),
      child: Column(
        children: List.generate(
          count,
          (_) => const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: ShimmerPlaceholder(height: 56),
          ),
        ),
      ),
    );
  }
}
