import 'package:flutter/material.dart';

import 'package:cupola/core/widgets/app_dialog.dart';

/// Result from the delete confirmation dialog.
class DeleteMediaResult {
  final bool confirmed;
  final bool deleteFiles;
  final bool addExclusion;

  const DeleteMediaResult({
    required this.confirmed,
    this.deleteFiles = false,
    this.addExclusion = false,
  });

  static const cancelled = DeleteMediaResult(confirmed: false);
}

enum DeleteMediaType {
  movie(label: 'movie', serviceName: 'Radarr'),
  series(label: 'series', serviceName: 'Sonarr'),
  artist(label: 'artist', serviceName: 'Lidarr');

  const DeleteMediaType({required this.label, required this.serviceName});

  final String label;
  final String serviceName;
}

/// Shows a confirmation dialog for deleting media with optional checkboxes.
///
/// Built on the shared [showAppConfirmDialog] so the destructive affordance
/// (red confirm, "delete files" warning banner) matches every other dialog.
Future<DeleteMediaResult> showDeleteMediaDialog({
  required BuildContext context,
  required String title,
  required DeleteMediaType mediaType,
}) async {
  final result = await showAppConfirmDialog(
    context: context,
    title: 'Delete $title?',
    message:
        'This will remove this ${mediaType.label} from ${mediaType.serviceName}.',
    destructive: true,
    confirmLabel: 'Delete',
    options: [
      AppConfirmOption(
        key: 'exclusion',
        label: 'Add list exclusion',
        subtitle:
            'Prevent this ${mediaType.label} from being re-added by lists',
      ),
      const AppConfirmOption(
        key: 'deleteFiles',
        label: 'Delete files',
        subtitle: 'Permanently delete downloaded files from disk',
        danger: true,
      ),
    ],
  );

  if (!result.confirmed) return DeleteMediaResult.cancelled;
  return DeleteMediaResult(
    confirmed: true,
    deleteFiles: result.option('deleteFiles'),
    addExclusion: result.option('exclusion'),
  );
}
