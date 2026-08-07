import 'package:flutter/material.dart';
import 'package:reel_text/reel_text.dart';

import 'package:cupola/core/reel_motion.dart';

/// A line of text that rolls its changed glyphs — but only while it genuinely
/// fits on one line, and falls back to a plain [Text] the moment it does not.
///
/// **This widget exists because `ReelText` cannot wrap and cannot elide.** It
/// takes no `maxLines` and no `overflow`, and internally lays every slot out at
/// `maxLines: 1, softWrap: false`. That is fine for a label that is short by
/// construction and fatal for anything else: at an accessibility reading size a
/// display headline that used to wrap onto three lines would instead run off the
/// side of the screen and paint the overflow stripe. Dynamic Type is a binding
/// commitment in this product, so the roll has to be the thing that yields.
///
/// So every call site goes through here, and the gate is a measurement rather
/// than a guessed scale threshold. [fitsOneLine] lays the real string out with a
/// [TextPainter] at `maxLines: 1` and **no width constraint**, then compares the
/// intrinsic width it reports against the width the parent offers — which is
/// exactly what `reel_text` does internally, including the reconciling step that
/// makes a slot-laid line's total width equal the shaped paragraph's to within
/// floating point. The comparison is therefore exact, and needs no headroom for
/// kerning lost between slots.
///
/// Laying out unconstrained is what makes the answer cacheable: the shaped width
/// depends on the span, the direction and the reading size but not on the box,
/// so the memo is keyed on those three and a resize re-answers the question
/// without re-shaping anything. The cache matters because this runs inside a
/// [LayoutBuilder] and would otherwise re-shape a paragraph on every frame of
/// every ancestor animation. Anything that reintroduces a `maxWidth` into the
/// layout must reintroduce it into the key.
///
/// When it falls back, it falls back to *the caller's own* [fallbackMaxLines]
/// and [fallbackOverflow], so a site that was correct before this widget was
/// introduced stays correct at the sizes where the roll is impossible.
///
/// The roll never carries information. [semanticsLabel] pins the spoken value
/// to the settled text so a screen reader hears the number, once, instead of
/// whatever frame the animation happened to be on.
class ReelLine extends StatelessWidget {
  /// A plain rolling line.
  const ReelLine(
    String this.text, {
    super.key,
    this.style,
    this.options = ReelMotion.figure,
    this.semanticsLabel,
    this.textAlign,
    this.fallbackMaxLines,
    this.fallbackOverflow,
  }) : span = null;

  /// A rolling line built from a styled span tree.
  ///
  /// Use where part of the line carries its own colour or weight — an accented
  /// word in a headline, a figure and its metric word as one run. Only the text
  /// clusters roll; a [WidgetSpan] leaf stays anchored.
  const ReelLine.rich(
    InlineSpan this.span, {
    super.key,
    required String plain,
    this.style,
    this.options = ReelMotion.figure,
    this.semanticsLabel,
    this.textAlign,
    this.fallbackMaxLines,
    this.fallbackOverflow,
  }) : text = plain;

  /// The plain string. In [ReelLine.rich] this is the flattened text, used for
  /// measurement and as the default spoken value.
  final String text;

  /// The styled tree, when built through [ReelLine.rich].
  final InlineSpan? span;

  final TextStyle? style;

  /// Which preset from [ReelMotion] this line rolls on. Never a hand-written
  /// [ReelTextOptions].
  final ReelTextOptions options;

  /// The spoken value. Defaults to [text].
  final String? semanticsLabel;

  final TextAlign? textAlign;

  /// What the plain-[Text] fallback does when the line cannot roll. Pass the
  /// values the site used before it became a [ReelLine] — `null` means wrap
  /// freely, which is what a headline or a paragraph wants.
  final int? fallbackMaxLines;
  final TextOverflow? fallbackOverflow;

  @override
  Widget build(BuildContext context) {
    final resolved = DefaultTextStyle.of(context).style.merge(style);

    // Reduce Motion removes the animator rather than neutering it, which is this
    // system's rule and not a shortcut: "instant" means dropping the widget and
    // rendering the child. `respectDisableAnimations` would make `ReelText` snap
    // instead of roll, but it would still lay the line out as one clipped slot
    // per grapheme — paying the whole machinery to produce a still image, and
    // giving up wrapping and eliding to do it. A plain `Text` is what a settled
    // roll looks like, and it is strictly more capable.
    if (MediaQuery.disableAnimationsOf(context)) {
      return _still(resolved);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // An unbounded parent sizes to the child, so there is nothing to
        // overflow and nothing to measure against. Roll.
        final bounded = constraints.maxWidth.isFinite;
        if (!bounded || _fits(context, resolved, constraints.maxWidth)) {
          // Clipped to its own line box, and this is not optional.
          //
          // `ReelText` paints its travelling glyphs *outside* its layout bounds
          // on purpose — 0.4.3 widened that bleed deliberately, so an accent or a
          // descender is not shaved off while an outgoing face fades. The
          // consequence is that a rolling line reaches roughly a full line height
          // above and below itself, and any neighbour closer than that gets
          // walked over: the onboarding step's eyebrow sits 8dp above its
          // headline, and mid-roll the two were drawing through each other.
          //
          // Clipping is also the more honest picture. Every roll in this app is a
          // value turning over in place, and a flap board's flaps live inside a
          // housing — glyphs that rise from behind an edge read as mechanism,
          // where glyphs floating free of the line read as a paint bug. Settled
          // text is unaffected: the clip is the widget's own box, which by
          // definition already contains the line it is laying out.
          return ClipRect(
            child: span == null
                ? ReelText(
                    text,
                    style: resolved,
                    options: options,
                    textAlign: textAlign,
                    semanticsLabel: semanticsLabel ?? text,
                  )
                : ReelText.rich(
                    span!,
                    style: resolved,
                    options: options,
                    textAlign: textAlign,
                    semanticsLabel: semanticsLabel ?? text,
                  ),
          );
        }

        return _still(resolved);
      },
    );
  }

  /// The line as ordinary text: what it looks like settled, and what it falls
  /// back to whenever it cannot roll.
  Widget _still(TextStyle resolved) => span == null
      ? Text(
          text,
          style: resolved,
          textAlign: textAlign,
          maxLines: fallbackMaxLines,
          overflow: fallbackOverflow,
          semanticsLabel: semanticsLabel,
        )
      : Text.rich(
          span!,
          style: resolved,
          textAlign: textAlign,
          maxLines: fallbackMaxLines,
          overflow: fallbackOverflow,
          semanticsLabel: semanticsLabel,
        );

  bool _fits(BuildContext context, TextStyle resolved, double maxWidth) =>
      fitsOneLine(
        context,
        span: span == null
            ? TextSpan(text: text, style: resolved)
            : TextSpan(style: resolved, children: [span!]),
        maxWidth: maxWidth,
      );

  /// Whether [span] lays out on one line inside [maxWidth].
  ///
  /// Measured at the ambient text scale, so the answer changes with the user's
  /// reading size — which is the whole point.
  ///
  /// The measurement itself is memoised — see [_oneLineWidth] — because this
  /// runs inside a [LayoutBuilder] on every build of every rolling line in the
  /// app, and shaping a paragraph is not a cheap thing to redo for an answer
  /// that cannot have changed. [maxWidth] is deliberately *not* part of what is
  /// cached: the painter is laid out unconstrained, so the width it reports is
  /// the line's intrinsic width and the constraint only enters as the
  /// comparison below. A resize therefore re-answers the question without
  /// re-shaping the text.
  ///
  /// Public because a *one-shot assemble* has to ask the question before it
  /// starts, not while it is running. A widget that mounts a placeholder and
  /// then rolls to the real text would otherwise paint the placeholder for one
  /// frame at reading sizes where the roll is impossible — a flash of filler
  /// with no animation behind it, which is worse than never animating.
  static bool fitsOneLine(
    BuildContext context, {
    required InlineSpan span,
    required double maxWidth,
  }) {
    if (!maxWidth.isFinite) return true;
    return _oneLineWidth(
          span,
          Directionality.of(context),
          MediaQuery.textScalerOf(context),
        ) <=
        maxWidth;
  }

  /// Test-only: how many paragraphs the shared cache has actually shaped.
  ///
  /// The memoisation is invisible from the outside — the answer is identical
  /// either way — so this counter is the only thing a test can assert on to
  /// prove the work is not being redone.
  @visibleForTesting
  static int get debugMeasurements => _measurements;

  /// Test-only: empties the shared cache and its counter, so one test cannot
  /// inherit another's entries.
  @visibleForTesting
  static void debugResetMeasurements() {
    _lineWidths.clear();
    _measurements = 0;
  }
}

/// Everything that can change a line's intrinsic width.
///
/// A record, so the map gets structural equality and hashing for free — which
/// is what makes a rebuilt-but-identical [TextSpan] hit the cache instead of
/// missing it on identity. [TextStyle] rides along inside the span and compares
/// structurally too, so a theme change invalidates exactly the lines it touched.
typedef _LineKey = ({
  InlineSpan span,
  TextDirection textDirection,
  TextScaler textScaler,
});

/// Intrinsic one-line widths, in insertion order (a map literal is a
/// `LinkedHashMap`), oldest first — which is what makes the eviction below LRU.
final Map<_LineKey, double> _lineWidths = {};

/// How many measurements the cache holds before evicting its coldest entry.
///
/// Generous relative to what any one screen can show — a dense hub is well under
/// a hundred rolling lines — and bounded because the keys hold onto their spans,
/// and a live figure re-rolling every poll would otherwise mint one entry per
/// distinct value forever.
const int _lineWidthCacheLimit = 256;

int _measurements = 0;
bool _listeningToSystemFonts = false;

/// The width [span] occupies on one unconstrained line, shaped at most once per
/// distinct (span, direction, scale).
///
/// The painter is disposed on every path: `reel_text` 0.4.2 shipped a fix for
/// exactly this leak in its own measurement code, and this is the same
/// measurement.
double _oneLineWidth(
  InlineSpan span,
  TextDirection textDirection,
  TextScaler textScaler,
) {
  final key = (
    span: span,
    textDirection: textDirection,
    textScaler: textScaler,
  );

  // Removed and re-inserted rather than read in place: that moves the entry to
  // the young end of the insertion order, so the eviction below drops the
  // least *recently used* line rather than merely the oldest one.
  final cached = _lineWidths.remove(key);
  if (cached != null) {
    _lineWidths[key] = cached;
    return cached;
  }

  // A cached shaping outlives a font change, and a font change moves every
  // width in it — swapping in a fallback face at startup, or the user changing
  // the system font. `PaintingBinding.systemFonts` is the framework's own
  // signal for exactly that, and it is the same one `RenderParagraph` listens
  // to. Registered once, on the first miss, because a static initialiser would
  // run before the binding exists.
  if (!_listeningToSystemFonts) {
    _listeningToSystemFonts = true;
    PaintingBinding.instance.systemFonts.addListener(_lineWidths.clear);
  }

  final painter = TextPainter(
    text: span,
    textDirection: textDirection,
    textScaler: textScaler,
    maxLines: 1,
  );
  try {
    // No constraint on purpose: this is the line's intrinsic width, so the
    // answer is reusable at any box width the caller later asks about.
    painter.layout();
    final width = painter.width;
    _measurements++;
    if (_lineWidths.length >= _lineWidthCacheLimit) {
      _lineWidths.remove(_lineWidths.keys.first);
    }
    _lineWidths[key] = width;
    return width;
  } finally {
    painter.dispose();
  }
}
