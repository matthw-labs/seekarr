import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:reel_text/reel_text.dart';

import 'package:seekarr/core/app_animation.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/reel_motion.dart';
import 'package:seekarr/core/service_theme.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/reel_line.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// The ring gives up size as the reading size grows, so the copy beside it never
/// loses room — the Column Floor Rule applied to a diagram instead of a grid.
double serviceRingDiameter(
  BuildContext context, {
  required double preferred,
  double horizontalPadding = AppSpacing.xl * 2,
}) {
  final available =
      MediaQuery.sizeOf(context).width - horizontalPadding - AppSpacing.xl;
  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
  final shrunk = preferred / scale.clamp(1.0, 1.6);
  return shrunk.clamp(96.0, available.clamp(96.0, preferred));
}

/// What one service's node on the ring is currently saying.
enum ServiceRingState {
  /// Not chosen. A dim dot, the smallest thing on the ring.
  unlit,

  /// Chosen but not yet reached — its accent, held back.
  picked,

  /// Answering. Full accent, a glow, and a spoke drawn in to the mark.
  connected,

  /// Configured and not answering. Drains to `onSurfaceVariant` with a hairline
  /// collar, because on this ring hue carries identity and never health — an
  /// unreachable service reads as unlit, not as differently coloured.
  silent,
}

/// The stack as a dial: every service is a dot on one circle around the product
/// mark, and a connected service draws a spoke to the centre.
///
/// This is the second sanctioned exception to the Room Light Rule, on the same
/// terms as `/services`: the surface is inherently about all fifteen services at
/// once, so accents are *confined* — a service's colour appears on its own node
/// and nowhere else. Nothing on the ring borrows a status tone.
///
/// **The ring animates itself.** Every visual a node can carry — radius, colour,
/// glow, collar, the length of its spoke — interpolates from whatever it was
/// showing to whatever it should show, so a service lighting up or draining is a
/// move rather than a cut. The caller changes [states] and nothing else. That is
/// also what lets one instance live *above* a pager and survive navigation
/// between the services being configured: the instrument is the fixed frame, the
/// forms are what page.
class ServiceRing extends StatefulWidget {
  const ServiceRing({
    super.key,
    required this.states,
    required this.diameter,
    this.entrance = 1,
    this.progress = 0,
    this.activeService,
    this.spin = false,
    this.markFraction = 0.42,
  });

  /// Per-service node state. A service absent from the map is
  /// [ServiceRingState.unlit].
  final Map<ServiceKey, ServiceRingState> states;

  /// Already-interpolated by the caller when it changes between screens, so the
  /// ring and the space it sits in resize on one clock rather than two.
  final double diameter;

  /// 0 → nodes still gathered at the mark, 1 → seated on the ring. The one
  /// caller-driven value: it is the flow's opening moment, not a state change.
  final double entrance;

  /// Fraction of the walk completed, drawn as an arc from noon clockwise.
  final double progress;

  /// Wears a collar and a glow while it is the service being configured.
  ///
  /// It is *marked*, not positioned. Parking the active node at noon was tried
  /// and it fights the sweep — the dial turns, so the node parked at the top
  /// drifts off it within a second, and the two rotations read as a bug rather
  /// than as either intention. The collar and the halo carry the job instead.
  final ServiceKey? activeService;

  /// A slow continuous sweep.
  ///
  /// Ambient motion is otherwise against the house rule, and this is the one
  /// carve-out: the ring is an instrument dial, one revolution takes 96 seconds
  /// — slower than anything else the app moves — it exists only where the ring
  /// is the subject of the screen, and Reduce Motion stops it dead.
  final bool spin;

  /// The mark's width as a fraction of the ring's diameter.
  final double markFraction;

  /// Services in ring order: registry order, grouped into domain arcs.
  static List<ServiceKey> get order => [
    for (final domain in ServiceDomain.values) ...domain.services,
  ];

  @override
  State<ServiceRing> createState() => _ServiceRingState();
}

class _ServiceRingState extends State<ServiceRing>
    with TickerProviderStateMixin {
  /// One revolution. Long enough to read as a live instrument rather than a
  /// spinner: at this rate a node crosses its own width in about two seconds.
  static const _spinPeriod = Duration(seconds: 96);

  late final AnimationController _transition = AnimationController(
    vsync: this,
    duration: AppAnimation.durationLg,
  );

  late final AnimationController _spinner = AnimationController(
    vsync: this,
    duration: _spinPeriod,
  );

  /// The frame the ring was showing when the current transition began, so an
  /// interrupted change continues from what is on screen instead of snapping
  /// back to the previous target.
  _RingFrame? _from;

  /// The frame last painted. Written during build deliberately: it is a record
  /// of output, never a trigger for one.
  _RingFrame? _painted;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSpinner();
  }

  @override
  void didUpdateWidget(ServiceRing old) {
    super.didUpdateWidget(old);
    if (old.spin != widget.spin) _syncSpinner();
    final changed =
        !_sameStates(old.states, widget.states) ||
        old.activeService != widget.activeService ||
        old.progress != widget.progress;
    if (!changed) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      // Removing the animator, not shortening it.
      _from = null;
      _transition.value = 1;
      return;
    }
    _from = _painted;
    _transition.forward(from: 0);
  }

  void _syncSpinner() {
    final wanted = widget.spin && !MediaQuery.disableAnimationsOf(context);
    if (wanted && !_spinner.isAnimating) {
      _spinner.repeat();
    } else if (!wanted && _spinner.isAnimating) {
      _spinner.stop();
    }
  }

  static bool _sameStates(
    Map<ServiceKey, ServiceRingState> a,
    Map<ServiceKey, ServiceRingState> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _transition.dispose();
    _spinner.dispose();
    super.dispose();
  }

  String _spoken() {
    final picked = widget.states.values
        .where((s) => s != ServiceRingState.unlit)
        .length;
    final connected = widget.states.values
        .where((s) => s == ServiceRingState.connected)
        .length;
    final silent = widget.states.values
        .where((s) => s == ServiceRingState.silent)
        .length;
    if (picked == 0) {
      return '${ServiceKey.values.length} services, none set up yet';
    }
    final parts = <String>['$picked of ${ServiceKey.values.length} chosen'];
    if (connected > 0) parts.add('$connected answering');
    if (silent > 0) parts.add('$silent not answering');
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = _RingFrame.resolve(
      states: widget.states,
      activeService: widget.activeService,
      progress: widget.progress,
      scheme: theme.colorScheme,
      isDark: theme.brightness == Brightness.dark,
    );

    return Semantics(
      label: _spoken(),
      excludeSemantics: true,
      child: RepaintBoundary(
        child: SizedBox(
          width: widget.diameter,
          height: widget.diameter,
          child: AnimatedBuilder(
            animation: Listenable.merge([_transition, _spinner]),
            builder: (context, _) {
              final t = AppAnimation.emphasizedCurve.transform(
                _transition.value,
              );
              final frame = _from == null
                  ? target
                  : _RingFrame.lerp(_from!, target, t);
              _painted = frame;
              return CustomPaint(
                painter: _ServiceRingPainter(
                  frame: frame,
                  entrance: widget.entrance,
                  sweep: _spinner.value * math.pi * 2,
                ),
                child: Center(
                  child: Opacity(
                    opacity: widget.entrance,
                    child: SizedBox(
                      width: widget.diameter * widget.markFraction,
                      height: widget.diameter * widget.markFraction,
                      child: const _Mark(),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Everything the painter needs, resolved and interpolable.
///
/// Resolving to numbers and colours up front is what makes the animation
/// possible at all: an enum cannot be lerped, and interpolating the *drawing*
/// rather than the state is what turns a node lighting up into a move.
@immutable
class _RingFrame {
  const _RingFrame({
    required this.nodes,
    required this.progress,
    required this.track,
  });

  final List<_NodeVisual> nodes;
  final double progress;
  final Color track;

  static _RingFrame resolve({
    required Map<ServiceKey, ServiceRingState> states,
    required ServiceKey? activeService,
    required double progress,
    required ColorScheme scheme,
    required bool isDark,
  }) {
    // The diagram's ink, and the reason it is not taken from the surface ladder:
    // a graphic drawn out of `outlineVariant` and `surfaceContainerHigh`
    // measures 1.16:1 and 1.03:1 on `surface-light`, because the light ladder's
    // steps are deliberately close together. `onSurfaceVariant` at a
    // per-brightness alpha gives both themes the same perceptual weight instead
    // — the hairline lands near 1.8:1 in each, and an unlit dot clears the 3:1
    // non-text floor in each (3.9:1 dark, 4.6:1 light) where one shared 55%
    // measured 1.9:1 on white.
    final unlit = scheme.onSurfaceVariant.withValues(
      alpha: isDark ? 0.55 : 0.80,
    );
    // A soft accent halo washes out faster on a light ground.
    final glowAlpha = isDark ? 0.34 : 0.42;
    final spokeAlpha = isDark ? 0.55 : 0.70;

    return _RingFrame(
      track: scheme.onSurfaceVariant.withValues(alpha: 0.30),
      progress: progress,
      nodes: [
        for (final key in ServiceRing.order)
          switch (states[key] ?? ServiceRingState.unlit) {
            ServiceRingState.unlit => _NodeVisual(
              accent: key.accent,
              radius: 4,
              color: unlit,
              glow: 0,
              spoke: 0,
              collar: 0,
              collarColor: key.accent,
              spokeAlpha: spokeAlpha,
            ),
            ServiceRingState.picked => _NodeVisual(
              accent: key.accent,
              radius: 5,
              color: key.accent.withValues(alpha: 0.78),
              glow: activeService == key ? glowAlpha : 0,
              spoke: 0,
              collar: activeService == key ? 1 : 0,
              collarColor: key.accent.withValues(alpha: 0.6),
              spokeAlpha: spokeAlpha,
            ),
            ServiceRingState.connected => _NodeVisual(
              accent: key.accent,
              radius: 6,
              color: key.accent,
              glow: glowAlpha,
              spoke: 1,
              collar: activeService == key ? 1 : 0,
              collarColor: key.accent.withValues(alpha: 0.6),
              spokeAlpha: spokeAlpha,
            ),
            ServiceRingState.silent => _NodeVisual(
              accent: key.accent,
              radius: 5,
              color: scheme.onSurfaceVariant,
              glow: activeService == key ? glowAlpha : 0,
              spoke: 0,
              collar: 1,
              collarColor: activeService == key
                  ? key.accent.withValues(alpha: 0.6)
                  : scheme.onSurfaceVariant.withValues(alpha: 0.35),
              spokeAlpha: spokeAlpha,
            ),
          },
      ],
    );
  }

  static _RingFrame lerp(_RingFrame a, _RingFrame b, double t) => _RingFrame(
    track: Color.lerp(a.track, b.track, t)!,
    progress: a.progress + (b.progress - a.progress) * t,
    nodes: [
      for (var i = 0; i < b.nodes.length; i++)
        _NodeVisual.lerp(
          i < a.nodes.length ? a.nodes[i] : b.nodes[i],
          b.nodes[i],
          t,
        ),
    ],
  );
}

@immutable
class _NodeVisual {
  const _NodeVisual({
    required this.accent,
    required this.radius,
    required this.color,
    required this.glow,
    required this.spoke,
    required this.collar,
    required this.collarColor,
    required this.spokeAlpha,
  });

  final Color accent;
  final double radius;
  final Color color;

  /// Peak alpha of the halo behind the dot; 0 for no halo.
  final double glow;

  /// How far the spoke has grown from the mark out to the node, 0–1.
  final double spoke;

  /// Opacity of the hairline ring around the dot.
  final double collar;
  final Color collarColor;
  final double spokeAlpha;

  static _NodeVisual lerp(_NodeVisual a, _NodeVisual b, double t) =>
      _NodeVisual(
        accent: Color.lerp(a.accent, b.accent, t)!,
        radius: a.radius + (b.radius - a.radius) * t,
        color: Color.lerp(a.color, b.color, t)!,
        glow: a.glow + (b.glow - a.glow) * t,
        spoke: a.spoke + (b.spoke - a.spoke) * t,
        collar: a.collar + (b.collar - a.collar) * t,
        collarColor: Color.lerp(a.collarColor, b.collarColor, t)!,
        spokeAlpha: a.spokeAlpha + (b.spokeAlpha - a.spokeAlpha) * t,
      );
}

/// The product mark — the Cupola from above: six lit window panes around the
/// central circular window. The ring's own nodes orbit it, so the mark supplies
/// the structure and never a second ring.
class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/brand/seekarr_mark.png',
    fit: BoxFit.contain,
    // Decorative here: [ServiceRing] already publishes the ring's meaning.
    excludeFromSemantics: true,
  );
}

/// Where each node sits, and how the circle divides into domain arcs.
///
/// Computed once: the geometry only depends on the registry, so the ring's
/// layout is a property of the stack rather than of a screen.
abstract final class _RingGeometry {
  /// Blank slots inserted between two domains, in node-widths. Wide enough to
  /// read as a gap, narrow enough that fifteen nodes still fill the circle.
  static const gap = 1.7;

  static final List<double> angles = _computeAngles();
  static final List<double> domainStarts = _computeDomainStarts();

  static double get _unit =>
      (math.pi * 2) /
      (ServiceKey.values.length + gap * ServiceDomain.values.length);

  static List<double> _computeAngles() {
    final out = <double>[];
    var slot = gap / 2;
    for (final domain in ServiceDomain.values) {
      for (var i = 0; i < domain.services.length; i++) {
        out.add(-math.pi / 2 + _unit * (slot + 0.5));
        slot += 1;
      }
      slot += gap;
    }
    return out;
  }

  static List<double> _computeDomainStarts() {
    final out = <double>[];
    var slot = 0.0;
    for (final domain in ServiceDomain.values) {
      out.add(-math.pi / 2 + _unit * slot);
      slot += domain.services.length + gap;
    }
    return out;
  }
}

class _ServiceRingPainter extends CustomPainter {
  _ServiceRingPainter({
    required this.frame,
    required this.entrance,
    required this.sweep,
  });

  final _RingFrame frame;
  final double entrance;

  /// The ambient rotation, kept separate from the frame so the sweep continues
  /// through a state transition instead of being interpolated by it.
  final double sweep;

  /// Room for the largest node plus its collar, so nothing clips at the rim.
  static const _nodeHalo = 14.0;

  double get _rotation => sweep;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - _nodeHalo;

    _paintTrack(canvas, centre, radius);
    _paintProgress(canvas, centre, radius);
    // Spokes first so the dots sit on top of them.
    _paintSpokes(canvas, centre, radius);
    _paintNodes(canvas, centre, radius);
  }

  void _paintTrack(Canvas canvas, Offset centre, double radius) {
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = frame.track,
    );
    // One tick where each domain arc begins — what makes the circle read as a
    // four-sector dial rather than a wreath.
    for (final angle in _RingGeometry.domainStarts) {
      final a = angle + _rotation;
      final direction = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        centre + direction * (radius - 5),
        centre + direction * (radius + 5),
        Paint()
          ..strokeWidth = 1
          ..color = frame.track,
      );
    }
  }

  void _paintProgress(Canvas canvas, Offset centre, double radius) {
    if (frame.progress <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -math.pi / 2 + _rotation,
      math.pi * 2 * frame.progress.clamp(0, 1),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        // Barely heavier than the 1px track, and translucent: this is the part
        // of the dial that is *lit*, not a second object laid over it. At full
        // weight and opacity a half-swept arc outshouted the fifteen nodes it
        // exists to serve.
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..color = AppColors.primary.withValues(alpha: 0.5),
    );
  }

  void _paintSpokes(Canvas canvas, Offset centre, double radius) {
    for (var i = 0; i < frame.nodes.length; i++) {
      final node = frame.nodes[i];
      if (node.spoke <= 0.001) continue;
      final a = _RingGeometry.angles[i] + _rotation;
      final direction = Offset(math.cos(a), math.sin(a));
      final start = centre + direction * (radius * 0.34);
      // Grows outward from the mark to the node, so a service connecting reads
      // as a line being drawn *in* rather than a line appearing.
      final full = radius * entrance - 9;
      final end =
          centre +
          direction * (radius * 0.34 + (full - radius * 0.34) * node.spoke);
      canvas.drawLine(
        start,
        end,
        Paint()
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(
            colors: [
              node.accent.withValues(alpha: 0.05 * node.spoke),
              node.accent.withValues(alpha: node.spokeAlpha * node.spoke),
            ],
          ).createShader(Rect.fromPoints(start, end)),
      );
    }
  }

  void _paintNodes(Canvas canvas, Offset centre, double radius) {
    for (var i = 0; i < frame.nodes.length; i++) {
      final node = frame.nodes[i];
      final a = _RingGeometry.angles[i] + _rotation;
      final point =
          centre + Offset(math.cos(a), math.sin(a)) * (radius * entrance);

      if (node.glow > 0.001) {
        final haloRadius = node.radius * 3.4;
        canvas.drawCircle(
          point,
          haloRadius,
          Paint()
            ..shader = RadialGradient(
              colors: [
                node.accent.withValues(alpha: node.glow),
                node.accent.withValues(alpha: 0),
              ],
            ).createShader(Rect.fromCircle(center: point, radius: haloRadius)),
        );
      }

      canvas.drawCircle(point, node.radius, Paint()..color = node.color);

      if (node.collar > 0.001) {
        canvas.drawCircle(
          point,
          node.radius + 4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = node.collarColor.withValues(
              alpha: node.collarColor.a * node.collar,
            ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ServiceRingPainter old) =>
      old.entrance != entrance || old.sweep != sweep || old.frame != frame;
}

/// The punchline, and the reason it is here rather than inlined in onboarding:
/// `/services`' empty state shows the same claim under the same ring.
///
/// Two accents, and they are the mark's own two — the ribbon "S" runs cyan to
/// blue, so the sentence takes the blue end for the app and the cyan end for the
/// stack. The cyan is a `nav-*` section accent rather than a service's, because
/// colouring "them all" with one service's identity would privilege it over the
/// other fourteen.
class OnePunchline extends StatelessWidget {
  const OnePunchline({super.key, this.style}) : assembling = false;

  /// The claim as a split-flap board resolving into itself, once, on mount.
  ///
  /// **This is the only decorative roll in the app, and it is deliberately not
  /// available anywhere else.** Every other `reel_text` surface animates because
  /// a value changed and the change is the information; this one animates a
  /// string that never changes, which both this project's motion rule ("motion
  /// is a response to the user, never ambient theatre") and the package's own
  /// guidance would otherwise reject.
  ///
  /// It is allowed here on three conditions, all of which the door meets and no
  /// other surface does. The onboarding door is the single **Persuade** moment
  /// in an Operate product — its job is to make a claim, not to complete a task.
  /// It plays **once per install**, so it is an entrance rather than a loop; the
  /// beat is over before the first tap and can never be sat through twice. And
  /// it is choreographed *with* the screen's existing authored moment rather
  /// than beside it: the ring's `durationXl` entrance and this assemble share
  /// one clock, so the room lights and the claim resolves as a single movement.
  ///
  /// `/services`' empty state uses the plain constructor. Same claim, same ring,
  /// no assemble — that surface is a state the user can arrive at repeatedly.
  const OnePunchline.assembling({super.key, this.style}) : assembling = true;

  /// Defaults to `displayMedium` — the ramp's own step between a heading and a
  /// hero line. Pass a smaller role where the claim is a caption, not the door.
  final TextStyle? style;

  /// Whether the claim rolls itself into place on mount.
  final bool assembling;

  static const _appInk = AppColors.primary;
  static const _stackInk = AppColors.navActivity;
  static const _spoken = 'One app to rule them all.';

  /// The two painted lines, longest first. The assemble's landing beat is
  /// aligned off the longest one.
  static const _leadLine = 'One app to rule';
  static const _markedLine = 'them all.';

  /// Marker alpha per brightness. Two values, not one: 12% is invisible on a
  /// light ground and 20% is a block on a near-black one.
  static double _markerAlpha(bool isDark) => isDark ? 0.16 : 0.20;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final base = (style ?? theme.textTheme.displayMedium!)
        .weight(FontWeight.w800)
        .copyWith(color: scheme.onSurface, height: 1.02);
    final alpha = _markerAlpha(isDark);

    // Both inks resolve against the composite they sit on. The cyan proves why
    // that is not optional: raw #06B6D4 measures 8.1:1 on `surface-dark` but
    // 2.20:1 on `surface-light`, below even the 3:1 large-text floor.
    final appInk = ServiceTheme.onTint(
      _appInk,
      surface: scheme.surface,
      tintAlpha: 0,
    );
    final stackInk = ServiceTheme.onTint(
      _stackInk,
      surface: scheme.surface,
      tintAlpha: alpha,
    );

    final leadSpan = TextSpan(
      children: [
        TextSpan(
          text: 'One',
          style: TextStyle(color: appInk),
        ),
        const TextSpan(text: ' app to rule'),
      ],
    );

    final markedStyle = base.copyWith(color: stackInk);
    final markedSpan = TextSpan(text: _markedLine);

    // Both lines land on the same beat: the shorter one starts later by exactly
    // the stagger it saves, so the board finishes as one board. See
    // `ReelMotion.headline`.
    const lead = _leadLine.length;
    const marked = _markedLine.length;

    return Semantics(
      label: _spoken,
      excludeSemantics: true,
      // **One decision for the whole claim, taken here rather than per line.**
      // Each line used to gate itself on whether it fit, and at a 1.8x reading
      // size that produced the worst of both: "One app to rule" was too wide to
      // roll so it wrapped and rendered plainly, while "them all." still fit and
      // duly sat there as `gurz nyy.` above the real sentence. Half a settled
      // claim beside half a scrambled one is worse than either whole. So the
      // composition assembles only if *every* line — and every line's mask — can
      // hold its own single line at the user's reading size.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final canAssemble =
              assembling &&
              !MediaQuery.disableAnimationsOf(context) &&
              _AssemblingLine.canRoll(
                context,
                lines: {leadSpan: base, markedSpan: markedStyle},
                maxWidth: constraints.maxWidth,
              );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (canAssemble)
                _AssemblingLine(
                  span: leadSpan,
                  plain: _leadLine,
                  style: base,
                  delay: ReelMotion.headlineLeadIn,
                )
              else
                Text.rich(leadSpan, style: base),
              _Marker(
                fill: _stackInk.withValues(alpha: alpha),
                child: canAssemble
                    ? _AssemblingLine(
                        span: markedSpan,
                        plain: _markedLine,
                        style: markedStyle,
                        delay:
                            ReelMotion.headlineLeadIn +
                            ReelMotion.headlineStagger * (lead - marked),
                      )
                    : Text(_markedLine, style: markedStyle),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One line of the claim, flipping from a filler board into its real glyphs.
///
/// Mounts showing [_mask] — the claim's own letters rotated half the alphabet,
/// so `One app to rule` starts as `Bar ncc gb ehyr` — and rolls to the real span
/// one [delay] later. A same-length mask rather than an empty string is what
/// keeps the line's *height* constant from the very first frame: an empty
/// [ReelText] measures no line box, so starting blank would shift the whole
/// composition down as the text arrived, and the fix for that would be a
/// hard-coded height wrapped around a `Text`, which this design system bans
/// outright.
///
/// **A rotation rather than a filler glyph, and that is a width decision before
/// it is an aesthetic one.** The first version masked every non-space character
/// with `0`, on the assumption that a digit is about letter-width in Inter. It is
/// not — Inter's digits are near-monospaced and markedly wider than average
/// lowercase — so the mask measured wider than the line it stood in for and ran
/// straight off the right edge of the phone. A rotation reuses the claim's own
/// letters, which keeps the mask's width in the same neighbourhood as the target
/// by construction. It also simply looks like what it is meant to look like: a
/// flap board one turn away from settling, rather than a field of zeros that
/// reads as a failed load.
///
/// Even so the mask is *measured*, not trusted: [build] gates on the wider of
/// mask and target. Gating on the target alone is what let the zero mask through
/// — the check passed on the string the widget ends at while the string it starts
/// at overflowed.
///
/// The line does not assemble at all when either string would miss its single
/// line at the user's reading size. `ReelText` cannot wrap, so the alternative is
/// a display headline running off the screen — and a mask makes that failure
/// worse than a plain overflow, because the first thing painted is filler with no
/// animation yet to explain it.
class _AssemblingLine extends StatefulWidget {
  const _AssemblingLine({
    required this.span,
    required this.plain,
    required this.style,
    required this.delay,
  });

  final InlineSpan span;
  final String plain;
  final TextStyle style;
  final Duration delay;

  /// Rotates every ASCII letter by half the alphabet, leaving spaces and
  /// punctuation alone and preserving span structure — so the accent colours are
  /// already in place before the words are, and the word rhythm is legible before
  /// a single word is.
  static InlineSpan _mask(InlineSpan span) {
    if (span is TextSpan) {
      return TextSpan(
        text: span.text == null ? null : _rot13(span.text!),
        style: span.style,
        children: span.children?.map(_mask).toList(growable: false),
      );
    }
    return span;
  }

  static String _rot13(String value) => String.fromCharCodes([
    for (final unit in value.codeUnits)
      if (unit >= 0x61 && unit <= 0x7A) // a-z
        (unit - 0x61 + 13) % 26 + 0x61
      else if (unit >= 0x41 && unit <= 0x5A) // A-Z
        (unit - 0x41 + 13) % 26 + 0x41
      else
        unit,
  ]);

  /// Whether every one of [lines] can assemble inside [maxWidth].
  ///
  /// Checks each line's target **and** its mask, because the widget paints both
  /// and a gate on the target alone passes a mask that overflows — which is
  /// exactly how a digit mask once ran off the right edge of a phone.
  static bool canRoll(
    BuildContext context, {
    required Map<InlineSpan, TextStyle> lines,
    required double maxWidth,
  }) => lines.entries.every((line) {
    bool fits(InlineSpan span) => ReelLine.fitsOneLine(
      context,
      span: TextSpan(style: line.value, children: [span]),
      maxWidth: maxWidth,
    );
    return fits(line.key) && fits(_mask(line.key));
  });

  @override
  State<_AssemblingLine> createState() => _AssemblingLineState();
}

class _AssemblingLineState extends State<_AssemblingLine> {
  bool _settled = false;
  Timer? _start;

  @override
  void initState() {
    super.initState();
    _start = Timer(widget.delay, () {
      if (mounted) setState(() => _settled = true);
    });
  }

  @override
  void dispose() {
    _start?.cancel();
    super.dispose();
  }

  @override
  // Clipped for the same reason every other roll in the app is — see [ReelLine].
  // Here it matters most: the claim's two lines are set at 1.02 leading, so
  // unclipped they would draw straight through each other. It is also what makes
  // the flaps read as flaps, turning over behind the edge of their own housing.
  Widget build(BuildContext context) => ClipRect(
    child: ReelText.rich(
      _settled ? widget.span : _AssemblingLine._mask(widget.span),
      style: widget.style,
      options: ReelMotion.headline,
      semanticsLabel: widget.plain,
    ),
  );
}

/// A quiet marker behind a phrase.
///
/// Drawn in a [Stack] rather than as padding on a container: padding insets the
/// glyphs, which pushes the phrase off the left margin the line above it aligns
/// to. The plate reaches past the text instead.
class _Marker extends StatelessWidget {
  const _Marker({required this.child, required this.fill});

  final Widget child;
  final Color fill;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        left: -7,
        right: -7,
        top: 5,
        bottom: 5,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      child,
    ],
  );
}
