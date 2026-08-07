import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/features/truenas/domain/models/app.dart';
import 'package:cupola/features/truenas/presentation/apps/truenas_apps_providers.dart';
import 'package:cupola/features/truenas/presentation/truenas_actions.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';

enum AppAction { start, stop, upgrade, delete }

/// Upgrades every app that has an update available, one after another, then
/// reports a combined outcome. No-op (with a friendly note) when everything is
/// already up to date.
Future<void> updateAllApps(
  BuildContext context,
  WidgetRef ref, {
  required List<TrueNasApp> apps,
}) async {
  final upgradable = apps.where((a) => a.upgradeAvailable).toList();
  if (upgradable.isEmpty) {
    SnackBarHelper.success(context, 'All apps are up to date');
    return;
  }

  final plural = upgradable.length > 1 ? 's' : '';
  final result = await showAppConfirmDialog(
    context: context,
    title: 'Update ${upgradable.length} app$plural?',
    message: upgradable.map((a) => a.title).join(', '),
    confirmLabel: 'Update all',
  );
  if (!result.confirmed || !context.mounted) return;

  final api = ref.read(truenasAppsApiProvider);
  final failures = <String>[];
  for (final app in upgradable) {
    try {
      await api.upgrade(app.name);
    } catch (_) {
      failures.add(app.title);
    }
  }

  ref.invalidate(truenasAppsProvider);
  if (!context.mounted) return;
  if (failures.isEmpty) {
    SnackBarHelper.success(context, 'Updated ${upgradable.length} app$plural');
  } else {
    SnackBarHelper.error(context, 'Failed to update: ${failures.join(', ')}');
  }
}

/// Runs an app lifecycle action, confirming destructive ones. Returns true on
/// success (callers pop the detail screen after a delete).
Future<bool> appLifecycleAction(
  BuildContext context,
  WidgetRef ref, {
  required TrueNasApp app,
  required AppAction action,
}) async {
  final api = ref.read(truenasAppsApiProvider);

  if (action == AppAction.delete) {
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Delete ${app.title}?',
      message: 'This removes the app and its data.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!result.confirmed || !context.mounted) return false;
  }

  Future<void> call() {
    switch (action) {
      case AppAction.start:
        return api.start(app.name);
      case AppAction.stop:
        return api.stop(app.name);
      case AppAction.upgrade:
        return api.upgrade(app.name);
      case AppAction.delete:
        return api.delete(app.name);
    }
  }

  const messages = {
    AppAction.start: 'Starting',
    AppAction.stop: 'Stopping',
    AppAction.upgrade: 'Upgrading',
    AppAction.delete: 'Deleting',
  };

  return runTrueNasAction(
    context,
    ref,
    action: call,
    successMessage: '${messages[action]} ${app.title}',
    failureMessage: 'Action failed',
    invalidate: [truenasAppsProvider, truenasAppProvider(app.name)],
  );
}
