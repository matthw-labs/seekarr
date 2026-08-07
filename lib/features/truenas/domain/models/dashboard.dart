import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/truenas/domain/models/alert.dart';
import 'package:cupola/features/truenas/domain/models/pool.dart';
import 'package:cupola/features/truenas/domain/models/service_item.dart';
import 'package:cupola/features/truenas/domain/models/system_info.dart';

/// Aggregated dashboard snapshot (system, pools, alerts, services).
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
