import 'package:seekarr/features/truenas/data/truenas_api_base.dart';
import 'package:seekarr/features/truenas/domain/models/pool.dart';

/// Storage pool operations (`pool.*`, `pool.scrub.*`).
class TrueNasStorageApi extends TrueNasApiBase {
  const TrueNasStorageApi(super.client);

  /// All pools, without topology (lighter — used for lists/KPIs).
  Future<List<TrueNasPool>> getPools() =>
      queryList('pool.query', TrueNasPool.fromJson);

  /// A single pool including its full topology.
  Future<TrueNasPool?> getPool(String name) async {
    final result = await client.call('pool.query', [
      [
        ['name', '=', name],
      ],
      {
        'extra': {'topology': true},
      },
    ]);
    if (result is! List || result.isEmpty) return null;
    final map = result.first;
    if (map is! Map) return null;
    return TrueNasPool.fromJson(Map<String, dynamic>.from(map));
  }

  /// Starts a scrub on [poolName] (`START`), or `STOP` to cancel.
  Future<void> runScrub(String poolName, {String action = 'START'}) =>
      client.call('pool.scrub.scrub', [poolName, action]);

  Future<List<Map<String, dynamic>>> getScrubTasks() async {
    final result = await client.call('pool.scrub.query');
    if (result is! List) return const [];
    return result
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }
}
