import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/truenas/data/reporting_api.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';
import 'package:cupola/features/truenas/domain/models/reporting.dart';

/// A [TrueNasWsClient] that answers `reporting.get_data` from [handler] and
/// records the query object each call carried.
class _FakeClient extends TrueNasWsClient {
  _FakeClient(this.handler) : super(baseUrl: 'https://nas.local', apiKey: 'k');

  final dynamic Function(Map<String, Object?> query) handler;
  final List<Map<String, Object?>> queries = [];

  @override
  Future<dynamic> call(String method, [List<dynamic> params = const []]) async {
    expect(method, 'reporting.get_data');
    final query = Map<String, Object?>.from(params[1] as Map);
    queries.add(query);
    return handler(query);
  }
}

/// A graph payload with [rows] samples of a single series.
Map<String, dynamic> _graph(String name, int rows) => {
  'name': name,
  'legend': ['time', 'received'],
  'data': [
    for (var i = 0; i < rows; i++) [1770000000 + i, i.toDouble()],
  ],
};

void main() {
  group('TrueNasReportingGraph.fromJson', () {
    test('keeps only the newest maxPoints rows', () {
      final graph = TrueNasReportingGraph.fromJson(
        _graph('interface', 500),
        maxPoints: 3,
      );

      expect(graph.data, hasLength(3));
      // The *newest* samples, not the oldest: the gauges read `data.last`.
      expect(graph.data.first[1], 497);
      expect(graph.data.last[1], 499);
    });

    test('keeps every row when no cap is given', () {
      final graph = TrueNasReportingGraph.fromJson(_graph('cpu', 42));
      expect(graph.data, hasLength(42));
    });

    test('tolerates a cap larger than the payload', () {
      final graph = TrueNasReportingGraph.fromJson(
        _graph('cpu', 2),
        maxPoints: 60,
      );
      expect(graph.data, hasLength(2));
    });
  });

  group('TrueNasReportingApi.getLiveGraphs', () {
    test('asks for an explicit recent range instead of a whole hour', () async {
      final client = _FakeClient((_) => [_graph('cpu', 500)]);
      final graphs = await TrueNasReportingApi(client).getLiveGraphs(
        ['cpu'],
        window: const Duration(minutes: 5),
        maxPoints: 10,
      );

      final query = client.queries.single;
      expect(query.containsKey('unit'), isFalse);
      final start = query['start']! as int;
      final end = query['end']! as int;
      expect(end - start, 300);
      // The hour-wide window is what made this expensive; only the tail of the
      // answer is ever mapped.
      expect(graphs.single.data, hasLength(10));
    });

    test(
      'falls back to the rolling window when the range is rejected',
      () async {
        var rangeCalls = 0;
        final client = _FakeClient((query) {
          if (query.containsKey('start')) {
            rangeCalls++;
            throw const TrueNasException('Invalid params');
          }
          return [_graph('cpu', 4)];
        });
        final api = TrueNasReportingApi(client);

        final first = await api.getLiveGraphs(['cpu']);
        expect(first.single.data, hasLength(4));
        expect(client.queries.last['unit'], 'HOUR');

        // The probe is not repeated: one wasted round-trip per connection, not
        // one per poll tick.
        await api.getLiveGraphs(['cpu']);
        expect(rangeCalls, 1);
      },
    );

    test('treats an accepted-but-empty range answer as unsupported', () async {
      final client = _FakeClient((query) {
        if (query.containsKey('start')) return [_graph('cpu', 0)];
        return [_graph('cpu', 3)];
      });

      final graphs = await TrueNasReportingApi(client).getLiveGraphs(['cpu']);

      expect(graphs.single.data, hasLength(3));
      expect(client.queries.last['unit'], 'HOUR');
    });
  });

  group('TrueNasReportingApi.getGraphs', () {
    test('sends the rolling unit window with a page floor of 1', () async {
      final client = _FakeClient((_) => [_graph('cpu', 1)]);
      await TrueNasReportingApi(client).getGraphs(['cpu'], unit: 'DAY');

      expect(client.queries.single, {'unit': 'DAY', 'page': 1});
    });

    test('retries graph by graph when the batch is rejected', () async {
      // One graph that needs an `identifier` can make the batched call reject
      // and blank the whole request; the per-name retry keeps the rest.
      var calls = 0;
      final client = _FakeClient((_) {
        calls++;
        if (calls == 1) throw const TrueNasException('bad graph');
        return [_graph('cpu', 1)];
      });
      final graphs = await TrueNasReportingApi(
        client,
      ).getGraphs(['cpu', 'disk']);

      expect(calls, 3); // batch + one per name
      expect(graphs, hasLength(2));
    });
  });
}
