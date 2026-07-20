import 'package:flutter/material.dart';

import 'package:seekarr/core/widgets/ambient_scaffold.dart';
import 'package:seekarr/core/widgets/glass_app_bar.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/truenas/presentation/widgets/truenas_version_banner.dart';

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
    return AmbientScaffold(
      accent: ServiceKey.truenas.accent,
      appBar: GlassAppBar(
        title: Text(title),
        actions: actions,
        bottom: appBarBottom,
      ),
      floatingActionButton: floatingActionButton,
      body: Column(
        children: [
          if (showVersionBanner) const TrueNasVersionBanner(),
          Expanded(child: body),
        ],
      ),
    );
  }
}
