import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/snack_bar_helper.dart';
import 'package:seekarr/features/npm/data/npm_client.dart';
import 'package:seekarr/features/npm/presentation/npm_provider.dart';

/// Runs an [NpmClient] mutation with the shared plumbing.
///
/// [NpmException.message] is always a static sentence or one of NPM's own fixed
/// strings — the client never interpolates a response body — so the `$e` below
/// cannot carry the bearer token or the password. That is the whole reason the
/// client is strict about it: this line is where it would otherwise surface.
Future<bool> runNpmAction(
  BuildContext context,
  WidgetRef ref, {
  required Future<void> Function(NpmClient client) action,
  String? successMessage,
  required String failureMessage,
  List<ProviderOrFamily> invalidate = const [],
}) async {
  final client = ref.read(npmClientProvider);
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
    for (final provider in invalidate) {
      ref.invalidate(provider);
    }
    if (context.mounted) {
      SnackBarHelper.error(context, '$failureMessage: $e');
    }
    return false;
  }
}

/// Asks the user to type [phrase] before an outward-facing change goes through.
///
/// A heavier gate than [showAppConfirmDialog], used where the blast radius
/// leaves the device: disabling a proxy host takes a hostname offline for
/// everyone who uses it, not just for the person holding the phone, and it does
/// so instantly and silently. A tap-to-confirm is calibrated for "are you
/// sure"; this is calibrated for "do you know which one you are about to take
/// down", which is a different question and the one that actually goes wrong on
/// a small screen.
///
/// Typing the hostname answers it directly — you cannot type the wrong one by
/// mistapping a row. Matching is trimmed and case-insensitive, because
/// hostnames are, and demanding exact case would only teach people to
/// copy-paste past the check.
Future<bool> confirmByTyping(
  BuildContext context, {
  required String title,
  required String message,
  required String phrase,
  required String confirmLabel,
}) async {
  final controller = TextEditingController();
  final matches = ValueNotifier<bool>(false);
  void update() {
    matches.value =
        controller.text.trim().toLowerCase() == phrase.trim().toLowerCase();
  }

  controller.addListener(update);

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final colorScheme = Theme.of(context).colorScheme;
      return AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: AppRadius.borderRadiusSm,
              ),
              child: SelectableText(
                phrase,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: controller,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Type it to confirm',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: matches,
            builder: (context, enabled, _) => FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              onPressed: enabled ? () => Navigator.of(context).pop(true) : null,
              child: Text(confirmLabel),
            ),
          ),
        ],
      );
    },
  );

  controller.removeListener(update);
  controller.dispose();
  matches.dispose();
  return confirmed ?? false;
}
