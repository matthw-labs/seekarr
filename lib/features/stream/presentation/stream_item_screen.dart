import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_poster_tile.dart';

/// One item on a media server, at any depth of the tree.
///
/// **One screen for film, show, season, episode, album and track.** A Jellyfin
/// `BaseItemDto` and a Plex `Metadata` element describe all of those with the same
/// fields, which is a real structural difference from the arr side: Radarr, Sonarr
/// and Lidarr each needed their own model and their own detail screen. So this is a
/// single recursive route — a show lists its seasons, a season lists its episodes,
/// and each of those pushes this same screen again.
class StreamItemScreen extends ConsumerWidget {
  const StreamItemScreen({
    super.key,
    required this.service,
    required this.itemId,
  });

  final ServiceKey service;
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemAsync = service == ServiceKey.jellyfin
        ? ref.watch(jellyfinItemProvider(itemId))
        : ref.watch(plexItemProvider(itemId));

    return AmbientScaffold(
      accent: service.accent,
      appBar: GlassAppBar(title: Text(itemAsync.value?.title ?? service.title)),
      body: SafeArea(
        child: AsyncValueWidget<StreamItem?>(
          value: itemAsync,
          serviceName: service.title,
          isEmpty: (item) => item == null,
          emptyBuilder: const AppEmptyState(
            icon: Icons.help_outline_rounded,
            title: 'Not on the server',
            message:
                'This item is no longer in the library, or the viewer it '
                'belongs to cannot see it.',
          ),
          data: (item) => _Body(service: service, item: item!),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.service, required this.item});

  final ServiceKey service;
  final StreamItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        FloatingNavBarMetrics.getScrollViewBottomPadding(context),
      ),
      children: [
        Text(item.title, style: theme.textTheme.headlineSmall),
        if (item.subtitle != null && item.subtitle!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              item.subtitle!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        _StateRow(item: item, accent: service.accent),
        const SizedBox(height: AppSpacing.lg),
        _HandoffButton(service: service, item: item),
        if (item.kind.hasChildren) ...[
          const SizedBox(height: AppSpacing.xl),
          _Children(service: service, itemId: item.id),
        ],
      ],
    );
  }
}

/// Watch state, as chips.
///
/// This is the whole reason a Stream detail page is not a duplicate of Radarr's:
/// where the arr answers "do I own it", this answers "has anyone watched it, and
/// where did they stop".
class _StateRow extends StatelessWidget {
  const _StateRow({required this.item, required this.accent});

  final StreamItem item;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final progress = item.resumeProgress;
    final unplayed = item.unplayedChildCount;
    final runtime = _runtimeLabel(item.runtimeMs);

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        if (progress != null)
          TagChip(
            text: '${(progress * 100).round()}% watched',
            color: accent,
            icon: Icons.play_circle_outline_rounded,
          )
        else if (item.isPlayed)
          TagChip(
            text: 'Watched',
            color: accent,
            icon: Icons.check_circle_outline_rounded,
          ),
        if (unplayed != null && unplayed > 0)
          GenreChip(genre: '$unplayed not played'),
        if (runtime != null) GenreChip(genre: runtime),
        if (item.year != null) GenreChip(genre: '${item.year}'),
      ],
    );
  }

  /// Runtime from milliseconds — the unit `StreamItem` normalises to, because the
  /// two servers disagree natively (Jellyfin counts .NET ticks, Plex milliseconds
  /// for duration but epoch seconds for dates).
  static String? _runtimeLabel(int? ms) {
    if (ms == null || ms <= 0) return null;
    final minutes = (ms / 60000).round();
    if (minutes < 60) return '${minutes}m';
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }
}

/// The handoff out to the real client.
///
/// **Named "Open in …", never "Play".** Cupola does not decode video, and once a
/// resume position has been shown on this very page a button labelled Play promises
/// playback this app cannot deliver — the tap would land the user on another app's
/// home screen having lost the position they were just looking at. Naming the door
/// makes it an honest door.
///
/// It also takes the **service accent** here rather than a host page's, because
/// this *is* the service's own screen. On a Radarr or Sonarr detail page the same
/// affordance must take the host's accent instead: `ArrMediaExtrasSection` already
/// settled that a section belongs to the screen it is rendered in, and one accent
/// lights a screen at a time.
class _HandoffButton extends ConsumerWidget {
  const _HandoffButton({required this.service, required this.item});

  final ServiceKey service;
  final StreamItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final baseUrl = settings.urlFor(service);

    // Plex's web client addresses an item by server identity as well as by key, so
    // without the machine identifier there is no URL to build. The button is absent
    // rather than broken.
    final machineId = service == ServiceKey.plex
        ? ref.watch(plexCapabilitiesProvider).value?.machineIdentifier
        : null;
    if (baseUrl.isEmpty) return const SizedBox.shrink();
    if (service == ServiceKey.plex &&
        (machineId == null || machineId.isEmpty)) {
      return const SizedBox.shrink();
    }

    final resuming = item.isInProgress;
    final label = resuming
        ? 'Resume in ${service.title}'
        : 'Open in ${service.title}';

    return FilledButton.icon(
      onPressed: () => _open(context, baseUrl, machineId),
      icon: Icon(
        resuming ? Icons.play_arrow_rounded : Icons.open_in_new_rounded,
      ),
      label: Text(label),
    );
  }

  Future<void> _open(
    BuildContext context,
    String baseUrl,
    String? machineId,
  ) async {
    final target = _webUrl(baseUrl, machineId);
    if (target == null) return;

    final launched = await launchUrl(
      target,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      SnackBarHelper.error(
        context,
        'Could not open ${service.title}',
        detail: target.toString(),
      );
    }
  }

  /// The server's own web client, deep-linked to this item.
  ///
  /// A web URL rather than an app scheme: neither Jellyfin nor Plex publishes a
  /// documented, reliably-registered scheme across iOS, Android and macOS, and a
  /// scheme that silently fails is worse than a browser that works. On a phone the
  /// installed app usually claims the URL anyway through universal links.
  Uri? _webUrl(String baseUrl, String? machineId) {
    final root = UrlUtils.normalizeBaseUrl(baseUrl);
    if (root.isEmpty) return null;

    if (service == ServiceKey.jellyfin) {
      return Uri.tryParse('$root/web/index.html#!/details?id=${item.id}');
    }
    final key = Uri.encodeComponent('/library/metadata/${item.id}');
    return Uri.tryParse(
      '$root/web/index.html#!/server/$machineId/details?key=$key',
    );
  }
}

/// Seasons, episodes or tracks.
///
/// Rendered as the same poster grid the library browse uses, so a season inside a
/// show looks like what it is — one more thing you can enter — rather than as a
/// list row that happens to navigate.
class _Children extends ConsumerWidget {
  const _Children({required this.service, required this.itemId});

  final ServiceKey service;
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final childrenAsync = service == ServiceKey.jellyfin
        ? ref.watch(jellyfinItemChildrenProvider(itemId))
        : ref.watch(plexChildrenProvider(itemId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Contents', showChevron: false),
        AsyncValueWidget<List<StreamItem>>(
          value: childrenAsync,
          serviceName: service.title,
          isEmpty: (list) => list.isEmpty,
          emptyBuilder: const AppEmptyState.compact(
            icon: Icons.inbox_outlined,
            title: 'Nothing inside',
          ),
          data: (list) => GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: list.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 130 + AppSpacing.gridGap,
              childAspectRatio: 2 / 3,
              crossAxisSpacing: AppSpacing.gridGap,
              mainAxisSpacing: AppSpacing.gridGap,
            ),
            itemBuilder: (context, index) => StreamPosterTile(
              service: service,
              item: list[index],
              index: index,
            ),
          ),
        ),
      ],
    );
  }
}
