import 'package:flutter/widgets.dart';

/// One addressable block inside a [MediaDetailBody] region.
///
/// The region label is a `String` and never a `Widget`: the spine builds every
/// heading, so every heading on every page is `Semantics(header: true)` with the
/// page accent by construction. A caller physically cannot ship an unlabelled or
/// accent-less section, and cannot inset one either — the spine owns the gutter.
///
/// A slot is emitted only when it has something to say. There is no "empty
/// slot" state: the widget cannot see through its own child, so a slot holding
/// an empty list would still spend a label and 24pt of air. **Omit the slot.**
@immutable
class MediaDetailSlot {
  /// Region label, rendered uppercase through the eyebrow. Null renders no
  /// label at all.
  ///
  /// **Pass sentence case** — `'Missing subtitles'`, not `'MISSING SUBTITLES'`.
  /// The widget uppercases for the eye and hands the string through *unchanged*
  /// to `Semantics(label:)`, so a pre-shouted label is read out as shouting by
  /// VoiceOver and cannot be un-shouted downstream.
  final String? label;

  /// Tabular count beside the label ('41 of 48 · 5 seasons'). Joined into the
  /// spoken label.
  final String? count;

  /// An interactive trailing control on the label row (a jump-to button, a
  /// refresh). Stays OUTSIDE the silenced region, so it remains reachable.
  final Widget? labelAction;

  /// Box content, inset by the spine's gutter. Mutually exclusive with
  /// [sliver] and [railBuilder].
  final Widget? box;

  /// Sliver content, wrapped in a `SliverPadding` carrying the gutter.
  ///
  /// This is what makes a lazy child list land mid-page: it contributes a real
  /// top-level sliver, so a `SliverList.builder` inside `operate` builds the
  /// eight rows on screen rather than all 250.
  final Widget? sliver;

  /// `.lazy` only: a box emitted between the label and [sliver] — a selector
  /// row, a summary line. Never staggered separately from the label.
  ///
  /// **Not auto-inset, horizontally or vertically.** A selector rail is supposed
  /// to bleed past the content column, so the caller owns this widget's
  /// horizontal padding; pad it with the screen gutter (`AppSpacing.lg`) when
  /// the content should align to the column. The caller also owns the gap
  /// between this box and the first row of [sliver] — the spine emits them
  /// flush, because a pill rail and a summary line want different air above the
  /// list and neither is the page's rhythm.
  ///
  /// Known limit, on a resizable macOS window only: unlike [railBuilder] this
  /// receives no resolved gutter, so above `MediaDetailMetrics.bodyMaxWidth` a
  /// leading box sits one surplus short of the centred column. Exact at every
  /// phone width. If a variant needs it exact on macOS, the fix is a
  /// `leadingBoxBuilder(EdgeInsets)` here rather than padding at the call site.
  final Widget? leadingBox;

  /// `.rail` only: receives the resolved gutter to hand to its own
  /// `ListView.padding`, so the first item aligns to the content column while
  /// the rail bleeds past it.
  final Widget Function(EdgeInsets padding)? railBuilder;

  const MediaDetailSlot.box({
    required Widget child,
    this.label,
    this.count,
    this.labelAction,
  }) : box = child,
       sliver = null,
       leadingBox = null,
       railBuilder = null;

  const MediaDetailSlot.lazy({
    required this.sliver,
    this.label,
    this.count,
    this.labelAction,
    this.leadingBox,
  }) : box = null,
       railBuilder = null;

  const MediaDetailSlot.rail({
    required Widget Function(EdgeInsets padding) builder,
    this.label,
    this.count,
    this.labelAction,
  }) : railBuilder = builder,
       box = null,
       sliver = null,
       leadingBox = null;
}

/// The media detail body's six regions, in canonical order.
///
/// Named regions rather than one list: the order is a structural guarantee, not
/// a per-caller declaration. A variant omits a region; it never reorders one.
///
/// This replaces the `contentSections` + `slivers` pair, which was the
/// mechanical cause of the ordering bug — every content section was emitted
/// inside one `SliverToBoxAdapter(Column(...))` and only then the slivers, so
/// any caller that needed a lazy child list got it rendered *after* everything
/// else on the page. Lidarr's Albums landed after the genre chips and Bazarr's
/// wanted episodes after Details and Tags for exactly that reason.
@immutable
class MediaDetailBody {
  /// Region 1 — the answer. One box, no label: every variant is *supposed* to
  /// have a state, even a reference page whose state is 'seven movies'.
  ///
  /// Null only where the status resolver a deck needs does not exist yet — the
  /// Seerr collection and person pages and the two Bazarr pages, which have no
  /// `seerrCollectionStatus`, `seerrPersonStatus` or `resolveBazarrAction`. It is
  /// nullable rather than defaulted to a blank box so that gap is visible in the
  /// type instead of hidden behind a `SizedBox.shrink()` — which is what those
  /// four passed, and which cost them 16pt of dead air that sat their first
  /// region lower than every other page's. **A page with a resolvable status
  /// must pass one**; a promoted verb is the whole point of the region.
  final Widget? deck;

  /// Region 2 — the decisive facts, glyph-led, as a bleeding rail. No label.
  ///
  /// Pass it with its own default screen-gutter padding (`AppSpacing.lg`): a
  /// caller builds this above `MediaDetailView` and so cannot see the resolved
  /// column gutter. The spine adds the surplus a centred column takes on above
  /// `MediaDetailMetrics.bodyMaxWidth`, which is zero on a phone, so the first
  /// cell lands on the column edge at every width while the rail still bleeds
  /// off the trailing edge. Do **not** pre-pad it by more than the screen
  /// gutter or the two insets compound.
  final Widget? readout;

  /// Region 3 — **the manifest**: the child records the service tracks under
  /// this title, checked against what actually arrived.
  ///
  /// A shipping manifest is a list of what a thing is supposed to consist of,
  /// checked against what actually turned up. That gap — `41 of 48`,
  /// `3 missing · 2 languages`, `No file` — exists only because the -arr
  /// services model *expected* children separately from *present* children
  /// (`episodeCount` vs `episodeFileCount`, `trackCount` vs `trackFileCount`,
  /// `missingSubtitlesCount`), and rendering it is the reason this page is an
  /// instrument rather than an article about a film.
  ///
  /// Region 3 sits above the synopsis on purpose: the hero says what this is
  /// and what state it is in, the deck says what to do about it, and this is
  /// the thing whose state that was. Prose about a film is never more
  /// operational than the list of episodes you are missing. Where a service
  /// tracks no children this is the file (Radarr) or the request ledger (a
  /// Seerr movie).
  final List<MediaDetailSlot> operate;

  /// Region 4 — running prose: the overview, or a person's biography.
  final List<MediaDetailSlot> synopsis;

  /// Region 5 — the encyclopaedic block, in this internal order: the `DETAILS`
  /// fact grid, then `SCORES`, then the catalogue (`GENRES` / `KEYWORDS` /
  /// `TAGS`).
  final List<MediaDetailSlot> reference;

  /// Region 6 — everything that is about other titles: the `CAST` rail, then
  /// `COLLECTION`, then `WATCH PROVIDERS` / `FILMOGRAPHY`.
  final List<MediaDetailSlot> related;

  const MediaDetailBody({
    this.deck,
    this.readout,
    this.operate = const <MediaDetailSlot>[],
    this.synopsis = const <MediaDetailSlot>[],
    this.reference = const <MediaDetailSlot>[],
    this.related = const <MediaDetailSlot>[],
  });

  /// Every slot, flattened in canonical region order.
  ///
  /// The spine walks this; nothing else should need it, but it is public so a
  /// test can assert the order without reaching into `build`.
  List<MediaDetailSlot> get slots => <MediaDetailSlot>[
    ...operate,
    ...synopsis,
    ...reference,
    ...related,
  ];
}
