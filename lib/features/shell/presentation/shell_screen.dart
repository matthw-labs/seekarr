import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/providers/navigation_refresh_provider.dart';
import 'package:seekarr/core/widgets/floating_bottom_nav_bar.dart';
import 'package:seekarr/features/import/presentation/manual_import_routes.dart';
import 'package:seekarr/features/settings/domain/nav_tab.dart';

/// Main shell screen with floating bottom navigation.
///
/// Uses a custom [FloatingBottomNavBar] with rounded corners and floating design.
/// Outlined icons for unselected state and filled icons for selected state.
class ShellScreen extends ConsumerWidget {
  final Widget child;

  const ShellScreen({super.key, required this.child});

  /// Width at or above which navigation moves from a bottom bar to a side rail.
  ///
  /// 840 rather than 600: at 600 a phone in landscape (roughly 850pt wide on a
  /// modern iPhone) also got the rail, replacing the thumb-reachable bottom bar
  /// with a side rail on a device held in two hands. 840 is Material's
  /// expanded-window breakpoint and keeps phones on the bar in both
  /// orientations, while tablets and desktop windows still get the rail.
  static const double _railBreakpoint = 840;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hideNav = _isImportRoute(context);
    final selectedIndex = hideNav ? -1 : _calculateSelectedIndex(context);
    final useRail = MediaQuery.sizeOf(context).width >= _railBreakpoint;

    if (useRail) {
      return Scaffold(
        body: Row(
          children: [
            if (!hideNav)
              // SafeArea on the rail side only: in landscape the notch and the
              // rounded corner sit on the leading edge, and the rail was laid
              // out underneath them. The content keeps its own insets.
              SafeArea(
                right: false,
                child: _ServicesNavRail(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (int idx) =>
                      _onItemTapped(idx, context, ref, selectedIndex),
                ),
              ),
            Expanded(child: child),
          ],
        ),
      );
    }

    final destinations = NavTab.values
        .map(_destinationFor)
        .toList(growable: false);

    return Scaffold(
      extendBody: !hideNav,
      body: child,
      bottomNavigationBar: hideNav
          ? null
          : FloatingBottomNavBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: (int idx) =>
                  _onItemTapped(idx, context, ref, selectedIndex),
              destinations: destinations,
            ),
    );
  }

  static bool _isImportRoute(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    return location.startsWith(manualImportPathPrefix);
  }

  static int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;

    for (var index = 0; index < NavTab.values.length; index++) {
      final tab = NavTab.values[index];
      if (location.startsWith(tab.routePath)) {
        return index;
      }
    }

    return -1;
  }

  void _onItemTapped(
    int index,
    BuildContext context,
    WidgetRef ref,
    int currentIndex,
  ) {
    HapticFeedback.selectionClick();

    final tab = NavTab.values[index];
    final currentPath = GoRouterState.of(context).uri.path;

    if (index == currentIndex && currentPath == tab.routePath) {
      final section = _refreshSectionFor(tab);
      if (section != null) {
        ref.triggerNavigationRefresh(section);
      }
      return;
    }

    context.go(tab.routePath);
  }

  FloatingNavDestination _destinationFor(NavTab tab) {
    return FloatingNavDestination(
      icon: tab.icon,
      selectedIcon: tab.selectedIcon,
      label: tab.label,
      accentColor: tab.accentColor,
    );
  }

  NavigationSection? _refreshSectionFor(NavTab tab) {
    switch (tab) {
      case NavTab.services:
        return NavigationSection.services;
      case NavTab.activity:
        return NavigationSection.activity;
      case NavTab.search:
        return NavigationSection.search;
      case NavTab.settings:
        return null;
    }
  }
}

/// Side navigation shown on tablet and desktop widths. Mirrors the bottom bar's
/// destinations so the information architecture is identical across form
/// factors — only the presentation adapts.
class _ServicesNavRail extends StatelessWidget {
  const _ServicesNavRail({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return NavigationRail(
      selectedIndex: selectedIndex >= 0 ? selectedIndex : null,
      onDestinationSelected: onDestinationSelected,
      labelType: NavigationRailLabelType.all,
      backgroundColor: colorScheme.surfaceContainerLow,
      indicatorColor: colorScheme.secondaryContainer,
      destinations: [
        for (final tab in NavTab.values)
          NavigationRailDestination(
            icon: Icon(tab.icon),
            selectedIcon: Icon(tab.selectedIcon),
            label: Text(tab.label),
          ),
      ],
    );
  }
}
