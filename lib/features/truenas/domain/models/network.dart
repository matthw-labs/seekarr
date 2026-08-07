import 'package:cupola/core/utils/dynamic_map_utils.dart';

/// A network interface from `interface.query`.
class TrueNasInterface {
  final String name;
  final String type;
  final String? linkState;
  final String? macAddress;
  final List<String> addresses;

  const TrueNasInterface({
    required this.name,
    required this.type,
    this.linkState,
    this.macAddress,
    this.addresses = const [],
  });

  bool get isUp => (linkState ?? '').toUpperCase().contains('UP');

  factory TrueNasInterface.fromJson(Map<String, dynamic> json) {
    final state = mapOrNull(json['state']);
    final aliasesJson = state?['aliases'];
    final addresses = <String>[];
    if (aliasesJson is List) {
      for (final alias in aliasesJson) {
        final map = mapOrNull(alias);
        final type = stringOrNull(map?['type'])?.toUpperCase();
        final address = stringOrNull(map?['address']);
        if (address != null && (type == 'INET' || type == 'INET6')) {
          final netmask = intOrNull(map?['netmask']);
          addresses.add(netmask != null ? '$address/$netmask' : address);
        }
      }
    }
    return TrueNasInterface(
      name: stringOrNull(json['name']) ?? stringOrNull(json['id']) ?? '—',
      type: stringOrNull(json['type']) ?? 'PHYSICAL',
      linkState: stringOrNull(state?['link_state']),
      macAddress: stringOrNull(state?['link_address']),
      addresses: addresses,
    );
  }
}

/// Global network settings from `network.configuration.config`.
class TrueNasNetworkConfig {
  final String? hostname;
  final String? domain;
  final String? ipv4Gateway;
  final String? ipv6Gateway;
  final List<String> nameservers;

  const TrueNasNetworkConfig({
    this.hostname,
    this.domain,
    this.ipv4Gateway,
    this.ipv6Gateway,
    this.nameservers = const [],
  });

  factory TrueNasNetworkConfig.fromJson(Map<String, dynamic> json) {
    final nameservers = <String>[];
    for (final key in ['nameserver1', 'nameserver2', 'nameserver3']) {
      final v = stringOrNull(json[key]);
      if (v != null) nameservers.add(v);
    }
    return TrueNasNetworkConfig(
      hostname: stringOrNull(json['hostname']),
      domain: stringOrNull(json['domain']),
      ipv4Gateway: stringOrNull(json['ipv4gateway']),
      ipv6Gateway: stringOrNull(json['ipv6gateway']),
      nameservers: nameservers,
    );
  }
}
