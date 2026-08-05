/// Accessible strings for the `/services` tab.
///
/// Pure and Flutter-free on purpose: a label composed inside a `build` method
/// and asserted in a test is two strings that drift. Everything a screen reader
/// says on this tab is built here, so the widget and the test read one source.
library;

import 'package:seekarr/core/utils/arr_activity_display.dart';

/// Joins the non-empty parts with the comma both screen readers read as a short
/// pause.
///
/// Delegates to [joinDisplayParts] — the same trimming and empty-dropping the
/// visible strings already get, with a separator meant for the ear rather than
/// the eye.
String joinSpokenParts(Iterable<String?> parts) =>
    joinDisplayParts(parts, separator: ', ');

/// Re-separates a visually dot-joined string for speech.
///
/// `·` is decoration: iOS reads it as "middle dot" or drops it depending on the
/// user's punctuation verbosity, and neither is what the layout meant.
String spokenFromDotted(String visual) => joinSpokenParts(visual.split('·'));

/// What one cell in the stack matrix announces after its service name.
///
/// Reachability first because it gates everything else, then the live signal —
/// the reason the cell is worth reading — then the host to disambiguate two
/// instances of the same service.
///
/// [signalSpoken] arrives already phrased as `label value` ("Missing 12") rather
/// than in the cell's visual order ("12 MISSING"): the cell leads with the figure
/// because the eye scans a column of numbers, but read aloud that order only
/// happens to work in English for counts and collapses entirely for a rate
/// ("2.4 MB/s Down"). It is null while the KPI is still resolving, and on an
/// unreachable service that has no signal to report.
String serviceMatrixCellValue({
  required String statusLabel,
  required String? signalSpoken,
  required String host,
}) => joinSpokenParts([statusLabel, signalSpoken, host]);

/// The trailing "set up n more services" cell in the stack matrix.
///
/// Used **both** on screen and by the screen reader. It used to be two strings:
/// the cell painted a bare count — "9 more services" — and this returned "9 more
/// services available to set up" to make sense of it. The spoken version having
/// to add the verb was the tell that the visible one was missing it: beside a
/// `+` icon, "9 more services" reads as the tail of a truncated list rather than
/// as somewhere to go. Naming the action once fixes the eye and the ear
/// together, and matches the verb on the all-unconfigured empty state.
String servicesUnconfiguredCellLabel({required int count}) {
  final noun = count == 1 ? 'service' : 'services';
  return 'Set up $count more $noun';
}

/// The × that acknowledges an outage notice.
///
/// Names the outage rather than the gesture, for the same reason the
/// more-services × does: the row holds a Retry and a dismiss, and "Dismiss"
/// alone leaves a screen-reader user to guess which of the two they are on —
/// where one re-checks the connection and the other hides the notice.
String servicesDismissAlertLabel(List<String> offlineServiceTitles) =>
    'Dismiss: ${servicesAlertBandMessage(offlineServiceTitles)}';

/// The × beside that hint.
///
/// Names what disappears, not the gesture. "Dismiss" alone, on a row whose
/// sibling node is already called "Set up 8 more services", leaves a screen
/// reader user to infer which of the two things on the row it acts on — and
/// the answer matters, because one navigates and one is permanent.
String servicesDismissMoreServicesLabel({required int count}) =>
    'Dismiss the $count remaining services hint';

/// What a folded domain band announces, after its name.
///
/// Just the size of the group. A folded band used to replace its cells with a
/// strip of bare glyphs, so this had to carry the health those unlit tiles
/// showed silently; the compact cards that replaced the strip are labelled
/// nodes of their own, each announcing its own service, reachability and
/// figure. Repeating "Lidarr isn't answering" on the header as well would make
/// a screen reader say it twice on the way into the band.
String serviceDomainBandValue({required int serviceCount}) {
  final noun = serviceCount == 1 ? 'service' : 'services';
  return '$serviceCount $noun';
}

/// The alert band's sentence, used **both** on screen and by the screen reader.
///
/// One string for both because this is the one place a paraphrase would be a
/// real defect: the band exists to name which services stopped answering, so a
/// visible list and a spoken count that disagree would each be a different bug
/// report.
///
/// Names at most [maxNamed] services and folds the rest into "and n others" — a
/// stack where nine services are down would otherwise produce a band taller than
/// the grid it is warning about.
///
/// Uses "and" rather than [joinSpokenParts]'s comma: a trailing comma list read
/// aloud ("Dockge, TrueNAS") sounds truncated, as though the sentence lost its
/// last item.
String servicesAlertBandMessage(
  List<String> offlineServiceTitles, {
  int maxNamed = 3,
}) {
  final titles = offlineServiceTitles
      .where((t) => t.trim().isNotEmpty)
      .toList();
  if (titles.isEmpty) return '';

  final verb = titles.length == 1 ? "isn't" : "aren't";

  final String subject;
  if (titles.length <= maxNamed) {
    subject = titles.length == 1
        ? titles.single
        : '${titles.take(titles.length - 1).join(', ')} and ${titles.last}';
  } else {
    final hidden = titles.length - maxNamed;
    final others = hidden == 1 ? '1 other' : '$hidden others';
    subject = '${titles.take(maxNamed).join(', ')} and $others';
  }

  return '$subject $verb answering';
}

/// What a dashboard section says when its sources came back empty because they
/// did not answer.
///
/// Shares the alert band's sentence so the two never disagree about the same
/// fact, but names at most two services: this sits inside a 176pt rail, not
/// across the full width, and it is a footnote to a band the user has already
/// scrolled past rather than the primary warning.
///
/// Cross-service sections could not say this at all before. They degrade to `[]`
/// per source, so an unreachable Radarr and an empty library arrived identically
/// and both printed the empty copy — sending the user to look for missing media
/// when the answer was a missing connection. Naming *which* sources are dark is
/// what makes it safe for a merged rail; the old design could only blame a
/// single declared service, so it stayed silent instead.
String servicesSectionOfflineMessage(List<String> offlineServiceTitles) =>
    servicesAlertBandMessage(offlineServiceTitles, maxNamed: 2);

/// What one request row announces after its title.
///
/// Shared by the dashboard's Recent Requests rail and the All Requests screen —
/// only the latter shows a date, hence the optional [dateLabel]. The avatar
/// initials beside the requester are deliberately not spoken: they are the same
/// name in shorter form.
String seerrRequestRowValue({
  required String mediaTypeLabel,
  required String requester,
  required String statusLabel,
  String? dateLabel,
}) => joinSpokenParts([
  mediaTypeLabel,
  'requested by $requester',
  statusLabel,
  dateLabel,
]);

/// What one Downloading row announces after its title.
///
/// Warning first, then the progress the user came for, then the release detail
/// last so it can be interrupted. On screen the progress bar and the "75%" sit
/// in sibling subtrees; here they are one field.
///
/// [percent] is null when the client reports no progress, and is simply absent
/// then — the row paints nothing in that slot either, and the section is already
/// headed "Downloading".
///
/// [warning] is the client's own message ("Download stalled", "Not an upgrade"),
/// spoken in full. It used to be a bool that produced the bare word "Warning",
/// which named that something was wrong without saying what — while the actual
/// reason sat unused in the model. The visible pill is still a scan marker
/// because there is no room for a sentence in it; the reason lives one tap away
/// on `/activity`, and now also in the ear.
String downloadRowValue({
  required String subtitle,
  required int? percent,
  required String? warning,
}) => joinSpokenParts([
  warning,
  percent == null ? null : '$percent% downloaded',
  spokenFromDotted(subtitle),
]);
