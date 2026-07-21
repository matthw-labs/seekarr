import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:seekarr/core/utils/snack_bar_helper.dart';
import 'package:seekarr/features/nzbget/data/nzbget_client.dart';
import 'package:seekarr/features/nzbget/presentation/nzbget_provider.dart';

/// Runs a [NzbgetClient] mutation with the shared plumbing: resolve the client,
/// await [action], invalidate [invalidate] providers on success and report the
/// outcome via [SnackBarHelper].
///
/// NZBGet keeps its Basic-auth credentials in the `Authorization` header, never
/// in the URL, so the [NzbgetException] surfaced below carries no secret.
Future<bool> runNzbgetAction(
  BuildContext context,
  WidgetRef ref, {
  required Future<void> Function(NzbgetClient client) action,
  String? successMessage,
  required String failureMessage,
  List<ProviderOrFamily> invalidate = const [],
}) async {
  final client = ref.read(nzbgetClientProvider);
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
