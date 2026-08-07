import 'package:flutter/material.dart';
import 'package:reel_text/reel_text.dart';

import 'package:seekarr/core/app_animation.dart';

/// The app's roll vocabulary: five presets, and no call site may hand-write a
/// `ReelTextOptions`.
///
/// `reel_text` ships its own defaults — a 300ms roll on `Cubic(0.34, 1.56, 0.64,
/// 1)` with `bounce: 0.6` — and they are a springy overshoot chosen to look good
/// in a package demo. Nothing in this app moves on that curve. Durations and
/// curves come from [AppAnimation], so they come from here too, and the presets
/// below are the only place the two systems meet.
///
/// **Stagger has no [AppAnimation] equivalent**, because nothing else in the app
/// staggers *within* a single string — [StaggeredEntrance] staggers between
/// siblings at 45ms and that is a different axis. The four values below are
/// authored, and each one is a ratio of the roll it belongs to rather than a
/// number picked by eye: a figure's glyphs travel almost together (the value is
/// one unit), a headline's sweep left to right (the line is being assembled).
///
/// See also the Reduce Motion note on [waiting] — the one preset that is not
/// self-suppressing.
abstract final class ReelMotion {
  ReelMotion._();

  /// A live number updating in place: a transfer rate, a queue count, a KPI.
  ///
  /// The quietest preset in the set, because it is the one that fires without
  /// being asked. A figure re-rolls on every poll on screens the user watches
  /// for minutes, so it gets no overshoot (`bounce: 0`), the app's own
  /// state-change duration, and a stagger tight enough that a four-digit value
  /// reads as one object dropping into place rather than four digits arriving in
  /// sequence.
  ///
  /// It also carries **no colour flash**. `ReelTextOptions.color` tints incoming
  /// glyphs before fading back, and spending that on a status figure would make
  /// hue carry health — which is the thing the Room Light Rule exists to
  /// prevent. A figure changes brightness and position, never hue.
  static const figure = ReelTextOptions(
    direction: ReelTextDirection.down,
    duration: AppAnimation.durationSm,
    stagger: Duration(milliseconds: 18),
    exitOffset: Duration(milliseconds: 28),
    curve: AppAnimation.emphasizedCurve,
    bounce: 0,
  );

  /// A state word changing because the thing it describes changed:
  /// `Queued` → `Downloading` → `Importing`.
  ///
  /// Same clock as [figure] and a slightly wider stagger. A word is read as a
  /// word, so its letters may arrive across a short sweep — but only just: past
  /// about 24ms per glyph a nine-letter state word takes longer to settle than
  /// the poll interval that produced it, and the label is then permanently in
  /// motion.
  static const word = ReelTextOptions(
    direction: ReelTextDirection.down,
    duration: AppAnimation.durationSm,
    stagger: Duration(milliseconds: 22),
    exitOffset: Duration(milliseconds: 34),
    curve: AppAnimation.emphasizedCurve,
    bounce: 0,
  );

  /// A command label answering a press: `Test connection` → `Next service`.
  ///
  /// The one preset that keeps a trace of overshoot, and it is earned rather
  /// than decorative — this roll is *feedback for a touch*, the same job
  /// [PressableScale]'s 0.97 dip does, and a label that lands dead-flat under
  /// the thumb reads as a repaint instead of a response. The bounce is a
  /// quarter of the package's default, so it settles rather than wobbles.
  ///
  /// `interrupt: false` is the important field. A primary button is spam-prone,
  /// and interrupting snaps the in-flight roll to its target before starting the
  /// next one — which on a double tap paints the intermediate label for one
  /// frame. Queueing the latest target instead is what the package recommends
  /// for exactly this case.
  static const command = ReelTextOptions(
    direction: ReelTextDirection.down,
    duration: AppAnimation.durationSm,
    stagger: Duration(milliseconds: 20),
    exitOffset: Duration(milliseconds: 30),
    curve: AppAnimation.emphasizedCurve,
    bounce: 0.15,
    interrupt: false,
  );

  /// The onboarding door's claim assembling itself on first frame.
  ///
  /// The only decorative roll in the app, and the only one on a *static* string.
  /// It is allowed exactly one surface: the door is the single Persuade moment
  /// in an Operate product, it plays once per install, and it is choreographed
  /// against the service ring's entrance rather than competing with it — see
  /// [OnePunchline.assembling].
  ///
  /// Split-flap timing: the app's standard-transition travel per glyph, a
  /// stagger wide enough that the line resolves left to right at a readable
  /// pace rather than all at once, and real bounce because a flap board
  /// *settles*. `down` is the direction a flap actually falls.
  ///
  /// The stagger is load-bearing beyond its own line, because a multi-line claim
  /// has to land on **one** beat: a short second line started at the same moment
  /// as a long first line settles early, and a bottom line that finishes before
  /// the top one reads as two animations rather than one board. Callers stagger
  /// their lines' *start* by `(longestLineGraphemes - thisLineGraphemes) *`
  /// [headlineStagger] so every line finishes together. See
  /// [OnePunchline.assembling].
  static const headline = ReelTextOptions(
    direction: ReelTextDirection.down,
    duration: AppAnimation.durationMd,
    stagger: headlineStagger,
    exitOffset: Duration(milliseconds: 60),
    curve: AppAnimation.emphasizedCurve,
    bounce: 0.45,
  );

  /// [headline]'s per-glyph offset, exposed so a caller can align two lines onto
  /// one landing beat without restating the number.
  static const headlineStagger = Duration(milliseconds: 34);

  /// How long after mount the claim starts assembling.
  ///
  /// Non-zero so the first painted frame is the settled composition rather than
  /// a board mid-flip, and small enough that the assemble overlaps the service
  /// ring's own `durationXl` entrance instead of queueing behind it — the ring
  /// seats, the last flaps land just after, and the door reads as one movement
  /// with a tail rather than as two things stopping at once.
  static const headlineLeadIn = Duration(milliseconds: 80);

  /// The busy loop under [ReelTextController.runWhile].
  ///
  /// Deliberately calmer and shorter than [command]: this one repeats on a timer
  /// for as long as a network call takes, and the same bounce that reads as
  /// tactile on a single press reads as a twitch at four ticks a second.
  ///
  /// **This preset is the one place `respectDisableAnimations` does not cover
  /// us.** That flag suppresses the *roll*; it does not stop the controller's
  /// frame timer, so under Reduce Motion an ellipsis loop still hard-swaps
  /// `Testing` → `Testing.` → `Testing..` four times a second. Text changing on
  /// a timer with no animation is not motion, but it is still something moving
  /// for a user who asked for less — so callers check
  /// [MediaQuery.disableAnimationsOf] and show a settled label instead. That
  /// check lives in [ReelCommandButton]; do not re-implement it per screen.
  static const waiting = ReelTextOptions(
    direction: ReelTextDirection.down,
    duration: AppAnimation.durationSm,
    stagger: Duration(milliseconds: 16),
    exitOffset: Duration(milliseconds: 24),
    curve: AppAnimation.emphasizedCurve,
    bounce: 0,
  );
}
