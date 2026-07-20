import 'package:seekarr/features/truenas/data/truenas_api_base.dart';
import 'package:seekarr/features/truenas/domain/models/data_protection.dart';

/// Data-protection tasks: periodic snapshots, replication, cloud sync, rsync,
/// and scrub tasks. Each kind maps to its own RPC namespace via
/// [TrueNasTaskKind].
class TrueNasDataProtectionApi extends TrueNasApiBase {
  const TrueNasDataProtectionApi(super.client);

  Future<List<TrueNasProtectionTask>> getTasks(TrueNasTaskKind kind) async {
    final result = await client.call(kind.queryMethod);
    if (result is! List) return const [];
    return result
        .whereType<Map>()
        .map(
          (m) => TrueNasProtectionTask.fromJson(
            kind,
            Map<String, dynamic>.from(m),
          ),
        )
        .toList(growable: false);
  }

  /// Enables/disables a task. Scrub and periodic snapshot tasks use `enabled`.
  Future<void> setEnabled(TrueNasTaskKind kind, int id, bool enabled) =>
      client.call(kind.updateMethod, [
        id,
        {'enabled': enabled},
      ]);

  /// Runs a task now. Snapshot/scrub tasks are fire-and-forget; replication,
  /// cloud sync and rsync return a job id.
  Future<dynamic> run(TrueNasTaskKind kind, int id) {
    switch (kind) {
      case TrueNasTaskKind.replication:
      case TrueNasTaskKind.cloudSync:
      case TrueNasTaskKind.rsync:
        return client.callJob(kind.runMethod, [id]);
      case TrueNasTaskKind.snapshot:
      case TrueNasTaskKind.scrub:
        return client.call(kind.runMethod, [id]);
    }
  }

  Future<void> delete(TrueNasTaskKind kind, int id) =>
      client.call(kind.deleteMethod, [id]);

  Future<List<Map<String, dynamic>>> getCloudCredentials() async {
    final result = await client.call('cloudsync.credentials.query');
    if (result is! List) return const [];
    return result
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }
}
