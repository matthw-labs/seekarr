import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/providers/navigation_refresh_provider.dart';
import 'package:seekarr/core/widgets/ambient_scaffold.dart';
import 'package:seekarr/core/widgets/app_empty_state.dart';
import 'package:seekarr/core/widgets/app_error_state.dart';
import 'package:seekarr/core/widgets/app_skeleton.dart';
import 'package:seekarr/core/widgets/floating_bottom_nav_bar.dart';
import 'package:seekarr/core/widgets/glass_app_bar.dart';
import 'package:seekarr/core/widgets/section_header.dart';
import 'package:seekarr/features/activity/presentation/activity_provider.dart';
import 'package:seekarr/features/activity/presentation/widgets/activity_item_tiles.dart';
import 'package:seekarr/features/activity/presentation/widgets/activity_tab.dart';
import 'package:seekarr/features/activity/presentation/widgets/requests_list.dart';
import 'package:seekarr/features/activity/presentation/widgets/wanted_tab.dart';
import 'package:seekarr/features/discover/presentation/discover_provider.dart';
import 'package:seekarr/features/import/presentation/import_service_picker_sheet.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

enum ServiceType { movies, series, music, discover }

/// Human-readable display titles for [ServiceType].
extension ServiceTypeDisplay on ServiceType {
  String get displayTitle {
    switch (this) {
      case ServiceType.movies:
        return 'Movies';
      case ServiceType.series:
        return 'Series';
      case ServiceType.music:
        return 'Music';
      case ServiceType.discover:
        return 'Requests';
    }
  }

  bool get supportsArrActivity => this != ServiceType.discover;
}

/// Per-service activity screen (reached from a service's library screen).
class ActivityScreen extends ConsumerWidget {
  final ServiceType serviceType;

  const ActivityScreen({super.key, required this.serviceType});

  Color get _accent => switch (serviceType) {
    ServiceType.movies => ServiceKey.radarr.accent,
    ServiceType.series => ServiceKey.sonarr.accent,
    ServiceType.music => ServiceKey.lidarr.accent,
    ServiceType.discover => ServiceKey.seerr.accent,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!serviceType.supportsArrActivity) {
      return AmbientScaffold(
        accent: _accent,
        appBar: const GlassAppBar(title: Text('Requests')),
        body: const RequestsList(),
      );
    }

    return DefaultTabController(
      length: 2,
      child: AmbientScaffold(
        accent: _accent,
        appBar: GlassAppBar(
          title: Text('${serviceType.displayTitle} Activity'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Activity'),
              Tab(text: 'Wanted'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ActivityTab(serviceType: serviceType),
            WantedTab(serviceType: serviceType),
          ],
        ),
      ),
    );
  }
}

/// The three top-level activity sections. Blocklist/Cutoff live inside the
/// per-service view; the global view keeps to these three clear buckets.
enum _ActivitySection {
  now('Now', Icons.downloading_rounded, 'Nothing downloading right now'),
  history('History', Icons.history_rounded, 'No recent history'),
  wanted('Wanted', Icons.manage_search_rounded, 'Nothing wanted');

  final String label;
  final IconData icon;
  final String emptyMessage;

  const _ActivitySection(this.label, this.icon, this.emptyMessage);
}

final _activitySectionProvider = StateProvider<_ActivitySection>(
  (ref) => _ActivitySection.now,
);

/// Selected service filter; null means "all services".
final _activityServiceFilterProvider = StateProvider<ServiceKey?>(
  (ref) => null,
);

/// Global cross-service activity (the Activity bottom-nav tab): one screen with
/// Now/History/Wanted sections and a per-service filter, grouped by service.
class GlobalActivityScreen extends ConsumerWidget {
  const GlobalActivityScreen({super.key});

  // Services that can appear in the global feed, in display order.
  static const _filterServices = [
    ServiceKey.radarr,
    ServiceKey.sonarr,
    ServiceKey.lidarr,
    ServiceKey.seerr,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomPadding = FloatingNavBarMetrics.getScrollViewBottomPadding(
      context,
    );

    ref.listen<int>(navigationRefreshProvider(NavigationSection.activity), (
      previous,
      next,
    ) {
      ref.invalidate(requestsProvider);
      ref.read(activityRefreshVersionProvider.notifier).state++;
    });

    final section = ref.watch(_activitySectionProvider);
    final filter = ref.watch(_activityServiceFilterProvider);
    final itemsAsync = switch (section) {
      _ActivitySection.now => ref.watch(globalNowItemsProvider),
      _ActivitySection.history => ref.watch(globalHistoryItemsProvider),
      _ActivitySection.wanted => ref.watch(globalWantedItemsProvider),
    };

    return AmbientScaffold(
      appBar: GlassAppBar(
        title: const Text('Activity'),
        actions: [
          IconButton(
            tooltip: 'Manual Import',
            icon: const Icon(Icons.download_for_offline_outlined),
            onPressed: () => showImportServicePickerSheet(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: SegmentedButton<_ActivitySection>(
              segments: [
                for (final s in _ActivitySection.values)
                  ButtonSegment(
                    value: s,
                    label: Text(s.label),
                    icon: Icon(s.icon, size: 18),
                  ),
              ],
              selected: {section},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  ref.read(_activitySectionProvider.notifier).state =
                      selection.first,
            ),
          ),
          _ServiceFilterChips(
            services: _filterServices,
            selected: filter,
            onSelected: (service) =>
                ref.read(_activityServiceFilterProvider.notifier).state =
                    service,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(requestsProvider);
                ref.read(activityRefreshVersionProvider.notifier).state++;
              },
              child: itemsAsync.when(
                loading: () => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  children: [AppSkeleton.listRows(count: 6)],
                ),
                error: (error, _) => _ScrollableState(
                  bottomPadding: bottomPadding,
                  child: AppErrorState(
                    error: error,
                    onRetry: () {
                      ref.invalidate(requestsProvider);
                      ref.read(activityRefreshVersionProvider.notifier).state++;
                    },
                  ),
                ),
                data: (items) => _ActivityData(
                  items: items,
                  section: section,
                  filter: filter,
                  bottomPadding: bottomPadding,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityData extends StatelessWidget {
  final List<GlobalActivityItem> items;
  final _ActivitySection section;
  final ServiceKey? filter;
  final double bottomPadding;

  const _ActivityData({
    required this.items,
    required this.section,
    required this.filter,
    required this.bottomPadding,
  });

  @override
  Widget build(BuildContext context) {
    final visible = filter == null
        ? items
        : items.where((i) => i.service == filter).toList(growable: false);

    if (visible.isEmpty) {
      return _ScrollableState(
        bottomPadding: bottomPadding,
        child: AppEmptyState(
          icon: section.icon,
          title: section.label,
          message: section.emptyMessage,
        ),
      );
    }

    // Flat list when a single service is selected.
    if (filter != null) {
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(top: AppSpacing.md, bottom: bottomPadding),
        itemCount: visible.length,
        itemBuilder: (context, index) =>
            GlobalActivityItemTile(item: visible[index]),
      );
    }

    // Otherwise group by service with an accented section header.
    final grouped = <ServiceKey, List<GlobalActivityItem>>{};
    for (final item in visible) {
      grouped.putIfAbsent(item.service, () => []).add(item);
    }
    final orderedServices = GlobalActivityScreen._filterServices
        .where(grouped.containsKey)
        .toList(growable: false);

    final children = <Widget>[];
    for (final service in orderedServices) {
      final group = grouped[service]!;
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: SectionHeader(
            title: service.title,
            showChevron: false,
            trailing: Text(
              '${group.length}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: service.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      );
      children.addAll(group.map((item) => GlobalActivityItemTile(item: item)));
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: bottomPadding),
      children: children,
    );
  }
}

class _ServiceFilterChips extends StatelessWidget {
  final List<ServiceKey> services;
  final ServiceKey? selected;
  final ValueChanged<ServiceKey?> onSelected;

  const _ServiceFilterChips({
    required this.services,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          _Chip(
            label: 'All',
            selected: selected == null,
            onTap: () => onSelected(null),
          ),
          for (final service in services)
            _Chip(
              label: service.title,
              color: service.accent,
              selected: selected == service,
              onTap: () => onSelected(service),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.onTap,
    this.color,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: selected
                ? effectiveColor
                : effectiveColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: selected ? Colors.white : effectiveColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScrollableState extends StatelessWidget {
  final double bottomPadding;
  final Widget child;

  const _ScrollableState({required this.bottomPadding, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: bottomPadding),
      children: [SizedBox(height: 320, child: child)],
    );
  }
}
