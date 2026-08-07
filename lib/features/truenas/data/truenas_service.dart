import 'package:cupola/features/truenas/data/storage_api.dart';
import 'package:cupola/features/truenas/data/system_api.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';
import 'package:cupola/features/truenas/domain/models/alert.dart';
import 'package:cupola/features/truenas/domain/models/dashboard.dart';
import 'package:cupola/features/truenas/domain/models/pool.dart';
import 'package:cupola/features/truenas/domain/models/service_item.dart';
import 'package:cupola/features/truenas/domain/models/system_info.dart';

/// Thin facade preserving the original dashboard/KPI surface, delegating to the
/// domain-grouped API classes over the shared [TrueNasWsClient].
class TrueNasService {
  final TrueNasWsClient client;
  final TrueNasSystemApi _system;
  final TrueNasStorageApi _storage;

  TrueNasService(this.client)
    : _system = TrueNasSystemApi(client),
      _storage = TrueNasStorageApi(client);

  Future<TrueNasSystemInfo> getSystemInfo() => _system.getSystemInfo();

  Future<List<TrueNasPool>> getPools() => _storage.getPools();

  Future<List<TrueNasAlert>> getAlerts() => _system.getAlerts();

  Future<List<TrueNasServiceItem>> getServices() => _system.getServices();

  /// Loads the full dashboard in parallel over the shared connection.
  Future<TrueNasDashboard> loadDashboard() async {
    final results = await Future.wait([
      getSystemInfo(),
      getPools(),
      getAlerts(),
      getServices(),
    ]);
    return TrueNasDashboard(
      system: results[0] as TrueNasSystemInfo,
      pools: results[1] as List<TrueNasPool>,
      alerts: results[2] as List<TrueNasAlert>,
      services: results[3] as List<TrueNasServiceItem>,
    );
  }

  /// Lightweight reachability + auth check for status/health.
  Future<bool> ping() async {
    await client.call('core.ping');
    return true;
  }

  Future<void> startService(String name) => _system.startService(name);

  Future<void> stopService(String name) => _system.stopService(name);

  Future<void> dismissAlert(String uuid) => _system.dismissAlert(uuid);
}
