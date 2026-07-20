import 'package:flutter/material.dart';

/// A near-transparent app-bar surface that lets the page's ambient gradient
/// read continuously behind it — no opaque strip and no hairline border that
/// would visually "cut" the gradient.
///
/// Instead of a flat translucent fill it paints a soft top-anchored scrim that
/// fades to fully transparent: just enough tint under the status bar / title to
/// keep icons and text legible where list content scrolls beneath, while the
/// lower edge blends seamlessly into the background.
///
/// Deliberately does NOT use a [BackdropFilter] blur — a real backdrop blur
/// re-rasterises everything behind it every frame, which visibly janks scroll
/// on screens whose content scrolls under the app bar. The gradient scrim gives
/// the same legibility protection at zero per-frame cost.
class GlassSurface extends StatelessWidget {
  final Widget? child;

  const GlassSurface({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final scrim = colorScheme.surface;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scrim.withValues(alpha: isDark ? 0.55 : 0.6),
            scrim.withValues(alpha: isDark ? 0.28 : 0.32),
            scrim.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: child,
    );
  }
}

/// A transparent [AppBar] with a [GlassSurface] behind it. Drop-in replacement
/// for `AppBar` on screens that sit over an [AmbientBackground], so the app bar
/// frosts the gradient/content instead of painting an opaque strip over it.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool centerTitle;
  final PreferredSizeWidget? bottom;
  final double toolbarHeight;
  final bool automaticallyImplyLeading;

  const GlassAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.centerTitle = false,
    this.bottom,
    this.toolbarHeight = kToolbarHeight,
    this.automaticallyImplyLeading = true,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(toolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      title: title,
      leading: leading,
      actions: actions,
      centerTitle: centerTitle,
      bottom: bottom,
      toolbarHeight: toolbarHeight,
      automaticallyImplyLeading: automaticallyImplyLeading,
      flexibleSpace: const GlassSurface(),
    );
  }
}
