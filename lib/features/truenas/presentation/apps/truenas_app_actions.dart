import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/widgets/app_dialog.dart';
import 'package:seekarr/features/truenas/domain/models/app.dart';
import 'package:seekarr/features/truenas/presentation/apps/truenas_apps_providers.dart';
import 'package:seekarr/features/truenas/presentation/truenas_actions.dart';
import 'package:seekarr/features/truenas/presentation/truenas_provider.dart';

enum AppAction { start, stop, upgrade, delete }

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
