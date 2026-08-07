import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reel_text/reel_text.dart';

/// Finds a line of text whether it is drawn as a `Text` or rolled by a
/// [ReelText].
///
/// `find.text` matches a `Text` widget's own `data`, and a rolling line has
/// none: `ReelText` splits its string into one clipped slot per grapheme and
/// each slot is its own `Text`. So `find.text('Available')` finds nothing on a
/// rolled label, while `find.text('R')` cheerfully matches a *slot* — which is
/// how a per-grapheme renderer turns into a false positive in a test that was
/// asserting something else entirely.
///
/// Use this wherever a test asserts *content* rather than motion. It matches the
/// value the user is actually given — the string on a `Text`, or a `ReelText`'s
/// target text and spoken label — so a test does not have to know which sites in
/// the app happen to roll, and does not break when one starts or stops.
///
/// Assertions genuinely about the roll should reach for [ReelText] by type
/// instead; this finder deliberately cannot tell the two renderings apart.
Finder findLine(String text) =>
    _match((value) => value == text, 'with value "$text"');

/// [findLine], matching on a substring — the counterpart to
/// `find.textContaining`.
Finder findLineContaining(String text) =>
    _match((value) => value.contains(text), 'containing "$text"');

Finder _match(
  bool Function(String value) matches,
  String description,
) => find.byElementPredicate((element) {
  final widget = element.widget;

  if (widget is ReelText) {
    // Both, not one or the other: a rolled line's painted string and its
    // spoken string are allowed to differ — an eyebrow is uppercased for the
    // eye and expanded for the ear — and a test may reasonably assert either.
    return [
      widget.text,
      widget.semanticsLabel,
    ].whereType<String>().any(matches);
  }

  if (widget is Text) {
    // Skip the slots. `ReelText` renders one `Text` per grapheme, so a
    // single-character value like "4" matches the line *and* the one slot
    // inside it — which is how this finder reported two widgets where the
    // screen shows one number.
    var insideReel = false;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is ReelText) {
        insideReel = true;
        return false;
      }
      return true;
    });
    if (insideReel) return false;

    final value = widget.data ?? widget.textSpan?.toPlainText();
    return value != null && matches(value);
  }

  return false;
}, description: 'Text or ReelText $description');
