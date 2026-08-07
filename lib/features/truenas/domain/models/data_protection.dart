import 'package:seekarr/core/utils/dynamic_map_utils.dart';

/// The kind of data-protection task, each backed by a distinct RPC namespace.
enum TrueNasTaskKind {
  snapshot('Snapshot Tasks', 'pool.snapshottask'),
  replication('Replication', 'replication'),
  cloudSync('Cloud Sync', 'cloudsync'),
  rsync('Rsync', 'rsynctask'),
  scrub('Scrub Tasks', 'pool.scrub');

  final String label;
  final String namespace;
  const TrueNasTaskKind(this.label, this.namespace);

  String get queryMethod => '$namespace.query';
  String get deleteMethod => '$namespace.delete';
  String get updateMethod => '$namespace.update';

  /// The RPC that starts the task immediately.
  ///
  /// Most namespaces expose `<namespace>.run`, but cloud sync is the exception:
  /// the middleware method is `cloudsync.sync` — `cloudsync.run` does not exist
  /// and every "Run now" against it failed server-side.
  String get runMethod =>
      this == TrueNasTaskKind.cloudSync ? 'cloudsync.sync' : '$namespace.run';
}

/// A normalized data-protection task for list display + generic actions.
class TrueNasProtectionTask {
  final TrueNasTaskKind kind;
  final int id;
  final String title;
  final String subtitle;
  final bool enabled;
  final String? state;

  /// The pool a scrub task belongs to. `pool.scrub.run` is keyed by pool *name*
  /// (`run(name: str, threshold: int)`), not by task id, so the name has to
  /// survive parsing for "Run now" to work at all. Null for every other kind.
  final String? poolName;

  const TrueNasProtectionTask({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.enabled,
    this.state,
    this.poolName,
  });

  factory TrueNasProtectionTask.fromJson(
    TrueNasTaskKind kind,
    Map<String, dynamic> json,
  ) {
    final id = intOrNull(json['id']) ?? 0;
    String title;
    String subtitle;
    String? state;
    String? poolName;

    switch (kind) {
      case TrueNasTaskKind.snapshot:
        title = stringOrNull(json['dataset']) ?? 'Snapshot task';
        final schema = stringOrNull(json['naming_schema']) ?? '';
        final recursive = json['recursive'] == true ? ' · recursive' : '';
        subtitle = '$schema$recursive';
      case TrueNasTaskKind.replication:
        title = stringOrNull(json['name']) ?? 'Replication';
        subtitle =
            '${stringOrNull(json['direction']) ?? ''} · '
            '${stringOrNull(json['transport']) ?? ''}';
        state = stringOrNull(mapOrNull(json['state'])?['state']);
      case TrueNasTaskKind.cloudSync:
        title = stringOrNull(json['description']) ?? 'Cloud sync';
        subtitle =
            '${stringOrNull(json['direction']) ?? ''} · '
            '${stringOrNull(json['path']) ?? ''}';
        state = stringOrNull(mapOrNull(json['job'])?['state']);
      case TrueNasTaskKind.rsync:
        title = stringOrNull(json['path']) ?? 'Rsync task';
        final host = stringOrNull(json['remotehost']) ?? '';
        subtitle = '${stringOrNull(json['direction']) ?? ''} · $host';
      case TrueNasTaskKind.scrub:
        poolName =
            stringOrNull(json['pool_name']) ??
            stringOrNull(mapOrNull(json['pool'])?['name']);
        title = poolName ?? 'Scrub';
        subtitle =
            stringOrNull(json['description']) ??
            'Threshold '
                '${intOrNull(json['threshold']) ?? '?'} days';
    }

    return TrueNasProtectionTask(
      kind: kind,
      id: id,
      title: title.isEmpty ? kind.label : title,
      subtitle: subtitle.trim().replaceAll(RegExp(r'^·\s*|\s*·$'), ''),
      enabled: json['enabled'] == true,
      state: state,
      poolName: poolName,
    );
  }
}
