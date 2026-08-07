import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/media_detail_slot.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/presentation/stream_lookup_provider.dart';

/// The "it's watchable, and you're 34 minutes in" slot for an *arr detail page.
///
/// **This is where the pipeline closes.** Radarr answers "do I own it"; a media
/// server is the only thing that knows "can anyone play it, and has anyone
/// started". Seekarr is the only place both facts sit on one screen, and this slot
/// is that sentence.
///
/// It is a *decoration on the arr's own record*, not a second catalogue and not a
/// search group — see [streamMatchProvider] for why adding Jellyfin and Plex as
/// their own global-search sources would have produced six sections for one film.
///
/// Renders **nothing** in three cases, all of them "we cannot say": no media
/// server configured, the title genuinely absent, or the server unreachable. An
/// explicit "not on your server" would be a claim, and two of those three are not.
///
/// [accent] is the **host** page's — Radarr amber, Sonarr violet — never Jellyfin's
/// or Plex's. The data comes from the media server but the section belongs to the
/// page it renders in, and one screen gets one accent. `ArrMediaExtrasSection`
/// settled this for Seerr data and the rule is the same here.
List<MediaDetailSlot> streamAvailabilitySlots(
  WidgetRef ref, {
  required Color accent,
  String? tmdbId,
  String? tvdbId,
  String? imdbId,
}) {
  final matchAsync = ref.watch(
    streamMatchProvider((tmdbId: tmdbId, tvdbId: tvdbId, imdbId: imdbId)),
  );

  final match = matchAsync.value;
  if (match == null) return const <MediaDetailSlot>[];

  return [
    MediaDetailSlot.box(
      label: 'On your server',
      child: _StreamAvailabilityCard(match: match, accent: accent),
    ),
  ];
}

class _StreamAvailabilityCard extends StatelessWidget {
  const _StreamAvailabilityCard({required this.match, required this.accent});

  final StreamMatch match;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = match.item;
    final line = _statusLine(item, match.service);

    return AppCard.filled(
      onTap: () => context.push(_itemRoute()),
      pressFeedback: AppCardPressFeedback.scale,
      semanticLabel: 'On ${match.service.title}',
      semanticValue: line,
      semanticHint: 'Open on ${match.service.title}',
      child: Row(
        children: [
          Icon(match.service.icon, size: 20, color: accent),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'On ${match.service.title}',
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  line,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (item.resumeProgress != null)
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                value: item.resumeProgress,
                strokeWidth: 3,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(accent),
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

  String _itemRoute() => match.service == ServiceKey.jellyfin
      ? ServiceRoutes.jellyfinItem(match.item.id)
      : ServiceRoutes.plexItem(match.item.id);

  /// The one line the slot exists to say.
  ///
  /// In-progress first, because a resume point is the only state that carries an
  /// action; then watched; then plain availability. Minutes rather than a
  /// percentage for a part-watched item: "34 min in" is where you are, where "28%"
  /// makes the reader do the arithmetic against a runtime they may not know.
  static String _statusLine(StreamItem item, ServiceKey service) {
    final offset = item.resumeOffsetMs;
    if (item.isInProgress && offset != null) {
      final minutes = (offset / 60000).round();
      return minutes < 1 ? 'Just started' : '$minutes min in';
    }
    if (item.isPlayed) return 'Watched';
    final unplayed = item.unplayedChildCount;
    if (unplayed != null && unplayed > 0) {
      return '$unplayed not played yet';
    }
    return 'Ready to watch';
  }
}
