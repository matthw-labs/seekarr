import 'package:seekarr/features/truenas/data/truenas_api_base.dart';
import 'package:seekarr/features/truenas/data/truenas_ws_client.dart';
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

  /// Runs [task] now.
  ///
  /// The RPC *and* its parameters differ per kind, so this takes the whole task
  /// rather than a bare id:
  /// * replication / rsync — `<namespace>.run(id)`, a job we wait on.
  /// * cloud sync — `cloudsync.sync(id)`, a job. (`cloudsync.run` does not
  ///   exist; sending it made every "Run now" fail server-side.)
  /// * snapshot — `pool.snapshottask.run(id)`, fire-and-forget.
  /// * scrub — `pool.scrub.run(name, threshold)`, keyed by *pool name*, not by
  ///   task id. `threshold` is "skip if scrubbed within N days", so an explicit
  ///   0 is what makes "Run now" actually run now. Fire-and-forget: a scrub
  ///   runs for hours and the UI must not block on it.
  Future<dynamic> run(TrueNasProtectionTask task) {
    switch (task.kind) {
      case TrueNasTaskKind.replication:
      case TrueNasTaskKind.cloudSync:
      case TrueNasTaskKind.rsync:
        return client.callJob(task.kind.runMethod, [task.id]);
      case TrueNasTaskKind.snapshot:
        return client.call(task.kind.runMethod, [task.id]);
      case TrueNasTaskKind.scrub:
        final pool = task.poolName;
        if (pool == null || pool.isEmpty) {
          throw const TrueNasException('Scrub task is missing its pool name');
        }
        return client.call(task.kind.runMethod, [pool, 0]);
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
