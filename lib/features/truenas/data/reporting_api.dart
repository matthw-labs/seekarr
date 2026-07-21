import 'package:seekarr/features/truenas/data/truenas_api_base.dart';
import 'package:seekarr/features/truenas/domain/models/reporting.dart';

/// Reporting graphs from Netdata (`reporting.netdata_graph`).
class TrueNasReportingApi extends TrueNasApiBase {
  const TrueNasReportingApi(super.client);

  /// Fetches graphs by [names] (e.g. `cpu`, `memory`, `interface`, `disk`).
  /// [identifier] narrows graphs that need one (e.g. an interface name).
  /// [unit]/[page] select a rolling window (`HOUR`, `DAY`, `WEEK`, ...).
  Future<List<TrueNasReportingGraph>> getGraphs(
    List<String> names, {
    String? identifier,
    String unit = 'HOUR',
    int page = 0,
  }) async {
    try {
      return await _fetch(
        names,
        identifier: identifier,
        unit: unit,
        page: page,
      );
    } catch (_) {
      // A single unsupported graph (e.g. one that requires an `identifier`)
      // can make the batched `reporting.netdata_graph` call reject and blank
      // the whole request. Fall back to fetching each graph independently and
      // keep whatever succeeds, so one bad name never hides the rest.
      final out = <TrueNasReportingGraph>[];
      for (final name in names) {
        try {
          out.addAll(
            await _fetch(
              [name],
              identifier: identifier,
              unit: unit,
              page: page,
            ),
          );
        } catch (_) {
          // Skip graphs the server can't satisfy for this request.
        }
      }
      return out;
    }
  }

  Future<List<TrueNasReportingGraph>> _fetch(
    List<String> names, {
    String? identifier,
    required String unit,
    required int page,
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
    final result = await client.call('reporting.get_data', [
      graphs,
      {'unit': unit, 'page': page < 1 ? 1 : page},
    ]);
    if (result is! List) return const [];
    return result
        .whereType<Map>()
        .map(
          (m) => TrueNasReportingGraph.fromJson(Map<String, dynamic>.from(m)),
        )
        .toList(growable: false);
  }
}
