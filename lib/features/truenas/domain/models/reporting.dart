import 'package:cupola/core/utils/dynamic_map_utils.dart';

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

  /// Parses one graph, keeping at most [maxPoints] of the **newest** rows.
  ///
  /// A netdata window is returned oldest-first and can run to thousands of rows
  /// per graph. Callers that only draw a live gauge or a short sparkline pass a
  /// cap so the discarded rows are never mapped into Dart objects at all — the
  /// dashboard polls this every few seconds on the UI isolate.
  factory TrueNasReportingGraph.fromJson(
    Map<String, dynamic> json, {
    int? maxPoints,
  }) {
    final legendJson = json['legend'];
    final legend = legendJson is List
        ? legendJson.map((e) => e.toString()).toList(growable: false)
        : <String>[];

    final dataJson = json['data'];
    final rows = <List<double?>>[];
    if (dataJson is List) {
      final skip = (maxPoints != null && dataJson.length > maxPoints)
          ? dataJson.length - maxPoints
          : 0;
      for (var i = skip; i < dataJson.length; i++) {
        final row = dataJson[i];
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
