/// One place where a byte count becomes a string.
///
/// Five call sites independently grew their own copy of this — SABnzbd's
/// `_formatMb`/`_formatBytes`/`speedLabel`, NZBGet's `formatNzbgetRate`/
/// `formatNzbgetMb`, qBittorrent's `formatSize`/`formatSpeed` (also used by
/// Transmission, NPM and every TrueNAS screen) and Interactive Search's
/// `formatReleaseSize` — with different unit ladders and different precision
/// rules, so the same 1.46 GiB rendered as `1.5 GB` on one dashboard and
/// `1500 MB` on another.
///
/// The rules here, chosen as the most defensible union of the five:
///
///  * **Binary units** (1024-based), labelled `KB`/`MB`/`GB` — every one of the
///    services reports binary quantities under those labels, and the numbers
///    have to agree with the service's own web UI.
///  * **Bytes are whole things.** `B` never carries a decimal; `512 B`, not
///    `512.0 B`.
///  * **Significant digits, not decimal places.** The compact ladder keeps two
///    (`1.5 GB`, `999 KB`); [formatBytesPrecise] keeps three (`1.50 GB`,
///    `45.5 TB`). A fixed decimal count is what produced both `1500 MB` and
///    `2048.00 GB` in the copies this replaces.
///  * **Promotion happens after rounding**, so 1023.7 KB prints `1.0 MB`
///    rather than the self-contradicting `1024 KB`.
///
/// Which ladder a call site takes is a UI decision, not a data one:
///
///  * **Compact** ([formatBytes], [formatBytesPerSecond], [formatMegabytes],
///    [formatKilobytesPerSecond]) for anything read at a glance — KPI cells,
///    dashboard tiles, transfer rates. Two digits is what keeps such a cell one
///    glance wide at every scale, and every service's rate must render the same
///    way when they sit side by side in the same grid.
///  * **Precise** ([formatBytesPrecise]) for a size the user *compares* or
///    watches grow — release candidates in Interactive Search, torrent and file
///    sizes, TrueNAS pools and datasets. Two digits would round a 45.5 TB pool
///    to `46 TB` and two 4-something-GB releases to the same `4 GB`, which is
///    the whole reason those numbers are on screen.
library;

const List<String> _units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];

const int _kib = 1024;

/// Renders a size in bytes: `0 B`, `512 B`, `1.5 GB`, `5.0 TB`.
String formatBytes(num bytes) => _format(bytes.toDouble(), '');

/// Renders a size in bytes one significant digit finer than [formatBytes]:
/// `512 B`, `4.37 GB`, `45.5 TB`, `798 MB`.
///
/// For sizes the user compares against each other (two release candidates, a
/// pool against its free space) rather than reads as a magnitude. Same ladder,
/// same promotion rule, same whole bytes — only the resolution differs.
String formatBytesPrecise(num bytes) =>
    _format(bytes.toDouble(), '', significantDigits: 3);

/// Renders a transfer rate in bytes per second: `512 B/s`, `2.0 MB/s`.
String formatBytesPerSecond(num bytesPerSecond) =>
    _format(bytesPerSecond.toDouble(), '/s');

/// Renders a size reported in whole megabytes — SABnzbd's `mbleft`/`mb` and
/// NZBGet's `*SizeMB` fields, which is how both APIs report queue sizes.
String formatMegabytes(num megabytes) =>
    formatBytes(megabytes.toDouble() * _kib * _kib);

/// Renders a rate reported in kilobytes per second — SABnzbd's `kbpersec`.
String formatKilobytesPerSecond(num kilobytesPerSecond) =>
    formatBytesPerSecond(kilobytesPerSecond.toDouble() * _kib);

String _format(double value, String suffix, {int significantDigits = 2}) {
  final sign = value.isNegative ? '-' : '';
  var magnitude = value.abs();
  if (!magnitude.isFinite) return '—';

  var unit = 0;
  while (true) {
    // Bytes are indivisible; above that the decimals are whatever is left of
    // the significant-digit budget once the whole part has taken its share.
    final decimals = unit == 0 ? 0 : _decimalsFor(magnitude, significantDigits);
    final text = magnitude.toStringAsFixed(decimals);
    // Rounding can push a value back over the promotion threshold (1023.7 KB
    // renders as "1024"), so the check reads the *rendered* number, not the
    // raw one — otherwise the string contradicts its own unit.
    if (unit == _units.length - 1 || double.parse(text) < _kib) {
      return '$sign$text ${_units[unit]}$suffix';
    }
    magnitude /= _kib;
    unit++;
  }
}

/// How many decimals [magnitude] earns on a [significantDigits] budget.
///
/// The whole part is counted first — 4.37 spends one digit and keeps two, 45.5
/// spends two and keeps one, 798 spends the lot and keeps none. Never negative:
/// the top rung of the ladder has nothing to promote into, so a magnitude
/// larger than the budget simply prints all its digits.
int _decimalsFor(double magnitude, int significantDigits) {
  var wholeDigits = 1;
  for (
    var bound = 10.0;
    magnitude >= bound && wholeDigits < significantDigits;
    bound *= 10
  ) {
    wholeDigits++;
  }
  return significantDigits - wholeDigits;
}
