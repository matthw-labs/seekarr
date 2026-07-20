import 'package:seekarr/core/utils/dynamic_map_utils.dart';

/// Reads the `parsed` (numeric) value out of a ZFS property object
/// (`{value, rawvalue, parsed, source}`), or a bare number.
int? _propInt(dynamic prop) {
  if (prop is Map)
    return intOrNull(prop['parsed']) ?? intOrNull(prop['rawvalue']);
  return intOrNull(prop);
}

/// Reads the display `value` out of a ZFS property object, or a bare string.
String? _propString(dynamic prop) {
  if (prop is Map)
    return stringOrNull(prop['value']) ?? stringOrNull(prop['rawvalue']);
  return stringOrNull(prop);
}

/// A ZFS dataset or zvol from `pool.dataset.query`.
class TrueNasDataset {
  final String id;
  final String name;
  final String pool;
  final String type; // FILESYSTEM | VOLUME
  final int? usedBytes;
  final int? availableBytes;
  final int? quotaBytes;
  final int? refquotaBytes;
  final int? volsizeBytes;
  final String? compression;
  final String? compressionRatio;
  final String? recordsize;
  final String? dedup;
  final String? comments;
  final String? mountpoint;
  final bool encrypted;
  final List<TrueNasDataset> children;

  const TrueNasDataset({
    required this.id,
    required this.name,
    required this.pool,
    required this.type,
    this.usedBytes,
    this.availableBytes,
    this.quotaBytes,
    this.refquotaBytes,
    this.volsizeBytes,
    this.compression,
    this.compressionRatio,
    this.recordsize,
    this.dedup,
    this.comments,
    this.mountpoint,
    this.encrypted = false,
    this.children = const [],
  });

  bool get isVolume => type.toUpperCase() == 'VOLUME';

  /// The trailing path segment (display name), e.g. `media` from `tank/media`.
  String get shortName {
    final idx = id.lastIndexOf('/');
    return idx >= 0 ? id.substring(idx + 1) : id;
  }

  factory TrueNasDataset.fromJson(Map<String, dynamic> json) {
    final childrenJson = json['children'];
    final children = <TrueNasDataset>[];
    if (childrenJson is List) {
      for (final child in childrenJson) {
        final map = mapOrNull(child);
        if (map != null) children.add(TrueNasDataset.fromJson(map));
      }
    }
    return TrueNasDataset(
      id: stringOrNull(json['id']) ?? stringOrNull(json['name']) ?? '',
      name: stringOrNull(json['name']) ?? '',
      pool: stringOrNull(json['pool']) ?? '',
      type: stringOrNull(json['type']) ?? 'FILESYSTEM',
      usedBytes: _propInt(json['used']),
      availableBytes: _propInt(json['available']),
      quotaBytes: _propInt(json['quota']),
      refquotaBytes: _propInt(json['refquota']),
      volsizeBytes: _propInt(json['volsize']),
      compression: _propString(json['compression']),
      compressionRatio: _propString(json['compressratio']),
      recordsize: _propString(json['recordsize']),
      dedup: _propString(json['deduplication']) ?? _propString(json['dedup']),
      comments: _propString(json['comments']),
      mountpoint: stringOrNull(json['mountpoint']),
      encrypted: json['encrypted'] == true,
      children: children,
    );
  }
}

/// A ZFS snapshot from `zfs.snapshot.query`.
class TrueNasSnapshot {
  final String id;
  final String name;
  final String dataset;
  final int? usedBytes;
  final int? referencedBytes;
  final int? createdMs;

  const TrueNasSnapshot({
    required this.id,
    required this.name,
    required this.dataset,
    this.usedBytes,
    this.referencedBytes,
    this.createdMs,
  });

  factory TrueNasSnapshot.fromJson(Map<String, dynamic> json) {
    final props = mapOrNull(json['properties']);
    final created = mapOrNull(json['properties'])?['creation'];
    int? createdMs;
    if (created is Map) {
      final parsed = intOrNull(
        created['parsed'] is Map ? null : created['parsed'],
      );
      if (parsed != null) createdMs = parsed * 1000;
    }
    return TrueNasSnapshot(
      id: stringOrNull(json['id']) ?? stringOrNull(json['name']) ?? '',
      name:
          stringOrNull(json['snapshot_name']) ??
          stringOrNull(json['name']) ??
          '',
      dataset: stringOrNull(json['dataset']) ?? '',
      usedBytes: _propInt(props?['used']),
      referencedBytes: _propInt(props?['referenced']),
      createdMs: createdMs,
    );
  }
}
