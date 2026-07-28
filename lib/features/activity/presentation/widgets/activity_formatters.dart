import 'package:seekarr/core/utils/dynamic_map_utils.dart'
    show intOrNull, mapOrNull, stringOrNull;
import 'package:seekarr/core/status/arr_queue_snapshot.dart';
import 'package:seekarr/core/utils/arr_activity_display.dart';
import 'package:seekarr/core/utils/release_utils.dart';
import 'package:seekarr/core/utils/string_utils.dart';
import 'package:seekarr/features/activity/presentation/activity_screen.dart';

export 'package:seekarr/core/utils/dynamic_map_utils.dart'
    show intOrNull, stringOrNull;
export 'package:seekarr/core/utils/string_utils.dart' show formatIsoDate;

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
    final date = DateTime.parse(isoDate).toLocal();
    final reference = (now ?? DateTime.now()).toLocal();
    final difference = reference.difference(date);
    final isFuture = difference.isNegative;
    final delta = isFuture ? date.difference(reference) : difference;

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

    return formatIsoDate(isoDate);
  } catch (_) {
    return isoDate;
  }
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

String formatSizeInGb(dynamic bytes) {
  if (bytes == null) return '—';

  final value = switch (bytes) {
    final num number => number.toDouble(),
    final String text => double.tryParse(text),
    _ => null,
  };

  if (value == null) return '—';

  const bytesPerGb = 1024 * 1024 * 1024;
  return '${(value / bytesPerGb).toStringAsFixed(2)} GB';
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

  final formattedSize = formatSizeInGb(size);
  return formattedSize == '—' ? null : formattedSize;
}

String humanizeEventType(String value) {
  switch (value) {
    case 'grabbed':
      return 'Grabbed';
    case 'downloadFolderImported':
    case 'downloadImported':
      return 'Imported';
    case 'downloadFailed':
      return 'Failed';
    case 'episodeFileDeleted':
    case 'movieFileDeleted':
      return 'Deleted';
    case 'episodeFileRenamed':
    case 'movieFileRenamed':
      return 'Renamed';
    default:
      return humanizeCamelCase(value);
  }
}

/// Resolves a queue record for display in the Activity tab.
///
/// A thin wrapper over the canonical [ArrQueueEntry] parser so Activity, the
/// media detail pages and the poster grids can never disagree about what a
/// queue record means. Unlike the media resolvers this always returns a status:
/// an already-imported record still has a row to render.
MediaStatusInfo resolveQueueDisplayStatus(Map<String, dynamic> item) {
  final entry = ArrQueueEntry.fromQueueItem(item);
  if (entry != null) {
    return MediaStatusInfo(
      pipeline: entry.pipeline,
      progress: entry.progress,
      hasWarning: entry.hasWarning,
      detail: entry.detail,
      labelOverride: entry.label,
    );
  }

  // `imported` / `ignored`: the pipeline is done with this record.
  final trackedState = stringOrNull(
    item['trackedDownloadState'],
  )?.toLowerCase();
  return MediaStatusInfo(
    availability: MediaAvailability.available,
    labelOverride: trackedState == 'ignored' ? 'Ignored' : 'Imported',
    hasWarning: arrQueueHasWarning(item),
  );
}

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
