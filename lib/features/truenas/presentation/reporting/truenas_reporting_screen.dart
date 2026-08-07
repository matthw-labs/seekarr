import 'package:flutter/material.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/features/truenas/domain/models/reporting.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';
import 'package:cupola/features/truenas/presentation/widgets/charts/line_area_chart.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_section_scaffold.dart';

/// Reporting graphs to show, in order.
///
/// Limited to graphs that don't require a per-device `identifier`. `load` and
/// `disk` (which need an identifier per disk) were making the batched
/// `reporting.netdata_graph` call reject and spin forever; the reporting API
/// now also degrades gracefully per-graph as a safety net.
const _graphNames = ['cpu', 'memory', 'interface'];

const _seriesPalette = [
  AppColors.truenas,
  AppColors.info,
  AppColors.warning,
  AppColors.success,
  AppColors.lidarr,
  AppColors.sonarr,
];

typedef _GraphQuery = ({String unit});

final _reportingProvider = FutureProvider.autoDispose
    .family<List<TrueNasReportingGraph>, _GraphQuery>((ref, query) async {
      ref.watch(truenasClientProvider);
      return ref
          .watch(truenasReportingApiProvider)
          .getGraphs(_graphNames, unit: query.unit);
    });

class TrueNasReportingScreen extends ConsumerStatefulWidget {
  const TrueNasReportingScreen({super.key});

  @override
  ConsumerState<TrueNasReportingScreen> createState() =>
      _TrueNasReportingScreenState();
}

class _TrueNasReportingScreenState
    extends ConsumerState<TrueNasReportingScreen> {
  String _unit = 'HOUR';

  static const _units = {
    'HOUR': '1H',
    'DAY': '1D',
    'WEEK': '1W',
    'MONTH': '1M',
  };

  @override
  Widget build(BuildContext context) {
    final query = (unit: _unit);
    final graphs = ref.watch(_reportingProvider(query));

    return TrueNasSectionScaffold(
      title: 'Reporting',
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_reportingProvider(query)),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          children: [
            Center(
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  for (final entry in _units.entries)
                    ButtonSegment(value: entry.key, label: Text(entry.value)),
                ],
                selected: {_unit},
                onSelectionChanged: (value) =>
                    setState(() => _unit = value.first),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            graphs.when(
              loading: () => AppSkeleton.listRows(count: 4),
              error: (e, _) => AppErrorState(
                error: e,
                onRetry: () => ref.invalidate(_reportingProvider(query)),
              ),
              data: (list) => list.isEmpty
                  ? AppCard.surfaceOutlined(
                      child: Text(
                        'No reporting data available.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  : Column(
                      children: [
                        for (final graph in list) _GraphCard(graph: graph),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GraphCard extends StatelessWidget {
  final TrueNasReportingGraph graph;
  const _GraphCard({required this.graph});

  @override
  Widget build(BuildContext context) {
    final labels = graph.seriesLabels;
    final series = <ChartSeries>[];
    for (var i = 0; i < labels.length; i++) {
      final points = graph
          .series(i)
          .map((p) => Offset(p.t, p.v ?? 0))
          .toList(growable: false);
      series.add(
        ChartSeries(
          label: labels[i],
          color: _seriesPalette[i % _seriesPalette.length],
          points: points,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard.surfaceOutlined(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              graph.name.toUpperCase(),
              style: Theme.of(
                context,
              ).textTheme.labelMedium!.weight(FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            LineAreaChart(series: series),
          ],
        ),
      ),
    );
  }
}
