/// Formats an ISO-8601 date string to `YYYY-MM-DD`.
///
/// Returns the original string if parsing fails.
String formatIsoDate(String isoDate) {
  try {
    final date = DateTime.parse(isoDate);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  } catch (_) {
    return isoDate;
  }
}

/// Capitalizes the first character of [value].
///
/// Returns [value] unchanged if it is empty.
String capitalizeFirst(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}

/// Turns an API identifier into display text: `importBlocked` → `Import
/// Blocked`, `download_client` → `Download Client`.
String humanizeCamelCase(String value) {
  if (value.trim().isEmpty) return value;

  final normalized = value.replaceAll('_', ' ').replaceAll('-', ' ');
  final withSpaces = normalized.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match[1]} ${match[2]}',
  );

  return withSpaces
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
