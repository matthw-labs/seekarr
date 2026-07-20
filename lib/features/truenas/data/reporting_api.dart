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
    final graphs = names
        .map(
          (n) => {'name': n, if (identifier != null) 'identifier': identifier},
        )
        .toList();
    final result = await client.call('reporting.netdata_graph', [
      graphs,
      {'unit': unit, 'page': page},
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
