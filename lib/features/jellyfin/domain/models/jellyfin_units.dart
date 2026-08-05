/// Unit conversions for the Jellyfin API, isolated in one file because the
/// feature carries **four different units at once** and mixing any two of them
/// produces a plausible-looking wrong number rather than an error.
///
///  * every `*Ticks` field (`RunTimeTicks`, `PositionTicks`,
///    `PlaybackPositionTicks`) is a .NET tick — 100 nanoseconds;
///  * `TranscodingInfo.Bitrate` is bits per second;
///  * `PlayedPercentage` / `CompletionPercentage` are 0–100 doubles, not 0–1;
///  * `/Sessions?activeWithinSeconds` is plain seconds.
///
/// The Stream models want milliseconds (`StreamItem.runtimeMs`,
/// `StreamItem.resumeOffsetMs`) and a 0–1 fraction (`StreamSession.progress`),
/// so every tick value crosses exactly one of the functions below and nothing
/// else divides by a magic constant.
///
/// Everything here is pure and top-level so the item mappers that call it stay
/// `Isolate.run`-safe.
library;

/// One .NET tick is 100 ns, so a millisecond is 10 000 ticks.
const int kJellyfinTicksPerMillisecond = 10000;

/// 10 000 000 — `TimeSpan.TicksPerSecond`. Kept even though the app converts to
/// milliseconds, because it is the constant every Jellyfin discussion quotes and
/// its absence is what makes `/ 10000` look like a typo.
const int kJellyfinTicksPerSecond = 10000000;

/// Reads a tick count as a Dart [int].
///
/// Ticks are `int64` server-side: a two-hour film is 7.2e10 ticks, far past the
/// 2^24 where a `double` starts rounding, so this must never route through
/// [double]. A JSON number arrives as an [int] from `jsonDecode` when it is
/// integral, but a proxy that re-serialises the payload can hand back `7.2e10`
/// as a [double] or a quoted string, and both still have to parse.
int? jellyfinTicks(Object? raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is double) {
    // Non-finite or fractional-beyond-precision values are not a tick count.
    if (!raw.isFinite) return null;
    return raw.toInt();
  }
  if (raw is num) return raw.toInt();
  return _intFromText(raw.toString());
}

/// A textual number → [int], accepting the forms a re-serialising proxy produces.
///
/// `int.tryParse` alone rejects `"7.2e10"` and `"7200.0"`, which is precisely how
/// a large tick count comes back through a gateway that round-trips the JSON
/// through a floating-point type and then quotes it. `Infinity` and `NaN` parse as
/// doubles but have no integer value at all, so the finiteness check is not
/// optional — `double.infinity.toInt()` throws.
int? _intFromText(String raw) {
  final text = raw.trim();
  final asInt = int.tryParse(text);
  if (asInt != null) return asInt;
  final asDouble = double.tryParse(text);
  if (asDouble == null || !asDouble.isFinite) return null;
  return asDouble.toInt();
}

/// Ticks → whole milliseconds, the unit both `StreamItem` fields use.
///
/// Integer division rather than `/`: the result feeds progress arithmetic and a
/// runtime label, and neither wants a float artefact.
///
/// [zeroAsNull] exists because Jellyfin overloads zero as "unknown" in two
/// places — `RunTimeTicks: 0` on an item whose media has not been probed, and
/// `PlaybackPositionTicks: 0` on an item that was never started. Both must
/// arrive as `null` so the UI shows no runtime and no resume bar, instead of
/// "0 min" and a progress bar pinned at the left edge.
int? jellyfinMillisecondsFromTicks(Object? raw, {bool zeroAsNull = false}) {
  final ticks = jellyfinTicks(raw);
  if (ticks == null) return null;
  if (ticks < 0) return null;
  if (ticks == 0) return zeroAsNull ? null : 0;
  return ticks ~/ kJellyfinTicksPerMillisecond;
}

/// Progress as a 0–1 fraction from a position and a runtime, both in ticks.
///
/// Returns null when either side is missing or the runtime is zero — a live TV
/// channel reports a position against no runtime at all, and dividing by it
/// would put `Infinity` into a progress bar.
double? jellyfinFractionFromTicks({
  required Object? position,
  required Object? runtime,
}) {
  final positionTicks = jellyfinTicks(position);
  final runtimeTicks = jellyfinTicks(runtime);
  if (positionTicks == null || runtimeTicks == null) return null;
  if (runtimeTicks <= 0 || positionTicks < 0) return null;
  return (positionTicks / runtimeTicks).clamp(0.0, 1.0);
}

/// `PlayedPercentage` (0–100) → a 0–1 fraction.
///
/// The scale is the trap: this field is a percentage while every other progress
/// value in the app is a fraction, so passing it through unconverted yields a
/// bar that is 100× too long and clamps to full on anything past 1% watched.
double? jellyfinFractionFromPercent(Object? raw) {
  if (raw == null) return null;
  final value = raw is num ? raw.toDouble() : double.tryParse(raw.toString());
  if (value == null || !value.isFinite) return null;
  return (value / 100).clamp(0.0, 1.0);
}

/// Bits per second, straight through — named so a caller cannot mistake it for
/// the bytes-per-second the download clients report.
///
/// `TranscodingInfo.Bitrate` and `MediaSource.Bitrate` are both already bits/s;
/// the only work here is tolerating a string or a float.
int? jellyfinBitsPerSecond(Object? raw) {
  if (raw == null) return null;
  final value = raw is num
      ? raw.toDouble()
      : double.tryParse(raw.toString().trim());
  if (value == null || !value.isFinite || value <= 0) return null;
  return value.round();
}

/// Lenient nullable [int] for the plain counters (`ProductionYear`,
/// `IndexNumber`, `UnplayedItemCount`).
///
/// Nullable on purpose rather than reusing `parseInt`'s `0` fallback: a series
/// with `UnplayedItemCount: 0` is fully watched and a series that never reported
/// the field is unknown, and a badge must not claim the first when it means the
/// second.
int? jellyfinInt(Object? raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.isFinite ? raw.toInt() : null;
  return _intFromText(raw.toString());
}
