import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:cupola/core/utils/service_action.dart';

/// Runs a TrueNAS mutation with the shared plumbing: await [action],
/// invalidate the [invalidate] providers on success, and report the outcome
/// via `SnackBarHelper`.
///
/// A thin alias over [runServiceAction], which the whole app shares; kept as a
/// named entry point because every TrueNAS action flow reads through it.
Future<bool> runTrueNasAction(
  BuildContext context,
  WidgetRef ref, {
  required Future<void> Function() action,
  String? successMessage,
  required String failureMessage,
  List<ProviderOrFamily> invalidate = const [],
}) {
  return runServiceAction(
    context,
    ref,
    action: action,
    successMessage: successMessage,
    failureMessage: failureMessage,
    invalidate: invalidate,
  );
}
