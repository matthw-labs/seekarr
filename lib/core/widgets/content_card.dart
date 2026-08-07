import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:cupola/core/app_elevation.dart';
import 'package:cupola/core/app_gradients.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';

/// A card widget for displaying media content with cached images.
///
/// Designed to work seamlessly with Hero transitions and follows
/// Material Design 3 styling guidelines with Seerr-inspired colors.
class ContentCard extends StatelessWidget {
  /// URL of the image to display
  final String? imageUrl;

  /// Optional headers used when fetching protected images.
  final Map<String, String>? httpHeaders;

  /// Optional badge widget to display in the corner (e.g., status badge).
  final Widget? badge;

  /// Whether to show a shimmer loading effect instead of spinner
  final bool useShimmer;

  /// Optional callback for tap gesture
  final VoidCallback? onTap;

  const ContentCard({
    super.key,
    required this.imageUrl,
    this.httpHeaders,
    this.badge,
    this.useShimmer = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final card = Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.borderRadiusMd,
        boxShadow: AppElevation.level2(colorScheme),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Image
          _buildImage(context, colorScheme),

          // Gradient overlay for better badge visibility
          if (badge != null)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: AppGradients.serviceGlow(
                    colorScheme.shadow,
                    radius: 1.5,
                  ),
                ),
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: badge!,
              ),
            ),
        ],
      ),
    );

    if (onTap == null) return card;

    return PressableScale(
      onTap: onTap,
      borderRadius: AppRadius.borderRadiusMd,
      child: card,
    );
  }

  Widget _buildImage(BuildContext context, ColorScheme colorScheme) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _buildPlaceholder(colorScheme);
    }

    return CachedNetworkImage(
      imageUrl: imageUrl!,
      httpHeaders: httpHeaders,
      cacheManager: pinnedImageCacheFor(imageUrl),
      fit: BoxFit.cover,
      placeholder: (context, url) => useShimmer
          ? _ShimmerPlaceholder(color: colorScheme.surfaceContainerHigh)
          : _buildLoadingPlaceholder(colorScheme),
      errorWidget: (context, url, error) => _buildErrorPlaceholder(colorScheme),
    );
  }

  Widget _buildPlaceholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainer,
      child: Icon(
        Icons.movie_outlined,
        color: colorScheme.onSurfaceVariant,
        size: 32,
      ),
    );
  }

  Widget _buildLoadingPlaceholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainer,
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorPlaceholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.broken_image_outlined,
        color: colorScheme.onSurfaceVariant,
        size: 32,
      ),
    );
  }
}

/// Simple shimmer effect for loading placeholders
class _ShimmerPlaceholder extends StatefulWidget {
  final Color color;

  const _ShimmerPlaceholder({required this.color});

  @override
  State<_ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<_ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
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
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(_animation.value - 1, 0),
              end: Alignment(_animation.value, 0),
              colors: [
                widget.color,
                widget.color.withValues(alpha: 0.5),
                widget.color,
              ],
            ),
          ),
        );
      },
    );
  }
}
