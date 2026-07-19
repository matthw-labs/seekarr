import 'package:flutter/material.dart';

/// A translucent "glass" surface: a translucent fill (so the ambient gradient
/// reads through) plus a hairline bottom border.
///
/// Deliberately does NOT use a [BackdropFilter] blur — a real backdrop blur
/// re-rasterises everything behind it every frame, which visibly janks scroll
/// on screens whose content scrolls under the app bar. The translucent fill
/// gives a frosted look at zero per-frame cost. It is kept fairly opaque so the
/// title/icons stay legible even where list content scrolls beneath it.
class GlassSurface extends StatelessWidget {
  final Widget? child;
  final bool bottomBorder;

  const GlassSurface({super.key, this.child, this.bottomBorder = true});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final glass = colorScheme.surface.withValues(alpha: isDark ? 0.82 : 0.86);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: glass,
        border: bottomBorder
            ? Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: 0.5,
                ),
              )
            : null,
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
