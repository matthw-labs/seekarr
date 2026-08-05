import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/utils/service_routes.dart';
import 'package:seekarr/core/utils/snack_bar_helper.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:seekarr/features/plex/presentation/plex_provider.dart';
import 'package:seekarr/features/services/presentation/service_kpi_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/stream/domain/models/stream_library.dart';
import 'package:seekarr/features/stream/domain/models/stream_session.dart';
import 'package:seekarr/features/stream/domain/stream_semantics.dart';
import 'package:seekarr/features/stream/presentation/widgets/stream_session_card.dart';

/// The Stream board — one dashboard serving both Jellyfin and Plex.
///
/// **What this page is.** A media server is the only service in Seekarr that knows
/// about *people*: every other domain answers questions about objects (is this film
/// owned, grabbed, subtitled, on disk), while Jellyfin and Plex are the only source
/// of subject-and-time state — who is watching, where they stopped, what is next
/// for them. So the board leads with the sessions, and the libraries sit at its
/// foot as *destinations* rather than as a poster wall.
///
/// **What it deliberately does not have: a total.** An earlier design opened on an
/// aggregate "egress" figure, on the theory that streams are the mirror of the
/// download rate. That figure does not exist. Jellyfin reports a bitrate only while
/// transcoding — a direct play carries none, so the only number available is the
/// source file's own — and Plex's `Session.bandwidth` is a reservation made by its
/// streaming brain. Summing those adds two different units together and presents
/// the result as the box's outbound traffic, which would be fabricated. Per-session
/// figures live on the cards, where `StreamSession.bitrateIsNominal` can say what
/// they actually are.
///
/// **Idle is the majority state and is built first.** Nobody watching is not an
/// empty state and not a failure — it is a quiet room, and on a home server it is
/// the normal condition. It gets one line, and the page's weight falls to the
/// libraries, which is the only region with content either way.
class StreamDashboardScreen extends ConsumerWidget {
  const StreamDashboardScreen({
    super.key,
    required this.service,
    this.showAppBar = true,
    this.topPadding = 0,
  });

  final ServiceKey service;
  final bool showAppBar;
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    assert(
      service.domain == ServiceDomain.stream,
      'StreamDashboardScreen only serves the Stream domain',
    );
    final settings = ref.watch(currentSettingsProvider);
    final isConfigured = settings.isServiceConfigured(service);

    return AmbientScaffold(
      accent: service.accent,
      appBar: showAppBar ? GlassAppBar(title: Text(service.title)) : null,
      body: SafeArea(
        top: showAppBar,
        child: isConfigured
            ? _StreamBoard(service: service, topPadding: topPadding)
            : NotConfiguredPlaceholder(serviceName: service.title),
      ),
    );
  }
}

class _StreamBoard extends ConsumerWidget {
  const _StreamBoard({required this.service, required this.topPadding});

  final ServiceKey service;
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = service == ServiceKey.jellyfin
        ? ref.watch(jellyfinSessionsProvider)
        : ref.watch(plexSessionsProvider);
    final librariesAsync = service == ServiceKey.jellyfin
        ? ref.watch(jellyfinLibrariesProvider)
        : ref.watch(plexLibrariesProvider);

    return RefreshIndicator(
      onRefresh: () async {
        if (service == ServiceKey.jellyfin) {
          ref.invalidate(jellyfinSessionsProvider);
          ref.invalidate(jellyfinLibrariesProvider);
        } else {
          ref.invalidate(plexSessionsProvider);
          ref.invalidate(plexLibrariesProvider);
        }
        ref.invalidate(serviceKpiProvider(service));
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          0,
          topPadding,
          0,
          // The nav bar floats over content and grows with the reading size, so
          // a constant here leaves the last library unreachable at large text.
          FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: [
          ServiceKpiPeek(
            kpis: ref.watch(serviceKpiProvider(service)),
            accent: service.accent,
          ),
          const SizedBox(height: AppSpacing.sm),
          _NowPlayingSection(service: service, sessions: sessionsAsync),
          const SizedBox(height: AppSpacing.xl),
          _LibrariesSection(service: service, libraries: librariesAsync),
        ],
      ),
    );
  }
}

class _NowPlayingSection extends ConsumerWidget {
  const _NowPlayingSection({required this.service, required this.sessions});

  final ServiceKey service;
  final AsyncValue<List<StreamSession>> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: SectionHeader(title: 'Now playing', showChevron: false),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: AsyncValueWidget<List<StreamSession>>(
            value: sessions,
            serviceName: service.title,
            isEmpty: (list) => list.isEmpty,
            emptyBuilder: const _IdleRoom(),
            data: (list) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < list.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: i == list.length - 1 ? 0 : AppSpacing.md,
                    ),
                    child: StaggeredEntrance(
                      index: i,
                      child: StreamSessionCard(
                        session: list[i],
                        accent: service.accent,
                        onStop: _stopHandler(context, ref, list[i]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The stop control, or null when stopping is not available.
  ///
  /// Plex gates termination behind Plex Pass *and* admin scope, and answers a
  /// server without it with a 401 that has nothing to do with the token. Reading
  /// `myPlexSubscription` first means the control is simply absent rather than
  /// present-and-misleading — and a user who taps it never gets sent off to
  /// re-paste a credential that was fine. A session with no server-side id cannot
  /// be terminated at all, which is a real Plex shape, not a defensive guard.
  VoidCallback? _stopHandler(
    BuildContext context,
    WidgetRef ref,
    StreamSession session,
  ) {
    if (session.id.isEmpty) return null;

    if (service == ServiceKey.plex) {
      final capabilities = ref.watch(plexCapabilitiesProvider).value;
      if (capabilities?.myPlexSubscription != true) return null;
    }

    return () => _confirmStop(context, ref, session);
  }

  Future<void> _confirmStop(
    BuildContext context,
    WidgetRef ref,
    StreamSession session,
  ) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Stop playback?',
      message: streamStopSessionPrompt(
        userName: session.userName,
        title: session.title,
      ),
      icon: Icons.stop_circle_outlined,
      confirmLabel: 'Stop',
      destructive: true,
      // The default note promises irreversibility, which is wrong here: both
      // servers only *dispatch* a stop, and the viewer can simply press play
      // again. Overstating it would make an ordinary courtesy feel like a purge.
      dangerNote: 'They can start it again straight away.',
    );
    if (!result.confirmed || !context.mounted) return;

    try {
      final client = service == ServiceKey.jellyfin
          ? ref.read(jellyfinServerProvider)
          : ref.read(plexServerProvider);
      await client.stopSession(session.id);
      // Both servers only *dispatch* a stop — Jellyfin's 204 means "sent to the
      // client", which may ignore it. So the board re-reads rather than removing
      // the row optimistically and claiming something it cannot know.
      if (service == ServiceKey.jellyfin) {
        ref.invalidate(jellyfinSessionsProvider);
      } else {
        ref.invalidate(plexSessionsProvider);
      }
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
/// Not `AppEmptyState` with a "nothing here" glyph and not an error: the server
/// answered, and an idle media server is the normal daily condition rather than a
/// state the user needs to fix. One quiet line, in the same register the
/// `/services` outage notice uses for a fault that is normal for the product.
class _IdleRoom extends StatelessWidget {
  const _IdleRoom();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Icon(
            Icons.nights_stay_outlined,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              streamIdleMessage,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LibrariesSection extends StatelessWidget {
  const _LibrariesSection({required this.service, required this.libraries});

  final ServiceKey service;
  final AsyncValue<List<StreamLibrary>> libraries;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: SectionHeader(title: 'Libraries', showChevron: false),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: AsyncValueWidget<List<StreamLibrary>>(
            value: libraries,
            serviceName: service.title,
            isEmpty: (list) => list.isEmpty,
            emptyBuilder: const AppEmptyState.compact(
              icon: Icons.video_library_outlined,
              title: 'No libraries yet',
              message: 'This server has no libraries set up.',
            ),
            data: (list) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final library in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _LibraryRow(service: service, library: library),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One library, as a destination.
///
/// Entering the collection through a *room on the server* rather than through a
/// global title list is what keeps the Stream browse from reading as a second copy
/// of Radarr's library — see `StreamLibraryLens` and the idle-month test.
class _LibraryRow extends StatelessWidget {
  const _LibraryRow({required this.service, required this.library});

  final ServiceKey service;
  final StreamLibrary library;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final route = service == ServiceKey.jellyfin
        ? ServiceRoutes.jellyfinLibrary(library.id, title: library.name)
        : ServiceRoutes.plexLibrary(library.id, title: library.name);

    return AppCard.filled(
      // A library row is a full-width card with plenty of surface, so the ink
      // ripple still reads as a touch spreading rather than as a selection — the
      // Ripple-Needs-Room Rule's threshold is not crossed here.
      onTap: () => context.push(route),
      semanticLabel: library.name,
      semanticValue: streamLibraryValue(
        kindLabel: library.kind.label,
        itemCount: library.itemCount,
        lastScannedLabel: _scannedLabel(library.lastScannedAt),
        isRefreshing: library.isRefreshing,
      ),
      semanticHint: 'Browse this library',
      child: Row(
        children: [
          Icon(_glyphFor(library.kind), size: 20, color: service.accent),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  library.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _subtitleFor(library),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (library.isRefreshing)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(service.accent),
              ),
            )
          else
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
        ],
      ),
    );
  }

  /// The line under the library name.
  ///
  /// Composed from whatever the server actually said. Jellyfin exposes no
  /// per-library scan timestamp — only a global scheduled task — so the scan half
  /// is simply absent there rather than printed as "unknown", which would imply
  /// the server was asked and declined.
  static String _subtitleFor(StreamLibrary library) {
    final parts = <String>[library.kind.label];
    final count = library.itemCount;
    if (count != null) parts.add('$count items');
    if (library.isRefreshing) {
      parts.add('Scanning');
    } else {
      final scanned = _scannedLabel(library.lastScannedAt);
      if (scanned != null) parts.add(scanned);
    }
    return parts.join(' · ');
  }

  static String? _scannedLabel(DateTime? at) {
    if (at == null) return null;
    final elapsed = DateTime.now().difference(at);
    if (elapsed.inDays >= 1) return 'Scanned ${elapsed.inDays}d ago';
    if (elapsed.inHours >= 1) return 'Scanned ${elapsed.inHours}h ago';
    return 'Scanned just now';
  }

  static IconData _glyphFor(StreamLibraryKind kind) => switch (kind) {
    StreamLibraryKind.movies => Icons.movie_outlined,
    StreamLibraryKind.shows => Icons.tv_outlined,
    StreamLibraryKind.music => Icons.library_music_outlined,
    StreamLibraryKind.photos => Icons.photo_library_outlined,
    StreamLibraryKind.other => Icons.folder_outlined,
  };
}
