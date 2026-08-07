import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/activity/presentation/activity_screen.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_item_tiles.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_tab_helpers.dart';
import 'package:cupola/features/activity/presentation/widgets/segment_selector.dart';

class ActivityTab extends ConsumerStatefulWidget {
  final ServiceType serviceType;

  const ActivityTab({super.key, required this.serviceType})
    : assert(
        serviceType != ServiceType.discover,
        'ActivityTab does not support ServiceType.discover.',
      );

  @override
  ConsumerState<ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends ConsumerState<ActivityTab>
    with ActivityTabHelpers {
  ActivitySegment _selectedSegment = ActivitySegment.queue;
  Key _refreshKey = UniqueKey();

  /// The in-flight request, held in state.
  ///
  /// This used to be created inside `build` — `service.getQueue()` as an
  /// argument — so every rebuild started a fresh request and the
  /// `FutureBuilder` fell back to its waiting state. Switching tabs animated the
  /// `TabBarView`, which rebuilt, which re-fetched, which flashed the spinner
  /// back over content that was already on screen.
  late Future<List<dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _items = _load();
  }

  Future<List<dynamic>> _load() {
    final service = ref.read(resolvedArrServiceProvider(widget.serviceType));
    return switch (_selectedSegment) {
      ActivitySegment.queue => service.getQueue(),
      ActivitySegment.history => service.getAllHistory(),
      ActivitySegment.blocklist => service.getBlocklist(),
    };
  }

  void _refresh({ActivitySegment? nextSegment}) {
    setState(() {
      if (nextSegment != null) {
        _selectedSegment = nextSegment;
      }
      _refreshKey = UniqueKey();
      _items = _load();
    });
  }

  Widget _buildContentSliver() {
    return switch (_selectedSegment) {
      ActivitySegment.queue => buildAsyncContentSliver(
        _items,
        (item) => QueueItemTile(
          item: item as Map<String, dynamic>,
          serviceType: widget.serviceType,
        ),
      ),
      ActivitySegment.history => buildAsyncContentSliver(
        _items,
        (item) => HistoryItemTile(
          item: item as Map<String, dynamic>,
          serviceType: widget.serviceType,
        ),
      ),
      ActivitySegment.blocklist => buildAsyncContentSliver(
        _items,
        (item) => BlocklistItemTile(
          item: item as Map<String, dynamic>,
          serviceType: widget.serviceType,
        ),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return buildRefreshableSegmentedView<ActivitySegment>(
      refreshKey: _refreshKey,
      onRefreshRequested: () => _refresh(),
      segments: ActivitySegment.values,
      selected: _selectedSegment,
      onSegmentChanged: (segment) => _refresh(nextSegment: segment),
      labelBuilder: (segment) => segment.label,
      contentSliver: _buildContentSliver(),
    );
  }
}
