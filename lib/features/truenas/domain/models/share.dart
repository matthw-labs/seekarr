import 'package:seekarr/core/utils/dynamic_map_utils.dart';

/// An SMB share from `sharing.smb.query`.
class TrueNasSmbShare {
  final int id;
  final String name;
  final String path;
  final bool enabled;
  final String? comment;
  final bool readonly;
  final String? purpose;

  const TrueNasSmbShare({
    required this.id,
    required this.name,
    required this.path,
    required this.enabled,
    this.comment,
    this.readonly = false,
    this.purpose,
  });

  factory TrueNasSmbShare.fromJson(Map<String, dynamic> json) {
    return TrueNasSmbShare(
      id: intOrNull(json['id']) ?? 0,
      name: stringOrNull(json['name']) ?? '—',
      path: stringOrNull(json['path']) ?? '',
      enabled: json['enabled'] == true,
      comment: stringOrNull(json['comment']),
      readonly: json['ro'] == true,
      purpose: stringOrNull(json['purpose']),
    );
  }
}

/// An NFS export from `sharing.nfs.query`.
class TrueNasNfsShare {
  final int id;
  final List<String> paths;
  final bool enabled;
  final String? comment;
  final bool readonly;
  final List<String> networks;
  final List<String> hosts;

  const TrueNasNfsShare({
    required this.id,
    required this.paths,
    required this.enabled,
    this.comment,
    this.readonly = false,
    this.networks = const [],
    this.hosts = const [],
  });

  String get displayPath => paths.isNotEmpty ? paths.join(', ') : '—';

  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList(growable: false);
    }
    final single = stringOrNull(value);
    return single == null ? const [] : [single];
  }

  factory TrueNasNfsShare.fromJson(Map<String, dynamic> json) {
    final paths = json.containsKey('paths')
        ? _stringList(json['paths'])
        : _stringList(json['path']);
    return TrueNasNfsShare(
      id: intOrNull(json['id']) ?? 0,
      paths: paths,
      enabled: json['enabled'] == true,
      comment: stringOrNull(json['comment']),
      readonly: json['ro'] == true,
      networks: _stringList(json['networks']),
      hosts: _stringList(json['hosts']),
    );
  }
}

/// An iSCSI target from `iscsi.target.query`.
class TrueNasIscsiTarget {
  final int id;
  final String name;
  final String? alias;
  final String? mode;

  const TrueNasIscsiTarget({
    required this.id,
    required this.name,
    this.alias,
    this.mode,
  });

  factory TrueNasIscsiTarget.fromJson(Map<String, dynamic> json) {
    return TrueNasIscsiTarget(
      id: intOrNull(json['id']) ?? 0,
      name: stringOrNull(json['name']) ?? '—',
      alias: stringOrNull(json['alias']),
      mode: stringOrNull(json['mode']),
    );
  }
}
