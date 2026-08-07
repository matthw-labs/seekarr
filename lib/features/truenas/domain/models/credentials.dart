import 'package:cupola/core/utils/dynamic_map_utils.dart';

/// A user account from `user.query`.
class TrueNasUser {
  final int id;
  final int? uid;
  final String username;
  final String? fullName;
  final bool builtin;
  final bool locked;
  final String? shell;
  final bool smb;

  const TrueNasUser({
    required this.id,
    this.uid,
    required this.username,
    this.fullName,
    this.builtin = false,
    this.locked = false,
    this.shell,
    this.smb = false,
  });

  factory TrueNasUser.fromJson(Map<String, dynamic> json) {
    return TrueNasUser(
      id: intOrNull(json['id']) ?? 0,
      uid: intOrNull(json['uid']),
      username: stringOrNull(json['username']) ?? '—',
      fullName: stringOrNull(json['full_name']),
      builtin: json['builtin'] == true,
      locked: json['locked'] == true,
      shell: stringOrNull(json['shell']),
      smb: json['smb'] == true,
    );
  }
}

/// A group from `group.query`.
class TrueNasGroup {
  final int id;
  final int? gid;
  final String name;
  final bool builtin;
  final bool sudo;
  final int userCount;

  const TrueNasGroup({
    required this.id,
    this.gid,
    required this.name,
    this.builtin = false,
    this.sudo = false,
    this.userCount = 0,
  });

  factory TrueNasGroup.fromJson(Map<String, dynamic> json) {
    final users = json['users'];
    return TrueNasGroup(
      id: intOrNull(json['id']) ?? 0,
      gid: intOrNull(json['gid']),
      name: stringOrNull(json['group']) ?? stringOrNull(json['name']) ?? '—',
      builtin: json['builtin'] == true,
      sudo:
          json['sudo_commands'] is List &&
          (json['sudo_commands'] as List).isNotEmpty,
      userCount: users is List ? users.length : 0,
    );
  }
}
