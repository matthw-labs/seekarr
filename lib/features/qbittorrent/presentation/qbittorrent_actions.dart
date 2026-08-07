import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_service.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';

/// Runs a [QbittorrentService] mutation with the plumbing every action
/// button shares: resolve the service, await [action], invalidate the
/// [invalidate] providers on success and report the outcome via
/// [SnackBarHelper].
///
/// Shows [successMessage] on success (when non-null) and the error-styled
/// `"$failureMessage: <error>"` on failure. Returns `true` when the action
/// completed without throwing so callers can chain follow-up work (clearing a
/// selection, popping a screen) only on success.
Future<bool> runTorrentAction(
  BuildContext context,
  WidgetRef ref, {
  required Future<void> Function(QbittorrentService service) action,
  String? successMessage,
  required String failureMessage,
  List<ProviderOrFamily> invalidate = const [],
}) async {
  final service = ref.read(qbittorrentServiceProvider);
  try {
    await action(service);
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
