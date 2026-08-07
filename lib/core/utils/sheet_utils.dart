import 'package:flutter/material.dart';

/// Utilities for showing modal bottom sheets that work correctly with the
/// floating navigation bar.
///
/// Problem: Bottom sheets shown within the shell's Navigator are covered by
/// the 80dp floating nav bar because the shell uses `extendBody: true`.
///
/// Solution: This helper uses `useRootNavigator: true` to show sheets above
/// the nav bar at a higher z-index, ensuring they are not obscured.
class SheetUtils {
  SheetUtils._();

  /// Shows a modal bottom sheet that appears above the floating nav bar.
  ///
  /// By using `useRootNavigator: true`, the sheet is rendered in the root
  /// navigator context, placing it above the shell's floating nav bar.
  ///
  /// Usage:
  /// ```dart
  /// SheetUtils.showCupolaModalSheet(
  ///   context: context,
  ///   builder: (context) => MyBottomSheet(),
  /// );
  /// ```
  static Future<T?> showCupolaModalSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isDismissible = true,
    bool enableDrag = true,
    Color? backgroundColor,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      // Use root navigator to show sheet ABOVE the nav bar (higher z-index)
      useRootNavigator: true,
      // Respect system safe areas (status bar, notches, home indicator)
      useSafeArea: true,
      // Allow sheets to use full screen height if needed
      isScrollControlled: true,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      backgroundColor: backgroundColor,
      builder: builder,
    );
  }
}
