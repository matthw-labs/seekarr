import 'package:flutter/material.dart';

import 'package:seekarr/core/utils/dynamic_map_utils.dart';
import 'package:seekarr/features/dockge/domain/models/dockge_stack.dart';

/// Full detail of a stack, returned by Dockge's `getStack` event.
///
/// Extends the summary [DockgeStack] fields with the editable compose sources.
@immutable
class DockgeStackDetail {
  final DockgeStack stack;
  final String composeYAML;
  final String composeENV;
  final String? primaryHostname;

  const DockgeStackDetail({
    required this.stack,
    this.composeYAML = '',
    this.composeENV = '',
    this.primaryHostname,
  });

  String get name => stack.name;
  DockgeStackStatus get status => stack.status;

  factory DockgeStackDetail.fromJson(Map<String, dynamic> json) {
    return DockgeStackDetail(
      stack: DockgeStack.fromJson(json),
      composeYAML: stringOrNull(json['composeYAML']) ?? '',
      composeENV: stringOrNull(json['composeENV']) ?? '',
      primaryHostname: stringOrNull(json['primaryHostname']),
    );
  }
}

/// A single container instance of a compose service, as reported by the
/// `serviceStatusList` event (`{status, name}`).
@immutable
class DockgeServiceInstance {
  final String containerName;
  final String status;

  const DockgeServiceInstance({
    required this.containerName,
    required this.status,
  });

  bool get isRunning {
    final s = status.toLowerCase();
    return s == 'running' || s == 'healthy' || s.startsWith('up');
  }

  factory DockgeServiceInstance.fromJson(Map<String, dynamic> json) {
    return DockgeServiceInstance(
      containerName: stringOrNull(json['name']) ?? '',
      status: stringOrNull(json['status']) ?? 'unknown',
    );
  }
}

/// Aggregated status of one compose service (a service can map to multiple
/// container instances, e.g. when scaled).
@immutable
class DockgeServiceStatus {
  final String serviceName;
  final List<DockgeServiceInstance> instances;

  const DockgeServiceStatus({
    required this.serviceName,
    this.instances = const [],
  });

  bool get isRunning =>
      instances.isNotEmpty && instances.every((i) => i.isRunning);

  /// A short combined status label for display.
  String get statusLabel {
    if (instances.isEmpty) return 'stopped';
    if (instances.length == 1) return instances.first.status;
    final running = instances.where((i) => i.isRunning).length;
    return '$running/${instances.length} up';
  }

  /// Parses the `serviceStatusList` map: `{serviceName: [{status, name}, ...]}`.
  static List<DockgeServiceStatus> listFromMap(Map<String, dynamic> map) {
    final result = <DockgeServiceStatus>[];
    map.forEach((serviceName, value) {
      final instances = <DockgeServiceInstance>[];
      if (value is List) {
        for (final entry in value) {
          final entryMap = mapOrNull(entry);
          if (entryMap != null) {
            instances.add(DockgeServiceInstance.fromJson(entryMap));
          }
        }
      }
      result.add(
        DockgeServiceStatus(serviceName: serviceName, instances: instances),
      );
    });
    result.sort((a, b) => a.serviceName.compareTo(b.serviceName));
    return result;
  }
}
