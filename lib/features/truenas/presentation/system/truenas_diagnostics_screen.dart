import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:seekarr/core/widgets/floating_bottom_nav_bar.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/snack_bar_helper.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/features/truenas/presentation/truenas_provider.dart';
import 'package:seekarr/features/truenas/presentation/widgets/truenas_section_scaffold.dart';

/// A raw JSON-RPC probe: a human label plus the method + params to send.
class _Probe {
  final String label;
  final String method;
  final List<dynamic> params;
  const _Probe(this.label, this.method, this.params);
}

const _probes = <_Probe>[
  // The now-correct call: batch `reporting.get_data` with page >= 1. Shows the
  // real cpu/memory legend + data so parsing can be confirmed.
  _Probe('reporting.get_data — cpu + memory (page 1)', 'reporting.get_data', [
    [
      {'name': 'cpu'},
      {'name': 'memory'},
    ],
    {'unit': 'HOUR', 'page': 1},
  ]),
];

/// A temporary, debug-only screen that fires a handful of raw JSON-RPC calls
/// against the connected TrueNAS server and shows their responses verbatim, so
/// their exact shape can be copied and inspected. Used to finalise the
/// CPU/memory parsing, the missing-VM list, and the reporting graphs.
class TrueNasDiagnosticsScreen extends ConsumerStatefulWidget {
  const TrueNasDiagnosticsScreen({super.key});

  @override
  ConsumerState<TrueNasDiagnosticsScreen> createState() =>
      _TrueNasDiagnosticsScreenState();
}

class _TrueNasDiagnosticsScreenState
    extends ConsumerState<TrueNasDiagnosticsScreen> {
  late Future<List<_ProbeResult>> _future;

  @override
  void initState() {
    super.initState();
    _future = _run();
  }

  Future<List<_ProbeResult>> _run() async {
    final client = ref.read(truenasClientProvider);
    final results = <_ProbeResult>[];

    // The authoritative answer: the exact accepted parameter schema for the
    // reporting methods, straight from the middleware's own introspection.
    const schemaProbe = _Probe(
      'reporting.* method schemas',
      'core.get_methods',
      [],
    );
    try {
      final methods = await client.call('core.get_methods');
      if (methods is Map) {
        final reporting = <String, dynamic>{};
        methods.forEach((key, value) {
          if (key is String &&
              key.startsWith('reporting') &&
              (key.contains('data') || key.contains('graph'))) {
            reporting[key] = value;
          }
        });
        results.add(_ProbeResult(schemaProbe, _pretty(reporting), false));
      } else {
        results.add(_ProbeResult(schemaProbe, _pretty(methods), false));
      }
    } catch (e) {
      results.add(_ProbeResult(schemaProbe, e.toString(), true));
    }

    for (final probe in _probes) {
      try {
        final raw = await client.call(probe.method, probe.params);
        results.add(_ProbeResult(probe, _pretty(raw), false));
      } catch (e) {
        results.add(_ProbeResult(probe, e.toString(), true));
      }
    }
    return results;
  }

  static String _pretty(dynamic value) {
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value.toString();
    }
  }

  void _refresh() => setState(() => _future = _run());

  @override
  Widget build(BuildContext context) {
    return TrueNasSectionScaffold(
      title: 'Diagnostics',
      showVersionBanner: false,
      actions: [
        IconButton(
          tooltip: 'Re-run',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _refresh,
        ),
      ],
      body: FutureBuilder<List<_ProbeResult>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final results = snapshot.data ?? const [];
          return ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              FloatingNavBarMetrics.getScrollViewBottomPadding(context),
            ),
            children: [
              Text(
                'Debug-only: raw JSON-RPC responses from the connected server. '
                'Copy these to help finalise parsing.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final result in results)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _ProbeCard(result: result),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ProbeResult {
  final _Probe probe;
  final String output;
  final bool isError;
  const _ProbeResult(this.probe, this.output, this.isError);
}

class _ProbeCard extends StatelessWidget {
  final _ProbeResult result;
  const _ProbeCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard.surfaceOutlined(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                size: 16,
                color: result.isError
                    ? theme.colorScheme.error
                    : AppColors.success,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  result.probe.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy_rounded, size: 16),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: result.output));
                  SnackBarHelper.success(
                    context,
                    'Copied ${result.probe.method}',
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 320),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                result.output,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
