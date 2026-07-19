import 'package:seekarr/core/utils/dynamic_map_utils.dart';

/// System overview from `system.info`.
class TrueNasSystemInfo {
  final String? version;
  final String? hostname;
  final int? uptimeSeconds;
  final int? cores;
  final int? physmemBytes;
  final double? loadAvg1m;

  const TrueNasSystemInfo({
    this.version,
    this.hostname,
    this.uptimeSeconds,
    this.cores,
    this.physmemBytes,
    this.loadAvg1m,
  });

  factory TrueNasSystemInfo.fromJson(Map<String, dynamic> json) {
    final loadavg = json['loadavg'];
    double? load1;
    if (loadavg is List && loadavg.isNotEmpty) {
      load1 = doubleOrNull(loadavg.first);
    }
    return TrueNasSystemInfo(
      version: stringOrNull(json['version']),
      hostname: stringOrNull(json['hostname']),
      uptimeSeconds: doubleOrNull(json['uptime_seconds'])?.round(),
      cores: intOrNull(json['cores']),
      physmemBytes: intOrNull(json['physmem']),
      loadAvg1m: load1,
    );
  }
}

/// A storage pool from `pool.query`.
class TrueNasPool {
  final String name;
  final String status;
  final bool healthy;
  final int? sizeBytes;
  final int? allocatedBytes;

  const TrueNasPool({
    required this.name,
    required this.status,
    required this.healthy,
    this.sizeBytes,
    this.allocatedBytes,
  });

  /// Used fraction 0..1 when capacity is known, else null.
  double? get usedFraction {
    final size = sizeBytes;
    final allocated = allocatedBytes;
    if (size == null || allocated == null || size <= 0) return null;
    return (allocated / size).clamp(0, 1);
  }

  factory TrueNasPool.fromJson(Map<String, dynamic> json) {
    return TrueNasPool(
      name: stringOrNull(json['name']) ?? 'Pool',
      status: stringOrNull(json['status']) ?? 'UNKNOWN',
      healthy: json['healthy'] == true,
      sizeBytes: intOrNull(json['size']),
      allocatedBytes: intOrNull(json['allocated']),
    );
  }
}

/// An alert from `alert.list`.
class TrueNasAlert {
  final String id;
  final String level;
  final String message;
  final bool dismissed;

  const TrueNasAlert({
    required this.id,
    required this.level,
    required this.message,
    required this.dismissed,
  });

  factory TrueNasAlert.fromJson(Map<String, dynamic> json) {
    return TrueNasAlert(
      id: stringOrNull(json['uuid']) ?? stringOrNull(json['id']) ?? '',
      level: stringOrNull(json['level']) ?? 'INFO',
      message:
          stringOrNull(json['formatted']) ??
          stringOrNull(json['text']) ??
          'Alert',
      dismissed: json['dismissed'] == true,
    );
  }
}

/// A system service from `service.query`.
class TrueNasServiceItem {
  final int? id;
  final String name;
  final bool running;
  final bool enabled;

  const TrueNasServiceItem({
    required this.id,
    required this.name,
    required this.running,
    required this.enabled,
  });

  factory TrueNasServiceItem.fromJson(Map<String, dynamic> json) {
    final state = stringOrNull(json['state'])?.toUpperCase();
    return TrueNasServiceItem(
      id: intOrNull(json['id']),
      name: stringOrNull(json['service']) ?? stringOrNull(json['name']) ?? '—',
      running: state == 'RUNNING' || json['running'] == true,
      enabled: json['enable'] == true,
    );
  }
}

/// Aggregated dashboard snapshot.
class TrueNasDashboard {
  final TrueNasSystemInfo system;
  final List<TrueNasPool> pools;
  final List<TrueNasAlert> alerts;
  final List<TrueNasServiceItem> services;

  const TrueNasDashboard({
    required this.system,
    required this.pools,
    required this.alerts,
    required this.services,
  });

  /// Active (non-dismissed) alerts.
  List<TrueNasAlert> get activeAlerts =>
      alerts.where((a) => !a.dismissed).toList(growable: false);

  static List<T> parseList<T>(
    dynamic result,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (result is! List) return const [];
    return result
        .map(mapOrNull)
        .whereType<Map<String, dynamic>>()
        .map(fromJson)
        .toList(growable: false);
  }
}
