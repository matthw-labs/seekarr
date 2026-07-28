import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:seekarr/core/app_gradients.dart';
import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/widgets/floating_bottom_nav_bar.dart';
import 'package:seekarr/core/widgets/media_detail_poster_row.dart';
import 'package:seekarr/core/widgets/shimmer_placeholder.dart';

/// A reusable view for displaying media details with a prototype-style hero,
/// compact poster/title block, and sliver-based scrollable content.
class MediaDetailView extends StatelessWidget {
  final String? posterUrl;
  final Map<String, String>? posterHeaders;

  /// Optional backdrop image shown in the expanded header.
  final String? backdropUrl;

  /// Builder for the poster row that stays pinned on scroll.
  ///
  /// Receives a `collapseFactor` from 0.0 (fully expanded) to 1.0
  /// (fully collapsed) for smooth interpolation of sizes. The poster's Hero is
  /// owned by the caller's poster row (via [MediaPosterCard]), so this view no
  /// longer needs a heroTag of its own.
  final Widget Function(double collapseFactor)? posterRow;

  final List<Widget> contentSections;
  final List<Widget> slivers;
  final Widget? background;

  /// Per-service accent used to tint the hero glow (Radarr amber, Sonarr
  /// violet, Lidarr pink, Seerr indigo). Falls back to no glow when null.
  final Color? accent;

  const MediaDetailView({
    super.key,
    required this.contentSections,
    this.posterUrl,
    this.posterHeaders,
    this.backdropUrl,
    this.posterRow,
    this.slivers = const [],
    this.background,
    this.accent,
  });

  /// Retained for loading skeleton sizing.
  static const collapsedHeight = MediaDetailPosterRow.collapsedHeight;

  /// Prototype hero height excluding the device safe-area inset.
  static const expandedHeight = 236.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final scrollBottomPadding =
        FloatingNavBarMetrics.getScrollViewBottomPadding(context);

    return Material(
      color: colorScheme.surface,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _PrototypeDetailHero(
              posterUrl: posterUrl,
              posterHeaders: posterHeaders,
              backdropUrl: backdropUrl,
              posterRow: posterRow,
              background: background,
              accent: accent,
              surfaceColor: colorScheme.surface,
            ),
          ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...contentSections,
                if (slivers.isEmpty) SizedBox(height: scrollBottomPadding),
              ],
            ),
          ),
          if (slivers.isNotEmpty)
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),

          ...slivers,

          if (slivers.isNotEmpty)
            SliverToBoxAdapter(child: SizedBox(height: scrollBottomPadding)),
        ],
      ),
    );
  }
}

class _PrototypeDetailHero extends StatelessWidget {
  final String? posterUrl;
  final Map<String, String>? posterHeaders;
  final String? backdropUrl;
  final Widget Function(double collapseFactor)? posterRow;
  final Widget? background;
  final Color? accent;
  final Color surfaceColor;

  const _PrototypeDetailHero({
    required this.surfaceColor,
    this.posterUrl,
    this.posterHeaders,
    this.backdropUrl,
    this.posterRow,
    this.background,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final hasBackdrop = backdropUrl != null && backdropUrl!.isNotEmpty;
    final topPadding = MediaQuery.paddingOf(context).top;

    return SizedBox(
      height: MediaDetailView.expandedHeight + topPadding,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasBackdrop)
              _BackdropHeader(
                backdropUrl: backdropUrl!,
                surfaceColor: surfaceColor,
              )
            else
              _FallbackHeroBackdrop(
                posterUrl: posterUrl,
                posterHeaders: posterHeaders,
                surfaceColor: surfaceColor,
              ),
            // Subtle per-service accent glow so the hero feels lit by the
            // service's colour instead of a flat neutral backdrop.
            if (accent != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppGradients.serviceGlow(
                        accent!,
                        center: Alignment.topRight,
                        radius: 1.3,
                      ),
                    ),
                  ),
                ),
              ),
            if (background != null) background!,
            Positioned(
              top: topPadding + AppSpacing.md,
              left: AppSpacing.md,
              child: const _HeroBackButton(),
            ),
            Positioned(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              bottom: AppSpacing.lg,
              child: posterRow?.call(0) ?? const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroBackButton extends StatelessWidget {
  const _HeroBackButton();

  @override
  Widget build(BuildContext context) {
    // The dark circle stays 36pt so it reads as a light touch over the backdrop
    // art, but the tappable area is padded out to the 44pt HIG minimum.
    return SizedBox.square(
      dimension: 44,
      child: Center(
        child: SizedBox.square(
          dimension: 36,
          child: IconButton.filled(
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withValues(alpha: 0.45),
              foregroundColor: Colors.white,
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            icon: const Icon(Icons.chevron_left_rounded, size: 22),
          ),
        ),
      ),
    );
  }
}

class _FallbackHeroBackdrop extends StatelessWidget {
  final String? posterUrl;
  final Map<String, String>? posterHeaders;
  final Color surfaceColor;

  const _FallbackHeroBackdrop({
    required this.surfaceColor,
    this.posterUrl,
    this.posterHeaders,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasPoster = posterUrl != null && posterUrl!.isNotEmpty;

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [colorScheme.surfaceContainerHighest, surfaceColor],
            ),
          ),
        ),
        Center(
          child: Opacity(
            opacity: 0.22,
            // Intentionally NOT a Hero: the source (poster grid/carousel) has
            // no matching `_backdrop` element, so a Hero here would be orphaned
            // and fade in on navigation. Plain faded art avoids that artifact
            // while the real poster flies via the poster-row Hero.
            child: hasPoster
                ? CachedNetworkImage(
                    imageUrl: posterUrl!,
                    httpHeaders: posterHeaders,
                    width: 120,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => Icon(
                      Icons.movie_outlined,
                      size: 90,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  )
                : Icon(
                    Icons.movie_outlined,
                    size: 90,
                    color: colorScheme.onSurfaceVariant,
                  ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [surfaceColor.withValues(alpha: 0.04), surfaceColor],
            ),
          ),
        ),
      ],
    );
  }
}

class MediaDetailTitleSection extends StatelessWidget {
  final String title;
  final TextAlign textAlign;

  const MediaDetailTitleSection({
    super.key,
    required this.title,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        textAlign: textAlign,
      ),
    );
  }
}

class MediaDetailTagSection extends StatelessWidget {
  final List<Widget> tags;
  final WrapAlignment alignment;

  const MediaDetailTagSection({
    super.key,
    required this.tags,
    this.alignment = WrapAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: alignment,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: tags,
      ),
    );
  }
}

class MediaDetailOverviewSection extends StatelessWidget {
  final String overview;
  final String heading;

  const MediaDetailOverviewSection({
    super.key,
    required this.overview,
    this.heading = 'Overview',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (overview.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Text(
        overview,
        style: theme.textTheme.bodyMedium?.copyWith(
          height: 1.6,
          color: colorScheme.onSurfaceVariant,
        ),
        textAlign: TextAlign.start,
      ),
    );
  }
}

class MediaDetailSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  /// Optional per-service accent; renders a short leading colour bar for a more
  /// premium, editorial section rhythm.
  final Color? accent;

  const MediaDetailSectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, AppSpacing.sm, 0, AppSpacing.xs),
      child: Row(
        children: [
          if (accent != null) ...[
            Container(
              width: 3,
              height: 16,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.1,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Shared loading-state flexible space for detail screen shimmer skeletons.
///
/// Encapsulates the LayoutBuilder + gradient + [MediaDetailPosterRow]
/// pattern used identically in all four detail-screen loading states.
///
/// Provide a custom [posterCard] widget (e.g. a [MediaPosterCard] with
/// an initial URL for hero animation) or leave `null` for the default
/// [ShimmerPlaceholder.card].
class MediaDetailLoadingView extends StatelessWidget {
  final Widget? posterCard;
  final double subtitleWidth;

  /// Optional poster URL rendered as a faint backdrop while loading, so the
  /// hero has visual body immediately and the real backdrop (which arrives with
  /// the data) doesn't appear to "fade in" over an empty gradient.
  final String? backdropPosterUrl;
  final Map<String, String>? backdropPosterHeaders;

  const MediaDetailLoadingView({
    super.key,
    this.posterCard,
    this.subtitleWidth = 160,
    this.backdropPosterUrl,
    this.backdropPosterHeaders,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surface,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: MediaDetailLoadingHeader(
              posterCard: posterCard,
              backdropPosterUrl: backdropPosterUrl,
              backdropPosterHeaders: backdropPosterHeaders,
            ),
          ),
          _MediaDetailLoadingBody(subtitleWidth: subtitleWidth),
        ],
      ),
    );
  }
}

class MediaDetailLoadingHeader extends StatelessWidget {
  final Widget? posterCard;
  final String? backdropPosterUrl;
  final Map<String, String>? backdropPosterHeaders;

  const MediaDetailLoadingHeader({
    super.key,
    this.posterCard,
    this.backdropPosterUrl,
    this.backdropPosterHeaders,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final topPadding = MediaQuery.paddingOf(context).top;
    final hasBackdropPoster =
        backdropPosterUrl != null && backdropPosterUrl!.isNotEmpty;

    return SizedBox(
      height: MediaDetailView.expandedHeight + topPadding,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasBackdropPoster)
              _FallbackHeroBackdrop(
                posterUrl: backdropPosterUrl,
                posterHeaders: backdropPosterHeaders,
                surfaceColor: colorScheme.surface,
              )
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      colorScheme.surfaceContainerHighest,
                      colorScheme.surface,
                    ],
                  ),
                ),
              ),
            Positioned(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              bottom: AppSpacing.lg,
              child: MediaDetailPosterRow(
                collapseFactor: 0,
                posterCard:
                    posterCard ??
                    ShimmerPlaceholder.card(
                      height: MediaDetailPosterRow.expandedHeight,
                    ),
                statusBadge: ShimmerPlaceholder(
                  width: 80,
                  height: 20,
                  borderRadius: AppRadius.borderRadiusSm,
                ),
                title: ' ',
                metadataItems: const [' '],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaDetailLoadingBody extends StatelessWidget {
  final double subtitleWidth;

  const _MediaDetailLoadingBody({required this.subtitleWidth});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShimmerPlaceholder.text(width: 220, height: 32),
            const SizedBox(height: AppSpacing.sm),
            ShimmerPlaceholder.text(width: subtitleWidth),
            const SizedBox(height: AppSpacing.xl),
            ShimmerPlaceholder.card(height: 48),
            const SizedBox(height: AppSpacing.xl),
            ShimmerPlaceholder.card(height: 140),
          ],
        ),
      ),
    );
  }
}

class _BackdropHeader extends StatelessWidget {
  final String backdropUrl;
  final Color surfaceColor;

  const _BackdropHeader({
    required this.backdropUrl,
    required this.surfaceColor,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: backdropUrl,
          fit: BoxFit.cover,
          errorWidget: (context, url, error) =>
              Container(color: Theme.of(context).colorScheme.surfaceContainer),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppGradients.heroScrim(surfaceColor),
          ),
        ),
      ],
    );
  }
}
