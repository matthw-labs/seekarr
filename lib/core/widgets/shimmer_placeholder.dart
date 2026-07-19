import 'package:flutter/material.dart';
import 'package:seekarr/core/app_animation.dart';
import 'package:seekarr/core/app_radius.dart';

/// A shimmer loading placeholder effect following Material Design 3.
///
/// Use this widget to show loading states for cards, lists, and other content.
class ShimmerPlaceholder extends StatefulWidget {
  /// Width of the placeholder (null for full width)
  final double? width;

  /// Height of the placeholder
  final double height;

  /// Border radius of the placeholder
  final BorderRadius? borderRadius;

  /// Whether to show as a circle
  final bool isCircle;

  const ShimmerPlaceholder({
    super.key,
    this.width,
    required this.height,
    this.borderRadius,
    this.isCircle = false,
  });

  /// Creates a card-shaped shimmer placeholder
  ShimmerPlaceholder.card({super.key, this.width, required this.height})
    : borderRadius = AppRadius.borderRadiusMd,
      isCircle = false;

  /// Creates a text line shimmer placeholder
  factory ShimmerPlaceholder.text({
    Key? key,
    double? width,
    double height = 14,
  }) {
    return ShimmerPlaceholder(
      key: key,
      width: width,
      height: height,
      borderRadius: AppRadius.borderRadiusXs,
    );
  }

  /// Creates a circular shimmer placeholder
  const ShimmerPlaceholder.circle({super.key, required double size})
    : width = size,
      height = size,
      borderRadius = null,
      isCircle = true;

  @override
  State<ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppAnimation.shimmerDuration,
    )..repeat();

    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseColor = colorScheme.surfaceContainerHigh;
    final highlightColor = colorScheme.surfaceContainer;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            shape: widget.isCircle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: widget.isCircle ? null : widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment(_animation.value - 1, 0),
              end: Alignment(_animation.value, 0),
              colors: [baseColor, highlightColor, baseColor],
            ),
          ),
        );
      },
    );
  }
}

/// A skeleton loading view for a list of items
class ShimmerList extends StatelessWidget {
  /// Number of shimmer items to show
  final int itemCount;

  /// Height of each shimmer item
  final double itemHeight;

  /// Spacing between items
  final double spacing;

  const ShimmerList({
    super.key,
    this.itemCount = 5,
    this.itemHeight = 72,
    this.spacing = 8,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      // Non-scrolling and shrink-wrapped so the skeleton can be nested inside
      // another scroll view (e.g. a loading state inside a ListView) without a
      // "viewport given unbounded height" error.
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      itemCount: itemCount,
      separatorBuilder: (context, index) => SizedBox(height: spacing),
      itemBuilder: (context, index) =>
          ShimmerPlaceholder.card(height: itemHeight),
    );
  }
}

/// A skeleton loading view for a grid of items
class ShimmerGrid extends StatelessWidget {
  /// Number of shimmer items to show
  final int itemCount;

  /// Number of columns
  final int crossAxisCount;

  const ShimmerGrid({super.key, this.itemCount = 9, this.crossAxisCount = 3});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 2 / 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) =>
          ShimmerPlaceholder.card(height: double.infinity),
    );
  }
}
