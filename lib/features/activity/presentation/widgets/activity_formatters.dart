import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart'
    show intOrNull, mapOrNull, stringOrNull;
import 'package:cupola/core/utils/release_utils.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/features/activity/domain/global_activity_status.dart';
import 'package:cupola/features/activity/presentation/activity_screen.dart';

export 'package:cupola/core/utils/dynamic_map_utils.dart'
    show intOrNull, stringOrNull;
export 'package:cupola/core/utils/string_utils.dart' show formatIsoDate;
// The status resolvers moved to the domain layer; re-exported so the existing
// presentation call sites keep one import.
export 'package:cupola/features/activity/domain/global_activity_status.dart'
    show
        GlobalActivityKind,
        historyEventDisplay,
        resolveActivityStatus,
        resolveBlocklistStatus,
        resolveHistoryStatus,
        resolveQueueDisplayStatus,
        resolveRequestStatus,
        resolveWantedStatus;

Map<String, dynamic>? asActivityMap(dynamic value) => mapOrNull(value);

String joinActivityParts(Iterable<String?> parts, {String separator = ' · '}) {
  return joinDisplayParts(parts, separator: separator);
}

String formatActivityBytes(dynamic bytes) {
  if (bytes == null) return '—';
  if (bytes is num) return formatReleaseSize(bytes.toInt());
  final parsed = int.tryParse(bytes.toString());
  return parsed == null ? bytes.toString() : formatReleaseSize(parsed);
}

String formatActivityDuration(String? value) {
  if (value == null || value.trim().isEmpty) return '—';

  final parts = value.split(':');
  if (parts.length != 3) return value;

  final hours = int.tryParse(parts[0]) ?? 0;
  final minutes = int.tryParse(parts[1]) ?? 0;
  final seconds = int.tryParse(parts[2].split('.').first) ?? 0;
  final labels = <String>[];

  if (hours > 0) labels.add('${hours}h');
  if (minutes > 0) labels.add('${minutes}m');
  if (hours == 0 && minutes == 0) labels.add('${seconds}s');

  return labels.join(' ');
}

String formatRelativeActivityDate(String? isoDate, {DateTime? now}) {
  if (isoDate == null || isoDate.trim().isEmpty) return '—';

  try {
    return formatRelativeDateTime(DateTime.parse(isoDate), now: now);
  } catch (_) {
    return isoDate;
  }
}

/// Relative label for an already-parsed timestamp: `just now`, `20m ago`,
/// `3h ago`, `2d ago`, then an absolute date beyond a week.
///
/// Split out from [formatRelativeActivityDate] so callers holding a `DateTime`
/// — the global activity feed keeps one as `sortDate` — do not have to
/// round-trip it through an ISO string to display it.
String formatRelativeDateTime(DateTime date, {DateTime? now}) {
  final local = date.toLocal();
  final reference = (now ?? DateTime.now()).toLocal();
  final difference = reference.difference(local);
  final isFuture = difference.isNegative;
  final delta = isFuture ? local.difference(reference) : difference;

  if (delta < const Duration(minutes: 1)) {
    return isFuture ? 'in <1m' : 'just now';
  }
  if (delta < const Duration(hours: 1)) {
    final minutes = delta.inMinutes;
    return isFuture ? 'in ${minutes}m' : '${minutes}m ago';
  }
  if (delta < const Duration(days: 1)) {
    final hours = delta.inHours;
    return isFuture ? 'in ${hours}h' : '${hours}h ago';
  }
  if (delta < const Duration(days: 7)) {
    final days = delta.inDays;
    return isFuture ? 'in ${days}d' : '${days}d ago';
  }

  return formatIsoDate(local.toIso8601String());
}

String formatActivityDateTime(String? isoDate) {
  if (isoDate == null || isoDate.trim().isEmpty) return '—';

  try {
    final date = DateTime.parse(isoDate).toLocal();
    final datePart = formatIsoDate(date.toIso8601String());
    final timePart =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return '$datePart $timePart';
  } catch (_) {
    return isoDate;
  }
}

String formatDateOnly(String? isoDate) {
  if (isoDate == null || isoDate.trim().isEmpty) return '—';
  return formatIsoDate(isoDate);
}

/// Renders a byte count for the Activity surfaces that get one from loosely
/// typed JSON — history `data.size`, `sizeOnDisk`, an episode file's `size`.
///
/// Was a private GB-only ladder (`'${bytes / 1024^3} GB'`, two decimals, no
/// rung either side), which put two different ladders on the *same* detail
/// sheet: the queue sheet's Size field renders through [formatActivityBytes]
/// and the history sheet's through this, so 297 MB read as `0.29 GB` one tap
/// away from `297 MB`, and a 2 TiB item as `2048.00 GB`. Only the parsing is
/// local now; the ladder is the shared one.
String formatActivitySize(dynamic bytes) {
  if (bytes == null) return '—';

  final value = switch (bytes) {
    final num number => number.toDouble(),
    final String text => double.tryParse(text),
    _ => null,
  };

  if (value == null || !value.isFinite) return '—';

  return formatReleaseSize(value.round());
}

String? formatCutoffSize(Map<String, dynamic> item, ServiceType serviceType) {
  final size = switch (serviceType) {
    ServiceType.movies =>
      item['sizeOnDisk'] ??
          asActivityMap(item['statistics'])?['sizeOnDisk'] ??
          asActivityMap(item['movieFile'])?['size'] ??
          item['size'],
    ServiceType.series =>
      item['sizeOnDisk'] ??
          asActivityMap(item['statistics'])?['sizeOnDisk'] ??
          asActivityMap(item['episodeFile'])?['size'] ??
          item['size'],
    ServiceType.music =>
      item['sizeOnDisk'] ??
          asActivityMap(item['albumFile'])?['size'] ??
          asActivityMap(item['trackFile'])?['size'] ??
          asActivityMap(item['statistics'])?['sizeOnDisk'] ??
          item['size'],
    ServiceType.discover => null,
  };

  final formattedSize = formatActivitySize(size);
  return formattedSize == '—' ? null : formattedSize;
}

/// The display label for an \*arr history `eventType`.
///
/// Delegates to the domain resolver so the label and the severity colour can
/// never drift apart — they used to live in two separate switches, one here and
/// one in the tile, and the tile's disagreed.
String humanizeEventType(String value) => historyEventDisplay(value).$1;

/// The Activity tab spells the warning out in text, since its rows carry no
/// coloured badge of their own.
String queueDisplayLabel(
  MediaStatusInfo status, {
  bool includeWarningSuffix = true,
}) {
  if (includeWarningSuffix && status.hasWarning) {
    return '${status.label} (Warning)';
  }
  return status.label;
}

String? wantedStatusText(Map<String, dynamic> item, ServiceType serviceType) {
  final normalizedStatus = stringOrNull(item['status'])?.toLowerCase();
  final hasFile = item['hasFile'] == true;

  switch (serviceType) {
    case ServiceType.movies:
      if (!hasFile &&
          (normalizedStatus == 'released' || normalizedStatus == 'incinemas')) {
        return 'Movie missing from disk';
      }
      if (normalizedStatus == 'announced') {
        return 'Movie not available yet';
      }
      break;
    case ServiceType.series:
      if (!hasFile) {
        return 'Episode missing from disk';
      }
      break;
    case ServiceType.music:
      final statistics = asActivityMap(item['statistics']);
      final trackFileCount = intOrNull(statistics?['trackFileCount']) ?? 0;
      if (!hasFile || trackFileCount == 0) {
        return 'Album missing from disk';
      }
      break;
    case ServiceType.discover:
      return null;
  }

  return normalizedStatus == null ? null : humanizeCamelCase(normalizedStatus);
}

String formatActivityValue(dynamic value) {
  if (value == null) return '—';
  if (value is bool) return value ? 'Yes' : 'No';

  if (value is num || value is String) {
    final text = value.toString().trim();
    return text.isEmpty ? '—' : text;
  }

  if (value is List) {
    if (value.isEmpty) return '—';
    return value.map(formatActivityValue).join(', ');
  }

  if (value is Map) {
    if (value.isEmpty) return '—';

    return value.entries
        .where((entry) => entry.value != null)
        .map(
          (entry) =>
              '${humanizeCamelCase(entry.key.toString())}: ${formatActivityValue(entry.value)}',
        )
        .join(' • ');
  }

  return value.toString();
}

List<String> extractStatusMessages(dynamic rawMessages) {
  return extractArrStatusMessages(rawMessages);
}

String? extractQualityName(Map<String, dynamic> item, {String? fileKey}) {
  final source = fileKey == null ? item : asActivityMap(item[fileKey]);
  final quality = asActivityMap(source?['quality']);
  final nestedQuality = asActivityMap(quality?['quality']);
  return stringOrNull(nestedQuality?['name'] ?? quality?['name']);
}

String? formatEpisodeCode(int? seasonNumber, int? episodeNumber) {
  return formatArrEpisodeCode(seasonNumber, episodeNumber);
}
