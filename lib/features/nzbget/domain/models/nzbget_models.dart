/// Typed models for the NZBGet JSON-RPC API.
///
/// NZBGet splits large 64-bit integers into `<field>Hi` / `<field>Lo` unsigned
/// 32-bit halves; [combineHiLo] recomposes them. Most sizes are also exposed
/// directly in MB, which the dashboard prefers.
///
/// Size and rate labels go through `core/utils/byte_format.dart`. This file
/// used to carry `formatNzbgetRate` and `formatNzbgetMb`, which disagreed with
/// SABnzbd's equivalents on both thresholds and precision — so an identical
/// quantity read differently depending on which download client reported it.
library;

import 'package:cupola/core/utils/byte_format.dart';

int _asInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  final s = '$value'.toLowerCase();
  return s == 'true' || s == '1';
}

/// Recomposes an unsigned 64-bit value from NZBGet's Hi/Lo 32-bit halves.
int combineHiLo(dynamic hi, dynamic lo) {
  return _asInt(hi) * (1 << 32) + _asInt(lo);
}

/// Global download status (`status`).
class NzbgetStatus {
  const NzbgetStatus({
    required this.downloadRateBytes,
    required this.remainingSizeMb,
    required this.paused,
  });

  /// Current download rate in bytes per second.
  final int downloadRateBytes;

  /// Megabytes remaining across the queue.
  final int remainingSizeMb;

  final bool paused;

  String get rateLabel => formatBytesPerSecond(downloadRateBytes);
  String get remainingLabel => formatMegabytes(remainingSizeMb);

  factory NzbgetStatus.fromJson(Map<String, dynamic> json) {
    // Prefer the direct MB field; fall back to Hi/Lo bytes if absent.
    final remainingMb = json.containsKey('RemainingSizeMB')
        ? _asInt(json['RemainingSizeMB'])
        : combineHiLo(json['RemainingSizeHi'], json['RemainingSizeLo']) ~/
              (1024 * 1024);
    return NzbgetStatus(
      downloadRateBytes: _asInt(json['DownloadRate']),
      remainingSizeMb: remainingMb,
      paused: _asBool(json['DownloadPaused']),
    );
  }
}

/// A queued NZB (`listgroups`).
class NzbgetGroup {
  const NzbgetGroup({
    required this.nzbId,
    required this.name,
    required this.status,
    required this.category,
    required this.fileSizeMb,
    required this.remainingSizeMb,
  });

  final int nzbId;
  final String name;
  final String status;
  final String category;
  final int fileSizeMb;
  final int remainingSizeMb;

  double get progress {
    if (fileSizeMb <= 0) return 0;
    return ((fileSizeMb - remainingSizeMb) / fileSizeMb).clamp(0, 1).toDouble();
  }

  int get percentage => (progress * 100).round();
  String get remainingLabel => formatMegabytes(remainingSizeMb);

  factory NzbgetGroup.fromJson(Map<String, dynamic> json) {
    final fileMb = json.containsKey('FileSizeMB')
        ? _asInt(json['FileSizeMB'])
        : combineHiLo(json['FileSizeHi'], json['FileSizeLo']) ~/ (1024 * 1024);
    final remainingMb = json.containsKey('RemainingSizeMB')
        ? _asInt(json['RemainingSizeMB'])
        : combineHiLo(json['RemainingSizeHi'], json['RemainingSizeLo']) ~/
              (1024 * 1024);
    return NzbgetGroup(
      nzbId: _asInt(json['NZBID']),
      name: (json['NZBName'] ?? json['NZBNicename'] ?? 'Unknown').toString(),
      status: (json['Status'] ?? '').toString(),
      category: (json['Category'] ?? '').toString(),
      fileSizeMb: fileMb,
      remainingSizeMb: remainingMb,
    );
  }
}

/// A completed/failed NZB (`history`).
class NzbgetHistoryItem {
  const NzbgetHistoryItem({
    required this.id,
    required this.name,
    required this.status,
    required this.category,
    this.time,
  });

  final int id;
  final String name;
  final String status;
  final String category;
  final DateTime? time;

  /// NZBGet statuses look like `SUCCESS/ALL`, `FAILURE/UNPACK`, etc.
  bool get failed => status.toUpperCase().startsWith('FAILURE');
  bool get success => status.toUpperCase().startsWith('SUCCESS');

  factory NzbgetHistoryItem.fromJson(Map<String, dynamic> json) {
    final historyTime = _asInt(json['HistoryTime']);
    return NzbgetHistoryItem(
      id: _asInt(json['ID']),
      name: (json['Name'] ?? json['NZBName'] ?? 'Unknown').toString(),
      status: (json['Status'] ?? '').toString(),
      category: (json['Category'] ?? '').toString(),
      time: historyTime > 0
          ? DateTime.fromMillisecondsSinceEpoch(historyTime * 1000)
          : null,
    );
  }
}
