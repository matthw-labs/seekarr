import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/providers/navigation_refresh_provider.dart';
import 'package:seekarr/core/service_theme.dart';
import 'package:seekarr/core/utils/a11y_announce.dart';
import 'package:seekarr/core/widgets/floating_bottom_nav_bar.dart';
import 'package:seekarr/features/import/presentation/manual_import_routes.dart';
import 'package:seekarr/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:seekarr/features/release_search/presentation/release_search_lifecycle.dart';
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

    // Built once, above the layout branch, and handed to whichever navigation
    // this window is wide enough for. The rail used to build its own bare
    // `NavigationRailDestination`s, which is how it ended up as the one surface
    // where a finished search never showed a badge — the channel that has to
    // keep working when notifications are denied, off, or missed.
    final searchesWaiting = ref.watch(unseenReleaseSearchCountProvider);
    final destinations = NavTab.values
        .map((tab) => _destinationFor(tab, searchesWaiting))
        .toList(growable: false);

    // Outside the branch, so it wraps *both* layouts and survives a resize.
    // Inside the phone branch it was two bugs at once: on macOS and tablet
    // nothing ever observed the app lifecycle — `appInForegroundProvider` stayed
    // permanently true, `noteBackgrounded()` never fired (so a search the OS
    // killed was blamed on the network instead of on leaving the app) and
    // `refreshWindows()` never ran on resume — and dragging a window across
    // 840pt mounted or unmounted the observer mid-session.
    return ReleaseSearchLifecycle(
      child: useRail
          ? Scaffold(
              body: Row(
                children: [
                  if (!hideNav)
                    // SafeArea on the rail side only: in landscape the notch and
                    // the rounded corner sit on the leading edge, and the rail
                    // was laid out underneath them. The content keeps its own
                    // insets.
                    SafeArea(
                      right: false,
                      child: _ServicesNavRail(
                        selectedIndex: selectedIndex,
                        destinations: destinations,
                        onDestinationSelected: (int idx) =>
                            _onItemTapped(idx, context, ref, selectedIndex),
                      ),
                    ),
                  Expanded(child: child),
                ],
              ),
            )
          : Scaffold(
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
        // A re-tap refresh changes nothing on screen — no spinner, no route
        // change, no focus move — so for a screen-reader user it is otherwise
        // indistinguishable from a no-op. Start only: the shell never learns
        // when the invalidated providers settle, so there is no completion to
        // announce.
        announce(context, 'Refreshing ${tab.label}');
      }
      return;
    }

    // Not announced: switching tabs replaces the whole screen, which is its own
    // feedback.
    context.go(tab.routePath);
  }

  FloatingNavDestination _destinationFor(NavTab tab, int searchesWaiting) {
    // Only Activity carries a count, and only for finished searches nobody has
    // opened — the channel that has to keep working when notifications are
    // denied, off, or missed.
    final badge = tab == NavTab.activity ? searchesWaiting : 0;
    return FloatingNavDestination(
      icon: tab.icon,
      selectedIcon: tab.selectedIcon,
      label: tab.label,
      accentColor: tab.accentColor,
      badgeCount: badge,
      badgeSemanticLabel: badge == 0
          ? null
          : '$badge finished search${badge == 1 ? '' : 'es'} to look at',
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

/// Side navigation shown on tablet and desktop widths.
///
/// Takes the *same* [FloatingNavDestination] list the bottom bar does rather
/// than rebuilding one from [NavTab]. That is the whole point: badge counts and
/// their spoken labels are set in one place, so a desktop window cannot end up
/// as the one form factor where a finished search is never announced.
class _ServicesNavRail extends StatelessWidget {
  const _ServicesNavRail({
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final List<FloatingNavDestination> destinations;
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
        for (final destination in destinations)
          NavigationRailDestination(
            icon: _RailBadgedIcon(
              destination: destination,
              icon: destination.icon,
            ),
            selectedIcon: _RailBadgedIcon(
              destination: destination,
              icon: destination.selectedIcon,
            ),
            // The count joins the *spoken* label the way the bottom bar does it:
            // a number painted on an icon is invisible to a screen reader, and
            // the badge itself is excluded so it is not then read twice.
            label: Text(
              destination.label,
              semanticsLabel: destination.badgeSemanticLabel == null
                  ? null
                  : '${destination.label}, ${destination.badgeSemanticLabel}',
            ),
          ),
      ],
    );
  }
}

/// A rail icon carrying its destination's count, in the destination's own
/// accent — never a status tone, for the reason
/// [FloatingNavDestination.badgeCount] documents.
class _RailBadgedIcon extends StatelessWidget {
  const _RailBadgedIcon({required this.destination, required this.icon});

  final FloatingNavDestination destination;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (destination.badgeCount <= 0) return Icon(icon);
    return ExcludeSemantics(
      child: Badge.count(
        count: destination.badgeCount,
        backgroundColor: destination.accentColor,
        textColor: ServiceTheme.foregroundOn(destination.accentColor),
        child: Icon(icon),
      ),
    );
  }
}
