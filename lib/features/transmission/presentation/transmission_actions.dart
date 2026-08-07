import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/features/transmission/data/transmission_client.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';

/// Runs a [TransmissionClient] mutation with the shared plumbing: resolve the
/// client, await [action], invalidate [invalidate] providers and report the
/// outcome. Returns whether the mutation was accepted.
///
/// Simpler than its NZBGet counterpart, and for a reason worth recording:
/// NZBGet signals a refused command by answering HTTP 200 with `{"result":
/// false}`, so its wrapper has to inspect the return value. Transmission never
/// does that — a refusal comes back as a `result` string that is not
/// `"success"`, and [TransmissionClient] has already turned that into a thrown
/// [TransmissionException] carrying the server's own words. So "did it work" is
/// exactly "did it throw", and there is no `_isRejection` equivalent to get
/// wrong.
///
/// The flip side, and the reason [invalidate] is not optional in practice:
/// Transmission's write methods return an empty `arguments` with no per-id
/// outcome and no echo of what was applied. Re-reading is the only way to know
/// what actually happened, so every caller passes the providers that answer
/// that question.
///
/// Transmission keeps its Basic credentials in the `Authorization` header and
/// never in the URL, and [TransmissionException.message] is always either a
/// static sentence or the server's own error string — so the `$e` interpolated
/// below cannot carry the password.
Future<bool> runTransmissionAction(
  BuildContext context,
  WidgetRef ref, {
  required Future<void> Function(TransmissionClient client) action,
  String? successMessage,
  required String failureMessage,
  List<ProviderOrFamily> invalidate = const [],
}) async {
  final client = ref.read(transmissionClientProvider);
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
    // Refreshed on failure too: a rejected command usually means the queue
    // moved under us, and re-reading is what shows the user what is there now.
    for (final provider in invalidate) {
      ref.invalidate(provider);
    }
    if (context.mounted) {
      SnackBarHelper.error(context, '$failureMessage: $e');
    }
    return false;
  }
}
