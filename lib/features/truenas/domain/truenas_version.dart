/// Minimum TrueNAS SCALE version Cupola's TrueNAS console supports.
///
/// 25.04 "Fangtooth" is the first release with the Incus virtualization API
/// (`virt.instance.*`, used for both LXC containers and VMs) and the stable
/// JSON-RPC transport at `/api/current` that this client speaks.
const String kTrueNasMinVersion = '25.04';

/// A parsed TrueNAS SCALE version train (`YY.MM[.patch]`).
///
/// TrueNAS reports versions like `TrueNAS-SCALE-25.04.1` or `25.04.2`; only the
/// `YY.MM` train matters for feature gating, with the patch as a tiebreaker.
class TrueNasVersion implements Comparable<TrueNasVersion> {
  final int year;
  final int month;
  final int patch;

  const TrueNasVersion(this.year, this.month, [this.patch = 0]);

  /// Extracts a `YY.MM(.patch)` version from an arbitrary TrueNAS version
  /// string, or null if none is present.
  static TrueNasVersion? parse(String? raw) {
    if (raw == null) return null;
    final match = RegExp(r'(\d{2})\.(\d{2})(?:\.(\d+))?').firstMatch(raw);
    if (match == null) return null;
    final year = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    if (year == null || month == null) return null;
    final patch = int.tryParse(match.group(3) ?? '0') ?? 0;
    return TrueNasVersion(year, month, patch);
  }

  /// Whether this version is at least [kTrueNasMinVersion].
  bool get isSupported => this >= const TrueNasVersion(25, 4);

  /// Whether [rawVersion] parses to a supported version. Returns true when the
  /// version cannot be parsed (fail open — avoid blocking on odd strings).
  static bool isVersionSupported(String? rawVersion) {
    final parsed = parse(rawVersion);
    return parsed == null || parsed.isSupported;
  }

  @override
  int compareTo(TrueNasVersion other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return patch.compareTo(other.patch);
  }

  bool operator >=(TrueNasVersion other) => compareTo(other) >= 0;
  bool operator <(TrueNasVersion other) => compareTo(other) < 0;

  @override
  String toString() =>
      '${year.toString().padLeft(2, '0')}.${month.toString().padLeft(2, '0')}'
      '${patch > 0 ? '.$patch' : ''}';

  @override
  bool operator ==(Object other) =>
      other is TrueNasVersion &&
      other.year == year &&
      other.month == month &&
      other.patch == patch;

  @override
  int get hashCode => Object.hash(year, month, patch);
}
