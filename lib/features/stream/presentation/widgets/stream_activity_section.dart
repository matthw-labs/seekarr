import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/stream_semantics.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_session_card.dart';

/// The Streaming half of `/activity`'s **Now** bucket.
///
/// `Now` used to hold one record type, and its own comment explained that the
/// single sub-segment existed only because a one-entry bucket renders no pill row
/// at all — while the pills that survived elsewhere had to "express a record type
/// no service filter can reach". An outbound playback is exactly that: downloads
/// are bytes coming in, sessions are bytes going out, and no amount of filtering
/// the arr services reaches one from the other.
///
/// It carries its own type rather than becoming a `GlobalActivityItem` — see
/// [streamActivityProvider] for the 27 exhaustive switches that decision avoids.
class StreamActivitySection extends ConsumerWidget {
  const StreamActivitySection({super.key, required this.bottomPadding});

  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(hasStreamServiceProvider)) {
      return _NoStreamService(bottomPadding: bottomPadding);
    }

    final rowsAsync = ref.watch(streamActivityProvider);
    final offline = ref.watch(streamActivityOfflineProvider).value ?? const [];

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(jellyfinSessionsProvider);
        ref.invalidate(plexSessionsProvider);
      },
      child: AsyncValueWidget<List<StreamActivityRow>>(
        value: rowsAsync,
        serviceName: 'your media servers',
        isEmpty: (rows) => rows.isEmpty,
        emptyBuilder: _IdleFeed(offline: offline, bottomPadding: bottomPadding),
        data: (rows) => ListView.separated(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            bottomPadding,
          ),
          itemCount: rows.length + (offline.isEmpty ? 0 : 1),
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) {
            // The offline note rides at the top of the list rather than above it,
            // so it scrolls with the rows instead of pinning a band over content.
            if (offline.isNotEmpty && index == 0) {
              return _OfflineNote(offline: offline);
            }
            final row = rows[index - (offline.isEmpty ? 0 : 1)];
            return StaggeredEntrance(
              index: index,
              child: StreamSessionCard(
                session: row.session,
                // Each row takes its own server's accent, the way a download row
                // carries its client's. The Room Light Rule's one-accent-per-screen
                // constraint is about what *lights* the room — `/activity` is
                // inherently cross-service, so identity stays confined to the row.
                accent: row.service.accent,
                onStop: _stopHandler(context, ref, row),
              ),
            );
          },
        ),
      ),
    );
  }

  /// The stop control, or null where stopping is not permitted.
  ///
  /// Same gate as the board: Plex puts termination behind Plex Pass and admin
  /// scope, and answers a server without it with a 401 that has nothing to do with
  /// the token — so the control is absent rather than present-and-failing.
  VoidCallback? _stopHandler(
    BuildContext context,
    WidgetRef ref,
    StreamActivityRow row,
  ) {
    if (row.session.id.isEmpty) return null;
    if (row.service == ServiceKey.plex) {
      final capabilities = ref.watch(plexCapabilitiesProvider).value;
      if (capabilities?.myPlexSubscription != true) return null;
    }
    return () => _confirmStop(context, ref, row);
  }

  Future<void> _confirmStop(
    BuildContext context,
    WidgetRef ref,
    StreamActivityRow row,
  ) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Stop playback?',
      message: streamStopSessionPrompt(
        userName: row.session.userName,
        title: row.session.title,
      ),
      icon: Icons.stop_circle_outlined,
      confirmLabel: 'Stop',
      destructive: true,
      dangerNote: 'They can start it again straight away.',
    );
    if (!result.confirmed || !context.mounted) return;

    try {
      final client = row.service == ServiceKey.jellyfin
          ? ref.read(jellyfinServerProvider)
          : ref.read(plexServerProvider);
      await client.stopSession(row.session.id);
      // Re-read rather than remove the row: both servers only dispatch a stop,
      // and the client is free to ignore it.
      ref.invalidate(
        row.service == ServiceKey.jellyfin
            ? jellyfinSessionsProvider
            : plexSessionsProvider,
      );
    } catch (error) {
      if (!context.mounted) return;
      SnackBarHelper.error(
        context,
        'Could not stop playback',
        detail: '$error',
      );
    }
  }
}

/// Nobody watching.
///
/// Reuses the board's own sentence so the two surfaces cannot disagree about the
/// same fact, and states an unreachable source by name when there is one —
/// otherwise a dark server and a quiet house look identical.
class _IdleFeed extends StatelessWidget {
  const _IdleFeed({required this.offline, required this.bottomPadding});

  final List<ServiceKey> offline;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xxl,
        AppSpacing.lg,
        bottomPadding,
      ),
      children: [
        if (offline.isNotEmpty) ...[
          _OfflineNote(offline: offline),
          const SizedBox(height: AppSpacing.lg),
        ],
        AppEmptyState(
          icon: Icons.nights_stay_outlined,
          title: streamIdleMessage,
          message: offline.isEmpty
              ? 'Playback shows up here the moment someone presses play.'
              : null,
        ),
      ],
    );
  }
}

/// Which media server stopped answering.
///
/// Keeps its **presence** as the signal and spends the error tone on one glyph, per
/// the Quiet Alarm Rule: a home server being down for an afternoon is normal for
/// this product, and alarm chrome for a normal condition trains the user to ignore
/// it.
class _OfflineNote extends StatelessWidget {
  const _OfflineNote({required this.offline});

  final List<ServiceKey> offline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = servicesAlertBandMessage([
      for (final service in offline) service.title,
    ]);

    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 16,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// No media server configured yet.
///
/// The sub-segment is still offered, because hiding a record type until it is
/// configured is how a feature becomes undiscoverable — so this names the way in
/// rather than reporting an absence.
class _NoStreamService extends StatelessWidget {
  const _NoStreamService({required this.bottomPadding});

  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xxl,
        AppSpacing.lg,
        bottomPadding,
      ),
      children: [
        AppEmptyState(
          icon: Icons.play_circle_outline_rounded,
          title: 'No media server yet',
          message:
              'Connect Jellyfin or Plex to see who is watching what, and why '
              'the box is working for it.',
          action: FilledButton(
            onPressed: () => context.go(ServiceRoutes.services),
            child: const Text('Set one up'),
          ),
        ),
      ],
    );
  }
}
