import 'package:flutter/material.dart';

import 'package:seekarr/core/app_gradients.dart';

/// Paints the app's ambient background — an opaque base surface with soft accent
/// radial glows — behind [child], full-bleed.
///
/// Because the base is opaque, this can sit directly behind a transparent
/// [Scaffold] (and a transparent/glass app bar) so the gradient reads
/// continuously across the whole screen, including the status-bar and app-bar
/// band. This is what fixes the "app bar breaks the gradient with a flat
/// black/white strip" seam: instead of an opaque scaffold surface showing
/// through the transparent app bar, the gradient shows through.
///
/// Pass [accent] to tint the glow with a per-service colour (e.g. Radarr amber,
/// Sonarr violet); defaults to the brand primary.
class AmbientBackground extends StatelessWidget {
  final Widget child;
  final Color? accent;

  const AmbientBackground({super.key, required this.child, this.accent});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glow = accent ?? scheme.primary;

    return DecoratedBox(
      // Opaque base so nothing behind (page transitions, shell) bleeds through.
      decoration: BoxDecoration(color: scheme.surface),
      child: DecoratedBox(
        // Primary glow anchored top-left.
        decoration: BoxDecoration(
          gradient: AppGradients.ambientBackground(scheme, accent: glow),
        ),
        child: DecoratedBox(
          // Fainter secondary glow bottom-right for depth.
          decoration: BoxDecoration(
            gradient: AppGradients.ambientBackground(
              scheme,
              accent: glow,
              center: const Alignment(0.95, 0.75),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
