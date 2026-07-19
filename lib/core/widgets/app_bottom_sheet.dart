import 'package:flutter/material.dart';

import 'package:seekarr/core/app_elevation.dart';
import 'package:seekarr/core/app_gradients.dart';
import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/utils/sheet_utils.dart';

/// Canonical drag handle for Seekarr bottom sheets (36×4, subtle).
class AppSheetHandle extends StatelessWidget {
  const AppSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
          borderRadius: AppRadius.borderRadiusFull,
        ),
      ),
    );
  }
}

/// Shared sheet header: optional accent icon tile, title + subtitle, and an
/// optional trailing widget / close button.
class AppSheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? accent;
  final Widget? trailing;
  final bool showClose;

  const AppSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.accent,
    this.trailing,
    this.showClose = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accentColor = accent ?? colorScheme.primary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: AppRadius.borderRadiusMd,
            ),
            child: Icon(icon, size: 20, color: accentColor),
          ),
          const SizedBox(width: AppSpacing.md),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
        if (showClose)
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

/// Premium bottom-sheet container used across the app.
///
/// Provides one canonical chrome: drag handle, optional [AppSheetHeader],
/// top radius [AppRadius.lg], [AppElevation.level3], an optional service-accent
/// glow behind the header, safe-area handling and keyboard avoidance.
///
/// Use [AppBottomSheet.show] for min-content forms/pickers, or
/// [AppBottomSheet.showScrollable] for large, drag-to-resize lists.
class AppBottomSheet extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final Color? accent;
  final Widget? headerTrailing;
  final bool showClose;
  final bool showHandle;

  /// The sheet body. For draggable sheets this is provided a [ScrollController]
  /// via [showScrollable]; for min-content sheets it is scrolled internally.
  final Widget child;
  final EdgeInsetsGeometry bodyPadding;

  /// When set, the body is wrapped in [Expanded] + a scroll view driven by this
  /// controller (draggable mode). When null, the sheet is min-content.
  final ScrollController? scrollController;

  const AppBottomSheet({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.icon,
    this.accent,
    this.headerTrailing,
    this.showClose = false,
    this.showHandle = true,
    this.bodyPadding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      0,
      AppSpacing.lg,
      AppSpacing.lg,
    ),
    this.scrollController,
  });

  bool get _hasHeader => title != null && title!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final draggable = scrollController != null;

    final header = _hasHeader
        ? Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              showHandle ? 0 : AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: AppSheetHeader(
              title: title!,
              subtitle: subtitle,
              icon: icon,
              accent: accent,
              trailing: headerTrailing,
              showClose: showClose,
            ),
          )
        : null;

    // Draggable mode: [child] is already a scrollable wired to
    // [scrollController]; just give it the remaining space. Min-content mode:
    // scroll [child] internally so it can't overflow with the keyboard open.
    final Widget body = draggable
        ? Expanded(child: child)
        : Flexible(
            child: SingleChildScrollView(padding: bodyPadding, child: child),
          );

    final column = Column(
      mainAxisSize: draggable ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (showHandle) const AppSheetHandle(),
        if (header != null) header,
        body,
      ],
    );

    final content = draggable
        ? column
        : ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.92,
            ),
            child: column,
          );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
          boxShadow: AppElevation.level3(colorScheme),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
          child: Stack(
            children: [
              if (accent != null)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 140,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppGradients.serviceGlow(
                          accent!,
                          center: Alignment.topCenter,
                          radius: 1.1,
                        ),
                      ),
                    ),
                  ),
                ),
              SafeArea(top: false, child: content),
            ],
          ),
        ),
      ),
    );
  }

  /// Shows a min-content bottom sheet (forms, pickers). The [builder] result is
  /// scrolled internally so it can never overflow with the keyboard open.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    String? title,
    String? subtitle,
    IconData? icon,
    Color? accent,
    Widget? headerTrailing,
    bool showClose = false,
    bool showHandle = true,
    bool isDismissible = true,
    bool enableDrag = true,
    EdgeInsetsGeometry? bodyPadding,
  }) {
    return SheetUtils.showSeekarrModalSheet<T>(
      context: context,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      backgroundColor: Colors.transparent,
      builder: (context) => AppBottomSheet(
        title: title,
        subtitle: subtitle,
        icon: icon,
        accent: accent,
        headerTrailing: headerTrailing,
        showClose: showClose,
        showHandle: showHandle,
        bodyPadding:
            bodyPadding ??
            const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
        child: Builder(builder: builder),
      ),
    );
  }

  /// Shows a large, drag-to-resize sheet. [builder] receives a
  /// [ScrollController] which MUST be attached to the returned scrollable for
  /// drag-to-expand to work.
  static Future<T?> showScrollable<T>({
    required BuildContext context,
    required Widget Function(BuildContext context, ScrollController controller)
    builder,
    String? title,
    String? subtitle,
    IconData? icon,
    Color? accent,
    Widget? headerTrailing,
    bool showClose = false,
    double initialSize = 0.6,
    double minSize = 0.4,
    double maxSize = 0.95,
    bool isDismissible = true,
    bool enableDrag = true,
    EdgeInsetsGeometry? bodyPadding,
  }) {
    return SheetUtils.showSeekarrModalSheet<T>(
      context: context,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: initialSize,
        minChildSize: minSize,
        maxChildSize: maxSize,
        expand: false,
        builder: (context, scrollController) => AppBottomSheet(
          title: title,
          subtitle: subtitle,
          icon: icon,
          accent: accent,
          headerTrailing: headerTrailing,
          showClose: showClose,
          scrollController: scrollController,
          bodyPadding: bodyPadding ?? EdgeInsets.zero,
          child: builder(context, scrollController),
        ),
      ),
    );
  }
}
