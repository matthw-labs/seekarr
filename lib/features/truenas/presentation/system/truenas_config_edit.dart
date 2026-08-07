import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/features/truenas/presentation/truenas_actions.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_form_sheet.dart';

/// Opens an edit form for a TrueNAS config section, then — before writing
/// anything — shows an explicit review of exactly what changed and asks for
/// confirmation.
///
/// This deliberate two-step flow (edit → review diff → confirm) is the guard
/// against accidental configuration changes: the form's submit button only
/// *stages* changes, and nothing is sent until the user confirms the summarised
/// old → new diff. Only fields that actually changed are included in the patch;
/// keys listed in [intKeys] are parsed to `int` before being written.
Future<void> editTrueNasConfig({
  required BuildContext context,
  required WidgetRef ref,
  required String title,
  required List<TrueNasFormField> fields,
  required Map<String, dynamic> current,
  required Map<String, String> labels,
  required Future<void> Function(Map<String, dynamic> patch) apply,
  required List<ProviderOrFamily> invalidate,
  Set<String> intKeys = const {},
}) async {
  final values = await showTrueNasFormSheet(
    context: context,
    title: title,
    fields: fields,
    submitLabel: 'Review changes',
  );
  if (values == null || !context.mounted) return;

  final patch = <String, dynamic>{};
  final diffLines = <String>[];
  for (final f in fields) {
    final label = labels[f.key] ?? f.key;
    if (f.boolField) {
      final oldBool = current[f.key] == true;
      final newBool = values[f.key] == true;
      if (newBool != oldBool) {
        patch[f.key] = newBool;
        diffLines.add(
          '$label: ${oldBool ? 'On' : 'Off'} → ${newBool ? 'On' : 'Off'}',
        );
      }
    } else {
      final oldStr = _norm(current[f.key]?.toString());
      final newStr = _norm(values[f.key] as String?);
      if (newStr != null && newStr != oldStr) {
        patch[f.key] = intKeys.contains(f.key)
            ? (int.tryParse(newStr) ?? newStr)
            : newStr;
        diffLines.add('$label: ${oldStr ?? '—'} → $newStr');
      }
    }
  }

  if (patch.isEmpty) {
    SnackBarHelper.success(context, 'No changes to save');
    return;
  }
  if (!context.mounted) return;

  final result = await showAppConfirmDialog(
    context: context,
    title: 'Apply these changes?',
    message: diffLines.join('\n'),
    confirmLabel: 'Save changes',
  );
  if (!result.confirmed || !context.mounted) return;

  await runTrueNasAction(
    context,
    ref,
    action: () => apply(patch),
    successMessage: 'Settings saved',
    failureMessage: 'Could not save',
    invalidate: invalidate,
  );
}

String? _norm(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
