import 'package:seekarr/features/truenas/data/truenas_api_base.dart';
import 'package:seekarr/features/truenas/domain/models/reporting.dart';

/// Reporting graphs from Netdata (`reporting.get_data`).
class TrueNasReportingApi extends TrueNasApiBase {
  TrueNasReportingApi(super.client);

  /// Flipped off the first time the server refuses (or ignores) an explicit
  /// `{start, end}` window, so the narrow live query costs at most one wasted
  /// round-trip per connection and then never runs again.
  bool _windowQuerySupported = true;

  /// Fetches graphs by [names] (e.g. `cpu`, `memory`, `interface`, `disk`).
  /// [identifier] narrows graphs that need one (e.g. an interface name).
  /// [unit]/[page] select a rolling window (`HOUR`, `DAY`, `WEEK`, ...).
  /// [maxPoints] caps how many of the newest samples are mapped per graph.
  Future<List<TrueNasReportingGraph>> getGraphs(
    List<String> names, {
    String? identifier,
    String unit = 'HOUR',
    int page = 0,
    int? maxPoints,
  }) async {
    final query = {'unit': unit, 'page': page < 1 ? 1 : page};
    try {
      return await _fetch(
        names,
        identifier: identifier,
        query: query,
        maxPoints: maxPoints,
      );
    } catch (_) {
      // A single unsupported graph (e.g. one that requires an `identifier`)
      // can make the batched `reporting.get_data` call reject and blank the
      // whole request. Fall back to fetching each graph independently and
      // keep whatever succeeds, so one bad name never hides the rest.
      final out = <TrueNasReportingGraph>[];
      for (final name in names) {
        try {
          out.addAll(
            await _fetch(
              [name],
              identifier: identifier,
              query: query,
              maxPoints: maxPoints,
            ),
          );
        } catch (_) {
          // Skip graphs the server can't satisfy for this request.
        }
      }
      return out;
    }
  }

  /// Fetches the *live* tail of each graph: an explicit `{start, end}` range
  /// covering the last [window], capped at [maxPoints] samples.
  ///
  /// The dashboard polls this every few seconds and only needs the newest
  /// sample (gauges) plus a short trend (sparkline); the rolling `unit` window
  /// has no grain finer than `HOUR`, so asking for one by unit drags a full
  /// hour of every series across the socket and through the parser on every
  /// tick. Servers that don't honour an explicit range fall back to that hourly
  /// window — same data, just more of it — and the attempt is not repeated.
  Future<List<TrueNasReportingGraph>> getLiveGraphs(
    List<String> names, {
    Duration window = const Duration(minutes: 5),
    int maxPoints = 60,
  }) async {
    if (_windowQuerySupported) {
      try {
        final end = DateTime.now();
        final start = end.subtract(window);
        final graphs = await _fetch(
          names,
          query: {
            'start': start.millisecondsSinceEpoch ~/ 1000,
            'end': end.millisecondsSinceEpoch ~/ 1000,
          },
          maxPoints: maxPoints,
        );
        // An accepted-but-empty answer counts as unsupported: some builds
        // ignore the range rather than rejecting it.
        if (graphs.any((g) => g.data.isNotEmpty)) return graphs;
      } catch (_) {
        // Fall through to the rolling window below.
      }
      _windowQuerySupported = false;
    }
    return getGraphs(names, maxPoints: maxPoints);
  }

  Future<List<TrueNasReportingGraph>> _fetch(
    List<String> names, {
    String? identifier,
    required Map<String, Object?> query,
    int? maxPoints,
  }) async {
    final graphs = names
        .map(
          (n) => {'name': n, if (identifier != null) 'identifier': identifier},
        )
        .toList();
    // `reporting.get_data` takes `[graphs, query]` where each graph is
    // `{name, identifier?}`. `query.page` has a server-side minimum of 1 —
    // sending 0 (the previous behaviour) fails validation with "Invalid
    // params". The previously-used `reporting.netdata_graph` is the *singular*
    // variant that expects a single name string, not a list.
    final result = await client.call('reporting.get_data', [graphs, query]);
    if (result is! List) return const [];
    return result
        .whereType<Map>()
        .map(
          (m) => TrueNasReportingGraph.fromJson(
            Map<String, dynamic>.from(m),
            maxPoints: maxPoints,
          ),
        )
        .toList(growable: false);
  }
}
