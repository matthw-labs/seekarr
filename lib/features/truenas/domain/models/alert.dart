import 'package:cupola/core/utils/dynamic_map_utils.dart';

/// An alert from `alert.list`.
class TrueNasAlert {
  final String id;
  final String level;
  final String message;
  final bool dismissed;
  final int? datetimeMs;

  const TrueNasAlert({
    required this.id,
    required this.level,
    required this.message,
    required this.dismissed,
    this.datetimeMs,
  });

  factory TrueNasAlert.fromJson(Map<String, dynamic> json) {
    final datetime = json['datetime'];
    int? ms;
    if (datetime is Map) ms = intOrNull(datetime['\$date']);

    return TrueNasAlert(
      id: stringOrNull(json['uuid']) ?? stringOrNull(json['id']) ?? '',
      level: stringOrNull(json['level']) ?? 'INFO',
      message:
          stringOrNull(json['formatted']) ??
          stringOrNull(json['text']) ??
          'Alert',
      dismissed: json['dismissed'] == true,
      datetimeMs: ms,
    );
  }
}
