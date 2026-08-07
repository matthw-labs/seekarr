import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/features/truenas/domain/models/reporting.dart';
import 'package:seekarr/features/truenas/presentation/dashboard/truenas_dashboard_screen.dart';

TrueNasReportingGraph _graph(
  String name,
  List<String> legend,
  List<List<double?>> data,
) => TrueNasReportingGraph(name: name, legend: legend, data: data);

void main() {
  group('TrueNasDashboardMetrics.cpuUsage', () {
    test('is null when the chart carries no idle dimension', () {
      // netdata's `system.cpu` is a stacked percentage that *excludes* idle.
      // The old `(total - idle) / total` then reduced to total/total, so a
      // completely idle box read a confident 100% — and because that is not
      // null, the load-per-core fallback never got to run.
      final metrics = TrueNasDashboardMetrics(
        cpu: _graph(
          'cpu',
          ['time', 'user', 'system', 'iowait'],
          [
            [1770000000, 1.5, 0.5, 0],
          ],
        ),
      );

      expect(metrics.cpuUsage, isNull);
    });

    test('is the busy share when an idle dimension is present', () {
      final metrics = TrueNasDashboardMetrics(
        cpu: _graph(
          'cpu',
          ['time', 'user', 'system', 'idle'],
          [
            [1770000000, 20, 5, 75],
          ],
        ),
      );

      expect(metrics.cpuUsage, closeTo(0.25, 1e-9));
    });

    test('reads the newest sample, not the first', () {
      final metrics = TrueNasDashboardMetrics(
        cpu: _graph(
          'cpu',
          ['time', 'busy', 'idle'],
          [
            [1770000000, 10, 90],
            [1770000001, 40, 60],
          ],
        ),
      );

      expect(metrics.cpuUsage, closeTo(0.4, 1e-9));
    });

    test('is null with no graph and with no samples', () {
      expect(const TrueNasDashboardMetrics().cpuUsage, isNull);
      expect(
        TrueNasDashboardMetrics(
          cpu: _graph('cpu', ['time', 'idle'], const []),
        ).cpuUsage,
        isNull,
      );
    });
  });

  group('TrueNasDashboardMetrics.memoryUsage', () {
    test('is null when no dimension is labelled used', () {
      // Mirror of the CPU bug: the old arithmetic answered a confident 0%.
      final metrics = TrueNasDashboardMetrics(
        memory: _graph(
          'memory',
          ['time', 'free', 'cached', 'buffers'],
          [
            [1770000000, 4, 2, 1],
          ],
        ),
      );

      expect(metrics.memoryUsage, isNull);
    });

    test('is the used share when the dimension exists', () {
      final metrics = TrueNasDashboardMetrics(
        memory: _graph(
          'memory',
          ['time', 'used', 'free'],
          [
            [1770000000, 3, 1],
          ],
        ),
      );

      expect(metrics.memoryUsage, closeTo(0.75, 1e-9));
    });
  });
}
