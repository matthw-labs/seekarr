import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:seekarr/core/utils/snack_bar_helper.dart';
import 'package:seekarr/features/nzbget/data/nzbget_client.dart';
import 'package:seekarr/features/nzbget/presentation/nzbget_provider.dart';

/// True when NZBGet answered the call but refused to do the work.
///
/// NZBGet does not signal a rejected command with a JSON-RPC `error` object —
/// it answers HTTP 200 with `{"result": false}` (`editqueue`) or `{"result":
/// 0}` (`append`). Pausing a group whose NZBID has just left the queue,
/// deleting an already-removed id, or appending a URL the server declines all
/// take that path, so the client's own return value is the only evidence a
/// mutation did not happen.
///
/// Anything else — including the `null` a `Future<void>` method resolves to —
/// counts as success, because a method that reports nothing has no failure to
/// report.
bool _isRejection(Object? result) {
  if (result is bool) return !result;
  // `append` documents 0 as its failure value; a real NZBID is always > 0.
  if (result is num) return result <= 0;
  return false;
}

/// Runs a [NzbgetClient] mutation with the shared plumbing: resolve the client,
/// await [action], invalidate [invalidate] providers and report the outcome via
/// [SnackBarHelper]. Returns whether the mutation actually took effect.
///
/// [action] returns `Future<Object?>` rather than `Future<void>` on purpose.
/// `void` is a top type in Dart, so the old signature silently accepted
/// `Future<bool>` and `Future<int>` and then discarded their results — this
/// wrapper returned `true` unconditionally and the UI reported "Job paused"
/// for calls NZBGet had refused. Widening the return type is what lets
/// [_isRejection] see the answer at all; a genuinely `void` client method still
/// satisfies it and resolves to `null`.
///
/// NZBGet keeps its Basic-auth credentials in the `Authorization` header, never
/// in the URL, so the [NzbgetException] surfaced below carries no secret.
Future<bool> runNzbgetAction(
  BuildContext context,
  WidgetRef ref, {
  required Future<Object?> Function(NzbgetClient client) action,
  String? successMessage,
  required String failureMessage,
  List<ProviderOrFamily> invalidate = const [],
}) async {
  final client = ref.read(nzbgetClientProvider);
  try {
    final result = await action(client);
    // Refreshed either way: when NZBGet refuses a command it is usually because
    // the queue moved under us, and re-reading is what shows the user what is
    // actually there now.
    for (final provider in invalidate) {
      ref.invalidate(provider);
    }
    if (_isRejection(result)) {
      if (context.mounted) {
        SnackBarHelper.error(
          context,
          '$failureMessage. NZBGet rejected the request.',
        );
      }
      return false;
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
