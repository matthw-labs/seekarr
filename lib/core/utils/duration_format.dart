/// Formatting for elapsed durations that are shown to the user and updated in
/// place — a release search's clock today, and the background job cards that will
/// read the same value later.
///
/// Two forms rather than one, because a screen reader cannot read `1:12`: the
/// glyph form is for the eye and carries `.tabular` at the call site so it does
/// not jitter as it counts, and the spoken form is for `Semantics(label:)`.
library;

/// Formats [elapsed] as `m:ss` — `0:07`, `1:12`, `12:04`.
///
/// Minutes are not zero-padded: this is a stopwatch, not a timestamp, and a
/// leading zero on the minutes reads as a clock time.
String formatElapsed(Duration elapsed) {
  final seconds = elapsed.inSeconds % 60;
  return '${elapsed.inMinutes}:${seconds.toString().padLeft(2, '0')}';
}

/// Spells [elapsed] out for a screen reader: `7 seconds`, `1 minute 12 seconds`,
/// `2 minutes`.
String formatElapsedForSpeech(Duration elapsed) {
  final minutes = elapsed.inMinutes;
  final seconds = elapsed.inSeconds % 60;
  final spokenSeconds = '$seconds second${seconds == 1 ? '' : 's'}';
  if (minutes == 0) return spokenSeconds;
  final spokenMinutes = '$minutes minute${minutes == 1 ? '' : 's'}';
  return seconds == 0 ? spokenMinutes : '$spokenMinutes $spokenSeconds';
}

/// Formats a remaining window compactly: `29m`, `4m 30s`, `0s`.
///
/// Always carries a unit, at every magnitude. A bare `4:30` in the same slot as
/// an elapsed clock is indistinguishable from one — and these two numbers mean
/// opposite things, so the unit is what keeps them apart.
String formatWindowRemaining(Duration remaining) {
  if (remaining.inMinutes >= 10) return '${remaining.inMinutes}m';
  final minutes = remaining.inMinutes;
  final seconds = remaining.inSeconds % 60;
  if (minutes == 0) return '${seconds}s';
  return seconds == 0 ? '${minutes}m' : '${minutes}m ${seconds}s';
}

/// Spells the same window out for a screen reader, which cannot read `4m 30s`.
String formatWindowForSpeech(Duration remaining) {
  final minutes = remaining.inMinutes;
  final seconds = remaining.inSeconds % 60;
  if (minutes == 0) return '$seconds second${seconds == 1 ? '' : 's'}';
  final spokenMinutes = '$minutes minute${minutes == 1 ? '' : 's'}';
  if (remaining.inMinutes >= 10 || seconds == 0) return spokenMinutes;
  return '$spokenMinutes $seconds second${seconds == 1 ? '' : 's'}';
}
