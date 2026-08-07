import 'package:cupola/core/utils/dynamic_map_utils.dart';

/// System overview from `system.info`.
class TrueNasSystemInfo {
  final String? version;
  final String? hostname;
  final int? uptimeSeconds;
  final int? cores;
  final int? physmemBytes;
  final double? loadAvg1m;
  final double? loadAvg5m;
  final double? loadAvg15m;
  final String? model;
  final String? systemProduct;
  final String? systemSerial;

  const TrueNasSystemInfo({
    this.version,
    this.hostname,
    this.uptimeSeconds,
    this.cores,
    this.physmemBytes,
    this.loadAvg1m,
    this.loadAvg5m,
    this.loadAvg15m,
    this.model,
    this.systemProduct,
    this.systemSerial,
  });

  factory TrueNasSystemInfo.fromJson(Map<String, dynamic> json) {
    final loadavg = json['loadavg'];
    double? load1, load5, load15;
    if (loadavg is List) {
      if (loadavg.isNotEmpty) load1 = doubleOrNull(loadavg[0]);
      if (loadavg.length > 1) load5 = doubleOrNull(loadavg[1]);
      if (loadavg.length > 2) load15 = doubleOrNull(loadavg[2]);
    }
    return TrueNasSystemInfo(
      version: stringOrNull(json['version']),
      hostname: stringOrNull(json['hostname']),
      uptimeSeconds: doubleOrNull(json['uptime_seconds'])?.round(),
      cores: intOrNull(json['cores']),
      physmemBytes: intOrNull(json['physmem']),
      loadAvg1m: load1,
      loadAvg5m: load5,
      loadAvg15m: load15,
      model: stringOrNull(json['model']),
      systemProduct: stringOrNull(json['system_product']),
      systemSerial: stringOrNull(json['system_serial']),
    );
  }
}
