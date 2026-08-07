import 'package:cupola/core/utils/dynamic_map_utils.dart';

/// A member device of a vdev (leaf disk).
class TrueNasVdevMember {
  final String name;
  final String status;

  const TrueNasVdevMember({required this.name, required this.status});

  factory TrueNasVdevMember.fromJson(Map<String, dynamic> json) {
    return TrueNasVdevMember(
      name:
          stringOrNull(json['disk']) ??
          stringOrNull(json['device']) ??
          stringOrNull(json['name']) ??
          '—',
      status: stringOrNull(json['status']) ?? 'UNKNOWN',
    );
  }
}

/// A vdev within a pool topology category.
class TrueNasVdev {
  final String type;
  final String status;
  final List<TrueNasVdevMember> members;

  const TrueNasVdev({
    required this.type,
    required this.status,
    required this.members,
  });

  factory TrueNasVdev.fromJson(Map<String, dynamic> json) {
    final children = json['children'];
    final members = <TrueNasVdevMember>[];
    if (children is List && children.isNotEmpty) {
      for (final child in children) {
        final map = mapOrNull(child);
        if (map != null) members.add(TrueNasVdevMember.fromJson(map));
      }
    } else {
      // A bare DISK vdev is its own member.
      members.add(TrueNasVdevMember.fromJson(json));
    }
    return TrueNasVdev(
      type: stringOrNull(json['type']) ?? 'DISK',
      status: stringOrNull(json['status']) ?? 'UNKNOWN',
      members: members,
    );
  }
}

/// A storage pool from `pool.query` (optionally with topology).
class TrueNasPool {
  final int? id;
  final String name;
  final String status;
  final bool healthy;
  final int? sizeBytes;
  final int? allocatedBytes;
  final int? freeBytes;
  final String? path;
  final Map<String, List<TrueNasVdev>> topology;
  final String? scanState;
  final double? scanPercentage;

  const TrueNasPool({
    this.id,
    required this.name,
    required this.status,
    required this.healthy,
    this.sizeBytes,
    this.allocatedBytes,
    this.freeBytes,
    this.path,
    this.topology = const {},
    this.scanState,
    this.scanPercentage,
  });

  /// Used fraction 0..1 when capacity is known, else null.
  double? get usedFraction {
    final size = sizeBytes;
    final allocated = allocatedBytes;
    if (size == null || allocated == null || size <= 0) return null;
    return (allocated / size).clamp(0, 1).toDouble();
  }

  bool get hasTopology => topology.values.any((v) => v.isNotEmpty);

  factory TrueNasPool.fromJson(Map<String, dynamic> json) {
    // pool.query returns size/allocated either at the top level or nested in
    // the root dataset stats depending on release; handle both.
    int? size = intOrNull(json['size']);
    int? allocated = intOrNull(json['allocated']);
    int? free = intOrNull(json['free']);
    final rootDataset = mapOrNull(json['root_dataset']);
    if (rootDataset != null) {
      // `root_dataset.available` is ZFS FREE space, not capacity: reading it as
      // the total made [usedFraction] compute used/free, which clamps every
      // pool at or past half full to a flat 100%. Capacity is used + available.
      final rootUsed = intOrNull(mapOrNull(rootDataset['used'])?['parsed']);
      final rootAvailable = intOrNull(
        mapOrNull(rootDataset['available'])?['parsed'],
      );
      allocated ??= rootUsed;
      free ??= rootAvailable;
      if (size == null && rootUsed != null && rootAvailable != null) {
        size = rootUsed + rootAvailable;
      }
    }

    final topology = <String, List<TrueNasVdev>>{};
    final topoJson = mapOrNull(json['topology']);
    if (topoJson != null) {
      for (final entry in topoJson.entries) {
        final list = entry.value;
        if (list is List && list.isNotEmpty) {
          final vdevs = list
              .map(mapOrNull)
              .whereType<Map<String, dynamic>>()
              .map(TrueNasVdev.fromJson)
              .toList(growable: false);
          if (vdevs.isNotEmpty) topology[entry.key] = vdevs;
        }
      }
    }

    final scan = mapOrNull(json['scan']);

    return TrueNasPool(
      id: intOrNull(json['id']),
      name: stringOrNull(json['name']) ?? 'Pool',
      status: stringOrNull(json['status']) ?? 'UNKNOWN',
      healthy: json['healthy'] == true,
      sizeBytes: size,
      allocatedBytes: allocated,
      freeBytes: free,
      path: stringOrNull(json['path']),
      topology: topology,
      scanState: stringOrNull(scan?['state']),
      scanPercentage: doubleOrNull(scan?['percentage']),
    );
  }
}
