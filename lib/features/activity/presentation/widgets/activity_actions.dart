import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/utils/snack_bar_helper.dart';
import 'package:seekarr/core/widgets/app_dialog.dart';
import 'package:seekarr/features/activity/presentation/activity_provider.dart';
import 'package:seekarr/features/activity/presentation/activity_screen.dart';
import 'package:seekarr/features/discover/data/seerr_service.dart';
import 'package:seekarr/features/discover/presentation/discover_provider.dart';

/// The write actions the Activity surfaces can perform on a queue or blocklist
/// record.
///
/// Activity was a read-only feed: it could tell you a download had stalled and
/// then offered no way to do anything about it, so the resolution path for every
/// problem it surfaced was to leave and open the service's web UI. These close
/// that loop.
///
/// Each one confirms first (destructive, and irreversible on the client side),
/// reports the outcome, and bumps [activityRefreshVersionProvider] so every
/// bucket re-reads rather than leaving a removed row on screen.
class ActivityActions {
  ActivityActions._();

  /// Removes a queue record, optionally blocklisting the release.
  ///
  /// The two toggles are the two decisions the \*arr API actually exposes, and
  /// they mean different things: deleting from the client frees the disk,
  /// blocklisting stops the same release being grabbed again on the next search.
  /// Blocklisting alone is the "this release is bad, find another" move.
  static Future<void> removeFromQueue(
    BuildContext context,
    WidgetRef ref, {
    required ServiceType serviceType,
    required int recordId,
    required String title,
  }) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Remove from queue?',
      message: title,
      icon: Icons.delete_outline_rounded,
      confirmLabel: 'Remove',
      destructive: true,
      options: const [
        AppConfirmOption(
          key: 'removeFromClient',
          label: 'Delete from download client',
          subtitle: 'Also removes the files that have been downloaded so far.',
          initialValue: true,
          danger: true,
        ),
        AppConfirmOption(
          key: 'blocklist',
          label: 'Blocklist this release',
          subtitle: 'Stops it being grabbed again, so a search finds another.',
        ),
      ],
    );

    if (!result.confirmed) return;
    if (!context.mounted) return;

    await _run(
      context,
      ref,
      action: () => ref
          .read(resolvedArrServiceProvider(serviceType))
          .removeFromQueue(
            recordId,
            removeFromClient: result.option('removeFromClient'),
            blocklist: result.option('blocklist'),
          ),
      successMessage: result.option('blocklist')
          ? 'Removed and blocklisted'
          : 'Removed from queue',
      failureMessage: 'Could not remove from queue',
    );
  }

  /// Blocklists the current release and immediately searches for another.
  ///
  /// This is what a user means by "retry": the \*arr API has no retry endpoint,
  /// so the equivalent is to reject what is there and go looking again.
  static Future<void> blocklistAndRetry(
    BuildContext context,
    WidgetRef ref, {
    required ServiceType serviceType,
    required int recordId,
    required String title,
  }) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Blocklist and search again?',
      message:
          '$title will be removed and blocklisted, then a new search runs for '
          'a different release.',
      icon: Icons.refresh_rounded,
      confirmLabel: 'Blocklist and retry',
      destructive: true,
    );

    if (!result.confirmed) return;
    if (!context.mounted) return;

    await _run(
      context,
      ref,
      action: () => ref
          .read(resolvedArrServiceProvider(serviceType))
          .removeFromQueue(recordId, removeFromClient: true, blocklist: true),
      successMessage: 'Blocklisted — searching for another release',
      failureMessage: 'Could not blocklist this release',
    );
  }

  /// Removes a release from the blocklist so it can be grabbed again.
  static Future<void> removeFromBlocklist(
    BuildContext context,
    WidgetRef ref, {
    required ServiceType serviceType,
    required int recordId,
    required String title,
  }) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Remove from blocklist?',
      message: '$title becomes eligible to be grabbed again.',
      icon: Icons.playlist_add_check_rounded,
      confirmLabel: 'Remove',
    );

    if (!result.confirmed) return;
    if (!context.mounted) return;

    await _run(
      context,
      ref,
      action: () => ref
          .read(resolvedArrServiceProvider(serviceType))
          .deleteBlocklistItem(recordId),
      successMessage: 'Removed from blocklist',
      failureMessage: 'Could not remove from blocklist',
    );
  }

  /// Approves a request that is waiting on somebody.
  ///
  /// This closes the loop the screen has always half-shown: `resolveRequestStatus`
  /// already tones a pending request `warning` precisely to say it needs a
  /// person, and until now the only way to be that person was to leave for the
  /// Seerr web UI.
  static Future<void> approveRequest(
    BuildContext context,
    WidgetRef ref, {
    required int requestId,
    required String title,
  }) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Approve this request?',
      message:
          '$title goes to the service that handles it and starts downloading.',
      icon: Icons.check_circle_outline_rounded,
      confirmLabel: 'Approve',
    );

    if (!result.confirmed) return;
    if (!context.mounted) return;

    await _run(
      context,
      ref,
      action: () => ref.read(seerrServiceProvider).approveRequest(requestId),
      successMessage: 'Request approved',
      failureMessage: 'Could not approve this request',
      invalidateRequests: true,
    );
  }

  /// Declines a request, leaving the media alone.
  static Future<void> declineRequest(
    BuildContext context,
    WidgetRef ref, {
    required int requestId,
    required String title,
  }) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Decline this request?',
      message:
          '$title will not be downloaded. The request stays on record as '
          'declined.',
      icon: Icons.cancel_outlined,
      confirmLabel: 'Decline',
      destructive: true,
    );

    if (!result.confirmed) return;
    if (!context.mounted) return;

    await _run(
      context,
      ref,
      action: () => ref.read(seerrServiceProvider).declineRequest(requestId),
      successMessage: 'Request declined',
      failureMessage: 'Could not decline this request',
      invalidateRequests: true,
    );
  }

  /// Runs a mutation, reports it, and refreshes the feed.
  ///
  /// The failure message names what did not happen rather than echoing a Dio
  /// exception: `'Search failed: $error'` was the previous house style and it
  /// surfaced transport internals to someone who wanted to know whether their
  /// download was gone.
  static Future<void> _run(
    BuildContext context,
    WidgetRef ref, {
    required Future<void> Function() action,
    required String successMessage,
    required String failureMessage,

    /// Seerr requests arrive through a separately cached provider, so bumping
    /// the feed version alone re-runs the merge over the same stale list.
    bool invalidateRequests = false,
  }) async {
    try {
      await action();
      if (context.mounted) SnackBarHelper.success(context, successMessage);
    } on SeerrRequestConflict catch (conflict) {
      // Deliberately not a `return`: the action did not fail, it was overtaken.
      // The stale thing is the list on screen, so this falls through to the
      // refresh below instead of leaving a row the server no longer agrees with.
      if (context.mounted) SnackBarHelper.error(context, '$conflict');
    } catch (_) {
      if (context.mounted) {
        SnackBarHelper.error(
          context,
          '$failureMessage. The service may be unreachable.',
        );
      }
      return;
    }

    if (invalidateRequests) ref.invalidate(requestsProvider);
    ref.read(activityRefreshVersionProvider.notifier).state++;
  }
}
