import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/media_detail_slot.dart';
import 'package:cupola/features/discover/presentation/arr_media_extras_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_cast_list.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_collection_banner.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Region-6 slots for an *arr (Radarr/Sonarr) detail page — the `CAST` rail and
/// the `COLLECTION` banner, fetched from TMDB via Seerr — or the "Connect Seerr"
/// prompt when Seerr isn't configured.
///
/// Returns slots rather than one widget, and that is the whole point. As a single
/// widget this had to draw its children's headings itself, which made
/// [MediaDetailSectionLabel] — documented as built *only* by the spine — a thing
/// two feature widgets also constructed, with their own accent fallback and their
/// own idea of the gap beneath a label. It also could not be given a slot label
/// from outside: it renders nothing while loading and nothing when Seerr has no
/// extras, so a labelled slot would have left an orphan heading over 24pt of air
/// on every -arr page load.
///
/// Slots fix both at once: a region with no data is *omitted*, so there is no
/// empty-state to label around, and each heading is the spine's, in the host
/// page's accent, with `Semantics(header: true)` for free.
///
/// [accent] is the *host* screen's (Radarr amber, Sonarr violet, …), not Seerr's:
/// the data comes from Seerr but the section belongs to the page it renders in,
/// and one screen gets one accent.
List<MediaDetailSlot> arrMediaExtrasSlots(
  WidgetRef ref, {
  required int tmdbId,
  required String mediaType,
  required Color accent,
}) {
  final extrasAsync = ref.watch(
    arrMediaExtrasProvider((tmdbId: tmdbId, mediaType: mediaType)),
  );

  return extrasAsync.maybeWhen(
    data: (extras) {
      // Seerr not configured → prompt the user to connect it. Deliberately
      // unlabelled: it is a prompt about a missing integration, not a region of
      // this title's record, and an accent eyebrow reading `CAST` above a card
      // that says "Connect Seerr" would name content that is not there.
      if (extras == null) {
        return [MediaDetailSlot.box(child: _ConnectSeerrCta(accent: accent))];
      }

      final collection = extras.collection;

      return [
        if (extras.cast.isNotEmpty)
          // `.rail`, not `.box`: the spine hands the builder the resolved
          // content-column gutter, so the first face aligns to the column while
          // the rail keeps bleeding off the trailing edge. A `.box` would inset
          // both ends and the rail would read as a cropped list.
          MediaDetailSlot.rail(
            label: 'Cast',
            builder: (padding) =>
                DiscoverCastList(cast: extras.cast, padding: padding),
          ),
        if (collection != null)
          MediaDetailSlot.box(
            label: 'Collection',
            child: DiscoverCollectionBanner(collection: collection),
          ),
      ];
    },
    orElse: () => const <MediaDetailSlot>[],
  );
}

class _ConnectSeerrCta extends StatelessWidget {
  /// The *host* page's accent, not Seerr's.
  ///
  /// The card's subject is Seerr, so `AppColors.seerr` looks like the obvious
  /// choice and is what this used to paint — but that put a second accent on a
  /// Radarr or Sonarr page, which is the one thing the accent budget forbids. The
  /// copy names the service; the colour names the page.
  final Color accent;

  const _ConnectSeerrCta({required this.accent});

  /// The icon tile. Fixed on purpose and *not* grown with the reading size: it
  /// holds an icon and no text, so it is the fixed half of the row — the copy
  /// beside it is the half that grows, and it lives in an `Expanded` with no
  /// height of its own.
  static const double _iconTileSize = 44;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final icon = Container(
      width: _iconTileSize,
      height: _iconTileSize,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: AppRadius.borderRadiusMd,
      ),
      child: Icon(
        Icons.people_alt_rounded,
        // Resolved against the tint it sits on, not painted raw: the raw accent
        // over its own 14% wash fails AA in light theme on several services.
        color: ServiceTheme.onTint(
          accent,
          surface: colorScheme.surface,
          tintAlpha: 0.14,
        ),
      ),
    );

    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cast & collections',
          style: theme.textTheme.titleSmall?.weight(FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Connect Seerr to see cast, collections and more.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    final action = FilledButton(
      onPressed: () =>
          context.go('/settings/service/${ServiceKey.seerr.routeParam}'),
      child: const Text('Connect'),
    );

    // Past this reading size the button's own label is wide enough to squeeze
    // the copy beside it into a column too narrow for its longest word, which
    // clips rather than wraps. So the row becomes a stack — the same answer
    // `SectionHeader` gives at the same threshold, keyed off the scaler rather
    // than a `LayoutBuilder` for the same reason.
    final stacked = MediaQuery.textScalerOf(context).scale(14) > 14 * 1.4;

    // Never pad this widget. It is a slot child now, and the detail spine owns
    // the gutter and every gap around a region — the `fromLTRB(lg, 0, lg, lg)`
    // this used to carry would compound with the spine's inset and sit the card
    // 32pt in on a page where every other region sits at 16.
    return AppCard.surfaceOutlined(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    icon,
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: copy),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(width: double.infinity, child: action),
              ],
            )
          : Row(
              children: [
                icon,
                const SizedBox(width: AppSpacing.md),
                Expanded(child: copy),
                const SizedBox(width: AppSpacing.sm),
                action,
              ],
            ),
    );
  }
}
