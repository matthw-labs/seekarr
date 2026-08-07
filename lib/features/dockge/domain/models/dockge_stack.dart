import 'package:flutter/material.dart';

import 'package:cupola/core/utils/dynamic_map_utils.dart';

/// Lifecycle state of a Dockge stack.
///
/// Mirrors the integer status constants used by the Dockge backend
/// (`common/util-common.ts`): `UNKNOWN=0`, `CREATED_FILE=1`,
/// `CREATED_STACK=2`, `RUNNING=3`, `EXITED=4`.
enum DockgeStackStatus {
  unknown(0, 'Unknown'),
  createdFile(1, 'Inactive'),
  createdStack(2, 'Inactive'),
  running(3, 'Running'),
  exited(4, 'Exited');

  const DockgeStackStatus(this.code, this.label);

  final int code;
  final String label;

  static DockgeStackStatus fromCode(int? code) {
    for (final status in values) {
      if (status.code == code) return status;
    }
    return DockgeStackStatus.unknown;
  }

  bool get isActive => this == DockgeStackStatus.running;

  /// Accent colour used for the status dot/badge in the UI.
  Color get color {
    switch (this) {
      case DockgeStackStatus.running:
        return const Color(0xFF3BB273); // green
      case DockgeStackStatus.exited:
        return const Color(0xFFE5484D); // red
      case DockgeStackStatus.createdFile:
      case DockgeStackStatus.createdStack:
        return const Color(0xFFF5A623); // amber (inactive)
      case DockgeStackStatus.unknown:
        return const Color(0xFF8A8F98); // grey
    }
  }
}

/// A Docker Compose stack as summarised by Dockge's `stackList` push event.
///
/// Corresponds to `Stack.toSimpleJSON()` on the backend.
@immutable
class DockgeStack {
  final String name;
  final DockgeStackStatus status;
  final List<String> tags;
  final bool isManagedByDockge;
  final String? composeFileName;

  /// The Dockge endpoint (agent) this stack belongs to. Empty string for a
  /// direct (single-instance) connection.
  final String endpoint;

  const DockgeStack({
    required this.name,
    required this.status,
    this.tags = const [],
    this.isManagedByDockge = true,
    this.composeFileName,
    this.endpoint = '',
  });

  factory DockgeStack.fromJson(Map<String, dynamic> json) {
    return DockgeStack(
      name: stringOrNull(json['name']) ?? '',
      status: DockgeStackStatus.fromCode(intOrNull(json['status'])),
      tags: _parseTags(json['tags']),
      isManagedByDockge: json['isManagedByDockge'] == true,
      composeFileName: stringOrNull(json['composeFileName']),
      endpoint: stringOrNull(json['endpoint']) ?? '',
    );
  }

  DockgeStack copyWith({
    String? name,
    DockgeStackStatus? status,
    List<String>? tags,
    bool? isManagedByDockge,
    String? composeFileName,
    String? endpoint,
  }) {
    return DockgeStack(
      name: name ?? this.name,
      status: status ?? this.status,
      tags: tags ?? this.tags,
      isManagedByDockge: isManagedByDockge ?? this.isManagedByDockge,
      composeFileName: composeFileName ?? this.composeFileName,
      endpoint: endpoint ?? this.endpoint,
    );
  }

  static List<String> _parseTags(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList(growable: false);
    }
    return const [];
  }
}
