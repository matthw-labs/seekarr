/// Formats an ISO-8601 date string to `YYYY-MM-DD`.
///
/// Returns the original string if parsing fails.
///
/// This is the *dense-row* date voice: the activity feed pairs it with a clock
/// time and sorts by it, where a fixed-width sortable form reads better than a
/// prose one. It is deliberately **not** the detail-page voice — see
/// [formatMediumDate].
String formatIsoDate(String isoDate) {
  try {
    final date = DateTime.parse(isoDate);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  } catch (_) {
    return isoDate;
  }
}

const List<String> _shortMonthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Formats an ISO-8601 date as `Jul 17, 2026` — the one date voice every media
/// detail page speaks.
///
/// The drift this exists to end was visible two taps apart: a Radarr movie
/// printed `2019-05-22` in its Details grid while the Seerr page for the same
/// film printed `May 22, 2019`. Both are correct and neither is wrong on its
/// own, which is exactly why the choice has to live in one place instead of
/// being re-made per screen. Prose form wins on a detail page because nothing
/// there is sorted or compared column-wise; [formatIsoDate] keeps the sortable
/// form for the rows that are.
///
/// Returns the input unchanged when it cannot be parsed, so a service that
/// answers with something unexpected still shows what it actually said rather
/// than an empty cell. English month names are hard-coded on purpose:
/// English-only is a decision here, not debt, so there is no `intl` dependency
/// to reach for.
String formatMediumDate(String isoDate) {
  final trimmed = isoDate.trim();
  if (trimmed.isEmpty) return trimmed;

  final parsed = DateTime.tryParse(trimmed);
  if (parsed == null) return isoDate;

  return '${_shortMonthNames[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
}

/// [formatMediumDate] for a nullable field, answering null rather than echoing
/// something unparseable back.
///
/// A dense child row states its facts in a dot-separated line built from a
/// `List<String>`: there is no cell to leave blank, so a date the service did
/// not send — or sent in a shape no one can read — has to disappear from the
/// line entirely rather than print raw JSON at the user. The prose form itself
/// is [formatMediumDate]'s, so a row and the Details grid above it cannot
/// disagree about what a date looks like.
String? formatMediumDateOrNull(String? isoDate) {
  final raw = isoDate?.trim();
  if (raw == null || raw.isEmpty) return null;
  if (DateTime.tryParse(raw) == null) return null;
  return formatMediumDate(raw);
}

/// Formats a whole number of minutes as `2h 7m`, or `47m` under the hour.
///
/// Radarr shipped `127 min` and Seerr `173min` for the same kind of fact. Hours
/// and minutes is the form a person actually reasons in ("do I have time for
/// this tonight?"), and it stops a three-digit minute count reading as a number
/// that needs dividing.
///
/// Returns an empty string for a non-positive value: a runtime of zero is a
/// fact the service does not have, not a film of no length, and an empty string
/// is dropped by the metadata line and the fact grid alike.
String formatRuntimeMinutes(int minutes) {
  if (minutes <= 0) return '';

  final hours = minutes ~/ 60;
  final remainder = minutes % 60;

  if (hours == 0) return '${remainder}m';
  if (remainder == 0) return '${hours}h';
  return '${hours}h ${remainder}m';
}

/// Caps a service-supplied title so it can be interpolated into a sheet header
/// or a dialog title without pushing the controls off the screen.
///
/// Both destinations render an unbounded [Text]: the sheet header's subtitle has
/// no `maxLines`, and an `AlertDialog` title sits *above* the scrollable
/// content, so a long title grows the header until the buttons leave the
/// viewport. A user cannot shorten their own library, and a 200-character title
/// is a normal thing for an anime release or a documentary series to have — so
/// the caller shortens the string rather than trusting the layout to cope.
///
/// Cuts on a word boundary where there is one within reach, so the tail reads
/// as a truncated title rather than a truncated word, and appends a single
/// ellipsis glyph (not three periods, which read as a pause).
String truncateTitle(String value, {int maxChars = 64}) {
  final trimmed = value.trim();
  if (trimmed.length <= maxChars) return trimmed;

  final hardCut = trimmed.substring(0, maxChars);
  final lastSpace = hardCut.lastIndexOf(' ');
  // Only honour a word boundary in the last third; a title whose first word is
  // longer than the budget would otherwise collapse to a single ellipsis.
  final cut = lastSpace >= (maxChars * 2) ~/ 3
      ? hardCut.substring(0, lastSpace)
      : hardCut;

  return '${cut.trimRight()}…';
}

/// Capitalizes the first character of [value].
///
/// Returns [value] unchanged if it is empty.
String capitalizeFirst(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}

/// Turns an API identifier into display text: `importBlocked` → `Import
/// Blocked`, `download_client` → `Download Client`.
String humanizeCamelCase(String value) {
  if (value.trim().isEmpty) return value;

  final normalized = value.replaceAll('_', ' ').replaceAll('-', ' ');
  final withSpaces = normalized.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match[1]} ${match[2]}',
  );

  return withSpaces
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
