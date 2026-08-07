import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/features/dockge/data/dockge_client.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';

/// Runs a [DockgeClient] mutation with the shared plumbing every action button
/// uses: resolve the client, await [action], invalidate [invalidate] providers
/// on success and report the outcome via [SnackBarHelper].
///
/// Returns `true` when the action completed without throwing so callers can
/// chain follow-up work (popping a screen, clearing state) only on success.
Future<bool> runDockgeAction(
  BuildContext context,
  WidgetRef ref, {
  required Future<void> Function(DockgeClient client) action,
  String? successMessage,
  required String failureMessage,
  List<ProviderOrFamily> invalidate = const [],
}) async {
  final client = ref.read(dockgeClientProvider);
  try {
    await action(client);
    for (final provider in invalidate) {
      ref.invalidate(provider);
    }
    if (successMessage != null && context.mounted) {
      SnackBarHelper.success(context, successMessage);
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      SnackBarHelper.error(context, '$failureMessage: $e');
    }
    return false;
  }
}

/// Convenience wrapper around [runDockgeAction] for the action buttons/chips
/// that fire a stack mutation with the positional
/// `(action, success, failure)` shape. Invalidates [invalidate] and runs
/// [onSuccess] only when the action succeeds. Returns the same `bool`.
Future<bool> runDockgeStackAction(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function(DockgeClient client) action,
  String success,
  String failure, {
  List<ProviderOrFamily> invalidate = const [],
  void Function()? onSuccess,
}) async {
  final ok = await runDockgeAction(
    context,
    ref,
    action: action,
    successMessage: success,
    failureMessage: failure,
    invalidate: invalidate,
  );
  if (ok && onSuccess != null) onSuccess();
  return ok;
}
