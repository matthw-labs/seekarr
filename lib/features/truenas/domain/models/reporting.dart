import 'package:seekarr/core/utils/dynamic_map_utils.dart';

/// A single reporting graph from `reporting.netdata_graph`.
///
/// Each row in [data] is `[timestampSeconds, series0, series1, ...]`, aligned
/// with [legend] (offset by one for the leading timestamp).
class TrueNasReportingGraph {
  final String name;
  final List<String> legend;
  final List<List<double?>> data;
  final int? start;
  final int? end;

  const TrueNasReportingGraph({
    required this.name,
    required this.legend,
    required this.data,
    this.start,
    this.end,
  });

  /// Series labels excluding the leading `time` column.
  List<String> get seriesLabels =>
      legend.isNotEmpty && legend.first.toLowerCase() == 'time'
      ? legend.sublist(1)
      : legend;

  /// Extracts the value series at [seriesIndex] (0-based, excluding time),
  /// paired with its row timestamp.
  List<({double t, double? v})> series(int seriesIndex) {
    final col = seriesIndex + 1; // skip timestamp column
    return data
        .where((row) => row.isNotEmpty)
        .map((row) => (t: row[0] ?? 0, v: col < row.length ? row[col] : null))
        .toList(growable: false);
  }

  factory TrueNasReportingGraph.fromJson(Map<String, dynamic> json) {
    final legendJson = json['legend'];
    final legend = legendJson is List
        ? legendJson.map((e) => e.toString()).toList(growable: false)
        : <String>[];

    final dataJson = json['data'];
    final rows = <List<double?>>[];
    if (dataJson is List) {
      for (final row in dataJson) {
        if (row is List) {
          rows.add(row.map(doubleOrNull).toList(growable: false));
        }
      }
    }

    return TrueNasReportingGraph(
      name: stringOrNull(json['name']) ?? '—',
      legend: legend,
      data: rows,
      start: intOrNull(json['start']),
      end: intOrNull(json['end']),
    );
  }
}
