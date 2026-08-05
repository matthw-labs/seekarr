import 'package:flutter/material.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';

/// A toggleable option (checkbox) shown inside [showAppConfirmDialog].
class AppConfirmOption {
  final String key;
  final String label;
  final String? subtitle;
  final bool initialValue;

  /// When a checked option is [danger], the dialog surfaces the "cannot be
  /// undone" warning banner and tints the option red.
  final bool danger;

  const AppConfirmOption({
    required this.key,
    required this.label,
    this.subtitle,
    this.initialValue = false,
    this.danger = false,
  });
}

/// Result of [showAppConfirmDialog].
class AppConfirmResult {
  final bool confirmed;
  final Map<String, bool> options;

  const AppConfirmResult({required this.confirmed, this.options = const {}});

  static const cancelled = AppConfirmResult(confirmed: false);

  bool option(String key) => options[key] ?? false;
}

/// One canonical confirmation dialog for the whole app.
///
/// Supports a plain confirm, a [destructive] variant (red confirm button +
/// warning affordance), and optional [options] (checkboxes) — e.g. the
/// "delete files" / "add exclusion" toggles used when removing media.
Future<AppConfirmResult> showAppConfirmDialog({
  required BuildContext context,
  required String title,
  String? message,
  IconData? icon,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
  List<AppConfirmOption> options = const [],
  String dangerNote = 'This cannot be undone.',
  bool useRootNavigator = true,
}) async {
  final values = {for (final o in options) o.key: o.initialValue};

  final result = await showDialog<AppConfirmResult>(
    context: context,
    useRootNavigator: useRootNavigator,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final errorColor = colorScheme.error;
        final headerColor = destructive ? errorColor : colorScheme.onSurface;
        final effectiveIcon =
            icon ?? (destructive ? Icons.warning_amber_rounded : null);
        final anyDangerChecked = options.any(
          (o) => o.danger && (values[o.key] ?? false),
        );
        final showDanger = anyDangerChecked || (destructive && options.isEmpty);

        return AlertDialog(
          title: Row(
            children: [
              if (effectiveIcon != null) ...[
                Icon(effectiveIcon, color: headerColor),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Text(
                  title,
                  // An `AlertDialog` title sits *above* the scrollable content,
                  // so an unbounded one grows the dialog until the buttons
                  // leave the viewport — there is no scroll to reach them by.
                  // Callers still cap the interpolated title; this is the floor
                  // under them.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge!.weight(FontWeight.w700),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message != null && message.isNotEmpty)
                Text(message, style: theme.textTheme.bodyMedium),
              if (options.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                for (final opt in options)
                  CheckboxListTile(
                    value: values[opt.key] ?? false,
                    onChanged: (v) =>
                        setState(() => values[opt.key] = v ?? false),
                    title: Text(
                      opt.label,
                      // Restructured onto the role ListTile would have given
                      // this title anyway: a bare TextStyle has no fontSize to
                      // hang `wght` on, so the bold never reached the face.
                      style: opt.danger && (values[opt.key] ?? false)
                          ? theme.textTheme.bodyLarge!
                                .weight(FontWeight.bold)
                                .copyWith(color: errorColor)
                          : null,
                    ),
                    subtitle: opt.subtitle == null
                        ? null
                        : Text(
                            opt.subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: opt.danger && (values[opt.key] ?? false)
                                  ? errorColor
                                  : null,
                            ),
                          ),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
              ],
              if (showDanger) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: errorColor.withValues(alpha: 0.10),
                    borderRadius: AppRadius.borderRadiusSm,
                    border: Border.all(
                      color: errorColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_rounded, color: errorColor, size: 20),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          dangerNote,
                          // Same restructure: `bodyMedium` is the dialog's own
                          // content role, which this note is an emphasis of.
                          style: theme.textTheme.bodyMedium!
                              .weight(FontWeight.bold)
                              .copyWith(color: errorColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(AppConfirmResult.cancelled),
              child: Text(cancelLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(
                context,
              ).pop(AppConfirmResult(confirmed: true, options: Map.of(values))),
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: errorColor,
                      foregroundColor: colorScheme.onError,
                    )
                  : null,
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    ),
  );

  return result ?? AppConfirmResult.cancelled;
}
