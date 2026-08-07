import 'dart:async';

import 'package:flutter/material.dart';
import 'package:seekarr/core/widgets/floating_bottom_nav_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/app_error_state.dart';
import 'package:seekarr/core/widgets/app_skeleton.dart';
import 'package:seekarr/core/widgets/section_header.dart';
import 'package:seekarr/features/qbittorrent/domain/models/parse_utils.dart';
import 'package:seekarr/features/truenas/domain/models/truenas_models.dart';
import 'package:seekarr/features/truenas/presentation/truenas_actions.dart';
import 'package:seekarr/features/truenas/presentation/truenas_provider.dart';
import 'package:seekarr/features/truenas/presentation/widgets/charts/radial_gauge.dart';
import 'package:seekarr/features/truenas/presentation/widgets/charts/sparkline.dart';
import 'package:seekarr/features/truenas/presentation/widgets/truenas_info_row.dart';
import 'package:seekarr/features/truenas/presentation/widgets/truenas_section_scaffold.dart';

/// Live metrics for the dashboard: the CPU/memory gauges and the network
/// sparkline, all derived from the newest reporting samples.
class TrueNasDashboardMetrics {
  final TrueNasReportingGraph? cpu;
  final TrueNasReportingGraph? memory;
  final TrueNasReportingGraph? network;

  /// The network sparkline series, derived once per fetch. Deriving it in the
  /// widget re-walked every sample on every rebuild — and the dashboard
  /// rebuilds on a timer.
  final List<double> networkSeries;

  const TrueNasDashboardMetrics({
    this.cpu,
    this.memory,
    this.network,
    this.networkSeries = const [],
  });

  /// CPU busy fraction from the last sample: `(total - idle) / total`, where
  /// `total` is the sum of all CPU-state series. Unit-independent.
  double? get cpuUsage => _busyFraction(cpu, idleLabel: 'idle');

  /// Memory used fraction from the last sample: `used / sum(all series)`.
  double? get memoryUsage => _fractionOf(memory, matching: 'used');

  static double? _busyFraction(
    TrueNasReportingGraph? g, {
    required String idleLabel,
  }) {
    final idle = _fractionOf(g, matching: idleLabel);
    return idle == null ? null : (1 - idle).clamp(0, 1).toDouble();
  }

  /// Fraction of the newest sample carried by the series whose label contains
  /// [matching], or null when **no** series matches.
  ///
  /// Answering null rather than a number is the whole point. Netdata's
  /// `system.cpu` chart is a stacked percentage that *excludes* idle, so with
  /// no `idle` dimension the old arithmetic returned `total/total` — a flat
  /// 100% CPU on a completely idle box, and non-null, so the load-per-core
  /// fallback never got a chance to run. The memory side had the mirror bug:
  /// no `used` dimension meant `0/total`, a confident 0%. A metric we cannot
  /// compute has to say so.
  static double? _fractionOf(
    TrueNasReportingGraph? g, {
    required String matching,
  }) {
    if (g == null || g.data.isEmpty) return null;
    final last = g.data.last;
    final labels = g.seriesLabels;
    double total = 0;
    double matched = 0;
    var sawMatch = false;
    for (var i = 0; i < labels.length; i++) {
      final v = (i + 1) < last.length ? (last[i + 1] ?? 0) : 0;
      total += v;
      if (labels[i].toLowerCase().contains(matching)) {
        matched += v;
        sawMatch = true;
      }
    }
    if (!sawMatch || total <= 0) return null;
    return (matched / total).clamp(0, 1).toDouble();
  }
}

/// Network interfaces. Split off the live metrics because addresses change on
/// a human timescale, not a 3-second one — this rides the slow refresh tick.
final truenasDashboardInterfacesProvider = FutureProvider.autoDispose((
  ref,
) async {
  ref.watch(truenasClientProvider);
  return ref.watch(truenasNetworkApiProvider).getInterfaces();
});

/// Fetches the reporting graphs behind the gauges and the sparkline.
///
/// Best-effort: if the whole call fails, or an individual graph is missing,
/// the affected metric degrades to null rather than failing the section.
final truenasDashboardMetricsProvider =
    FutureProvider.autoDispose<TrueNasDashboardMetrics>((ref) async {
      ref.watch(truenasClientProvider);
      final reporting = ref.watch(truenasReportingApiProvider);

      // One WS round-trip for all three graphs, over the shortest window that
      // still feeds a sparkline — the gauges only ever read the last sample.
      List<TrueNasReportingGraph> graphs;
      try {
        graphs = await reporting.getLiveGraphs(['cpu', 'memory', 'interface']);
      } catch (_) {
        graphs = const [];
      }

      TrueNasReportingGraph? byName(String name) {
        for (final g in graphs) {
          if (g.name.toLowerCase() == name) return g;
        }
        return null;
      }

      final network = byName('interface');
      return TrueNasDashboardMetrics(
        cpu: byName('cpu'),
        memory: byName('memory'),
        network: network,
        networkSeries: (network == null || network.seriesLabels.isEmpty)
            ? const []
            : network.series(0).map((p) => p.v ?? 0).toList(growable: false),
      );
    });

class TrueNasDashboardScreen extends ConsumerStatefulWidget {
  const TrueNasDashboardScreen({super.key});

  @override
  ConsumerState<TrueNasDashboardScreen> createState() =>
      _TrueNasDashboardScreenState();
}

class _TrueNasDashboardScreenState extends ConsumerState<TrueNasDashboardScreen>
    with WidgetsBindingObserver {
  Timer? _timer;

  /// Fast cadence for live metrics (CPU / memory / network).
  static const _liveInterval = Duration(seconds: 3);

  /// The heavier system/pools/alerts snapshot — and the interface list, which
  /// changes on a human timescale — refresh every [_slowEvery] live ticks
  /// (~15s) so they stay fresh without hammering the server.
  static const _slowEvery = 5;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause live polling while the app is backgrounded to save battery and
    // avoid needless WebSocket traffic.
    if (state == AppLifecycleState.resumed) {
      _startTimer();
    } else {
      _timer?.cancel();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_liveInterval, (_) {
      ref.invalidate(truenasDashboardMetricsProvider);
      _tick++;
      if (_tick % _slowEvery == 0) {
        ref.invalidate(truenasDashboardProvider);
        ref.invalidate(truenasDashboardInterfacesProvider);
      }
    });
  }

  void _refresh() {
    ref.invalidate(truenasDashboardProvider);
    ref.invalidate(truenasDashboardMetricsProvider);
    ref.invalidate(truenasDashboardInterfacesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(truenasDashboardProvider);

    return TrueNasSectionScaffold(
      title: 'Dashboard',
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: dashboard.when(
          skipLoadingOnReload: true,
          loading: () => ListView(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            children: [AppSkeleton.listRows()],
          ),
          error: (error, _) => ListView(
            children: [AppErrorState(error: error, onRetry: () => _refresh())],
          ),
          data: (data) => _DashboardBody(data: data),
        ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  final TrueNasDashboard data;
  const _DashboardBody({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(truenasDashboardMetricsProvider);
    final system = data.system;
    final alerts = data.activeAlerts;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        FloatingNavBarMetrics.getScrollViewBottomPadding(context),
      ),
      children: [
        // System summary.
        AppCard.surfaceOutlined(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TrueNasInfoRow(label: 'Hostname', value: system.hostname),
              TrueNasInfoRow(label: 'Version', value: system.version),
              TrueNasInfoRow(
                label: 'Uptime',
                value: system.uptimeSeconds != null
                    ? formatDuration(system.uptimeSeconds!)
                    : null,
              ),
              TrueNasInfoRow(
                label: 'CPU cores',
                value: system.cores?.toString(),
              ),
              TrueNasInfoRow(
                label: 'Total memory',
                value: system.physmemBytes != null
                    ? formatSize(system.physmemBytes!)
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // CPU + memory gauges.
        Row(
          children: [
            Expanded(
              child: _CpuCard(system: system, metrics: metrics),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _MemoryCard(system: system, metrics: metrics),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        const SectionHeader(title: 'Network', showChevron: false),
        const SizedBox(height: AppSpacing.sm),
        _NetworkCard(
          metrics: metrics,
          interfaces: ref.watch(truenasDashboardInterfacesProvider),
        ),
        const SizedBox(height: AppSpacing.md),

        const SectionHeader(title: 'Pool health', showChevron: false),
        const SizedBox(height: AppSpacing.sm),
        _PoolHealthCard(pools: data.pools),
        const SizedBox(height: AppSpacing.md),

        SectionHeader(
          title: 'Alerts${alerts.isEmpty ? '' : ' (${alerts.length})'}',
          showChevron: false,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (alerts.isEmpty)
          AppCard.surfaceOutlined(
            child: Text(
              'No active alerts. 🎉',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          for (final alert in alerts)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _AlertCard(alert: alert),
            ),
      ],
    );
  }
}

class _CpuCard extends StatelessWidget {
  final TrueNasSystemInfo system;
  final AsyncValue<TrueNasDashboardMetrics> metrics;

  const _CpuCard({required this.system, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final usage = metrics.value?.cpuUsage;
    final cores = system.cores ?? 1;
    final load = system.loadAvg1m;
    // Prefer measured CPU %, fall back to a load-per-core proxy.
    final fraction =
        usage ?? (load != null ? (load / cores).clamp(0, 1).toDouble() : null);
    final label = usage != null
        ? '${(usage * 100).round()}%'
        : (load != null ? load.toStringAsFixed(2) : '—');

    return AppCard.surfaceOutlined(
      child: Column(
        children: [
          RadialGauge(
            value: fraction ?? 0,
            valueLabel: label,
            caption: usage != null ? 'CPU' : 'load 1m',
            color: AppColors.truenas,
            size: 108,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('CPU', style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  final TrueNasSystemInfo system;
  final AsyncValue<TrueNasDashboardMetrics> metrics;

  const _MemoryCard({required this.system, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final usage = metrics.value?.memoryUsage;
    final total = system.physmemBytes;
    final label = usage != null ? '${(usage * 100).round()}%' : '—';
    final caption = (usage != null && total != null)
        ? formatSize((usage * total).round())
        : (total != null ? formatSize(total) : 'memory');

    return AppCard.surfaceOutlined(
      child: Column(
        children: [
          RadialGauge(
            value: usage ?? 0,
            valueLabel: label,
            caption: caption,
            color: AppColors.info,
            size: 108,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('Memory', style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _NetworkCard extends StatelessWidget {
  final AsyncValue<TrueNasDashboardMetrics> metrics;
  final AsyncValue<List<TrueNasInterface>> interfaces;
  const _NetworkCard({required this.metrics, required this.interfaces});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return interfaces.when(
      skipLoadingOnReload: true,
      loading: () => AppSkeleton.listRows(count: 2),
      error: (_, __) => AppCard.surfaceOutlined(
        child: Text(
          'Network data unavailable',
          style: theme.textTheme.bodySmall,
        ),
      ),
      data: (list) {
        final upInterfaces = list.where((i) => i.addresses.isNotEmpty);
        // Already derived once per fetch by the provider.
        final series = metrics.value?.networkSeries ?? const <double>[];
        return AppCard.surfaceOutlined(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (series.isNotEmpty) ...[
                Sparkline(values: series, color: AppColors.truenas),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (upInterfaces.isEmpty)
                Text('No active interfaces', style: theme.textTheme.bodySmall)
              else
                for (final iface in upInterfaces)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          iface.isUp ? Icons.circle : Icons.circle_outlined,
                          size: 8,
                          color: iface.isUp
                              ? AppColors.success
                              : theme.colorScheme.outline,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          iface.name,
                          style: theme.textTheme.bodyMedium!.weight(
                            FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Flexible(
                          child: Text(
                            iface.addresses.join(', '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.end,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _PoolHealthCard extends StatelessWidget {
  final List<TrueNasPool> pools;
  const _PoolHealthCard({required this.pools});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (pools.isEmpty) {
      return AppCard.surfaceOutlined(
        child: Text('No pools reported.', style: theme.textTheme.bodySmall),
      );
    }
    return AppCard.surfaceOutlined(
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final pool in pools)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color:
                    (pool.healthy ? AppColors.success : theme.colorScheme.error)
                        .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    pool.healthy
                        ? Icons.check_circle_rounded
                        : Icons.error_rounded,
                    size: 14,
                    color: pool.healthy
                        ? AppColors.success
                        : theme.colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    pool.name,
                    style: theme.textTheme.labelMedium!.weight(FontWeight.w700),
                  ),
                  if (pool.usedFraction != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${(pool.usedFraction! * 100).round()}%',
                      style: theme.textTheme.labelSmall!.tabular.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AlertCard extends ConsumerWidget {
  final TrueNasAlert alert;
  const _AlertCard({required this.alert});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final level = alert.level.toUpperCase();
    final color = (level == 'CRITICAL' || level == 'ERROR')
        ? colorScheme.error
        : (level == 'WARNING')
        ? AppColors.warning
        : AppColors.truenas;

    return AppCard.surfaceOutlined(
      borderColor: color.withValues(alpha: 0.4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(alert.message, style: theme.textTheme.bodySmall),
          ),
          const SizedBox(width: AppSpacing.sm),
          TextButton(
            onPressed: () => runTrueNasAction(
              context,
              ref,
              action: () =>
                  ref.read(truenasSystemApiProvider).dismissAlert(alert.id),
              successMessage: 'Alert dismissed',
              failureMessage: 'Could not dismiss alert',
              invalidate: [truenasDashboardProvider],
            ),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }
}
