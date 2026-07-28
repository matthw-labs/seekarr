import 'package:flutter/material.dart' show Color, IconData, Icons;

import 'package:seekarr/core/theme.dart';

/// The four canonical tabs.
///
/// Accents are the app's own indigo throughout. They used to vary per tab —
/// Activity borrowed the Radarr amber while its content is Seerr-indigo, and
/// Settings used `onSurfaceVariantDark`, a dark-mode token that rendered the
/// selected pill as washed-out grey in light mode and read as disabled. The
/// per-service accents belong to service surfaces; the app shell is one colour.
enum NavTab {
  services(
    label: 'Services',
    icon: Icons.view_list_outlined,
    selectedIcon: Icons.view_list_rounded,
    routePath: '/services',
    accentColor: AppColors.primary,
  ),
  activity(
    label: 'Activity',
    icon: Icons.monitor_heart_outlined,
    selectedIcon: Icons.monitor_heart_rounded,
    routePath: '/activity',
    accentColor: AppColors.primary,
  ),
  search(
    label: 'Search',
    icon: Icons.search_outlined,
    selectedIcon: Icons.search_rounded,
    routePath: '/search',
    accentColor: AppColors.primary,
  ),
  settings(
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    routePath: '/settings',
    accentColor: AppColors.primary,
  );

  const NavTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.routePath,
    required this.accentColor,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String routePath;
  final Color accentColor;

  static final Map<String, NavTab> _tabsByName = {
    for (final tab in values) tab.name: tab,
  };

  static NavTab? fromName(String name) => _tabsByName[name];
}
