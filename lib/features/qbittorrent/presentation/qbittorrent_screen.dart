import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/widgets/ambient_scaffold.dart';
import 'package:seekarr/core/widgets/async_value_widget.dart';
import 'package:seekarr/core/widgets/search_bar_header.dart';
import 'package:seekarr/features/qbittorrent/domain/models/torrent.dart';
import 'package:seekarr/features/qbittorrent/domain/models/transfer_info.dart';
import 'package:seekarr/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:seekarr/features/qbittorrent/presentation/widgets/speed_stats_bar.dart';
import 'package:seekarr/features/qbittorrent/presentation/widgets/torrent_list_controls.dart';
import 'package:seekarr/features/qbittorrent/presentation/widgets/torrent_selection_bar.dart';
import 'package:seekarr/features/qbittorrent/presentation/widgets/torrent_tile.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

class QbittorrentScreen extends ConsumerStatefulWidget {
  final bool showAppBar;
  final double topPadding;
  final VoidCallback? onAddTorrent;

  const QbittorrentScreen({
    super.key,
    this.showAppBar = true,
    this.topPadding = 0,
    this.onAddTorrent,
  });

  @override
  ConsumerState<QbittorrentScreen> createState() => _QbittorrentScreenState();
}

class _QbittorrentScreenState extends ConsumerState<QbittorrentScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause polling while the app is in the background to save battery and
    // avoid hammering the qBittorrent WebUI when the user can't see it.
    final enabled = state == AppLifecycleState.resumed;
    if (ref.read(torrentPollingEnabledProvider) != enabled) {
      ref.read(torrentPollingEnabledProvider.notifier).state = enabled;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(torrentPollingProvider);
    final torrentsAsync = ref.watch(torrentsProvider);
    final selectedHashes = ref.watch(selectedTorrentHashesProvider);

    return AmbientScaffold(
      accent: ServiceKey.qbittorrent.accent,
      body: Column(
        children: [
          if (widget.topPadding > 0)
            SizedBox(
              height: widget.topPadding + MediaQuery.paddingOf(context).top,
            ),
          _buildStatsBar(),
          SearchBarHeader(
            hintText: 'Search torrents...',
            onQueryChanged: (query) {
              ref.read(torrentSearchQueryProvider.notifier).state = query;
            },
          ),
          const TorrentFilterChipsRow(),
          const TorrentFilterPillsRow(),
          const TorrentSortRow(),
          Expanded(
            child: _buildTorrentList(context, torrentsAsync, selectedHashes),
          ),
          TorrentSelectionBar(
            onConfirmDelete: () =>
                confirmDeleteTorrents(context, ref, selectedHashes),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    final transferAsync = ref.watch(transferInfoProvider);
    final torrentsAsync = ref.watch(torrentsProvider);

    TransferInfo? info;
    transferAsync.whenOrNull(data: (d) => info = d);

    int total = 0;
    int active = 0;
    torrentsAsync.whenOrNull(
      data: (list) {
        total = list.length;
        active = list.where((t) => t.parsedState.isActive).length;
      },
    );

    return SpeedStatsBar(info: info, torrentCount: total, activeCount: active);
  }

  Widget _buildTorrentList(
    BuildContext context,
    AsyncValue<List<Torrent>> torrentsAsync,
    Set<String> selectedHashes,
  ) {
    return AsyncValueWidget<List<Torrent>>(
      value: torrentsAsync,
      serviceName: 'qBittorrent',
      data: (torrents) {
        if (torrents.isEmpty) {
          return _EmptyTorrents(colorScheme: Theme.of(context).colorScheme);
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(allTorrentsProvider);
            ref.invalidate(torrentsProvider);
            ref.invalidate(transferInfoProvider);
          },
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 4, bottom: 80),
            itemCount: torrents.length,
            itemBuilder: (context, index) {
              final torrent = torrents[index];
              return TorrentTile(
                torrent: torrent,
                selected: selectedHashes.contains(torrent.hash),
                onTap: () {
                  if (selectedHashes.isNotEmpty) {
                    _toggleSelection(ref, torrent.hash);
                  } else {
                    context.push(
                      '/services/qbittorrent/torrent/${torrent.hash}',
                    );
                  }
                },
                onLongPress: () => _toggleSelection(ref, torrent.hash),
              );
            },
          ),
        );
      },
    );
  }

  void _toggleSelection(WidgetRef ref, String hash) {
    final notifier = ref.read(selectedTorrentHashesProvider.notifier);
    final current = Set<String>.from(notifier.state);
    if (current.contains(hash)) {
      current.remove(hash);
    } else {
      current.add(hash);
    }
    notifier.state = current;
  }
}

class _EmptyTorrents extends StatelessWidget {
  final ColorScheme colorScheme;

  const _EmptyTorrents({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 48,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'No torrents',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
