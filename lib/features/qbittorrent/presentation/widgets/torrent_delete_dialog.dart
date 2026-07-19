import 'package:flutter/material.dart';

import 'package:seekarr/core/widgets/app_dialog.dart';

/// Result returned by [showTorrentDeleteDialog].
class TorrentDeleteResult {
  final bool confirmed;
  final bool deleteFiles;

  const TorrentDeleteResult({
    required this.confirmed,
    required this.deleteFiles,
  });

  static const cancelled = TorrentDeleteResult(
    confirmed: false,
    deleteFiles: false,
  );
}

/// Shows a confirmation dialog for deleting one or more torrents with a
/// warning banner when "Delete files" is selected. Returns
/// [TorrentDeleteResult.cancelled] when the user dismisses the dialog.
///
/// Built on the shared [showAppConfirmDialog] for a consistent destructive
/// affordance across the app.
Future<TorrentDeleteResult> showTorrentDeleteDialog({
  required BuildContext context,
  required String title,
  required String message,
  bool multi = false,
}) async {
  final result = await showAppConfirmDialog(
    context: context,
    title: title,
    message: message,
    destructive: true,
    confirmLabel: 'Delete',
    dangerNote: multi
        ? 'This cannot be undone! All selected torrents and their files will be permanently removed.'
        : 'This cannot be undone! Files will be permanently removed from disk.',
    options: const [
      AppConfirmOption(
        key: 'deleteFiles',
        label: 'Delete files',
        subtitle: 'Permanently delete downloaded files from disk',
        danger: true,
      ),
    ],
  );

  if (!result.confirmed) return TorrentDeleteResult.cancelled;
  return TorrentDeleteResult(
    confirmed: true,
    deleteFiles: result.option('deleteFiles'),
  );
}
