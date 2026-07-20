import 'package:seekarr/core/utils/dynamic_map_utils.dart';

/// A system service from `service.query`.
class TrueNasServiceItem {
  final int? id;
  final String name;
  final bool running;
  final bool enabled;
  final String state;

  const TrueNasServiceItem({
    required this.id,
    required this.name,
    required this.running,
    required this.enabled,
    required this.state,
  });

  factory TrueNasServiceItem.fromJson(Map<String, dynamic> json) {
    final state = stringOrNull(json['state'])?.toUpperCase() ?? 'UNKNOWN';
    return TrueNasServiceItem(
      id: intOrNull(json['id']),
      name: stringOrNull(json['service']) ?? stringOrNull(json['name']) ?? '—',
      running: state == 'RUNNING' || json['running'] == true,
      enabled: json['enable'] == true,
      state: state,
    );
  }
}
