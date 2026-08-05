/// The stack matrix: the instrument at the top of `/services`.
///
/// One cell per configured service, answering three questions at once —
/// *is it reachable* (the pip and the state word), *what is it doing* (the live
/// line), and *take me there* (the whole cell is the button). That is why this
/// replaced a status grid and a separate feed: they were the same three
/// questions asked in three places.
///
/// Lives in the feature rather than in `lib/core/widgets/` because it is the
/// anatomy of exactly one screen. Convention reserves `core/widgets` for
/// genuinely reusable components, and a matrix cell that hard-codes the
/// `/services/{key}` destination is not one.
///
/// ## Why there is no horizontal scroll here
///
/// The grid this replaced laid 13 services out in two rows scrolling sideways,
/// column-major, sized so the next card was clipped at 80% as a scroll hint.
/// Three things were wrong with that and all three are load-bearing for the
/// design: reading order ran top-left, bottom-left, top-right, so the grid had
/// to be decoded rather than scanned; the page scrolls vertically while the
/// primary readout scrolled horizontally, so the first two gestures fought; and
/// the single cell that matters — the one that is down — had an even chance of
/// being off-screen. A health readout you have to swipe to finish is not one.
///
/// ## The two densities
///
/// A band renders its services either **expanded** or **compact**, and both are
/// cards. The fold used to swap the cells for a strip of bare 24pt glyphs,
/// which answered "is anything dark in here" and nothing else — you could see
/// that Lidarr was out but not that Radarr was missing twelve films, and it was
/// a second try at the same problem that had put a live figure on every
/// compact card: at three-to-a-row and barely 30pt tall, a figure and a metric word
/// had nowhere to sit without either eliding or reintroducing the wall of
/// numbers the quiet cell exists to avoid. So the compact card asks a smaller
/// question than the expanded one — glyph, name, and a coloured dot for
/// reachability — and what expanding adds is the figure, the host, and the
/// light. The dot is not a downgrade of the state word; it is the same
/// three-value reachability the expanded card spells out, just carried by
/// colour where there is no room for a sentence.
///
/// ## The compact card is a card, not a chip
///
/// Two properties keep it one, and both were fixed after the folded matrix was
/// caught reading as a filter-chip strip.
///
/// **The radius is on the fold clock**, `md` compact to `lg` open. It was a
/// constant `lg` at both densities — the only dimension in a container
/// transform that did not move — and at 32pt tall a 16dp radius is *exactly*
/// half the height, which is a stadium. Thirteen stadiums in wrapping rows,
/// each with a coloured pip at its trailing edge, is chip anatomy, and the
/// Pill-for-Metadata Rule had already ruled on it: full radius is metadata, an
/// interactive container stays on the 12dp default.
///
/// **The press feedback is the scale, not the ink**, for the same reason: a
/// ripple flooding a stadium *is* the feedback of a chip being selected, where
/// a card that navigates should dip under the thumb. This cell is what
/// `AppCardPressFeedback` was added for — the first attempt bypassed
/// `AppCard`'s `onTap` and wrapped the card from outside, which also moved it
/// onto the untappable branch whose border insets its child, and cost
/// [ServiceMatrixMetrics.compactCellBaseHeight] two points it should not have
/// had to spend.
///
/// ## Why the cell is quiet
///
/// The first version packed identity, a figure, a metric word and a host into
/// 168×96pt and bought the hierarchy that space could not give it with weight:
/// an 800-weight `titleMedium` figure beside an uppercase eyebrow tracked out to
/// +1.4. One cell reads well. Thirteen are a wall of shouting, and DESIGN.md's
/// Eyebrow Rule says why — the eyebrow "earns its emphasis by being rare", and
/// a grid is the definition of not rare.
///
/// The card that replaced *that* over-corrected into the other failure: an icon
/// tile, a name, a figure and a host, stacked and evenly spaced in a rounded
/// rectangle — the same-size card of icon plus heading plus text, which is the
/// lazy container. The current one keeps the quiet and drops the box: the tile
/// is gone and the glyph is drawn in the service's own colour, a faint wash of
/// that colour lights the card from its top-left corner, the host tucks under
/// the name as its subtitle, and the live readout gets a tier of its own.
/// Emphasis is still scarce — tone and the metric's icon arrive only when
/// [ServiceSignal.needsAttention] — but the card is now lit rather than drawn.
///
/// ## The header is engraved on the panel, not boxed on top of it
///
/// [_DomainBand]'s header is an eyebrow row — kicker, service count, the
/// folded band's rollup at the trailing edge, and an unfold glyph — with no
/// fill and no border. Grouping is carried by **proximity** alone: the gap
/// from a header up to the previous band's cards is several times the gap
/// down to its own, so a squint still reveals which cards belong to which
/// label.
///
/// It was a boxed lid once — the same `surfaceContainer`-over-`outlineVariant`
/// recipe a cell uses — and the box was the mistake, three times over. A
/// folded band's compact cards are *smaller than the lid that introduces
/// them*, so the screen's chrome outweighed its instruments; the page's own
/// hierarchy inverted, because "Services" and "Downloading" are bare text
/// while their subordinate group labels wore containers; and a full-width
/// contained row with a chevron is the visual idiom of a list row that
/// navigates somewhere. The engraved row keeps the two things the lid
/// actually fixed — the asymmetric gaps, and an ink splash shaped by
/// `customBorder` rather than Flutter's bare rectangle — and gives back the
/// mass.
///
/// The rollup is what makes the header worth its line. Folding a band hides
/// every card's figure, so the header carries the one fact the closed band
/// would otherwise swallow — "3 pending · 1 down" — and hands it off to the
/// cards as the band opens. And the affordance glyph is `unfold_more`, the
/// double vertical arrow: the fold is a *density* toggle, its cards visible
/// in both states, and "these get taller" is the honest metaphor where a
/// rotating chevron promised a disclosure.
library;

import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_animation.dart';
import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/service_theme.dart';
import 'package:seekarr/core/text_scale.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/pressable_scale.dart';
import 'package:seekarr/core/widgets/shimmer_placeholder.dart';
import 'package:seekarr/core/widgets/status_badge.dart';
import 'package:seekarr/features/services/domain/service_signal.dart';
import 'package:seekarr/features/services/domain/services_semantics.dart';
import 'package:seekarr/features/services/presentation/service_kpi_provider.dart';
import 'package:seekarr/features/services/presentation/service_matrix_collapse_provider.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// Reachability of one service, as the matrix paints it.
///
/// `checking` is a state of its own rather than "offline with a different word".
/// The grid this replaced fabricated an offline summary while loading, which made
/// its border resolve to error red — so every service flashed as failed on cold
/// open, before a single request had come back.
enum ServiceReachability { online, checking, offline }

/// Layout constants for the matrix grid.
class ServiceMatrixMetrics {
  ServiceMatrixMetrics._();

  /// Preferred cell width. Columns are resolved against this, not declared.
  static const double preferredCellWidth = 168;

  /// The folded card is narrower as well as shorter, so a phone fits three
  /// across instead of two. Six services fold from three rows of 96pt to two
  /// rows of 32, on a tighter row gap besides — a Media band goes from roughly
  /// 300pt to well under 80. Two columns of short cards was still a column of
  /// cards; this is a strip you scan.
  static const double compactPreferredCellWidth = 104;

  /// Minimum columns, per the Column Floor Rule: the count is a floor, and a
  /// single-column matrix would read as a list of unrelated rows rather than as
  /// one instrument.
  static const int minColumns = 2;

  /// Gap between cells, both axes, for the expanded card.
  static const double gap = AppSpacing.sm;

  /// Vertical gap between rows of *compact* cards.
  ///
  /// Deliberately tighter than [gap]: three short cards to a row already read
  /// as a strip rather than a stack, and the standard `sm` row gap — tuned for
  /// 96pt cards with three lines each — reads as loose air between rows that
  /// are mostly border. The column gap stays `gap`; only the row-to-row
  /// spacing tightens.
  static const double compactRowGap = AppSpacing.xs;

  /// The service glyph, drawn straight on the card.
  ///
  /// No tile behind it. A 28pt rounded square holding a 16pt icon is an avatar,
  /// and thirteen of them in a grid are the visual signature of a template. The
  /// colour alone carries the identity now, which is also what lets the wash
  /// below do the rest of the work.
  static const double glyphSize = 18;
  static const double compactGlyphSize = 14;

  /// Strength of the accent wash lighting a live card from its top-left corner.
  ///
  /// Deliberately the same 0.14 the icon tile this replaced used for its fill:
  /// the card carries exactly as much of the service's colour as before, spread
  /// as light across a corner instead of stamped into a 28pt square. That is the
  /// whole move, and keeping the quantity identical is what keeps it inside the
  /// Room Light Rule's documented `/services` exception rather than widening it.
  ///
  /// Rendered at 0.08 first and it was invisible — under a tenth of a step on
  /// the dark surface ladder, which is a decision nobody can see. Signature
  /// strength (0.22) is the other failure: one card owning a screen can take it,
  /// six in a band cannot.
  static const double accentWashAlpha = 0.14;

  /// Cell height before text growth: glyph row, host, and the readout tier.
  static const double cellBaseHeight = 96;

  /// How much of [cellBaseHeight] follows the reading size.
  ///
  /// Unchanged by the type ramp's new per-role line heights, and deliberately
  /// so: the app root installs a [DefaultTextHeightBehavior] with
  /// `applyHeightToFirstAscent` and `applyHeightToLastDescent` both false, so
  /// the leading applies only *between* lines while a block's outer edges keep
  /// Inter's natural metrics. Every role in the ramp measures the same for a
  /// single line as it did before — `bodyLarge` 19.0, `bodySmall` 15.0,
  /// `labelSmall` 13.0 — and every line in this cell is a single line. Growing
  /// this constant against the raw `height` multipliers would only make the
  /// cells too tall.
  static const double cellTextHeight = 54;

  /// The folded card: one line — glyph, name, connection dot — and nothing
  /// else. No figure, no host; those are what expanding is for.
  ///
  /// This is the box the *row* reserves, and it has to track the card's own
  /// intrinsic height or the difference shows up as dead air around the card
  /// rather than as padding inside it — a `SizedBox`-then-`Row` slot centers a
  /// smaller child instead of stretching it, so a slot taller than the card
  /// reads as extra space *between* rows, not extra space *in* the card.
  /// Raising this without also raising [compactVerticalPadding] is exactly the
  /// bug that shipped first: the card stayed the same size and the gap grew.
  ///
  /// It is `sm` + a `bodySmall` line + `sm`, with nothing spare, which held
  /// only once `AppCard` grew `AppCardPressFeedback`. The first pass took the
  /// press-scale by leaving `AppCard`'s `onTap` unset and wrapping the card
  /// from outside, which silently moved it onto the untappable branch — a
  /// `Container` whose `BoxDecoration.border` *insets* its child 1px per side
  /// where the tappable `Material`'s `shape` costs no layout — and the line
  /// overflowed by exactly 2. `AppCard` now keeps the `Material` in both
  /// feedback modes, so the interior is the same either way and this can stay
  /// an honest 32.
  ///
  /// "Nothing spare" survived the type ramp intact: see [cellTextHeight] for
  /// why the root's [DefaultTextHeightBehavior] keeps a single `bodySmall` line
  /// at exactly the 15.0pt it always measured, so `sm` + line + `sm` still fits.
  static const double compactCellBaseHeight = 32;
  static const double compactCellTextHeight = 20;

  /// Vertical padding inside the compact card.
  ///
  /// One step up from the expanded-card baseline (`xs`) to `sm` — the ask was
  /// for slightly more room around the single line, and `sm` is the next rung
  /// on the spacing scale. Horizontal padding is unchanged.
  static const double compactVerticalPadding = AppSpacing.sm;

  /// How long a band takes to open, and to close.
  ///
  /// Opening is a layout transition with real travel — cards change column,
  /// change size and gain two lines — so it sits at the `lg` end of the scale
  /// rather than the `md` used for a simple state change. Closing is a step
  /// quicker: the exit is a reversal the user already knows the shape of, and
  /// waiting out the full entrance to put something away reads as latency.
  static const Duration foldOpenDuration = AppAnimation.durationLg;
  static const Duration foldCloseDuration = AppAnimation.durationMd;

  /// Columns that fit [availableWidth], never fewer than [minColumns].
  ///
  /// The compact preferred width follows [textScale], so the folded grid gives
  /// up density as the reading size grows rather than holding three columns and
  /// eliding the service names. Truncating "qBittorrent" to "qBittor…" costs
  /// more than a row does: the name is the card's primary, and at 104pt with
  /// 24pt type there is nothing else the layout can give back. Two columns at
  /// 1.6x, three at the default.
  ///
  /// The full card does not need the same treatment — 168pt already resolves to
  /// the [minColumns] floor on a phone.
  static int resolveColumns(
    double availableWidth, {
    bool compact = false,
    double textScale = 1.0,
  }) {
    final preferred = compact
        ? compactPreferredCellWidth * textScale
        : preferredCellWidth;
    final fit = ((availableWidth + gap) / (preferred + gap)).floor();
    return fit < minColumns ? minColumns : fit;
  }
}

/// Where a band is between folded (0) and open (1), and what each part of the
/// card should read off that.
///
/// One number, three curves, derived in one place — because the whole point of
/// the transition is that the box, the light and the contents are the *same*
/// event seen from three angles, and three widgets each easing their own copy
/// of `t` is how that stops being true.
///
/// The staging is deliberate and it is the thesis: **geometry leads, content
/// follows.** [geometry] is already 94% done by the time [detail] starts
/// moving, so the card finishes claiming its space before anything is asked to
/// appear inside it. The alternative — fading the host in while the box is
/// still growing under it — is what makes an expanding card feel like two
/// unrelated animations that happen to share a start time.
@immutable
class _FoldPhase {
  const _FoldPhase(this.t);

  /// Linear progress, 0 folded to 1 open. Every curve below is applied to this
  /// and never to an already-curved value.
  final double t;

  /// Which grid cell a card belongs to — the 3-across strip or the 2-across
  /// grid — resolved early and on its own clock.
  ///
  /// Split from [geometry] because a folded band and an open band do not just
  /// differ in size, they differ in *column count*, and the third card in a
  /// three-wide strip becomes the first card of the second row. Interpolating
  /// position and size together sends that card diagonally through the card
  /// currently sitting where it is headed: at the halfway point two opaque
  /// cards occupy the same pixels and one simply disappears behind the other.
  ///
  /// Running the reflow first, while every card is still folded-size and inside
  /// folded row pitch, keeps the swap inside the strip's own tight geometry
  /// where the cards are small and the crossings are glancing. By the time
  /// anything grows, every card is already in the lane it will finish in.
  /// Deliberately over in the first ~40% of the fold. Two cards trading places
  /// must pass through each other at *some* point — no simultaneous path
  /// avoids it — so the goal is not to eliminate the crossing but to spend as
  /// little time in it as possible. Compressed into 160ms and eased hard out,
  /// the swap is three or four frames of one card sliding behind another,
  /// which reads as exactly that; stretched across the whole 400ms it reads as
  /// a card being covered up.
  double get reflow =>
      const Interval(0, 0.4, curve: AppAnimation.emphasizedCurve).transform(t);

  /// Card width, on its own window behind [reflow].
  ///
  /// Width is a property of the column count, so it cannot ride [geometry] —
  /// a three-up card widening toward its two-up size would climb over the card
  /// beside it. But it cannot ride
  /// [reflow] either: widening *while* two cards trade places makes their
  /// footprints bigger during the one moment they are closest, and turns a
  /// glancing pass into a real occlusion.
  ///
  /// So it trails — the cards stay narrow through the swap, arrive in their
  /// new lanes still folded-width, and only then spread into them.
  double get width => const Interval(
    0.25,
    0.6,
    curve: AppAnimation.emphasizedCurve,
  ).transform(t);

  /// Size, padding, row pitch, type scale: everything that makes a folded card
  /// into an open one, once it is already standing in the right place.
  ///
  /// Overlaps [reflow]'s tail rather than waiting for it, so the two read as
  /// one continuous move and not as two beats.
  /// Card *width* is deliberately not on this clock — it belongs to [reflow],
  /// because a card's width is decided by the column count and nothing else.
  /// Growing it here instead would widen three-up cards past their own lane
  /// and stack them on their neighbours.
  double get geometry =>
      const Interval(0.3, 1, curve: AppAnimation.emphasizedCurve).transform(t);

  /// The host line and the live readout, unrolling into a box that has already
  /// almost finished opening.
  double get detail =>
      const Interval(0.45, 1, curve: AppAnimation.emphasizedCurve).transform(t);

  /// The service's accent wash, which is the last thing to arrive: a card is a
  /// card before it is a *lit* card.
  double get wash => const Interval(0.2, 1, curve: Curves.easeIn).transform(t);

  bool get isFolded => t <= 0;
  bool get isOpen => t >= 1;
}

/// Reveals [child] top-down by [value], clipping rather than squashing.
///
/// `Align(heightFactor:)` shrinks the *slot* while the child keeps its natural
/// size, so the text inside never scales or reflows on its way in — it is
/// uncovered, like a blind being raised. Scaling it instead would make the
/// glyph and the type breathe at different rates from the card around them,
/// which is the tell of a transition assembled from whatever animated widget
/// was nearest.
///
/// Both wrappers drop out at the ends: at 1 the child is returned bare, so a
/// settled card pays for no clip layer and no opacity layer per frame.
class _Unroll extends StatelessWidget {
  const _Unroll({required this.value, required this.child});

  final double value;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (value >= 1) return child;
    if (value <= 0) return const SizedBox.shrink();
    return Opacity(
      opacity: value,
      child: ClipRect(
        child: Align(
          alignment: Alignment.topLeft,
          heightFactor: value,
          child: child,
        ),
      ),
    );
  }
}

/// The whole matrix: domain bands of cells, then the unconfigured affordance.
class ServiceMatrix extends ConsumerWidget {
  const ServiceMatrix({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final configured = ServiceKey.values
        .where(settings.isServiceConfigured)
        .toList(growable: false);

    if (configured.isEmpty) return const SizedBox.shrink();

    final expanded = ref.watch(expandedServiceDomainsProvider);

    final bands = <Widget>[];
    for (final domain in ServiceDomain.values) {
      final services = domain.services
          .where(settings.isServiceConfigured)
          .toList(growable: false);
      if (services.isEmpty) continue;

      bands.add(
        _DomainBand(
          domain: domain,
          services: services,
          expanded: expanded.contains(domain),
          // Only the first band demonstrates the fold. A page that folds three
          // bands shut in sequence has not hinted at an affordance, it has
          // animated a list.
          demo: bands.isEmpty,
        ),
      );
    }

    bands.add(
      _MoreServicesHint(
        remaining: ServiceKey.values.length - configured.length,
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: bands,
    );
  }
}

/// One domain of the matrix: a foldable header over its cards.
///
/// The fold exists because thirteen services is a lot of instrument to scroll
/// past on the way to Downloading, and which third of the stack you actually
/// watch is personal. Its state is persisted, and the matrix opens folded — see
/// [expandedServiceDomainsProvider].
///
/// Note what folding no longer buys. It used to remove the cells from the tree
/// entirely, so a folded band stopped watching [serviceSignalProvider] and its
/// services stopped fetching KPIs. The compact card paints no figure at all —
/// only a name and a connection dot — but [ServiceMatrixCell] still watches the
/// signal to compose the *spoken* value, so the fetch is not reclaimed by not
/// drawing it: the fold is a space optimisation, not a network one. The cost is
/// bounded — `serviceKpiProvider` is `autoDispose` and shared with each service
/// page's KPI peek, so a folded band fetches nothing the app would not fetch
/// anyway — and a screen reader that lost the figure on fold would cost more
/// than the request saves.
class _DomainBand extends ConsumerStatefulWidget {
  const _DomainBand({
    required this.domain,
    required this.services,
    required this.expanded,
    this.demo = false,
  });

  final ServiceDomain domain;
  final List<ServiceKey> services;
  final bool expanded;

  /// Whether this band may play the fold demo on the first `/services` of the
  /// launch: it mounts **open** and folds itself shut with the real close
  /// animation, so the expanded state is shown existing rather than described.
  ///
  /// The demo used to grow the cards partway and settle back, on every
  /// landing. Both halves were wrong ways round. Partway growth demonstrated
  /// an abstraction of the transition instead of the transition — the reflow,
  /// the widening, the host unrolling were exactly the parts it skipped — and
  /// per-landing repetition meant a hub visited many times a day kept moving
  /// on its own. Starting from open and closing is the honest version: the
  /// user sees the full instrument once, watches it pack itself away into the
  /// default, and knows precisely what the unfold glyph buys. Once per launch,
  /// via [servicesFoldDemoPlayedProvider].
  ///
  /// It still never plays under Reduce Motion, and never on a band the user
  /// keeps open — there is nothing to demonstrate either way.
  final bool demo;

  @override
  ConsumerState<_DomainBand> createState() => _DomainBandState();
}

class _DomainBandState extends ConsumerState<_DomainBand>
    with SingleTickerProviderStateMixin {
  /// How long the demo holds the band open before folding it.
  ///
  /// Long enough to register as a state — the expanded cards are legible, not
  /// a flash — and to let the page's own staggered entrance finish before
  /// anything else moves. Short enough that the fold is over before a
  /// deliberate first tap could land on a moving target.
  static const _demoHold = Duration(milliseconds: 1100);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ServiceMatrixMetrics.foldOpenDuration,
    reverseDuration: ServiceMatrixMetrics.foldCloseDuration,
    // Starts settled, never animated on first build: a band restored open from
    // `services_expanded_domains` was open before the user got here, and
    // playing its entrance on arrival would claim it just happened.
    value: widget.expanded ? 1 : 0,
  );

  /// Held rather than awaited as a bare `Future.delayed`, so leaving the tab
  /// inside the hold cancels it. An uncancellable one fires into a disposed
  /// state, and the framework is right to call that a leak.
  Timer? _demoTimer;
  bool _demoDecided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decided here rather than in `initState` because the decision reads
    // `MediaQuery` — and decided exactly once, on the mount: a rebuild — a
    // pull-to-refresh, a summary arriving — must not restart a demo
    // mid-flight.
    if (_demoDecided) return;
    _demoDecided = true;

    if (!widget.demo || widget.expanded) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    if (ref.read(servicesFoldDemoPlayedProvider)) return;
    // After the frame, because `didChangeDependencies` runs during build and
    // Riverpod (rightly) refuses writes from there. Only one band carries
    // `demo`, so nothing else can race the flag inside the same frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(servicesFoldDemoPlayedProvider.notifier).markPlayed();
    });

    // Before the first frame paints, so the band *starts* open rather than
    // popping open: the demo is "this is the expanded state, and this is it
    // folding into the default", played with the real close animation.
    _controller.value = 1;
    _demoTimer = Timer(_demoHold, () {
      if (!mounted) return;
      _controller.reverse();
    });
  }

  /// The first touch anywhere in the band ends the demo: fold now rather than
  /// keep moving while the user is reaching for something. A touch during the
  /// close itself is left alone — the real close is short, and the band's own
  /// taps (the header toggle, the cells) still work throughout.
  void _cancelDemo(PointerDownEvent _) {
    final timer = _demoTimer;
    if (timer == null || !timer.isActive) return;
    timer.cancel();
    _controller.reverse();
  }

  @override
  void didUpdateWidget(_DomainBand oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded == oldWidget.expanded) return;

    // A toggle while the demo holds the band open adopts it rather than
    // replaying it: the controller is already at 1, so `forward()` is a no-op
    // and the band simply stays open — which is what the tap asked for.
    _demoTimer?.cancel();

    if (MediaQuery.disableAnimationsOf(context)) {
      // The Reduce Motion Rule: an instant state, not a fast animation.
      _controller.value = widget.expanded ? 1 : 0;
    } else if (widget.expanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _demoTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Not a `GestureDetector`: this must observe the touch without competing
      // for it, so the header's own tap and the cells' taps still win.
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: _cancelDemo,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => _build(context, _FoldPhase(_controller.value)),
      ),
    );
  }

  Widget _build(BuildContext context, _FoldPhase phase) {
    final domain = widget.domain;
    final services = widget.services;
    final expanded = widget.expanded;

    void toggle() {
      HapticFeedback.selectionClick();
      ref.read(expandedServiceDomainsProvider.notifier).toggle(domain);
    }

    // The folded band hides every card's figure, so the header carries the
    // band's single most useful fact while it is shut: the count of services
    // not answering, or failing that, the first live signal that wants
    // attention. Watching these providers here costs no extra fetch — every
    // cell in the band (compact ones included) already watches the same ones.
    var down = 0;
    String? attention;
    for (final service in services) {
      final summary = ref.watch(serviceSummaryProvider(service));
      final reachability = switch (summary) {
        AsyncData(:final value) =>
          value.isOnline
              ? ServiceReachability.online
              : ServiceReachability.offline,
        AsyncError() => ServiceReachability.offline,
        _ => ServiceReachability.checking,
      };
      if (reachability == ServiceReachability.offline) {
        down++;
      } else if (reachability == ServiceReachability.online &&
          attention == null) {
        final signal = ref.watch(serviceSignalProvider(service)).asData?.value;
        if (signal != null && signal.needsAttention) {
          attention = '${signal.value} ${signal.label}';
        }
      }
    }
    final rollupParts = [
      if (attention != null) attention,
      if (down > 0) '$down down',
    ];
    final rollup = rollupParts.isEmpty ? null : rollupParts.join(' · ');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // `expanded:` rather than an announcement on toggle: the platform speaks
        // the change off the node update, it works on TalkBack where
        // announcements are dropped, and the state stays discoverable on
        // re-focus instead of only at the moment of the tap. Same contract as
        // `CollapsibleDomainSection`.
        Semantics(
          container: true,
          explicitChildNodes: true,
          header: true,
          button: true,
          expanded: expanded,
          // The un-uppercased label: `.toUpperCase()` is typography, and
          // VoiceOver spells out all-caps tokens it does not recognise.
          label: domain.label,
          value: joinSpokenParts([
            serviceDomainBandValue(serviceCount: services.length),
            if (rollup != null && !expanded) spokenFromDotted(rollup),
          ]),
          hint: expanded ? 'collapses this group' : 'expands this group',
          onTap: toggle,
          // Generous above, tight below: the gap that separates this header
          // from the *previous* section's cards is deliberately several times
          // the gap to its *own* cards underneath. Proximity is the grouping
          // cue — before this both gaps were the same `xs`, so the header read
          // as a caption floating between two equally-distant things rather
          // than as the lid on the grid directly under it.
          child: _engravedHeader(
            context,
            phase: phase,
            onToggle: toggle,
            rollup: rollup,
          ),
        ),
        // No `AnimatedSize`. The band's height is now an explicit lerp between
        // the two grid layouts, driven by the same phase as everything inside
        // it — which is both more honest (the height and the cards can no
        // longer disagree about how open the band is) and one less zero-
        // duration implicit-animation footgun to route around.
        _ServiceMatrixBand(services: services, phase: phase),
      ],
    );
  }

  /// The engraved label — see "The header is engraved on the panel" in the
  /// library doc. No container: an eyebrow kicker with the service count, the
  /// folded rollup at the trailing edge, and an unfold glyph. Grouping is
  /// carried by the asymmetric gaps alone.
  Widget _engravedHeader(
    BuildContext context, {
    required _FoldPhase phase,
    required VoidCallback onToggle,
    String? rollup,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dim =
        theme.extension<SeekarrThemeColors>()?.dimText ??
        colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      // Press-scale, not ink. The boxed header this replaced kept Material's
      // ripple because it had a surface for the splash to live on; on a bare
      // engraved row the M3 sparkle paints a phantom box that flashes into
      // existence around the label. The Funnel Rule's press-down is the
      // system's feedback for a surfaceless tappable row — and `PressableScale`
      // brings the Reduce Motion check with it. Its haptic is off because
      // `toggle` already fires the selection click, and its own semantics node
      // is excluded the same way the InkWell's was: the band's `Semantics`
      // above carries the header contract (label, value, expanded, hint).
      child: ExcludeSemantics(
        child: PressableScale(
          onTap: onToggle,
          haptic: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Row(
                children: [
                  Text(
                    widget.domain.label.toUpperCase(),
                    style: AppTheme.eyebrow(colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '· ${widget.services.length}',
                    style: AppTheme.eyebrow(dim),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Opacity(
                      opacity: (1 - phase.geometry).clamp(0, 1),
                      child: Text(
                        rollup ?? '',
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _UnfoldGlyph(
                    progress: phase.geometry,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The density affordance: `unfold_more` crossfading to `unfold_less` as the
/// band opens, on the same clock as the cards. Vertical double arrows say
/// "these get taller" — the metaphor the fold actually is — where a rotating
/// chevron said "this navigates".
class _UnfoldGlyph extends StatelessWidget {
  const _UnfoldGlyph({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: Stack(
        children: [
          Opacity(
            opacity: (1 - progress).clamp(0, 1),
            child: Icon(Icons.unfold_more_rounded, size: 20, color: color),
          ),
          Opacity(
            opacity: progress.clamp(0, 1),
            child: Icon(Icons.unfold_less_rounded, size: 20, color: color),
          ),
        ],
      ),
    );
  }
}

/// Where every card in one grid sits, at one density.
///
/// Resolved for the folded and the open density independently, then lerped —
/// which is what makes the fold a *transform* rather than a swap. A card is not
/// removed from a three-wide strip and re-added to a two-wide grid; it is the
/// same card, told where it is at this instant.
@immutable
class _GridGeometry {
  const _GridGeometry({
    required this.count,
    required this.columns,
    required this.cellWidth,
    required this.cellHeight,
    required this.rowGap,
  });

  factory _GridGeometry.resolve({
    required int count,
    required double availableWidth,
    required double cellHeight,
    required double rowGap,
    required bool compact,
    required double textScale,
  }) {
    final columns = ServiceMatrixMetrics.resolveColumns(
      availableWidth,
      compact: compact,
      textScale: textScale,
    );
    final gaps = ServiceMatrixMetrics.gap * (columns - 1);
    return _GridGeometry(
      count: count,
      columns: columns,
      cellWidth: (availableWidth - gaps) / columns,
      cellHeight: cellHeight,
      rowGap: rowGap,
    );
  }

  final int count;
  final int columns;
  final double cellWidth;
  final double cellHeight;
  final double rowGap;

  int get rows => (count / columns).ceil();

  /// Row-major, matching reading order.
  int rowOf(int index) => index ~/ columns;

  double xOf(int index) =>
      (index % columns) * (cellWidth + ServiceMatrixMetrics.gap);

  /// Distance from one row's top edge to the next. Kept separate from [rowOf]
  /// so a card's row *assignment* and the grid's row *spacing* can be
  /// interpolated on different clocks — the reflow moves cards between rows
  /// while the pitch is still tight, then the pitch opens up underneath them.
  double get rowPitch => cellHeight + rowGap;

  double get height => rows * cellHeight + (rows - 1) * rowGap;
}

/// One domain's services, laid out at whatever point of the fold [phase] names.
///
/// A `Stack` of absolutely positioned cards rather than a `Column` of `Row`s,
/// and that is the whole animation: with both grids resolved up front, each
/// card's rect is a straight `Rect.lerp` between where it sits folded and where
/// it sits open. Rows of `Expanded` cells cannot express the in-between — a
/// card that moves from the third column of a three-wide strip to the first
/// column of the next row down is changing parents, and no amount of
/// `AnimatedSize` on the container will carry it there.
///
/// Still not a `GridView`: this sits inside the page's own scroll view, and a
/// nested scrollable would need shrink-wrapping and physics juggling for a grid
/// that never scrolls on its own.
class _ServiceMatrixBand extends StatelessWidget {
  const _ServiceMatrixBand({required this.services, required this.phase});

  final List<ServiceKey> services;
  final _FoldPhase phase;

  @override
  Widget build(BuildContext context) {
    // The box grew by the clamped scale, so the text has to be laid out at the
    // same clamp or the two disagree: `boxHeight` stops growing at 1.6x by
    // design — "compact chrome ellipsises rather than clipping" — but a `Text`
    // reads the ambient scaler, so at 3x the cell would be sized for 1.6 and
    // painted at 3. That is the overflow stripe, not an ellipsis. Same
    // `MediaQuery` clamp the floating nav bar uses to stay a bar.
    final clamped = TextScaleMetrics.clampedScalerOf(context);
    final textScale = clamped.scale(14) / 14;

    final compactHeight = TextScaleMetrics.boxHeight(
      context,
      base: ServiceMatrixMetrics.compactCellBaseHeight,
      textHeight: ServiceMatrixMetrics.compactCellTextHeight,
    );
    final fullHeight = TextScaleMetrics.boxHeight(
      context,
      base: ServiceMatrixMetrics.cellBaseHeight,
      textHeight: ServiceMatrixMetrics.cellTextHeight,
    );

    final reflow = phase.reflow;
    final t = phase.geometry;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final folded = _GridGeometry.resolve(
            count: services.length,
            availableWidth: width,
            cellHeight: compactHeight,
            rowGap: ServiceMatrixMetrics.compactRowGap,
            compact: true,
            textScale: textScale,
          );
          final open = _GridGeometry.resolve(
            count: services.length,
            availableWidth: width,
            cellHeight: fullHeight,
            rowGap: ServiceMatrixMetrics.gap,
            compact: false,
            textScale: textScale,
          );

          // Row *pitch* follows the size clock while a card's row *assignment*
          // follows the reflow clock. Multiplying the two is what keeps the
          // swap tidy: the third card slides into the second row while that
          // row is still only 36pt below the first, so it travels a short
          // distance through a strip whose cards are all 32pt tall, and only
          // then does the whole grid unfold to 104pt pitch beneath it.
          final pitch = lerpDouble(folded.rowPitch, open.rowPitch, t)!;
          final cellWidth = lerpDouble(
            folded.cellWidth,
            open.cellWidth,
            phase.width,
          )!;
          final cellHeight = lerpDouble(folded.cellHeight, open.cellHeight, t)!;
          final lastRow = lerpDouble(folded.rows - 1, open.rows - 1, reflow)!;

          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: clamped),
            child: SizedBox(
              width: width,
              // Derived from the same numbers the cards are, rather than
              // lerped independently, so the band is never shorter than the
              // card sitting lowest in it — which would clip that card against
              // the `Stack`'s edge for the length of the animation.
              height: lastRow * pitch + cellHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < services.length; i++)
                    Positioned.fromRect(
                      // Keyed by service, so the element — and the ink, the
                      // press state, the provider subscriptions — follows the
                      // card across a reflow instead of being recycled into
                      // whichever card happens to land at that index.
                      key: ValueKey(services[i]),
                      rect: Rect.fromLTWH(
                        lerpDouble(folded.xOf(i), open.xOf(i), reflow)!,
                        lerpDouble(
                              folded.rowOf(i).toDouble(),
                              open.rowOf(i).toDouble(),
                              reflow,
                            )! *
                            pitch,
                        cellWidth,
                        cellHeight,
                      ),
                      child: ServiceMatrixCell(
                        service: services[i],
                        phase: phase,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One service: identity, reachability, live figure, and — expanded — its host.
class ServiceMatrixCell extends ConsumerWidget {
  const ServiceMatrixCell({
    super.key,
    required this.service,
    this.phase = const _FoldPhase(0),
  });

  final ServiceKey service;

  /// How far open the card's band is. Every dimension and every opacity inside
  /// reads off this, so there is no state in which the card is "half compact"
  /// in one respect and "fully open" in another.
  final _FoldPhase phase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(serviceSummaryProvider(service));
    final settings = ref.watch(currentSettingsProvider);

    final reachability = switch (summary) {
      AsyncData(:final value) =>
        value.isOnline
            ? ServiceReachability.online
            : ServiceReachability.offline,
      AsyncError() => ServiceReachability.offline,
      _ => ServiceReachability.checking,
    };

    // Falls back to the configured URL's host so the cell can name which
    // instance it is talking about before the first response arrives.
    final host =
        summary.asData?.value.host ??
        service.extractHost(settings.urlFor(service)) ??
        '';

    // Only asked for once the service has answered. Watching it while offline
    // would fan out a library fetch per unreachable service on every rebuild,
    // and there is nothing to paint with the result.
    final signal = reachability == ServiceReachability.online
        ? ref.watch(serviceSignalProvider(service)).asData?.value
        : null;

    return _ServiceMatrixCellBody(
      service: service,
      reachability: reachability,
      signal: signal,
      host: host,
      phase: phase,
    );
  }
}

/// The painted cell, split from the provider reads so every state is reachable
/// by passing values in rather than by staging a container.
class _ServiceMatrixCellBody extends StatelessWidget {
  const _ServiceMatrixCellBody({
    required this.service,
    required this.reachability,
    required this.signal,
    required this.host,
    required this.phase,
  });

  final ServiceKey service;
  final ServiceReachability reachability;
  final ServiceSignal? signal;
  final String host;
  final _FoldPhase phase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isOnline = reachability == ServiceReachability.online;
    // An unreachable service recedes instead of changing colour: the surface
    // steps *down* the ladder so the cell reads as unlit. Health has nowhere to
    // hide in a hue — see the Room Light note in DESIGN.md — and a brightness
    // step survives colour blindness, which a red border does not.
    final surface = isOnline
        ? colorScheme.surfaceContainer
        : colorScheme.surfaceContainerLow;

    final statusLabel = switch (reachability) {
      ServiceReachability.online => 'Online',
      ServiceReachability.checking => 'Checking',
      ServiceReachability.offline => 'Offline',
    };

    final detail = phase.detail;
    final showHost = detail > 0 && host.isNotEmpty;

    // One structure for both densities, not two branches — the folded card is
    // the open card with its lower two lines rolled up to nothing. Written as a
    // pair of branches, an intermediate frame would have to belong to one of
    // them, and there is no honest answer to which.
    //
    // `spaceBetween` between the identity block and the readout is what pins
    // the figure to the bottom of the open card while the host stays welded
    // under the name. During the fold the slack simply shrinks with the box, so
    // the readout rides the bottom edge down rather than sliding independently
    // of the card that contains it.
    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _CellIdentity(
              service: service,
              reachability: reachability,
              surface: surface,
              phase: phase,
            ),
            if (showHost)
              _Unroll(
                value: detail,
                child: Padding(
                  // Tight to the name, so the two read as one identity block
                  // rather than as the second and third of three evenly spaced
                  // lines. That even spacing is most of what made the old card
                  // look generated.
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.tabular.copyWith(
                      // A step dimmer than the metric word below it. The host
                      // is the cell's least urgent line — it disambiguates two
                      // instances of one service and is otherwise something
                      // you already know — so it should be the first thing
                      // the eye skips.
                      color:
                          theme.extension<SeekarrThemeColors>()?.dimText ??
                          colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (detail > 0)
          _Unroll(
            value: detail,
            child: _CellLiveLine(
              reachability: reachability,
              signal: signal,
              statusLabel: statusLabel,
              surface: surface,
            ),
          ),
      ],
    );

    // Corner radius rides the fold like every other dimension.
    //
    // It used to be `lg` at both densities, and that constant was the one
    // thing in a container transform that did not move — with the compact card
    // 32pt tall, a 16dp radius is *exactly* half its height, which is a
    // stadium. Thirteen stadiums in wrapping rows, each with a coloured pip at
    // the trailing edge, is the anatomy of a filter-chip strip, so the folded
    // matrix read as something you tap to filter rather than to navigate. The
    // Pill-for-Metadata Rule already said so: full radius is metadata, and an
    // interactive container stays on the 12dp default. `md` folded is that
    // default, and it is proportionate — 12 on 32pt is a rounded rectangle,
    // where 8 (`sm`) would have been the small-*chip* step and given the
    // semantics back.
    final radius = BorderRadius.lerp(
      AppRadius.borderRadiusMd,
      AppRadius.borderRadiusLg,
      phase.geometry,
    )!;

    return AppCard.surfaceOutlined(
      key: ValueKey('service-matrix-cell-${service.routeParam}'),
      onTap: () => context.push('/services/${service.routeParam}'),
      // The card dips under the thumb instead of rippling. A ripple flooding a
      // 32pt box is how a chip signals selection, not how a surface signals a
      // touch — the same judgment as the radius above, and the reason
      // `AppCardPressFeedback` exists.
      pressFeedback: AppCardPressFeedback.scale,
      semanticLabel: service.title,
      // Spoken in full regardless of density: the compact card paints only a
      // name and a dot, but a screen reader user loses nothing by folding — the
      // figure and the host are still one property read away. Eye and ear are
      // allowed to diverge; this is that, deliberately.
      semanticValue: serviceMatrixCellValue(
        statusLabel: statusLabel,
        signalSpoken: signal?.spoken,
        host: host,
      ),
      // Nothing inside is separately interactive, and every visible fragment is
      // already in the composed value above.
      excludeChildSemantics: true,
      backgroundColor: surface,
      // The light, and the only place a service accent appears on this screen.
      // Withheld from an unreachable card: a service that is not answering
      // should look unlit, and that has to include its own colour. Withheld
      // from the folded card too — a wash needs a corner of surface to bloom
      // into, and a 32pt strip does not have one; see DESIGN.md. It fades up
      // last of all, on its own late interval, so the card finishes becoming a
      // card before it becomes a *lit* card.
      accentColor: isOnline && phase.wash > 0 ? service.accent : null,
      accentGlowAlpha: ServiceMatrixMetrics.accentWashAlpha * phase.wash,
      accentGlowCenter: Alignment.topLeft,
      borderRadius: radius,
      padding: EdgeInsets.lerp(
        const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: ServiceMatrixMetrics.compactVerticalPadding,
        ),
        const EdgeInsets.all(AppSpacing.md),
        phase.geometry,
      ),
      child: child,
    );
  }
}

/// The glyph, the name, and the reachability dot.
///
/// The dot's job changes with the density, which is why both are drawn by the
/// same widget rather than two. Expanded, [_CellLiveLine] underneath already
/// spells reachability out as a word ("Offline"), so the dot there is pure
/// reinforcement and only appears when there is a fault to reinforce — a green
/// dot on every healthy cell is a mark present on almost every open, and a mark
/// that is always the same is one nobody reads the day it changes. Compact has
/// no word underneath it at all: the dot *is* the reachability line, so it is
/// always present and coloured for all three states, not just the bad ones.
class _CellIdentity extends StatelessWidget {
  const _CellIdentity({
    required this.service,
    required this.reachability,
    required this.surface,
    required this.phase,
  });

  final ServiceKey service;
  final ServiceReachability reachability;
  final Color surface;
  final _FoldPhase phase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isOnline = reachability == ServiceReachability.online;
    final t = phase.geometry;

    // The one thing on the card that never fades. Through the whole fold the
    // glyph and the name stay fully opaque and simply grow, which is what makes
    // six cards changing column legible instead of chaotic: the eye tracks
    // "Sonarr" from where it was to where it lands. Cross-fading the identity
    // would turn a container transform back into a dissolve.
    final dotOpacity = isOnline ? 1 - phase.detail : 1.0;

    return Row(
      children: [
        // Drawn straight on the card, no tile. Resolved through `onTint` for the
        // same reason a label over a tint is: an icon is a graphical object with
        // a 3:1 floor, and the raw accent measures about 1.9:1 on the light
        // card — Radarr's amber especially. The tile used to hide that by
        // putting the glyph on a 14% fill of its own colour; an 8% wash does
        // not, and dark theme passing is not evidence about light.
        Icon(
          service.icon,
          size: lerpDouble(
            ServiceMatrixMetrics.compactGlyphSize,
            ServiceMatrixMetrics.glyphSize,
            t,
          ),
          color: isOnline
              ? ServiceTheme.onTint(
                  service.accent,
                  surface: surface,
                  // Tracks the wash it is measured against, so the glyph is
                  // never resolved for a tint that is not on screen yet.
                  tintAlpha: ServiceMatrixMetrics.accentWashAlpha * phase.wash,
                )
              : colorScheme.onSurfaceVariant,
        ),
        SizedBox(width: lerpDouble(AppSpacing.xs, AppSpacing.sm, t)),
        Expanded(
          child: Text(
            service.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            // Interpolated rather than swapped at a threshold: the name grows
            // with the card instead of snapping a size partway through.
            // Re-weighted through `.weight()` *after* the lerp, so the `wght`
            // axis follows: `copyWith(fontWeight:)` on a lerped variable style
            // leaves `fontVariations` at the interpolated 400 and the name
            // renders Regular at both ends of the fold.
            style:
                TextStyle.lerp(
                      theme.textTheme.bodySmall,
                      theme.textTheme.bodyMedium,
                      t,
                    )
                    ?.weight(FontWeight.w600)
                    .copyWith(
                      color: isOnline
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant,
                    ),
          ),
        ),
        // Folded, the dot *is* the reachability line; open, the readout spells
        // it out in words and the dot is only worth keeping as a fault marker.
        // So on a healthy service the two cross-fade — the dot leaves on the
        // same interval the readout arrives on, and reachability is never
        // unstated in between. On an unhealthy one the dot simply stays.
        if (dotOpacity > 0) ...[
          const SizedBox(width: AppSpacing.xs),
          Opacity(
            opacity: dotOpacity,
            child: _ReachabilityPip(
              reachability: reachability,
              // 8pt folded matches `components.status-dot`, the token this app
              // uses everywhere a bare dot carries state; 6pt open is the
              // smaller, merely-reinforcing mark it has always been.
              size: lerpDouble(8, 6, t)!,
            ),
          ),
        ],
      ],
    );
  }
}

/// A tone-coloured dot. See [_CellIdentity] for what it means at each density.
class _ReachabilityPip extends StatelessWidget {
  const _ReachabilityPip({required this.reachability, this.size = 6});

  final ServiceReachability reachability;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = switch (reachability) {
      ServiceReachability.online => AppColors.success,
      ServiceReachability.checking => AppColors.warning,
      ServiceReachability.offline => colorScheme.error,
    };

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// The readout: the live figure when the service is up, the state word when it
/// is not.
///
/// One slot for both is the point. The old card spent a row on `ONLINE` next to
/// a green dot saying the same thing, and spent the row below it on a library
/// total that does not change from one week to the next — so the only genuinely
/// live line on a control-room screen was chrome.
class _CellLiveLine extends StatelessWidget {
  const _CellLiveLine({
    required this.reachability,
    required this.signal,
    required this.statusLabel,
    required this.surface,
  });

  final ServiceReachability reachability;
  final ServiceSignal? signal;
  final String statusLabel;

  /// The cell's own background, which is what a tone-coloured word here is
  /// measured against. An offline cell sits a step lower on the surface ladder,
  /// so it is not the same composite as an online one.
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // Only reachable from the expanded card now — the compact card's identity
    // row carries reachability as a dot instead. One tier above the name is
    // the whole hierarchy: the figure is the only thing on the cell allowed to
    // be larger and bolder than the service's own name, and only just.
    final figureStyle = theme.textTheme.bodyLarge?.weight(FontWeight.w700);

    if (reachability != ServiceReachability.online) {
      return Text(
        statusLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: figureStyle?.copyWith(
          // Through `onTint` even though there is no tint here: `tintAlpha: 0`
          // makes the composite the surface itself, and the same lightness walk
          // that saves a label over a tint is what keeps the saturated amber
          // legible on a light card. Painting `AppColors.warning` raw would
          // measure about 2:1 against `surface-light`.
          color: ServiceTheme.onTint(
            statusToneColor(
              colorScheme,
              reachability == ServiceReachability.checking
                  ? StatusTone.warning
                  : StatusTone.error,
            ),
            surface: surface,
            tintAlpha: 0,
          ),
        ),
      );
    }

    final current = signal;
    if (current == null) {
      // Reachable, metric still in flight. A shimmer says "coming"; blank space
      // would say "nothing to report", which is a different fact.
      return ShimmerPlaceholder.text(width: 64);
    }

    final needsAttention = current.needsAttention;
    final toneColor = needsAttention
        ? ServiceTheme.onTint(
            statusToneColor(colorScheme, current.tone),
            surface: surface,
            tintAlpha: 0,
          )
        : colorScheme.onSurface;

    return Row(
      children: [
        // Only when the figure is asking for something. On a healthy service the
        // glyph restates the metric word beside it, and thirteen of them turned
        // the grid into a sheet of pictograms.
        if (needsAttention) ...[
          Icon(current.icon, size: 13, color: toneColor),
          const SizedBox(width: AppSpacing.xs),
        ],
        // One text run, not two `Text`s in a `Row`. Two of them cannot both be
        // right: unflexed, a wide figure has no way to shrink — a transfer rate
        // is service-supplied and `1023.9 KB/s` at the band's 1.6x clamp is
        // wider on its own than the 143pt a two-column cell has on a 375pt
        // phone, which is an overflow stripe rather than an ellipsis. Made
        // flexible instead, Flutter splits the free space by flex factor and
        // never hands the remainder back, so `12 missing` elided to "12 missi…"
        // at the *default* reading size with room to spare.
        //
        // A single line with two spans has neither problem: the figure keeps its
        // own weight, colour and tabular figures, and the ellipsis lands where
        // it should — in the word, which is the recoverable half.
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: current.value,
                  // The figure updates in place; proportional digits make it
                  // jitter.
                  style: figureStyle?.tabular.copyWith(color: toneColor),
                ),
                // Absent when the value is already a state word — "Paused"
                // needs no "status" after it. See `ServiceSignal.label`.
                if (current.label.isNotEmpty)
                  TextSpan(
                    text: ' ${current.label}',
                    // Plain body, not `AppTheme.eyebrow`. The Eyebrow Rule stops
                    // at repetition: "the eyebrow earns its emphasis by being
                    // rare", and one per cell across a thirteen-cell grid is the
                    // "eyebrow everywhere" noise the style exists to avoid.
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// The tail of the matrix: how many services are still unconfigured.
///
/// A line of text with a dismiss, not a card. It used to be a full-width
/// outlined affordance with a 700-weight label — a permanent row of the
/// instrument spent advertising services the user may have deliberately never
/// installed, and no way to say so. Settings lists all thirteen and is one tap
/// away from every screen; this is only a nudge, so it is sized like one and it
/// takes no for an answer.
class _MoreServicesHint extends ConsumerWidget {
  const _MoreServicesHint({required this.remaining});

  final int remaining;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (remaining <= 0) return const SizedBox.shrink();

    final dismissedAt = ref.watch(dismissedMoreServicesCountProvider);
    if (remaining <= dismissedAt) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final label = servicesUnconfiguredCellLabel(count: remaining);

    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.sm,
        top: AppSpacing.xs,
        bottom: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              container: true,
              button: true,
              label: label,
              hint: 'opens the service settings',
              excludeSemantics: true,
              onTap: () => context.go('/settings/services'),
              child: InkWell(
                onTap: () => context.go('/settings/services'),
                excludeFromSemantics: true,
                borderRadius: AppRadius.borderRadiusSm,
                child: ConstrainedBox(
                  // The label is small on purpose; the target must not be.
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Row(
                    children: [
                      Icon(
                        Icons.add_rounded,
                        size: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          // The same string the screen reader gets: see
                          // `servicesUnconfiguredCellLabel`.
                          label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: () => ref
                .read(dismissedMoreServicesCountProvider.notifier)
                .dismiss(remaining),
            icon: const Icon(Icons.close_rounded, size: 16),
            color: colorScheme.onSurfaceVariant,
            tooltip: servicesDismissMoreServicesLabel(count: remaining),
            // Material's default 48x48 clears both floors; stated so a later
            // density tweak cannot quietly drop under them.
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
