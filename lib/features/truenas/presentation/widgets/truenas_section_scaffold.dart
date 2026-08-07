import 'package:flutter/material.dart';

import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_version_banner.dart';

/// Standard chrome for a pushed TrueNAS section/detail screen: ambient
/// background, a glass app bar with back navigation, and an optional
/// min-version warning banner above the body.
class TrueNasSectionScaffold extends StatelessWidget {
  final String title;
  final List<Widget>? actions;
  final Widget body;
  final Widget? floatingActionButton;
  final bool showVersionBanner;
  final PreferredSizeWidget? appBarBottom;

  const TrueNasSectionScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.showVersionBanner = true,
    this.appBarBottom,
  });

  @override
  Widget build(BuildContext context) {
    // These section screens are pushed *inside* the app shell, so the floating
    // bottom nav bar overlays them. The body's own scroll view is responsible
    // for reserving bottom space (via
    // `FloatingNavBarMetrics.getScrollViewBottomPadding`) so content scrolls
    // *under* the translucent bar — exactly like the TrueNAS hub. Here we only
    // lift the FAB so it can't be hidden behind the bar.
    return AmbientScaffold(
      accent: ServiceKey.truenas.accent,
      appBar: GlassAppBar(
        title: Text(title),
        actions: actions,
        bottom: appBarBottom,
      ),
      floatingActionButton: floatingActionButton == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(
                bottom: FloatingNavBarMetrics.totalHeight,
              ),
              child: floatingActionButton,
            ),
      body: Column(
        children: [
          if (showVersionBanner) const TrueNasVersionBanner(),
          Expanded(child: body),
        ],
      ),
    );
  }
}
