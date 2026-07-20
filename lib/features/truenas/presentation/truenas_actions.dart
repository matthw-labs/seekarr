import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:seekarr/core/utils/snack_bar_helper.dart';

/// Runs a TrueNAS mutation with the shared plumbing: await [action],
/// invalidate the [invalidate] providers on success, and report the outcome
/// via [SnackBarHelper].
///
/// Shows [successMessage] on success (when non-null) and the error-styled
/// `"$failureMessage: <error>"` on failure. Returns `true` when the action
/// completed without throwing, so callers can chain follow-up work (popping a
/// detail screen after a delete) only on success.
Future<bool> runTrueNasAction(
  BuildContext context,
  WidgetRef ref, {
  required Future<void> Function() action,
  String? successMessage,
  required String failureMessage,
  List<ProviderOrFamily> invalidate = const [],
}) async {
  try {
    await action();
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
