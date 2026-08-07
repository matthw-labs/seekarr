import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/features/truenas/domain/models/dataset.dart';
import 'package:cupola/features/truenas/presentation/datasets/truenas_dataset_providers.dart';
import 'package:cupola/features/truenas/presentation/truenas_actions.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_form_sheet.dart';

/// Creates a dataset. With [parentId], asks for a child name and creates
/// `parentId/child`; without it, asks for a full `pool/dataset` path.
Future<void> createDatasetFlow(
  BuildContext context,
  WidgetRef ref, {
  required String? parentId,
}) async {
  final values = await showTrueNasFormSheet(
    context: context,
    title: parentId == null ? 'New dataset' : 'New child dataset',
    subtitle: parentId,
    submitLabel: 'Create',
    fields: [
      TrueNasFormField(
        key: 'name',
        label: parentId == null ? 'Full name (pool/dataset)' : 'Name',
        required: true,
        hint: parentId == null ? 'tank/media' : 'documents',
      ),
      const TrueNasFormField(key: 'comments', label: 'Comment (optional)'),
    ],
  );
  if (values == null || !context.mounted) return;

  final rawName = values['name'] as String;
  final fullName = parentId == null ? rawName : '$parentId/$rawName';
  final payload = <String, dynamic>{
    'name': fullName,
    'type': 'FILESYSTEM',
    if (values['comments'] != null) 'comments': values['comments'],
  };

  await runTrueNasAction(
    context,
    ref,
    action: () => ref.read(truenasDatasetApiProvider).createDataset(payload),
    successMessage: 'Created $fullName',
    failureMessage: 'Could not create dataset',
    invalidate: [truenasDatasetTreeProvider],
  );
}

/// Edits mutable properties (comment, quota, compression) of a dataset.
Future<void> editDatasetFlow(
  BuildContext context,
  WidgetRef ref,
  TrueNasDataset dataset,
) async {
  final values = await showTrueNasFormSheet(
    context: context,
    title: 'Edit ${dataset.shortName}',
    submitLabel: 'Save',
    fields: [
      TrueNasFormField(
        key: 'comments',
        label: 'Comment',
        initialValue: dataset.comments,
      ),
      TrueNasFormField(
        key: 'compression',
        label: 'Compression (e.g. LZ4, ZSTD, OFF)',
        initialValue: dataset.compression,
      ),
    ],
  );
  if (values == null || !context.mounted) return;

  final patch = <String, dynamic>{};
  if (values['comments'] != null) patch['comments'] = values['comments'];
  final compression = values['compression'] as String?;
  if (compression != null) patch['compression'] = compression.toUpperCase();
  if (patch.isEmpty) return;

  await runTrueNasAction(
    context,
    ref,
    action: () =>
        ref.read(truenasDatasetApiProvider).updateDataset(dataset.id, patch),
    successMessage: 'Updated ${dataset.shortName}',
    failureMessage: 'Could not update dataset',
    invalidate: [
      truenasDatasetTreeProvider,
      truenasDatasetProvider(dataset.id),
    ],
  );
}

/// Deletes a dataset after confirmation. Returns true if deleted.
Future<bool> deleteDatasetFlow(
  BuildContext context,
  WidgetRef ref,
  TrueNasDataset dataset,
) async {
  final result = await showAppConfirmDialog(
    context: context,
    title: 'Delete ${dataset.shortName}?',
    message:
        'This permanently destroys "${dataset.id}" and all its data. '
        'This cannot be undone.',
    confirmLabel: 'Delete',
    destructive: true,
    dangerNote: dataset.children.isNotEmpty
        ? 'This dataset has children that will also be destroyed.'
        : 'This cannot be undone.',
    options: dataset.children.isNotEmpty
        ? const [
            AppConfirmOption(
              key: 'recursive',
              label: 'Delete child datasets recursively',
              danger: true,
            ),
          ]
        : const [],
  );
  if (!result.confirmed || !context.mounted) return false;

  return runTrueNasAction(
    context,
    ref,
    action: () => ref
        .read(truenasDatasetApiProvider)
        .deleteDataset(dataset.id, recursive: result.option('recursive')),
    successMessage: 'Deleted ${dataset.shortName}',
    failureMessage: 'Could not delete dataset',
    invalidate: [truenasDatasetTreeProvider],
  );
}

Future<void> createSnapshotFlow(
  BuildContext context,
  WidgetRef ref,
  String dataset,
) async {
  final values = await showTrueNasFormSheet(
    context: context,
    title: 'New snapshot',
    subtitle: dataset,
    submitLabel: 'Create',
    fields: [
      const TrueNasFormField(
        key: 'name',
        label: 'Snapshot name',
        required: true,
        hint: 'manual-2025-01-01',
      ),
      const TrueNasFormField(
        key: 'recursive',
        label: 'Recursive',
        boolField: true,
      ),
    ],
  );
  if (values == null || !context.mounted) return;

  await runTrueNasAction(
    context,
    ref,
    action: () => ref
        .read(truenasDatasetApiProvider)
        .createSnapshot(
          dataset,
          values['name'] as String,
          recursive: values['recursive'] == true,
        ),
    successMessage: 'Snapshot created',
    failureMessage: 'Could not create snapshot',
    invalidate: [truenasSnapshotsProvider(dataset)],
  );
}
