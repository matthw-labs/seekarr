import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/route_utils.dart';
import 'package:seekarr/core/utils/service_routes.dart';
import 'package:seekarr/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:seekarr/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:seekarr/features/prowlarr/presentation/widgets/prowlarr_indexer_tile.dart';
import 'package:seekarr/features/prowlarr/presentation/widgets/prowlarr_list_shimmer.dart';

enum _ProtocolFilter { all, torrent, usenet }

enum _StatusFilter { all, enabled, disabled }

class ProwlarrLibraryScreen extends ConsumerStatefulWidget {
  const ProwlarrLibraryScreen({super.key});

  @override
  ConsumerState<ProwlarrLibraryScreen> createState() =>
      _ProwlarrLibraryScreenState();
}

class _ProwlarrLibraryScreenState extends ConsumerState<ProwlarrLibraryScreen> {
  _ProtocolFilter _protocol = _ProtocolFilter.all;
  _StatusFilter _status = _StatusFilter.all;

  bool _matches(ProwlarrIndexer indexer) {
    final protocolOk = switch (_protocol) {
      _ProtocolFilter.all => true,
      _ProtocolFilter.torrent =>
        (indexer.protocol ?? '').toLowerCase() == 'torrent',
      _ProtocolFilter.usenet =>
        (indexer.protocol ?? '').toLowerCase() == 'usenet',
    };
    final statusOk = switch (_status) {
      _StatusFilter.all => true,
      _StatusFilter.enabled => indexer.enable,
      _StatusFilter.disabled => !indexer.enable,
    };
    return protocolOk && statusOk;
  }

  @override
  Widget build(BuildContext context) {
    final indexersAsync = ref.watch(prowlarrIndexersProvider);
    final statusAsync = ref.watch(prowlarrIndexerStatusProvider);
    final disabledIds = statusAsync.maybeWhen(
      data: (statuses) => statuses.map((s) => s.indexerId).toSet(),
      orElse: () => const <int>{},
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.prowlarr.withValues(alpha: 0.12),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () => RouteUtils.popOrGo(context, ServiceRoutes.prowlarr),
          tooltip: 'Back',
        ),
        title: const Text('Indexers'),
      ),
      body: Column(
        children: [
          _FilterBar(
            protocol: _protocol,
            status: _status,
            onProtocol: (value) => setState(() => _protocol = value),
            onStatus: (value) => setState(() => _status = value),
          ),
          Expanded(
            child: indexersAsync.when(
              data: (indexers) {
                final filtered = indexers.where(_matches).toList()
                  ..sort(
                    (a, b) => (a.name ?? '').toLowerCase().compareTo(
                      (b.name ?? '').toLowerCase(),
                    ),
                  );
                if (filtered.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No indexers match the current filters.'),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(prowlarrIndexersProvider);
                    ref.invalidate(prowlarrIndexerStatusProvider);
                    await Future<void>.delayed(
                      const Duration(milliseconds: 300),
                    );
                  },
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final indexer = filtered[index];
                      return ProwlarrIndexerTile(
                        indexer: indexer,
                        failing: disabledIds.contains(indexer.id),
                        onTap: () => context.push(
                          ServiceRoutes.prowlarrIndexer(indexer.id),
                        ),
                      );
                    },
                  ),
                );
              },
              loading: () =>
                  const ProwlarrListShimmer(count: 6, verticalPadding: 8),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Failed to load indexers'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () =>
                            ref.invalidate(prowlarrIndexersProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.protocol,
    required this.status,
    required this.onProtocol,
    required this.onStatus,
  });

  final _ProtocolFilter protocol;
  final _StatusFilter status;
  final ValueChanged<_ProtocolFilter> onProtocol;
  final ValueChanged<_StatusFilter> onStatus;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _FilterChip(
            label: 'All',
            selected: protocol == _ProtocolFilter.all,
            onTap: () => onProtocol(_ProtocolFilter.all),
          ),
          _FilterChip(
            label: 'Torrent',
            selected: protocol == _ProtocolFilter.torrent,
            onTap: () => onProtocol(_ProtocolFilter.torrent),
          ),
          _FilterChip(
            label: 'Usenet',
            selected: protocol == _ProtocolFilter.usenet,
            onTap: () => onProtocol(_ProtocolFilter.usenet),
          ),
          const _FilterDivider(),
          _FilterChip(
            label: 'Enabled',
            selected: status == _StatusFilter.enabled,
            onTap: () => onStatus(
              status == _StatusFilter.enabled
                  ? _StatusFilter.all
                  : _StatusFilter.enabled,
            ),
          ),
          _FilterChip(
            label: 'Disabled',
            selected: status == _StatusFilter.disabled,
            onTap: () => onStatus(
              status == _StatusFilter.disabled
                  ? _StatusFilter.all
                  : _StatusFilter.disabled,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterDivider extends StatelessWidget {
  const _FilterDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected
            ? AppColors.prowlarr.withValues(alpha: 0.15)
            : colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.borderRadiusSm,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.borderRadiusSm,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: AppRadius.borderRadiusSm,
              border: Border.all(
                color: selected
                    ? AppColors.prowlarr.withValues(alpha: 0.5)
                    : Colors.transparent,
              ),
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium!
                  .weight(FontWeight.w700)
                  .copyWith(
                    color: selected
                        ? AppColors.prowlarr
                        : colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
