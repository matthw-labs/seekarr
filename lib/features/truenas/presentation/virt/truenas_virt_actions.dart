import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/utils/dynamic_map_utils.dart';
import 'package:seekarr/features/truenas/presentation/truenas_actions.dart';
import 'package:seekarr/features/truenas/presentation/truenas_provider.dart';
import 'package:seekarr/features/truenas/presentation/virt/truenas_virt_providers.dart';
import 'package:seekarr/features/truenas/presentation/widgets/truenas_form_sheet.dart';

/// Creates a new Incus instance (container or VM). This is a best-effort
/// minimal create — the server validates the full payload and surfaces any
/// missing requirements via the error snackbar.
Future<void> createInstanceFlow(
  BuildContext context,
  WidgetRef ref, {
  required String type,
}) async {
  final isVm = type.toUpperCase() == 'VM';
  final values = await showTrueNasFormSheet(
    context: context,
    title: isVm ? 'New VM' : 'New container',
    submitLabel: 'Create',
    fields: [
      const TrueNasFormField(key: 'name', label: 'Name', required: true),
      TrueNasFormField(
        key: 'image',
        label: 'Image',
        required: true,
        hint: isVm ? 'ubuntu/24.04' : 'alpine/edge',
      ),
      const TrueNasFormField(
        key: 'cpu',
        label: 'vCPUs',
        keyboardType: TextInputType.number,
      ),
      const TrueNasFormField(
        key: 'memory',
        label: 'Memory (MiB)',
        keyboardType: TextInputType.number,
      ),
    ],
  );
  if (values == null || !context.mounted) return;

  final cpu = intOrNull(values['cpu']);
  final memoryMib = intOrNull(values['memory']);
  final payload = <String, dynamic>{
    'name': values['name'],
    'instance_type': type.toUpperCase(),
    'source_type': 'IMAGE',
    'image': values['image'],
    if (cpu != null) 'cpu': '$cpu',
    if (memoryMib != null) 'memory': memoryMib * 1024 * 1024,
  };

  await runTrueNasAction(
    context,
    ref,
    action: () => ref.read(truenasVirtApiProvider).create(payload),
    successMessage: 'Created ${values['name']}',
    failureMessage: 'Could not create instance',
    invalidate: [truenasVirtInstancesProvider(type)],
  );
}
