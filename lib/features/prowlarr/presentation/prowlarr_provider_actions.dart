import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:cupola/core/utils/service_action.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/prowlarr/presentation/widgets/prowlarr_field_inputs.dart';
import 'package:cupola/features/prowlarr/presentation/widgets/prowlarr_provider_form_sheet.dart';
import 'package:cupola/features/prowlarr/presentation/widgets/prowlarr_provider_pickers.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Write flows for the field-driven Prowlarr resources: apps, download clients,
/// notifications and indexer proxies. Indexers have their own flows in
/// `prowlarr_indexer_actions.dart` — they carry enough extra state (priority,
/// sync profile, bulk editing) to be worth their own file.

List<ProviderOrFamily> _invalidations(ProwlarrProviderKind kind) => [
  prowlarrProvidersProvider(kind),
  prowlarrHealthProvider,
  // Apps decide what the sync pushes and download clients feed the indexer
  // form, so both ripple past their own list.
  if (kind == ProwlarrProviderKind.application) ...[
    serviceKpiProvider(ServiceKey.prowlarr),
    serviceSummaryProvider(ServiceKey.prowlarr),
  ],
];

/// Picks an implementation, then opens the generated form to add it.
Future<void> addProviderFlow(
  BuildContext context,
  WidgetRef ref,
  ProwlarrProviderKind kind,
) async {
  final implementation = await showProwlarrImplementationPicker(
    context: context,
    kind: kind,
  );
  if (implementation == null || !context.mounted) return;

  final outcome = await showProwlarrProviderFormSheet(
    context: context,
    kind: kind,
    resource: implementation,
    isNew: true,
  );
  if (outcome != ProwlarrFormOutcome.saved) return;

  for (final provider in _invalidations(kind)) {
    ref.invalidate(provider);
  }
  if (context.mounted) {
    SnackBarHelper.success(context, 'Added ${kind.singular}');
  }
}

/// Opens the generated form for an existing provider. Returns true if it ended
/// up deleted.
Future<bool> editProviderFlow(
  BuildContext context,
  WidgetRef ref,
  ProwlarrProviderKind kind,
  ProwlarrProviderResource resource,
) async {
  final outcome = await showProwlarrProviderFormSheet(
    context: context,
    kind: kind,
    resource: resource,
  );

  switch (outcome) {
    case ProwlarrFormOutcome.cancelled:
      return false;
    case ProwlarrFormOutcome.saved:
      for (final provider in _invalidations(kind)) {
        ref.invalidate(provider);
      }
      if (context.mounted) {
        SnackBarHelper.success(
          context,
          'Saved ${resource.name ?? kind.singular}',
        );
      }
      return false;
    case ProwlarrFormOutcome.deleteRequested:
      if (!context.mounted) return false;
      return deleteProviderFlow(context, ref, kind, resource);
  }
}

Future<bool> deleteProviderFlow(
  BuildContext context,
  WidgetRef ref,
  ProwlarrProviderKind kind,
  ProwlarrProviderResource resource,
) async {
  final name = resource.name ?? 'this ${kind.singular}';
  final result = await showAppConfirmDialog(
    context: context,
    title: 'Delete $name?',
    message: kind == ProwlarrProviderKind.application
        ? 'Prowlarr stops syncing indexers to it. The app itself keeps the '
              'indexers it already has.'
        : 'Prowlarr stops using it straight away.',
    confirmLabel: 'Delete',
    destructive: true,
  );
  if (!result.confirmed || !context.mounted) return false;

  return runServiceAction(
    context,
    ref,
    action: () =>
        ref.read(prowlarrServiceProvider).deleteProvider(kind, resource.id),
    successMessage: 'Deleted $name',
    failureMessage: 'Could not delete $name',
    invalidate: _invalidations(kind),
  );
}

/// Tests one saved provider.
Future<void> testProviderFlow(
  BuildContext context,
  WidgetRef ref,
  ProwlarrProviderKind kind,
  ProwlarrProviderResource resource,
) async {
  await runServiceAction(
    context,
    ref,
    action: () => ref
        .read(prowlarrServiceProvider)
        .testProvider(kind, resource.toPayload()),
    successMessage: '${resource.name ?? kind.singular} answered',
    failureMessage: 'Test failed for ${resource.name ?? kind.singular}',
    invalidate: [prowlarrHealthProvider],
  );
}

/// Tests every provider of [kind] and reports how many answered.
Future<void> testAllProvidersFlow(
  BuildContext context,
  WidgetRef ref,
  ProwlarrProviderKind kind,
) async {
  SnackBarHelper.info(context, 'Testing ${kind.title.toLowerCase()}…');
  try {
    final results = await ref
        .read(prowlarrServiceProvider)
        .testAllProviders(kind);
    ref.invalidate(prowlarrHealthProvider);
    if (!context.mounted) return;

    final failed = results.where((result) => !result.isValid).toList();
    if (results.isEmpty) {
      SnackBarHelper.info(context, 'Nothing to test');
    } else if (failed.isEmpty) {
      SnackBarHelper.success(context, 'All ${results.length} passed');
    } else {
      final firstReason = failed
          .expand((result) => result.failures)
          .map((failure) => failure.errorMessage)
          .whereType<String>()
          .firstOrNull;
      SnackBarHelper.error(
        context,
        '${failed.length} of ${results.length} failed',
        detail: firstReason,
      );
    }
  } catch (e) {
    if (context.mounted) {
      SnackBarHelper.error(context, 'Could not run the tests', detail: e);
    }
  }
}
