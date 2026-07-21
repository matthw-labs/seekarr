/// Typed models for the Unraid GraphQL API.
///
/// Unraid's GraphQL schema evolves between releases, so field access is
/// deliberately tolerant: missing fields degrade to sensible defaults rather
/// than throwing. Confirm exact field names against the target instance's
/// schema (SDL / Apollo sandbox) before relying on any one of them.
library;

int? _asIntOrNull(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

/// System information (`info`).
class UnraidInfo {
  const UnraidInfo({required this.distro, required this.version, this.uptime});

  final String distro;

  /// Unraid release string, surfaced as the service version.
  final String version;

  final String? uptime;

  factory UnraidInfo.fromJson(Map<String, dynamic> json) {
    final os = (json['os'] as Map?)?.cast<String, dynamic>() ?? const {};
    return UnraidInfo(
      distro: (os['distro'] ?? 'Unraid').toString(),
      version: (os['release'] ?? '').toString(),
      uptime: os['uptime']?.toString(),
    );
  }
}

/// Storage array status (`array`).
class UnraidArray {
  const UnraidArray({
    required this.state,
    required this.usedFraction,
    required this.disks,
  });

  final String state;

  /// Fraction of total capacity used (0..1), or null when unknown.
  final double? usedFraction;

  final List<UnraidDisk> disks;

  int get usedPercent => ((usedFraction ?? 0) * 100).round();

  factory UnraidArray.fromJson(Map<String, dynamic> json) {
    double? usedFraction;
    final capacity = (json['capacity'] as Map?)?.cast<String, dynamic>();
    final bucket =
        (capacity?['kilobytes'] as Map?)?.cast<String, dynamic>() ??
        (capacity?['bytes'] as Map?)?.cast<String, dynamic>();
    if (bucket != null) {
      final total = _asDouble(bucket['total']);
      final used = _asDouble(bucket['used']);
      if (total > 0) usedFraction = (used / total).clamp(0, 1).toDouble();
    }
    final disks = (json['disks'] as List?) ?? const [];
    return UnraidArray(
      state: (json['state'] ?? 'UNKNOWN').toString(),
      usedFraction: usedFraction,
      disks: disks
          .whereType<Map>()
          .map((e) => UnraidDisk.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }
}

/// A single array disk.
class UnraidDisk {
  const UnraidDisk({
    required this.name,
    required this.status,
    required this.temp,
  });

  final String name;
  final String status;
  final int? temp;

  factory UnraidDisk.fromJson(Map<String, dynamic> json) {
    return UnraidDisk(
      name: (json['name'] ?? 'disk').toString(),
      status: (json['status'] ?? '').toString(),
      temp: _asIntOrNull(json['temp']),
    );
  }
}

/// A Docker container (`dockerContainers`).
class UnraidDockerContainer {
  const UnraidDockerContainer({
    required this.id,
    required this.name,
    required this.state,
    required this.status,
    required this.autoStart,
  });

  final String id;
  final String name;
  final String state;
  final String status;
  final bool autoStart;

  bool get running => state.toLowerCase() == 'running';

  factory UnraidDockerContainer.fromJson(Map<String, dynamic> json) {
    final names = json['names'];
    String name;
    if (names is List && names.isNotEmpty) {
      name = names.first.toString().replaceFirst(RegExp(r'^/'), '');
    } else {
      name = (json['name'] ?? 'container').toString();
    }
    return UnraidDockerContainer(
      id: (json['id'] ?? '').toString(),
      name: name,
      state: (json['state'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      autoStart: json['autoStart'] == true,
    );
  }
}
