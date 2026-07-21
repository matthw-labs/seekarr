import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:seekarr/core/utils/snack_bar_helper.dart';
import 'package:seekarr/features/sabnzbd/data/sabnzbd_client.dart';
import 'package:seekarr/features/sabnzbd/presentation/sabnzbd_provider.dart';

/// Runs a [SabnzbdClient] mutation with the shared plumbing: resolve the client,
/// await [action], invalidate [invalidate] providers on success and report the
/// outcome via [SnackBarHelper].
///
/// [SabnzbdClient] always throws a [SabnzbdException] whose message has been run
/// through [redactSabnzbdSecrets], so interpolating the error below can never
/// leak the API key that SABnzbd carries in the request URL (security §10.2 #7).
Future<bool> runSabnzbdAction(
  BuildContext context,
  WidgetRef ref, {
  required Future<void> Function(SabnzbdClient client) action,
  String? successMessage,
  required String failureMessage,
  List<ProviderOrFamily> invalidate = const [],
}) async {
  final client = ref.read(sabnzbdClientProvider);
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
