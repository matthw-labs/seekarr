import 'package:seekarr/core/utils/dynamic_map_utils.dart';

/// Global Incus virtualization config from `virt.global.config`.
class TrueNasVirtGlobalConfig {
  final String? pool;
  final String? dataset;
  final String state;
  final String? bridge;

  const TrueNasVirtGlobalConfig({
    this.pool,
    this.dataset,
    required this.state,
    this.bridge,
  });

  /// Whether virtualization is initialized and ready to host instances.
  bool get isReady => state.toUpperCase() == 'INITIALIZED' && pool != null;

  factory TrueNasVirtGlobalConfig.fromJson(Map<String, dynamic> json) {
    return TrueNasVirtGlobalConfig(
      pool: stringOrNull(json['pool']),
      dataset: stringOrNull(json['dataset']),
      state: stringOrNull(json['state']) ?? 'UNKNOWN',
      bridge: stringOrNull(json['bridge']),
    );
  }
}

/// A device attached to a virt instance, from `virt.device.query`.
class TrueNasVirtDevice {
  final String name;
  final String type;
  final String description;

  const TrueNasVirtDevice({
    required this.name,
    required this.type,
    required this.description,
  });

  factory TrueNasVirtDevice.fromJson(Map<String, dynamic> json) {
    final type =
        stringOrNull(json['dev_type']) ?? stringOrNull(json['type']) ?? '—';
    final parts = <String>[];
    for (final key in [
      'source',
      'destination',
      'nic_type',
      'bus',
      'product_id',
    ]) {
      final v = stringOrNull(json[key]);
      if (v != null) parts.add(v);
    }
    return TrueNasVirtDevice(
      name: stringOrNull(json['name']) ?? type,
      type: type,
      description: parts.join(' · '),
    );
  }
}

/// An Incus instance (LXC container or VM) from `virt.instance.query`.
class TrueNasVirtInstance {
  final String id;
  final String name;
  final String type; // CONTAINER | VM
  final String status; // RUNNING | STOPPED | ...
  final int? cpuCount;
  final int? memoryBytes;
  final bool autostart;
  final String? image;

  const TrueNasVirtInstance({
    required this.id,
    required this.name,
    required this.type,
    required this.status,
    this.cpuCount,
    this.memoryBytes,
    this.autostart = false,
    this.image,
  });

  bool get isRunning => status.toUpperCase() == 'RUNNING';
  bool get isVm => type.toUpperCase() == 'VM';

  factory TrueNasVirtInstance.fromJson(Map<String, dynamic> json) {
    final imageJson = mapOrNull(json['image']);
    String? image;
    if (imageJson != null) {
      final os = stringOrNull(imageJson['os']);
      final release = stringOrNull(imageJson['release']);
      image = [os, release].whereType<String>().join(' ');
      if (image.isEmpty) image = null;
    }
    // `cpu` may be a count or a pinned-core string; keep only integer counts.
    return TrueNasVirtInstance(
      id: stringOrNull(json['id']) ?? stringOrNull(json['name']) ?? '',
      name: stringOrNull(json['name']) ?? '',
      type: stringOrNull(json['type']) ?? 'CONTAINER',
      status: stringOrNull(json['status']) ?? 'UNKNOWN',
      cpuCount: intOrNull(json['cpu']),
      memoryBytes: intOrNull(json['memory']),
      autostart: json['autostart'] == true,
      image: image,
    );
  }
}
