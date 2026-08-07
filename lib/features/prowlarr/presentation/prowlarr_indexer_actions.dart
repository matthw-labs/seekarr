import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:cupola/core/utils/service_action.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/prowlarr/presentation/widgets/prowlarr_add_indexer_sheet.dart';
import 'package:cupola/features/prowlarr/presentation/widgets/prowlarr_bulk_edit_sheet.dart';
import 'package:cupola/features/prowlarr/presentation/widgets/prowlarr_field_inputs.dart';
import 'package:cupola/features/prowlarr/presentation/widgets/prowlarr_indexer_form_sheet.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Everything a write action can invalidate: the indexer list itself plus the
/// derived views (stats, failure state, health, activity) and the `/services`
/// cards, which all read the same instance.
List<ProviderOrFamily> _indexerProviders() => [
  prowlarrIndexersProvider,
  prowlarrIndexerStatusProvider,
  prowlarrIndexerStatsProvider,
  prowlarrRecentHistoryProvider,
  prowlarrHealthProvider,
  serviceKpiProvider(ServiceKey.prowlarr),
  serviceSummaryProvider(ServiceKey.prowlarr),
];

/// Picks a definition, then opens the generated form to add it.
Future<void> addIndexerFlow(BuildContext context, WidgetRef ref) async {
  final definition = await showProwlarrAddIndexerSheet(context: context);
  if (definition == null || !context.mounted) return;

  final outcome = await showProwlarrIndexerFormSheet(
    context: context,
    indexer: definition,
    isNew: true,
  );
  if (outcome != ProwlarrFormOutcome.saved) return;

  for (final provider in _indexerProviders()) {
    ref.invalidate(provider);
  }
  if (context.mounted) {
    SnackBarHelper.success(context, 'Added ${definition.name ?? 'indexer'}');
  }
}

/// Opens the generated form for an existing indexer.
///
/// Returns true when the indexer was deleted, so a detail screen can leave.
Future<bool> editIndexerFlow(
  BuildContext context,
  WidgetRef ref,
  ProwlarrIndexer indexer,
) async {
  final outcome = await showProwlarrIndexerFormSheet(
    context: context,
    indexer: indexer,
  );

  switch (outcome) {
    case ProwlarrFormOutcome.cancelled:
      return false;
    case ProwlarrFormOutcome.saved:
      for (final provider in _indexerProviders()) {
        ref.invalidate(provider);
      }
      ref.invalidate(prowlarrIndexerHistoryProvider(indexer.id));
      if (context.mounted) {
        SnackBarHelper.success(context, 'Saved ${indexer.name ?? 'indexer'}');
      }
      return false;
    case ProwlarrFormOutcome.deleteRequested:
      if (!context.mounted) return false;
      return deleteIndexerFlow(context, ref, indexer);
  }
}

/// Deletes an indexer after confirmation. Returns true once it is gone.
Future<bool> deleteIndexerFlow(
  BuildContext context,
  WidgetRef ref,
  ProwlarrIndexer indexer,
) async {
  final name = indexer.name ?? 'this indexer';
  final result = await showAppConfirmDialog(
    context: context,
    title: 'Delete $name?',
    message:
        'Prowlarr stops querying it and removes it from every app it syncs to.',
    confirmLabel: 'Delete',
    destructive: true,
  );
  if (!result.confirmed || !context.mounted) return false;

  return runServiceAction(
    context,
    ref,
    action: () => ref.read(prowlarrServiceProvider).deleteIndexer(indexer.id),
    successMessage: 'Deleted $name',
    failureMessage: 'Could not delete $name',
    invalidate: _indexerProviders(),
  );
}

/// Enables or disables one indexer through the bulk endpoint, which is what the
/// web UI's row toggle uses too.
Future<void> toggleIndexerFlow(
  BuildContext context,
  WidgetRef ref,
  ProwlarrIndexer indexer,
) async {
  final enable = !indexer.enable;
  await runServiceAction(
    context,
    ref,
    action: () => ref
        .read(prowlarrServiceProvider)
        .bulkUpdateIndexers(ids: [indexer.id], enable: enable),
    successMessage:
        '${indexer.name ?? 'Indexer'} ${enable ? 'enabled' : 'disabled'}',
    failureMessage: 'Could not update ${indexer.name ?? 'the indexer'}',
    invalidate: _indexerProviders(),
  );
}

/// Tests one saved indexer against its tracker.
Future<void> testIndexerFlow(
  BuildContext context,
  WidgetRef ref,
  ProwlarrIndexer indexer,
) async {
  await runServiceAction(
    context,
    ref,
    action: () =>
        ref.read(prowlarrServiceProvider).testIndexer(indexer.toPayload()),
    successMessage: '${indexer.name ?? 'Indexer'} answered',
    failureMessage: 'Test failed for ${indexer.name ?? 'the indexer'}',
    invalidate: [prowlarrIndexerStatusProvider, prowlarrHealthProvider],
  );
}

/// Tests every indexer and reports how many came back healthy.
Future<void> testAllIndexersFlow(BuildContext context, WidgetRef ref) async {
  SnackBarHelper.info(context, 'Testing all indexers…');
  try {
    final results = await ref.read(prowlarrServiceProvider).testAllIndexers();
    ref.invalidate(prowlarrIndexerStatusProvider);
    ref.invalidate(prowlarrHealthProvider);
    if (!context.mounted) return;

    final failed = results.where((result) => !result.isValid).toList();
    if (results.isEmpty) {
      SnackBarHelper.info(context, 'Prowlarr reported no test results');
    } else if (failed.isEmpty) {
      SnackBarHelper.success(context, 'All ${results.length} indexers passed');
    } else {
      final firstReason = failed
          .expand((result) => result.failures)
          .map((failure) => failure.errorMessage)
          .whereType<String>()
          .firstOrNull;
      SnackBarHelper.error(
        context,
        '${failed.length} of ${results.length} indexers failed',
        detail: firstReason,
      );
    }
  } catch (e) {
    if (context.mounted) {
      SnackBarHelper.error(context, 'Could not test the indexers', detail: e);
    }
  }
}

/// Runs `ApplicationIndexerSync` — the web UI's "Sync App Indexers".
///
/// The command is queued, so its outcome is polled briefly: a sync that fails
/// (an app that is unreachable) does so within a second or two, and reporting
/// "started" for a failure would be worse than saying nothing.
Future<void> syncAppIndexersFlow(BuildContext context, WidgetRef ref) async {
  final service = ref.read(prowlarrServiceProvider);
  try {
    final queued = await service.syncAppIndexers();
    var command = queued;
    for (var attempt = 0; attempt < 5 && !command.isFinished; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      command = await service.getCommand(queued.id);
    }
    ref.invalidate(prowlarrApplicationsProvider);
    if (!context.mounted) return;

    if (command.isFailed) {
      SnackBarHelper.error(context, 'App sync failed', detail: command.message);
    } else if (command.isFinished) {
      SnackBarHelper.success(context, 'Indexers synced to your apps');
    } else {
      SnackBarHelper.info(context, 'App sync is running in Prowlarr');
    }
  } catch (e) {
    if (context.mounted) {
      SnackBarHelper.error(context, 'Could not start the app sync', detail: e);
    }
  }
}

/// Applies one set of changes to many indexers.
Future<bool> bulkEditIndexersFlow(
  BuildContext context,
  WidgetRef ref,
  List<int> ids,
) async {
  final edit = await showProwlarrBulkEditSheet(
    context: context,
    count: ids.length,
  );
  if (edit == null || !context.mounted) return false;
  if (edit.isEmpty) {
    SnackBarHelper.info(context, 'Nothing to change');
    return false;
  }

  return runServiceAction(
    context,
    ref,
    action: () => ref
        .read(prowlarrServiceProvider)
        .bulkUpdateIndexers(
          ids: ids,
          enable: edit.enable,
          priority: edit.priority,
          appProfileId: edit.appProfileId,
          minimumSeeders: edit.minimumSeeders,
          seedRatio: edit.seedRatio,
          seedTime: edit.seedTime,
          packSeedTime: edit.packSeedTime,
          preferMagnetUrl: edit.preferMagnetUrl,
        ),
    successMessage: 'Updated ${ids.length} ${_indexerWord(ids.length)}',
    failureMessage: 'Could not update the selected indexers',
    invalidate: _indexerProviders(),
  );
}

/// Adds, removes or replaces tags on many indexers.
Future<bool> bulkTagIndexersFlow(
  BuildContext context,
  WidgetRef ref,
  List<int> ids,
) async {
  final result = await showProwlarrBulkTagsSheet(
    context: context,
    count: ids.length,
  );
  if (result == null || !context.mounted) return false;

  return runServiceAction(
    context,
    ref,
    action: () => ref
        .read(prowlarrServiceProvider)
        .bulkUpdateIndexers(
          ids: ids,
          tags: result.tags,
          applyTags: result.applyTags,
        ),
    successMessage: 'Tags updated on ${ids.length} ${_indexerWord(ids.length)}',
    failureMessage: 'Could not update the tags',
    invalidate: _indexerProviders(),
  );
}

/// Deletes many indexers after confirmation.
///
/// Takes the indexers, not their ids, because the dialog has to **name** them.
/// A count alone ("Delete 7 indexers?") is unverifiable: the caller's selection
/// can outlive the filter that put those rows on screen, and a user who cannot
/// see what is about to go is being asked to confirm a number.
Future<bool> bulkDeleteIndexersFlow(
  BuildContext context,
  WidgetRef ref,
  List<ProwlarrIndexer> indexers,
) async {
  if (indexers.isEmpty) return false;
  final ids = indexers.map((indexer) => indexer.id).toList(growable: false);
  final word = _indexerWord(ids.length);
  final result = await showAppConfirmDialog(
    context: context,
    title: 'Delete ${ids.length} $word?',
    message:
        '${_indexerNames(indexers)}\n\n'
        'Prowlarr stops querying them and removes them from every app it '
        'syncs to.',
    confirmLabel: 'Delete',
    destructive: true,
  );
  if (!result.confirmed || !context.mounted) return false;

  return runServiceAction(
    context,
    ref,
    action: () => ref.read(prowlarrServiceProvider).bulkDeleteIndexers(ids),
    successMessage: 'Deleted ${ids.length} $word',
    failureMessage: 'Could not delete the selected indexers',
    invalidate: _indexerProviders(),
  );
}

String _indexerWord(int count) => count == 1 ? 'indexer' : 'indexers';

/// The names about to be deleted, capped so the dialog stays readable.
String _indexerNames(List<ProwlarrIndexer> indexers) {
  const limit = 8;
  final names = indexers
      .map((indexer) => indexer.name ?? 'Unnamed indexer')
      .toList(growable: false);
  if (names.length <= limit) return names.join(', ');
  return '${names.take(limit).join(', ')} and ${names.length - limit} more';
}
