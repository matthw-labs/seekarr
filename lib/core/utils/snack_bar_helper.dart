import 'package:flutter/material.dart';

/// Convenience helpers for showing semantically typed snackbars.
///
/// The app theme already configures shared snackbar styling in `core/theme.dart`.
/// These helpers keep call sites small and centralize semantic variants.
///
/// Usage:
/// ```dart
/// SnackBarHelper.success(context, 'Settings saved');
/// SnackBarHelper.info(context, 'Coming soon!');
/// SnackBarHelper.error(context, "Couldn't delete this movie from Radarr.", detail: e);
/// ```
class SnackBarHelper {
  SnackBarHelper._();

  /// Strips the `Exception: ` prefix Dart's own `toString()` adds and trims,
  /// so a thrown `Exception('404 Not Found')` demotes to `404 Not Found`
  /// rather than shouting its own type at the user.
  ///
  /// Returns `null` when nothing legible survives, which is the signal to show
  /// the human sentence alone rather than a blank second line.
  static String? _demote(Object? detail) {
    if (detail == null) return null;
    final text = detail
        .toString()
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .trim();
    return text.isEmpty ? null : text;
  }

  /// Composes a human sentence with an optional demoted diagnostic line.
  ///
  /// One message, two registers: the first line says what failed in words the
  /// user can act on, the second carries whatever the service actually said.
  /// The diagnostic never replaces the sentence — a raw `DioException` is not
  /// an explanation — and it is dropped entirely when it is empty, so the
  /// snackbar never grows a blank row.
  static String _compose(String message, Object? detail) {
    final demoted = _demote(detail);
    return demoted == null ? message : '$message\n$demoted';
  }

  /// Shows an informational snackbar with the default themed appearance.
  static void info(BuildContext context, String message, {Object? detail}) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_compose(message, detail))));
  }

  /// Shows a success snackbar using the default themed appearance.
  static void success(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Shows an error snackbar with the theme error background color.
  ///
  /// Pass the caught object as [detail] rather than interpolating it into
  /// [message]: `'Search failed: $e'` puts a stack-trace fragment where a
  /// sentence belongs, while `error(context, "Couldn't start a search in
  /// Radarr.", detail: e)` leads with what the user needs and demotes the
  /// diagnostic to its own line — the same two-register shape `AppErrorState`
  /// uses.
  static void error(BuildContext context, String message, {Object? detail}) {
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_compose(message, detail)),
        backgroundColor: colorScheme.error,
      ),
    );
  }
}
