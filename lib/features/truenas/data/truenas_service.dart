import 'package:seekarr/core/utils/dynamic_map_utils.dart';
import 'package:seekarr/features/truenas/data/truenas_ws_client.dart';
import 'package:seekarr/features/truenas/domain/models/truenas_models.dart';

/// Typed operations over a [TrueNasWsClient].
class TrueNasService {
  final TrueNasWsClient client;

  TrueNasService(this.client);

  Future<TrueNasSystemInfo> getSystemInfo() async {
    final result = await client.call('system.info');
    final map = mapOrNull(result);
    if (map == null) {
      throw const TrueNasException('Unexpected system.info response');
    }
    return TrueNasSystemInfo.fromJson(map);
  }

  Future<List<TrueNasPool>> getPools() async {
    final result = await client.call('pool.query');
    return TrueNasDashboard.parseList(result, TrueNasPool.fromJson);
  }

  Future<List<TrueNasAlert>> getAlerts() async {
    final result = await client.call('alert.list');
    return TrueNasDashboard.parseList(result, TrueNasAlert.fromJson);
  }

  Future<List<TrueNasServiceItem>> getServices() async {
    final result = await client.call('service.query');
    return TrueNasDashboard.parseList(result, TrueNasServiceItem.fromJson);
  }

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

  Future<void> startService(String name) =>
      client.call('service.start', [name]);

  Future<void> stopService(String name) => client.call('service.stop', [name]);

  Future<void> dismissAlert(String uuid) =>
      client.call('alert.dismiss', [uuid]);
}
