import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show OverScrollHeaderStretchConfiguration;

import 'package:seekarr/core/app_animation.dart';
import 'package:seekarr/core/app_gradients.dart';
import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/network/pinned_image_cache.dart';
import 'package:seekarr/core/text_scale.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/ambient_background.dart';
import 'package:seekarr/core/widgets/floating_bottom_nav_bar.dart';
import 'package:seekarr/core/widgets/glass_app_bar.dart';
import 'package:seekarr/core/widgets/media_detail_back_button.dart';
import 'package:seekarr/core/widgets/media_detail_body_metrics.dart';
import 'package:seekarr/core/widgets/media_detail_header_metrics.dart';
import 'package:seekarr/core/widgets/media_detail_poster_row.dart';
import 'package:seekarr/core/widgets/media_detail_section_label.dart';
import 'package:seekarr/core/widgets/media_detail_slot.dart';
import 'package:seekarr/core/widgets/shimmer_placeholder.dart';
import 'package:seekarr/core/widgets/staggered_entrance.dart';

/// A reusable view for displaying media details with a cinematic collapsing
/// hero, compact poster/title block, and a six-region sliver body.
///
/// The hero is a pinned [SliverPersistentHeader]: at rest it is the full
/// backdrop stage; on scroll the art parallaxes away, the scrim deepens, the
/// poster row slides under the incoming content, and a glass title bar
/// materialises with [title]. On iOS/macOS bouncing physics, pulling down
/// stretches the backdrop.
///
/// The body is declared as a [MediaDetailBody] — six named regions, emitted in
/// one fixed order, each holding [MediaDetailSlot]s. The spine owns every
/// heading, every gap and every horizontal inset; a caller owns only content.
/// That is what makes the section order a structural guarantee rather than
/// seven screens' worth of good intentions.
class MediaDetailView extends StatelessWidget {
  final String? posterUrl;
  final Map<String, String>? posterHeaders;

  /// Optional backdrop image shown in the expanded header.
  final String? backdropUrl;

  /// The poster row rendered at the bottom of the hero.
  ///
  /// The poster's Hero is owned by the caller's poster row (via
  /// [MediaPosterCard]), so this view no longer needs a heroTag of its own.
  final Widget? posterRow;

  /// Title shown in the collapsed glass bar once the hero folds away.
  final String? title;

  final Widget? background;

  /// Per-service accent: the room light, every region label, the deck's verb and
  /// the current selection. Falls back to the brand primary when null, which is
  /// only correct for a page that genuinely has no service.
  final Color? accent;

  /// Glyph for the no-backdrop fallback hero.
  ///
  /// No default, deliberately. A backdrop-less series used to get a film reel on
  /// Sonarr's own page (which passed nothing) and a television on the Bazarr
  /// page (which passed one); requiring it makes that impossible.
  final IconData heroFallbackIcon;

  /// The page body, in six regions.
  final MediaDetailBody body;

  /// Pull-to-refresh, available on every variant.
  ///
  /// Owned here so the indicator, the always-scrollable physics and the hero's
  /// overscroll stretch are reconciled in one place. This replaces the old
  /// `physics` escape hatch, which existed only so two screens could feed their
  /// own [RefreshIndicator] — and left the pull gesture visibly accepted and
  /// inert on the other six.
  final Future<void> Function()? onRefresh;

  /// Whether the body's boxes cascade in with a staggered fade + rise on first
  /// mount. The replay guard is structural: the animation lives in each
  /// [StaggeredEntrance]'s `State` and fires in `initState`, so refreshes and
  /// provider invalidations rebuild in place without replaying it.
  final bool staggerSections;

  const MediaDetailView({
    super.key,
    required this.body,
    required this.heroFallbackIcon,
    this.posterUrl,
    this.posterHeaders,
    this.backdropUrl,
    this.posterRow,
    this.title,
    this.background,
    this.accent,
    this.onRefresh,
    this.staggerSections = true,
  });

  @override
  Widget build(BuildContext context) {
    // If this view mounts while its route is still pushing, hold the section
    // cascade until the transition (and the poster's Hero flight) has landed,
    // so the two motions never compete. One authored moment at a time.
    final route = ModalRoute.of(context);
    final entranceDelay =
        route != null && !(route.animation?.isCompleted ?? true)
        ? route.transitionDuration
        : Duration.zero;

    return AmbientBackground(
      accent: accent,
      child: Material(
        // Transparent, not `colorScheme.surface`: an opaque Material here
        // occludes the ambient glow entirely and the whole change becomes a
        // silent no-op that still looks right in dark theme.
        // `MaterialType.transparency` keeps the ink and text defaults without
        // painting a fill. Locked by a widget test.
        type: MaterialType.transparency,
        child: LayoutBuilder(
          // Not `MediaQuery.sizeOf`: above 840dp the shell switches to a
          // `NavigationRail`, so the window width is not the route width and a
          // column centred on the window would sit off-centre in the route. The
          // usual objection to a `LayoutBuilder` — it cannot report intrinsics —
          // does not apply to a route body that fills its parent.
          builder: (context, constraints) {
            final gutter = MediaDetailMetrics.gutterOf(constraints.maxWidth);

            Widget view = CustomScrollView(
              physics: onRefresh == null
                  ? null
                  : const AlwaysScrollableScrollPhysics(),
              slivers: [
                mediaDetailHeaderSliver(
                  context,
                  posterUrl: posterUrl,
                  posterHeaders: posterHeaders,
                  backdropUrl: backdropUrl,
                  posterRow: posterRow,
                  title: title,
                  background: background,
                  accent: accent,
                  heroFallbackIcon: heroFallbackIcon,
                ),
                ..._emitBody(context, gutter, entranceDelay),
                // The Nav Clearance Rule, unconditionally and in exactly one
                // place: the floating bar overlaps this scroll view and grows
                // with the reading size, so the last slot cannot end on a
                // constant.
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: FloatingNavBarMetrics.getScrollViewBottomPadding(
                      context,
                    ),
                  ),
                ),
              ],
            );

            if (onRefresh != null) {
              // `edgeOffset` puts the spinner below the pinned collapsed bar
              // instead of behind the stretching backdrop, so the indicator and
              // the hero's `OverScrollHeaderStretchConfiguration` stop reading
              // as one gesture with two claimants. The delegate is untouched.
              view = RefreshIndicator(
                color: accent,
                edgeOffset: MediaDetailHeaderMetrics.minExtent(context),
                onRefresh: onRefresh!,
                child: view,
              );
            }
            return view;
          },
        ),
      ),
    );
  }

  /// Flattens [body] into top-level slivers, in canonical region order.
  ///
  /// Every slot contributes real slivers rather than rows inside one
  /// `SliverToBoxAdapter(Column(...))`, which is what lets a `SliverList.builder`
  /// stay lazy *and* land mid-page. A 250-episode season builds the eight rows
  /// on screen, not 250.
  ///
  /// Gaps live here and nowhere else — a caller that pads its own slot is
  /// fighting the page's rhythm. The 24-above / 8-below asymmetry around a label
  /// is the grouping mechanism (DESIGN.md: sections separated by 24dp, plus the
  /// `/services` engraved header's asymmetric-proximity argument). No dividers,
  /// no boxes around labels.
  List<Widget> _emitBody(
    BuildContext context,
    double gutter,
    Duration entranceDelay,
  ) {
    final labelAccent = accent ?? Theme.of(context).colorScheme.primary;
    final horizontal = EdgeInsets.symmetric(horizontal: gutter);
    final slivers = <Widget>[];

    var staggerIndex = 0;

    /// One stagger unit. A label and its box share an index so they arrive as
    /// one object; a lazy list and a rail are never wrapped at all — a
    /// [StaggeredEntrance] inside a `SliverList.builder` fires in `initState` on
    /// every scroll-in and replays forever.
    Widget stagger(Widget child, int index) {
      if (!staggerSections) return child;
      return StaggeredEntrance(
        index: index,
        wrapCount: 0,
        delay: entranceDelay,
        child: child,
      );
    }

    // Region 1 — the deck. Never labelled: it is the answer, not a section.
    //
    // Skipped entirely when null rather than padded around a blank box: the four
    // variants whose status resolver does not exist yet used to pass
    // `SizedBox.shrink()`, and this padding then sat their first region 16pt
    // lower than every other page's.
    if (body.deck != null) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(gutter, AppSpacing.lg, gutter, 0),
            child: stagger(body.deck!, staggerIndex++),
          ),
        ),
      );
    }

    // Region 2 — the readout. A bleeding rail: it owns its own horizontal
    // padding so the first cell aligns to the column while the rail runs past
    // it.
    //
    // The `left` inset is the *surplus* the centred column takes on above
    // `bodyMaxWidth`, and it is zero on every phone. A caller builds the readout
    // outside this `LayoutBuilder`, so it cannot know the resolved gutter; its
    // own padding is the screen gutter, and adding the surplus here lands its
    // first cell on the column edge on a wide macOS window without touching the
    // frozen `Widget?` signature. The rail still bleeds off the trailing edge.
    if (body.readout != null) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(
              top: AppSpacing.md,
              left: math.max(0.0, gutter - AppSpacing.lg),
            ),
            child: stagger(body.readout!, staggerIndex++),
          ),
        ),
      );
    }

    for (final slot in body.slots) {
      final index = staggerIndex++;
      final hasLabel = slot.label != null && slot.label!.trim().isNotEmpty;

      if (hasLabel) {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(
                left: gutter,
                right: gutter,
                top: AppSpacing.xl,
                bottom: AppSpacing.sm,
              ),
              child: stagger(
                MediaDetailSectionLabel(
                  label: slot.label!,
                  accent: labelAccent,
                  count: slot.count,
                  action: slot.labelAction,
                ),
                index,
              ),
            ),
          ),
        );
      } else {
        // An unlabelled slot buys its own section gap: it either follows the
        // deck or another region, or — on a deck-less variant — it is the first
        // thing under the hero, which wants the same air.
        slivers.add(
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
        );
      }

      // `.lazy`'s leading box shares the label's clock: a selector row and the
      // heading it belongs to are one object.
      if (slot.leadingBox != null) {
        slivers.add(
          SliverToBoxAdapter(child: stagger(slot.leadingBox!, index)),
        );
      }

      if (slot.box != null) {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: horizontal,
              child: stagger(slot.box!, index),
            ),
          ),
        );
      } else if (slot.sliver != null) {
        slivers.add(SliverPadding(padding: horizontal, sliver: slot.sliver!));
      } else if (slot.railBuilder != null) {
        slivers.add(SliverToBoxAdapter(child: slot.railBuilder!(horizontal)));
      }
    }

    return slivers;
  }
}

/// Builds the shared pinned hero header sliver.
///
/// Used by both [MediaDetailView] and [MediaDetailLoadingView] so the header
/// geometry is identical in the loading and loaded states — swapping one for
/// the other produces zero header displacement.
@visibleForTesting
Widget mediaDetailHeaderSliver(
  BuildContext context, {
  String? posterUrl,
  Map<String, String>? posterHeaders,
  String? backdropUrl,
  Widget? posterRow,
  String? title,
  Widget? background,
  Color? accent,
  IconData heroFallbackIcon = Icons.movie_outlined,
  bool isLoading = false,
}) {
  // Resolved here, not inside the delegate: `stretchConfiguration` is queried
  // by the render object outside the build phase, where MediaQuery lookups
  // are unavailable.
  final reduceMotion = MediaQuery.disableAnimationsOf(context);

  return SliverPersistentHeader(
    pinned: true,
    delegate: _MediaDetailHeaderDelegate(
      routeAnimation: ModalRoute.of(context)?.animation,
      minExtentValue: MediaDetailHeaderMetrics.minExtent(context),
      maxExtentValue: MediaDetailHeaderMetrics.maxExtent(context),
      posterUrl: posterUrl,
      posterHeaders: posterHeaders,
      backdropUrl: backdropUrl,
      posterRow: posterRow,
      title: title,
      background: background,
      accent: accent,
      heroFallbackIcon: heroFallbackIcon,
      isLoading: isLoading,
      surfaceColor: Theme.of(context).colorScheme.surface,
      reduceMotion: reduceMotion,
    ),
  );
}

class _MediaDetailHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double minExtentValue;
  final double maxExtentValue;
  final String? posterUrl;
  final Map<String, String>? posterHeaders;
  final String? backdropUrl;
  final Widget? posterRow;
  final String? title;
  final Widget? background;
  final Color? accent;
  final IconData heroFallbackIcon;
  final bool isLoading;
  final Color surfaceColor;
  final bool reduceMotion;

  /// The owning route's animation, used to develop the backdrop behind the
  /// poster's Hero flight (fade + settle from a slight zoom). Null when the
  /// view is not hosted in a route.
  final Animation<double>? routeAnimation;

  _MediaDetailHeaderDelegate({
    this.routeAnimation,
    required this.minExtentValue,
    required this.maxExtentValue,
    required this.posterUrl,
    required this.posterHeaders,
    required this.backdropUrl,
    required this.posterRow,
    required this.title,
    required this.background,
    required this.accent,
    required this.heroFallbackIcon,
    required this.isLoading,
    required this.surfaceColor,
    required this.reduceMotion,
  });

  @override
  double get minExtent => minExtentValue;

  @override
  double get maxExtent => maxExtentValue;

  /// Overscroll stretch of the backdrop on bouncing physics (iOS/macOS).
  /// Under clamping physics (Android) this is a silent no-op, and under
  /// Reduce Motion the stretch is disabled — the scene must not grow on its
  /// own past the finger's pull.
  @override
  OverScrollHeaderStretchConfiguration? get stretchConfiguration =>
      reduceMotion ? null : _stretchConfiguration;
  static final _stretchConfiguration = OverScrollHeaderStretchConfiguration();

  // Deliberately always true: [posterRow] and [background] are caller-built
  // widgets that are never `==` across a parent rebuild, so memoising here
  // would produce a header whose title/art silently go stale after a refresh.
  // The rebuild is one Stack; it is cheap.
  @override
  bool shouldRebuild(covariant _MediaDetailHeaderDelegate oldDelegate) => true;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The framework lays this child out at
        // max(minExtent, maxExtent - shrinkOffset) + stretchOffset, so the
        // box height is the single source of truth for both the collapse
        // progress and the overscroll stretch.
        final h = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : maxExtentValue;
        final range = math.max(1.0, maxExtentValue - minExtentValue);
        final t = ((maxExtentValue - h) / range).clamp(0.0, 1.0);
        final stretch = math.max(0.0, h - maxExtentValue);
        final phase = MediaDetailHeroPhase(t: t, reduceMotion: reduceMotion);

        return _MediaDetailHeader(
          phase: phase,
          routeAnimation: routeAnimation,
          stretch: stretch,
          range: range,
          maxExtentValue: maxExtentValue,
          minExtentValue: minExtentValue,
          posterUrl: posterUrl,
          posterHeaders: posterHeaders,
          backdropUrl: backdropUrl,
          posterRow: posterRow,
          title: title,
          background: background,
          accent: accent,
          heroFallbackIcon: heroFallbackIcon,
          isLoading: isLoading,
          surfaceColor: surfaceColor,
        );
      },
    );
  }
}

class _MediaDetailHeader extends StatelessWidget {
  final MediaDetailHeroPhase phase;
  final Animation<double>? routeAnimation;
  final double stretch;
  final double range;
  final double maxExtentValue;
  final double minExtentValue;
  final String? posterUrl;
  final Map<String, String>? posterHeaders;
  final String? backdropUrl;
  final Widget? posterRow;
  final String? title;
  final Widget? background;
  final Color? accent;
  final IconData heroFallbackIcon;
  final bool isLoading;
  final Color surfaceColor;

  const _MediaDetailHeader({
    required this.phase,
    required this.routeAnimation,
    required this.stretch,
    required this.range,
    required this.maxExtentValue,
    required this.minExtentValue,
    required this.posterUrl,
    required this.posterHeaders,
    required this.backdropUrl,
    required this.posterRow,
    required this.title,
    required this.background,
    required this.accent,
    required this.heroFallbackIcon,
    required this.isLoading,
    required this.surfaceColor,
  });

  /// How fast the poster row exits under the incoming content edge, as a
  /// multiple of the collapse range. 0.7 clears the tallest row (a 123pt
  /// poster scaled to 0.86 plus the 16pt inset ≈ 122pt against a 184pt range)
  /// with margin, so by t = 1 the row is fully clipped and only the glass bar
  /// remains. Under Reduce Motion the row moves at exactly content speed
  /// instead (factor 1.0) — a plain scroll with no differential motion.
  double get _posterExitFactor => phase.reduceMotion ? 1.0 : 0.7;

  @override
  Widget build(BuildContext context) {
    final t = phase.t;
    final barVisible = phase.barReveal >= 0.5;

    Widget backdropGroup = Stack(
      fit: StackFit.expand,
      children: [
        if (backdropUrl != null && backdropUrl!.isNotEmpty)
          _BackdropHeader(backdropUrl: backdropUrl!)
        else
          _FallbackHeroBackdrop(
            posterUrl: posterUrl,
            posterHeaders: posterHeaders,
            surfaceColor: surfaceColor,
            fallbackIcon: heroFallbackIcon,
          ),
        if (accent != null)
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppGradients.serviceGlow(
                  accent!,
                  center: Alignment.topRight,
                  radius: 1.3,
                  alpha: phase.glowAlpha,
                ),
              ),
            ),
          ),
      ],
    );
    // Destination settle: the scene develops behind the poster's Hero flight —
    // the art fades in and eases home from a slight zoom as the push
    // completes, and reverses under an interactive pop. Identity once the
    // route is settled (value 1), so resting frames are unaffected.
    if (routeAnimation != null && !phase.reduceMotion) {
      // `drive(CurveTween(...))` and never a `CurvedAnimation`, which is not a
      // style choice: this build runs from a `SliverPersistentHeaderDelegate`
      // whose `shouldRebuild` is deliberately always true, inside a
      // `LayoutBuilder` — so it runs once per frame for the whole collapse
      // range. `CurvedAnimation`'s constructor registers a status listener on
      // its parent that only `dispose()` removes, and the parent here is the
      // *route's* animation, which outlives every one of those frames; each
      // scroll frame therefore left another listener on it, for the life of the
      // page. A `CurveTween` allocates none, and with no `reverseCurve` a
      // `CurvedAnimation` evaluates to exactly this.
      final settle = routeAnimation!.drive(
        CurveTween(curve: AppAnimation.emphasizedCurve),
      );
      backdropGroup = FadeTransition(
        opacity: settle,
        child: ScaleTransition(
          scale: settle.drive(Tween<double>(begin: 1.06, end: 1.0)),
          child: backdropGroup,
        ),
      );
    }

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Art + scrim, stopping one gutter short of the header's own bottom
          // edge so the seam band below can carry the scrim's floor tone out to
          // nothing. See the band for why.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: AppSpacing.lg,
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Backdrop group: art + accent glow, kept at the full
                  // expanded height and translated for parallax so the
                  // shrinking box never reveals a gap. The glow lives inside
                  // the group so the room light scrolls away with the art
                  // instead of staying hot in the corner of a slim bar.
                  Positioned(
                    top: -(t * range * phase.parallaxFactor),
                    left: 0,
                    right: 0,
                    height: maxExtentValue + stretch,
                    child: backdropGroup,
                  ),
                  // Legibility scrim over the visible band; deepens as the art
                  // gives way to chrome.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: AppGradients.heroScrim(
                            surfaceColor,
                            depth: phase.scrimDepth,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // The permeable bottom edge.
          //
          // `heroScrim` bottoms out on *opaque* `surface`, which occludes the
          // page's ambient accent radials — while the body one pixel below
          // shows them. Measured on a 390x844 phone with a violet accent, that
          // put a hard single-row step of up to 19/255 in the blue channel
          // across the full width, at every collapse position and in both
          // themes, worsening as the header shrinks toward the hotter part of
          // the glow. An opaque strip cutting the room's gradient is the exact
          // seam `AmbientBackground` + `GlassSurface` were introduced to
          // remove; it simply came back at the hero's lower edge once the body
          // became ambient-lit.
          //
          // So the fix is the house discipline, not a blur: a gradient scrim
          // that continues the art group's own floor tone and fades it to
          // nothing, letting the room read through the last gutter. Same RGB at
          // both stops with only the alpha moving — lerping to
          // `Colors.transparent` would travel through transparent *black* and
          // smudge a grey band across the light theme.
          //
          // One gutter, not more: at full collapse this band is the pinned
          // bar's bottom 16pt, which sits clear of the bar's title, so the
          // collapsed title keeps its full backing while content still fades
          // under the bar instead of being cut by it. Costs no `saveLayer` —
          // the art group is clipped short rather than masked, so the poster
          // row (a Hero source that must never be faded), the glass bar and the
          // back button all stay outside it.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: AppSpacing.lg,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [surfaceColor, surfaceColor.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
          if (background != null) background!,
          // Poster row: glued to the rising bottom edge (content speed) plus
          // an exit push so it slides under the incoming content and is fully
          // clipped by the time the bar owns the band. Never wrapped in an
          // Opacity — a Hero source at opacity 0 would make the return flight
          // materialise from nothing instead of sliding out from under the
          // bar. The damped `stretch * 0.35` holds the row near the bottom
          // while the art stretches further on overscroll.
          Positioned(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom:
                AppSpacing.lg + stretch * 0.35 - t * range * _posterExitFactor,
            child: ExcludeSemantics(
              // Exactly one spoken title at a time: the row hands off to the
              // collapsed bar on the same threshold the bar becomes real.
              excluding: barVisible,
              child: Transform.scale(
                scale: phase.posterScale,
                alignment: Alignment.bottomLeft,
                child: posterRow ?? const SizedBox.shrink(),
              ),
            ),
          ),
          // Collapsed glass bar. GlassSurface is a gradient scrim, not a
          // BackdropFilter — the No-Blur-Under-Scroll rule applies to a
          // pinned bar with content scrolling beneath it.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: minExtentValue,
            child: IgnorePointer(
              ignoring: !barVisible,
              child: Opacity(
                opacity: phase.barReveal,
                child: GlassSurface(
                  child: _CollapsedBarContent(
                    title: title,
                    isLoading: isLoading,
                    excludeSemantics: !barVisible,
                  ),
                ),
              ),
            ),
          ),
          // Back button: outside the fading bar so it is never less than
          // fully opaque or untappable at any scroll position.
          _MorphingBackButton(reveal: phase.barReveal),
        ],
      ),
    );
  }
}

class _CollapsedBarContent extends StatelessWidget {
  final String? title;
  final bool isLoading;
  final bool excludeSemantics;

  const _CollapsedBarContent({
    required this.title,
    required this.isLoading,
    required this.excludeSemantics,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;

    Widget content;
    if (title != null && title!.trim().isNotEmpty) {
      content = ExcludeSemantics(
        excluding: excludeSemantics,
        child: Semantics(
          header: true,
          child: Text(
            title!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium!.weight(FontWeight.w700),
          ),
        ),
      );
    } else if (isLoading) {
      content = ExcludeSemantics(child: ShimmerPlaceholder.text(width: 140));
    } else {
      content = const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      // The bar's height grew on the single-line-chrome clamp, so its text
      // must lay out on the same clamp — otherwise a 2x reader gets an
      // overflow stripe instead of the promised ellipsis.
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaleMetrics.clampedScalerOf(
            context,
            maxScaleFactor: TextScaleMetrics.singleLineChromeMaxScaleFactor,
          ),
        ),
        child: Row(
          children: [
            // Read off the button, never restated: a hardcoded 44 here is what
            // made `MediaDetailBackButton.targetSize` unraisable from outside
            // that file.
            const SizedBox(width: MediaDetailBackButton.barClearance),
            Expanded(child: Center(child: content)),
            const SizedBox(width: MediaDetailBackButton.barClearance),
          ],
        ),
      ),
    );
  }
}

/// Positions [MediaDetailBackButton], which owns both poses — a dark floating
/// disc over the expanded artwork, and a bare chrome glyph centred in the
/// collapsed glass bar. Shared with the placeholder/error pages so the two
/// cannot drift apart.
class _MorphingBackButton extends StatelessWidget {
  /// Bar reveal progress, 0 (over art) → 1 (in bar).
  final double reveal;

  const _MorphingBackButton({required this.reveal});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaDetailBackButton.topOffsetFor(context, reveal),
      // Derived, not `AppSpacing.md`: the inset that keeps the *plate* on the
      // content gutter is a function of the target and plate sizes, so it moves
      // with them instead of silently drifting when either changes.
      left: MediaDetailBackButton.gutterAlignedLeftInset,
      child: MediaDetailBackButton(reveal: reveal),
    );
  }
}

class _FallbackHeroBackdrop extends StatelessWidget {
  final String? posterUrl;
  final Map<String, String>? posterHeaders;
  final Color surfaceColor;
  final IconData fallbackIcon;

  const _FallbackHeroBackdrop({
    required this.surfaceColor,
    this.posterUrl,
    this.posterHeaders,
    this.fallbackIcon = Icons.movie_outlined,
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
                    cacheManager: pinnedImageCacheFor(posterUrl),
                    width: 120,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => Icon(
                      fallbackIcon,
                      size: 90,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  )
                : Icon(
                    fallbackIcon,
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

/// Shared loading-state view for detail screen shimmer skeletons.
///
/// Builds the same pinned hero header as [MediaDetailView] (via
/// [mediaDetailHeaderSliver]) so the load → data swap produces zero header
/// displacement, and the same room and the same measure below it — same
/// [AmbientBackground], same transparent [Material], same
/// [MediaDetailMetrics.gutterOf] column — so nothing moves sideways either.
///
/// The skeleton is shaped like the body it becomes: a deck-sized card, then a
/// readout-sized rail, then a section. A generic stack of text lines and a card
/// promised a page that no longer exists.
///
/// Provide a custom [posterCard] widget (e.g. a [MediaPosterCard] with
/// an initial URL for hero animation) or leave `null` for the default
/// [ShimmerPlaceholder.card].
class MediaDetailLoadingView extends StatelessWidget {
  final Widget? posterCard;

  /// Optional poster URL rendered as a faint backdrop while loading, so the
  /// hero has visual body immediately and the real backdrop (which arrives with
  /// the data) doesn't appear to "fade in" over an empty gradient.
  final String? backdropPosterUrl;
  final Map<String, String>? backdropPosterHeaders;

  /// Mirrors [MediaDetailView.heroFallbackIcon] so the skeleton and the
  /// loaded hero agree on the fallback glyph.
  final IconData heroFallbackIcon;

  /// The service accent, so the room is already lit when the data lands.
  ///
  /// Nullable rather than required: a screen that reaches its loading branch
  /// before it knows which service it is showing (a deep link resolving an id)
  /// passes null and gets the brand primary.
  final Color? accent;

  const MediaDetailLoadingView({
    super.key,
    this.posterCard,
    this.backdropPosterUrl,
    this.backdropPosterHeaders,
    this.heroFallbackIcon = Icons.movie_outlined,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return AmbientBackground(
      accent: accent,
      child: Material(
        type: MaterialType.transparency,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final gutter = MediaDetailMetrics.gutterOf(constraints.maxWidth);

            return CustomScrollView(
              slivers: [
                mediaDetailHeaderSliver(
                  context,
                  posterUrl: backdropPosterUrl,
                  posterHeaders: backdropPosterHeaders,
                  heroFallbackIcon: heroFallbackIcon,
                  accent: accent,
                  isLoading: true,
                  posterRow: MediaDetailPosterRow(
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
                _MediaDetailLoadingBody(gutter: gutter),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MediaDetailLoadingBody extends StatelessWidget {
  final double gutter;

  const _MediaDetailLoadingBody({required this.gutter});

  /// Deck height at the default reading size: a tone well and a two-line status
  /// run, a 48pt action band and the monitor row.
  static const double _deckHeight = 132.0;

  /// One row of readout cells.
  static const double _readoutHeight = 78.0;

  /// A first section — the manifest, usually.
  static const double _sectionHeight = 140.0;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        // The Nav Clearance Rule applies to the skeleton too: the floating bar
        // overlaps this scroll view exactly as it overlaps the loaded one, and
        // it grows with the reading size, so the last shimmer card cannot end on
        // a constant.
        padding: EdgeInsets.fromLTRB(
          gutter,
          AppSpacing.lg,
          gutter,
          FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShimmerPlaceholder.card(height: _deckHeight),
            const SizedBox(height: AppSpacing.md),
            ShimmerPlaceholder.card(height: _readoutHeight),
            const SizedBox(height: AppSpacing.xl),
            ShimmerPlaceholder.card(height: _sectionHeight),
          ],
        ),
      ),
    );
  }
}

class _BackdropHeader extends StatelessWidget {
  final String backdropUrl;

  const _BackdropHeader({required this.backdropUrl});

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: backdropUrl,
      cacheManager: pinnedImageCacheFor(backdropUrl),
      fit: BoxFit.cover,
      errorWidget: (context, url, error) =>
          Container(color: Theme.of(context).colorScheme.surfaceContainer),
    );
  }
}
