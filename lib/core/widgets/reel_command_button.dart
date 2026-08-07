import 'package:flutter/material.dart';
import 'package:reel_text/reel_text.dart';

import 'package:cupola/core/reel_motion.dart';

/// A primary button whose label rolls instead of being replaced by a spinner.
///
/// The pattern it replaces was: swap the label for an 18pt
/// [CircularProgressIndicator] while the future runs. That loses the one thing
/// naming what you just pressed, at exactly the moment you are waiting to find
/// out whether it worked — a service test on a home lab can take fifteen seconds
/// behind a reverse proxy, and for all fifteen the button said nothing. Here the
/// label stays, and being *in motion* is what says busy.
///
/// Three things make that safe rather than merely prettier:
///
/// **The slot is reserved, so the button never resizes and the label never
/// re-centres.** [_slotWidth] measures every label this button can ever show —
/// including the widest ellipsis frame of the busy label — and reserves the
/// maximum. Without it a full-width button's centred text slides sideways on
/// every state change, which reads as a layout bug rather than as feedback.
///
/// **The resting label is declarative, the busy span is imperative.** The parent
/// owns what the button says at rest and may change it freely — `Test
/// connection` becomes `Next service` once the service answers, because there is
/// no reason to make someone press Test and then press Next. [didUpdateWidget]
/// rolls to whatever the parent now wants. The controller only takes over
/// between the press and the future resolving.
///
/// **Reduce Motion gets a settled label, not a silent timer.**
/// `respectDisableAnimations` suppresses the roll but not
/// [ReelTextController]'s frame timer, so an ellipsis loop would still hard-swap
/// four times a second for a user who asked for less movement. See
/// [ReelMotion.waiting].
class ReelCommandButton extends StatefulWidget {
  const ReelCommandButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busyLabel,
    this.failureLabel,
    this.slotLabels = const <String>[],
  });

  /// What the button says at rest. Change it to roll to a new resting label.
  final String label;

  /// What it says while [onPressed]'s future is in flight. Rolling dots are
  /// appended to it, so pass a bare participle — `Testing`, not `Testing…`.
  ///
  /// `null` means the press has no waiting state worth showing: the label is not
  /// taken over, the button is not disabled, and the action simply runs. That is
  /// the right shape for a press that navigates rather than waits — and it lets
  /// **one** button instance serve an action whose job changes underneath it. A
  /// service step's primary control tests while the service is silent and
  /// advances once it answers; keeping it the same widget through that change is
  /// what lets `Test connection` *roll* into `Next service` instead of being
  /// replaced by it.
  final String? busyLabel;

  /// Rolled to when the future throws. Falls back to [label], which is right
  /// whenever the action is simply retryable.
  final String? failureLabel;

  /// `null` disables the button, matching [FilledButton].
  final Future<void> Function()? onPressed;

  /// Labels this button will show later, so the slot is wide enough for them
  /// now. Pass the *other* arm of a two-state action — a button that will
  /// become `Next service` reserves room for it while it still says `Test
  /// connection`, otherwise the width changes on the one transition the
  /// reservation exists to absorb.
  final List<String> slotLabels;

  @override
  State<ReelCommandButton> createState() => _ReelCommandButtonState();
}

class _ReelCommandButtonState extends State<ReelCommandButton> {
  late final ReelTextController _label = ReelTextController(
    initialText: widget.label,
  );

  bool _busy = false;

  @override
  void didUpdateWidget(ReelCommandButton old) {
    super.didUpdateWidget(old);
    // While the future owns the label, the parent's value is staged rather than
    // applied — the completion below reads `widget.label` after the await and
    // therefore lands on whatever the parent decided in the meantime.
    if (_busy) return;
    if (widget.label != _label.value) {
      _label.set(widget.label, options: ReelMotion.command);
    }
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  /// Where a thrown action ends, since the button's own future has nowhere to go.
  ///
  /// [FilledButton.onPressed] is a `VoidCallback`, so the `Future` [_run]
  /// returns is discarded the moment it is handed over — a `rethrow` from here
  /// landed in nothing and surfaced as an unhandled async exception, because
  /// `main()` runs a plain `runApp` with no zone guard. The label roll is the
  /// user-facing half of handling it; this is the other half, so the failure is
  /// still reported through the framework's own channel (and is visible to
  /// `tester.takeException`) instead of escaping the app.
  ///
  /// A *failed* connection test does not come through here — `diagnoseCredentials`
  /// returns a failure value rather than throwing — so this is reserved for the
  /// genuinely exceptional: a malformed URL, a client constructor that raises.
  void _reportFailure(Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'cupola',
        context: ErrorDescription(
          'while running the "${widget.label}" command button action',
        ),
      ),
    );
  }

  Future<void> _run() async {
    final action = widget.onPressed;
    if (action == null || _busy) return;

    final busyLabel = widget.busyLabel;
    if (busyLabel == null) {
      // Nothing to wait for. Not even a one-frame disabled flash: the parent
      // will hand us a new resting label and `didUpdateWidget` rolls to it.
      //
      // Guarded all the same: this branch never took over the label, so a throw
      // here left the button looking untouched *and* escaped as an unhandled
      // async error. A failure label, when the parent supplied one, is the only
      // thing that can say otherwise.
      try {
        await action();
      } catch (error, stack) {
        if (mounted && widget.failureLabel != null) {
          _label.set(widget.failureLabel!, options: ReelMotion.command);
        }
        _reportFailure(error, stack);
      }
      return;
    }

    // No frame loop under Reduce Motion: one settled `Testing`, and the
    // disabled button is what carries "in progress". See [ReelMotion.waiting].
    final reduced = MediaQuery.disableAnimationsOf(context);
    final ReelTextProgress? handle;
    if (reduced) {
      handle = null;
      _label.set(busyLabel, options: ReelMotion.command);
    } else {
      handle = _label.startWaiting(busyLabel, options: ReelMotion.waiting);
    }
    setState(() => _busy = true);

    try {
      await action();
      // Read after the await on purpose: a successful test rebuilds this widget
      // with its next resting label, and that is the label to land on.
      if (!mounted) return;
      final settled = widget.label;
      handle == null
          ? _label.set(settled, options: ReelMotion.command)
          : handle.complete(settled, options: ReelMotion.command);
    } catch (error, stack) {
      if (mounted) {
        final settled = widget.failureLabel ?? widget.label;
        handle == null
            ? _label.set(settled, options: ReelMotion.command)
            : handle.fail(settled, options: ReelMotion.command);
      }
      _reportFailure(error, stack);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The widest the label can get, so the slot can hold all of it.
  ///
  /// Includes the busy label with a full set of trailing dots, because
  /// [ReelWaiting.ellipsis] genuinely renders `Testing...` and a slot measured
  /// on `Testing` alone would clip the frame it was built for.
  double _slotWidth(BuildContext context, TextStyle style) {
    final candidates = <String>[
      widget.label,
      if (widget.busyLabel case final busy?) ...[busy, '$busy...'],
      if (widget.failureLabel case final f?) f,
      ...widget.slotLabels,
    ];
    var widest = 0.0;
    for (final candidate in candidates) {
      final painter = TextPainter(
        text: TextSpan(text: candidate, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      );
      try {
        painter.layout();
        if (painter.width > widest) widest = painter.width;
      } finally {
        painter.dispose();
      }
    }
    return widest;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The label style the button would have used anyway, resolved so the
    // reservation is measured in the same type it will paint in.
    final style =
        theme.filledButtonTheme.style?.textStyle?.resolve(<WidgetState>{}) ??
        theme.textTheme.labelLarge!;

    // Reduce Motion drops the slot renderer entirely rather than asking it to
    // stand still — same rule as [ReelLine]. The reservation stays, because the
    // label still changes and a button that resizes under a settled swap is the
    // same defect with the animation removed.
    if (MediaQuery.disableAnimationsOf(context)) {
      return FilledButton(
        onPressed: widget.onPressed == null || _busy ? null : _run,
        child: SizedBox(
          width: _slotWidth(context, style),
          // Read off this widget's own state rather than the controller: a
          // `ChangeNotifier` this `State` does not listen to cannot schedule a
          // rebuild on its own, and every transition that matters here already
          // arrives with one.
          child: Text(
            _busy ? widget.busyLabel ?? widget.label : widget.label,
            style: style,
            textAlign: TextAlign.center,
            maxLines: 1,
          ),
        ),
      );
    }

    return FilledButton(
      onPressed: widget.onPressed == null || _busy ? null : _run,
      child: SizedBox(
        width: _slotWidth(context, style),
        // Clipped like every other roll — see [ReelLine]. A button is the
        // tightest housing in the app: unclipped, a label's travelling glyphs
        // reach past the button's own fill and paint on the surface behind it.
        child: ClipRect(
          child: ReelText.controller(
            controller: _label,
            options: ReelMotion.command,
            style: style,
            textAlign: TextAlign.center,
            // Pinned to the resting label. Without it a screen reader reads the
            // button's name as whatever ellipsis frame is on screen, so the
            // control announces itself as "Testing.." — a name that is different
            // every time it is focused.
            semanticsLabel: _busy
                ? widget.busyLabel ?? widget.label
                : widget.label,
          ),
        ),
      ),
    );
  }
}
