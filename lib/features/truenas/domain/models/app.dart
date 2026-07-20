import 'package:seekarr/core/utils/dynamic_map_utils.dart';

/// An installed application from `app.query`.
class TrueNasApp {
  final String name;
  final String title;
  final String state; // RUNNING | STOPPED | DEPLOYING | CRASHED
  final String? humanVersion;
  final bool upgradeAvailable;
  final String? iconUrl;
  final String? train;
  final Map<String, String> portals;

  const TrueNasApp({
    required this.name,
    required this.title,
    required this.state,
    this.humanVersion,
    this.upgradeAvailable = false,
    this.iconUrl,
    this.train,
    this.portals = const {},
  });

  bool get isRunning => state.toUpperCase() == 'RUNNING';

  factory TrueNasApp.fromJson(Map<String, dynamic> json) {
    final metadata = mapOrNull(json['metadata']);
    final portalsJson = mapOrNull(json['portals']);
    final portals = <String, String>{};
    if (portalsJson != null) {
      for (final entry in portalsJson.entries) {
        final url = stringOrNull(entry.value);
        if (url != null) portals[entry.key] = url;
      }
    }
    return TrueNasApp(
      name: stringOrNull(json['name']) ?? stringOrNull(json['id']) ?? '—',
      title:
          stringOrNull(metadata?['title']) ?? stringOrNull(json['name']) ?? '—',
      state: stringOrNull(json['state']) ?? 'UNKNOWN',
      humanVersion: stringOrNull(json['human_version']),
      upgradeAvailable: json['upgrade_available'] == true,
      iconUrl: stringOrNull(metadata?['icon']),
      train: stringOrNull(metadata?['train']),
      portals: portals,
    );
  }
}
