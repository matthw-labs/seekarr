/// Accessible strings for the Stream surfaces.
///
/// Pure and Flutter-free, the same discipline as `services_semantics.dart`: a
/// label composed inside a `build` method and asserted in a test is two strings
/// that drift.
///
/// The Stream board needs this more than most screens do. A session card paints
/// three stacked lines whose *visual* order is chosen for scanning — the title
/// first, because that is what the eye looks for — while the useful spoken order
/// is different: who, then what, then the thing you would act on. Reading the card
/// top to bottom aloud produces a comma list with no structure, which is the exact
/// failure `serviceMatrixCellValue` already documents for the matrix cell.
library;

import 'package:seekarr/core/utils/arr_activity_display.dart';

String _join(Iterable<String?> parts) =>
    joinDisplayParts(parts, separator: ', ');

/// What one session card announces.
///
/// Order is deliberate and differs from the visual order:
///
///  * **[userName] first.** On a household server the first question is whose
///    playback this is, and it is the one fact the visual layout puts *last*
///    (bottom line, beside the device) because the poster and title dominate.
///  * **The cost next**, when there is one. [transcodeReason] is the reason the
///    board exists, so it is spoken before the device and the position rather
///    than after them, where a long title could push it past the point a listener
///    stops attending.
///  * **[bitrateLabel] is spoken as "about"** when nominal, because it is the
///    file's own bitrate rather than measured throughput. Saying a precise-sounding
///    figure would assert something neither server reports.
///
/// [isPaused] is spoken rather than left to the icon: a paused session still holds
/// its transcode, so "paused" and "playing" are materially different states for
/// the operator and a pause glyph is not announced by itself.
String streamSessionValue({
  required String userName,
  required String title,
  required String? subtitle,
  required String playMethodLabel,
  required String? transcodeReason,
  required String deviceLabel,
  required String? progressLabel,
  required String? bitrateLabel,
  required bool bitrateIsNominal,
  required bool isPaused,
}) {
  final cost = transcodeReason == null
      ? playMethodLabel
      : '$playMethodLabel, $transcodeReason';
  final rate = bitrateLabel == null
      ? null
      : (bitrateIsNominal ? 'about $bitrateLabel' : bitrateLabel);

  return _join([
    userName,
    isPaused ? 'paused' : null,
    title,
    subtitle,
    cost,
    rate,
    'on $deviceLabel',
    progressLabel,
  ]);
}

/// The board's own state, when nobody is watching.
///
/// Used **both** on screen and by the screen reader — one string, because this is
/// a state and not a failure, and a visible "Nothing playing" beside a spoken
/// "error" would be two different bug reports. Deliberately not phrased as an
/// absence of content ("No sessions found"): the server is answering, and an idle
/// media server at 3pm on a Tuesday is the normal condition, not an empty state.
const String streamIdleMessage = 'Nobody is watching right now';

/// What one library row announces.
///
/// [lastScannedLabel] is null on Jellyfin, which exposes no per-library scan
/// timestamp — only a global scheduled task. The row simply omits it rather than
/// speaking "unknown", which would imply the server was asked and declined.
String streamLibraryValue({
  required String kindLabel,
  required int? itemCount,
  required String? lastScannedLabel,
  required bool isRefreshing,
}) => _join([
  kindLabel,
  itemCount == null ? null : '$itemCount items',
  isRefreshing ? 'scanning now' : lastScannedLabel,
]);

/// The confirm prompt for stopping someone else's playback.
///
/// Names the person and the title, because this is the one Stream action that
/// interrupts another human being in the house. Both servers only *dispatch* a
/// stop — the client may ignore it — so the copy promises to ask, not to succeed.
String streamStopSessionPrompt({
  required String userName,
  required String title,
}) => 'Ask $userName’s player to stop $title?';

/// What the lens chips announce on a library browse.
///
/// The visible label is a short chip ("Continue", "A–Z"); spoken, it needs the
/// noun back — "Continue" alone on a row of five chips does not say what it
/// continues, and "A–Z" is read character by character by both screen readers.
String streamLensLabel(String lensLabel) => switch (lensLabel) {
  'Continue' => 'Continue watching',
  'Next up' => 'Next up',
  'Recent' => 'Recently added',
  'Unplayed' => 'Not yet played',
  'A–Z' => 'All, alphabetical',
  _ => lensLabel,
};
