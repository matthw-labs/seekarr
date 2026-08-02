import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/service_theme.dart';
import 'package:seekarr/core/text_scale.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/image_utils.dart';
import 'package:seekarr/core/utils/service_routes.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/app_skeleton.dart';
import 'package:seekarr/core/widgets/async_value_widget.dart';
import 'package:seekarr/core/widgets/content_card.dart';
import 'package:seekarr/core/widgets/pressable_scale.dart';
import 'package:seekarr/core/widgets/section_header.dart';
import 'package:seekarr/core/widgets/shimmer_placeholder.dart';
import 'package:seekarr/core/widgets/status_badge.dart';
import 'package:seekarr/features/activity/presentation/widgets/activity_actions.dart';
import 'package:seekarr/features/discover/domain/models/seerr_request.dart';
import 'package:seekarr/features/services/domain/recently_added.dart';
import 'package:seekarr/features/services/domain/request_ordering.dart';
import 'package:seekarr/features/services/domain/services_semantics.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';

/// Everything currently transferring, across every configured source.
///
/// Second on the screen, directly under the matrix. It used to be last, below
/// three browse rails, which put the only time-sensitive region on the page
/// furthest from the first viewport.
class ServicesInFlightSection extends ConsumerWidget {
  const ServicesInFlightSection({super.key});

  /// Any service that can report a transfer, not just the two arrs the old gate
  /// checked.
  static const _sources = [
    ServiceKey.radarr,
    ServiceKey.sonarr,
    ServiceKey.lidarr,
    ServiceKey.readarr,
    ServiceKey.qbittorrent,
    ServiceKey.sabnzbd,
    ServiceKey.nzbget,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final sources = _sources
        .where(settings.isServiceConfigured)
        .toList(growable: false);
    if (sources.isEmpty) return const SizedBox.shrink();

    return _ListSection<ServiceQueueItem>(
      // "In Flight" was an ops metaphor in a region whose own empty state said
      // "Nothing downloading" and whose rows are announced against a section
      // this code already assumed was headed "Downloading" — see
      // `downloadRowValue`. One word for one thing, and it is the word the
      // audience already uses.
      title: 'Downloading',
      // Brand primary, not a service accent: the region spans up to seven
      // sources and no one of them owns it.
      accent: Theme.of(context).colorScheme.primary,
      sources: sources,
      asyncValue: ref.watch(servicesQueueProvider),
      serviceName: 'download queue',
      actionLabel: 'Activity',
      onAction: () => context.go('/activity'),
      onRetry: () => ref.invalidate(servicesQueueProvider),
      // Not "Nothing downloading", which the header now says. An empty transfer
      // list is a fact about the queue, so name the queue.
      emptyLabel: 'The queue is empty',
      itemsBuilder: (items) => items.map(_DownloadRow.new).toList(),
    );
  }
}

/// The single Requests region: pending first with inline actions, then the rest.
///
/// See `domain/request_ordering.dart` for why this is one region that sorts
/// rather than two that filter.
class ServicesRequestsSection extends ConsumerWidget {
  const ServicesRequestsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    if (!settings.isServiceConfigured(ServiceKey.seerr)) {
      return const SizedBox.shrink();
    }

    final requests = ref.watch(servicesRequestsProvider);
    // Counted over the whole set, not the visible slice, so the header stays
    // honest when there are more pending than fit.
    final pendingCount = requests.asData == null
        ? 0
        : countAwaitingApproval(requests.asData!.value);

    return _ListSection<SeerrRequest>(
      title: 'Requests',
      accent: ServiceKey.seerr.accent,
      sources: const [ServiceKey.seerr],
      asyncValue: requests,
      serviceName: 'Seerr',
      actionLabel: 'See all',
      onAction: () => context.push(ServiceRoutes.seerrRequests),
      onRetry: () => ref.invalidate(servicesRequestsProvider),
      emptyLabel: 'No requests yet',
      titleBadge: pendingCount == 0
          ? null
          : _PendingCountBadge(count: pendingCount),
      semanticLabel: pendingCount == 0
          ? 'Requests'
          : servicesRequestsHeaderLabel(pending: pendingCount),
      itemsBuilder: (items) =>
          sortRequestsPendingFirst(items, limit: servicesRequestsPreviewLimit)
              .map(
                (request) => isAwaitingApproval(request)
                    ? _PendingRequestRow(request)
                    : _RequestRow(request),
              )
              .toList(),
      loadingWidget: const Column(
        children: [
          _RequestRowSkeleton(),
          _RequestRowSkeleton(),
          _RequestRowSkeleton(),
        ],
      ),
    );
  }
}

/// The newest library additions across Radarr, Sonarr and Lidarr, in one rail.
///
/// Replaces two rails that each claimed "Recently Added" while showing an
/// unsorted slice of a full library fetch. See `domain/recently_added.dart`.
class ServicesRecentlyAddedSection extends ConsumerWidget {
  const ServicesRecentlyAddedSection({super.key});

  static const _libraries = [
    ServiceKey.radarr,
    ServiceKey.sonarr,
    ServiceKey.lidarr,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final libraries = _libraries
        .where(settings.isServiceConfigured)
        .toList(growable: false);
    if (libraries.isEmpty) return const SizedBox.shrink();

    return _PosterSection<RecentlyAddedItem>(
      title: 'Recently Added',
      // The rail spans three services, so its action colour cannot belong to one
      // of them. The action goes to search, the one place all three libraries
      // are reachable together.
      accent: Theme.of(context).colorScheme.primary,
      sources: libraries,
      asyncValue: ref.watch(servicesRecentlyAddedProvider),
      serviceName: 'your libraries',
      actionLabel: 'Search',
      onAction: () => context.go('/search'),
      onRetry: () => ref.invalidate(servicesRecentlyAddedProvider),
      itemTitle: (item) => item.title,
      itemSubtitle: (item) => item.subtitle,
      imageUrl: (item, _) => item.posterUrl,
      heroTag: (item) => item.heroTag,
      // Unlike the single-service rails this replaced, the accent varies per
      // tile: it is the only thing saying which library an item came from.
      itemAccent: (item) => item.service.accent,
      accentLabel: (item) => item.service.title,
      onTap: (item) => _openRecentlyAdded(context, item),
      limit: servicesRecentlyAddedLimit,
    );
  }
}

void _openRecentlyAdded(BuildContext context, RecentlyAddedItem item) {
  final route = switch (item.service) {
    ServiceKey.radarr => ServiceRoutes.radarrMovie(
      item.id,
      heroTag: item.heroTag,
    ),
    ServiceKey.sonarr => ServiceRoutes.sonarrSeries(
      item.id,
      heroTag: item.heroTag,
    ),
    ServiceKey.lidarr => ServiceRoutes.lidarrArtist(
      item.id,
      heroTag: item.heroTag,
    ),
    // Unreachable: the provider only emits these three. Falling back to the
    // service hub rather than throwing keeps a future fourth source from
    // crashing a tap before its route exists.
    _ => '/services/${item.service.routeParam}',
  };
  context.push(route);
}

class _PosterSection<T> extends StatelessWidget {
  final String title;

  /// Colour of the header action.
  final Color accent;

  /// The configured services this section's data comes from.
  ///
  /// Browse calls degrade to `[]` on remote failure by convention, so an
  /// unreachable service and an empty library arrive here identically. This is
  /// what lets the empty state tell them apart — see [_SectionEmptyState].
  ///
  /// Must be filtered to *configured* services by the caller: an unconfigured
  /// one reports offline, and naming it would blame a user for not running
  /// something they never installed.
  final List<ServiceKey> sources;
  final AsyncValue<List<T>> asyncValue;
  final String serviceName;
  final String actionLabel;
  final VoidCallback onAction;
  final String Function(T item) itemTitle;
  final String Function(T item) itemSubtitle;
  final String Function(T item, SettingsModel settings) imageUrl;
  final String Function(T item)? heroTag;
  final void Function(T item) onTap;
  final VoidCallback? onRetry;
  final int limit;

  /// Per-item accent, for a rail whose items come from more than one service.
  ///
  /// Defaults to [service]'s accent, which is right for a single-service rail
  /// and wrong for the merged one.
  final Color Function(T item)? itemAccent;

  /// What [itemAccent] means, in words.
  ///
  /// Required whenever [itemAccent] varies: the accent dot on a tile is the only
  /// thing distinguishing a Radarr item from a Sonarr one, and a colour is not
  /// information. Left null on a single-service rail, where the accent is
  /// constant and the header already named the service — announcing it on eight
  /// consecutive tiles would be noise.
  final String Function(T item)? accentLabel;

  const _PosterSection({
    required this.title,
    required this.accent,
    required this.sources,
    required this.asyncValue,
    required this.serviceName,
    required this.actionLabel,
    required this.onAction,
    required this.itemTitle,
    required this.itemSubtitle,
    required this.imageUrl,
    required this.onTap,
    this.heroTag,
    this.onRetry,
    this.limit = 10,
    this.itemAccent,
    this.accentLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          showChevron: false,
          trailing: _SectionAction(label: actionLabel, color: accent),
          // `_SectionAction` sits inside the region the header silences — its
          // "\u2192" would otherwise be read out as "rightwards arrow" — so the
          // visible action words come back as the hint.
          semanticHint: actionLabel,
          onTap: onAction,
        ),
        const SizedBox(height: AppSpacing.sm),
        // The rail's height is fixed around a 138pt poster; the empty state's is
        // a sentence and a button. Sizing the second by the first is what makes
        // "Radarr and Sonarr aren't answering" plus a 44pt Retry overflow the
        // box at accessibility reading sizes — the poster budget grows by the
        // 34pt of label a *tile* has, not by the four wrapped lines the sentence
        // gains. So the empty branch is hoisted out of the `SizedBox` and left
        // free to be as tall as it needs.
        if (_isEmpty(asyncValue))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: _SectionEmptyState(
              // Not "No items found", which is search vocabulary and implies a
              // query this rail never ran.
              label: 'Nothing added yet',
              sources: sources,
              onRetry: onRetry,
            ),
          )
        else
          SizedBox(
            // 138pt poster + gap + title/subtitle: grows with the reading size
            // so the labels are not clipped at accessibility text sizes.
            height: TextScaleMetrics.boxHeight(
              context,
              base: 176,
              textHeight: 34,
            ),
            // The box grew by the *clamped* scale, so the text has to be laid
            // out at the same clamp or the two disagree: `boxHeight` stops at
            // 1.6x by design, but a `Text` reads the ambient scaler, so at 2x
            // the tile was sized for 1.6 and painted at 2 — nine pixels of
            // overflow stripe. The matrix band has always done this; the rail
            // got away without it only because its subtitle carried a
            // hard-coded `fontSize: 10` that made the labels small enough to
            // fit by accident.
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaleMetrics.clampedScalerOf(context)),
              child: AsyncValueWidget<List<T>>(
                value: asyncValue,
                serviceName: serviceName,
                onRetry: onRetry,
                skeleton: AppSkeleton.posterRow(height: 138),
                data: (items) {
                  final visibleItems = items
                      .take(limit)
                      .toList(growable: false);

                  return Consumer(
                    builder: (context, ref, _) {
                      final settings = ref.watch(currentSettingsProvider);
                      return ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                        ),
                        itemCount: visibleItems.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: AppSpacing.carouselGap),
                        itemBuilder: (context, index) {
                          final item = visibleItems[index];
                          return _ServicePosterTile(
                            title: itemTitle(item),
                            subtitle: itemSubtitle(item),
                            imageUrl: imageUrl(item, settings),
                            accent: itemAccent?.call(item) ?? accent,
                            accentLabel: accentLabel?.call(item),
                            heroTag: heroTag?.call(item),
                            onTap: () => onTap(item),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

class _ListSection<T> extends StatelessWidget {
  final String title;

  /// Colour of the header action.
  final Color accent;

  /// The configured services this section's data comes from. See
  /// [_PosterSection.sources].
  final List<ServiceKey> sources;
  final AsyncValue<List<T>> asyncValue;
  final String serviceName;
  final String actionLabel;
  final VoidCallback onAction;
  final String emptyLabel;
  final List<Widget> Function(List<T> items) itemsBuilder;

  /// Optional widget shown while [asyncValue] is loading.
  /// Defaults to a centered [CircularProgressIndicator].
  final Widget? loadingWidget;
  final VoidCallback? onRetry;

  /// A count or state marker shown beside the action, e.g. "3 PENDING".
  ///
  /// Sits inside the region the header silences, so a caller passing one must
  /// also pass [semanticLabel] with the count folded into the sentence.
  final Widget? titleBadge;

  /// Overrides the header's spoken name. See [titleBadge].
  final String? semanticLabel;

  const _ListSection({
    required this.title,
    required this.accent,
    required this.sources,
    required this.asyncValue,
    required this.serviceName,
    required this.actionLabel,
    required this.onAction,
    required this.emptyLabel,
    required this.itemsBuilder,
    this.loadingWidget,
    this.onRetry,
    this.titleBadge,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final badge = titleBadge;
    final action = _SectionAction(label: actionLabel, color: accent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          showChevron: false,
          semanticLabel: semanticLabel,
          // A `Wrap`, not a `Row`: at an accessibility reading size "3 PENDING"
          // and "See all →" together measure wider than a phone's content
          // column, and a `Row` answers that with the overflow stripe. The
          // header stacks its trailing under the title at those sizes, which
          // gives this the full width it needs to break onto a second line.
          trailing: badge == null
              ? action
              : Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [badge, action],
                ),
          // `_SectionAction` sits inside the region the header silences — its
          // "\u2192" would otherwise be read out as "rightwards arrow" — so the
          // visible action words come back as the hint.
          semanticHint: actionLabel,
          onTap: onAction,
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: AsyncValueWidget<List<T>>(
            value: asyncValue,
            serviceName: serviceName,
            loadingWidget: loadingWidget,
            onRetry: onRetry,
            data: (items) {
              final rows = itemsBuilder(items);
              if (rows.isEmpty) {
                return _SectionEmptyState(
                  label: emptyLabel,
                  sources: sources,
                  onRetry: onRetry,
                );
              }

              return Column(children: rows);
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

class _ServicePosterTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imageUrl;
  final Color accent;

  /// The service the accent dot stands for, when the rail mixes services.
  final String? accentLabel;
  final String? heroTag;
  final VoidCallback onTap;

  const _ServicePosterTile({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.accent,
    required this.onTap,
    this.accentLabel,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // On a merged rail the accent dot is the only thing saying which library the
    // item came from, so it has to be spoken. On a single-service rail
    // `accentLabel` is null and the dot stays silent — see the note on it below.
    final spoken = joinSpokenParts([accentLabel, subtitle]);

    return SizedBox(
      width: 96,
      child: PressableScale(
        onTap: onTap,
        // The tile is a poster plus a truncated title; announce the full title
        // and its subtitle as one button rather than an unlabelled image.
        semanticLabel: title,
        semanticValue: spoken.isEmpty ? null : spoken,
        excludeChildSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              height: 138,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _HeroContentCard(
                      heroTag: heroTag,
                      imageUrl: imageUrl,
                    ),
                  ),
                  // The dot encodes which service the item came from. Whether
                  // that is worth saying depends on the rail: on a
                  // single-service rail the accent is constant and the header
                  // already named it, so repeating it on eight consecutive
                  // tiles would be noise. On the merged Recently Added rail it
                  // varies per tile and is the only carrier of that fact, so
                  // the caller passes `accentLabel` and it is folded into the
                  // tile's spoken value above.
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            spreadRadius: 1.5,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // No `fontSize` override. A hard-coded 10 sat under the
                // ladder's smallest step and under the 11pt floor both
                // platforms name, and the No Fixed Size Rule bans it outright:
                // the separation from the title above is already weight and
                // colour.
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeroContentCard extends StatelessWidget {
  final String? heroTag;
  final String imageUrl;

  const _HeroContentCard({required this.heroTag, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final card = ContentCard(imageUrl: imageUrl);
    // Only fly a Hero when there is both a tag AND an image on this end. An
    // empty image would produce a blank/orphaned Hero whose destination has no
    // matching poster (common for Seerr items without a posterPath), which
    // shows up as a fade instead of a shared-element flight.
    if (heroTag == null || heroTag!.isEmpty || imageUrl.isEmpty) {
      return card;
    }

    return Hero(tag: heroTag!, child: card);
  }
}

class _RequestRow extends StatelessWidget {
  final SeerrRequest request;

  const _RequestRow(this.request);

  @override
  Widget build(BuildContext context) {
    final media = request.media;
    final title = media?.title ?? 'Unknown Media';
    final requester = request.requestedBy?.displayName ?? 'Unknown';
    final subtitle =
        '$requester · ${request.type == 'tv' ? 'Series' : 'Movie'}';
    final displayStatus = request.displayStatus;
    final statusColor = _requestStatusColor(displayStatus.kind);
    final posterUrl = ImageUtils.buildTmdbPosterUrl(media?.posterPath);
    final heroTag = _requestHeroTag(request);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: _CompactListRow(
        icon: request.type == 'tv' ? Icons.tv_rounded : Icons.movie_rounded,
        title: title,
        subtitle: subtitle,
        imageUrl: posterUrl,
        heroTag: heroTag,
        trailing: _SmallStatusPill(
          label: displayStatus.label,
          color: statusColor,
        ),
        // Composed from the parts rather than from `subtitle`, which carries a
        // raw '·', and picking up the status pill the row now silences.
        semanticValue: seerrRequestRowValue(
          mediaTypeLabel: request.type == 'tv' ? 'Series' : 'Movie',
          requester: requester,
          statusLabel: displayStatus.label,
        ),
        onTap: () => _openRequest(context, request, heroTag: heroTag),
      ),
    );
  }
}

/// Opens a request's media detail.
///
/// Top-level because both the read-only row and the pending row need it.
void _openRequest(
  BuildContext context,
  SeerrRequest request, {
  String? heroTag,
}) {
  final media = request.media;
  final id = media?.tmdbId ?? media?.id;
  if (id == null || id <= 0) {
    context.go(ServiceRoutes.seerr);
    return;
  }

  final mediaType = request.type == 'tv' ? 'tv' : 'movie';
  final posterUrl = ImageUtils.buildTmdbPosterUrl(media?.posterPath);
  final tag = heroTag ?? 'services_request_${request.id}';
  context.push(
    ServiceRoutes.seerrDetail(
      mediaType: mediaType,
      id: id,
      heroTag: tag,
      posterUrl: posterUrl,
    ),
  );
}

/// The pending count beside the Requests header.
///
/// A tinted pill rather than bare text: the count is the one thing on the header
/// row that changes, and it is what makes the difference between a region worth
/// stopping at and one worth scrolling past.
class _PendingCountBadge extends StatelessWidget {
  const _PendingCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // The badge fills with amber at 14%, and the label is measured against that
    // composite. The saturated amber over its own tint lands near 1.8:1 in light
    // theme; `onTint` walks its lightness until it clears AA while keeping the
    // hue, so the pill stays recognisably amber.
    const tintAlpha = 0.14;
    final onTint = ServiceTheme.onTint(
      AppColors.warning,
      surface: colorScheme.surfaceContainer,
      tintAlpha: tintAlpha,
    );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: tintAlpha),
        borderRadius: AppRadius.borderRadiusSm,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      child: Text(
        '$count PENDING',
        style: theme.textTheme.labelSmall?.copyWith(
          color: onTint,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// A request waiting on a decision, with the decision attached.
///
/// The read-only [_RequestRow] silences its whole subtree, which is correct for a
/// row that is only a link. This one holds two real controls, so it labels itself
/// and silences only the parts its own label already speaks — per the contract in
/// `AppCard.semanticLabel`. Passing `excludeChildSemantics` here would drop both
/// buttons out of the accessibility tree entirely.
class _PendingRequestRow extends ConsumerWidget {
  const _PendingRequestRow(this.request);

  final SeerrRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final media = request.media;
    final title = media?.title ?? 'Unknown Media';
    final requester = request.requestedBy?.displayName ?? 'Unknown';
    final mediaTypeLabel = request.type == 'tv' ? 'Series' : 'Movie';
    final posterUrl = ImageUtils.buildTmdbPosterUrl(media?.posterPath);
    final heroTag = _requestHeroTag(request);
    // The word sits directly on the card, not on a tint, so the composite is the
    // surface itself.
    final onTint = ServiceTheme.onTint(
      AppColors.warning,
      surface: colorScheme.surfaceContainer,
      tintAlpha: 0,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard.surfaceOutlined(
        key: ValueKey('services-pending-request-${request.id}'),
        onTap: () => _openRequest(context, request, heroTag: heroTag),
        semanticLabel: title,
        // 'Pending' is stated rather than read off `displayStatus`, which would
        // say "Available" for a still-unapproved request whose media already
        // exists — see `isAwaitingApproval`.
        semanticValue: seerrRequestRowValue(
          mediaTypeLabel: mediaTypeLabel,
          requester: requester,
          statusLabel: 'Pending approval',
        ),
        borderColor: AppColors.warning.withValues(alpha: 0.28),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            // Everything the row's own label already speaks.
            Expanded(
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    SizedBox(
                      width: 38,
                      height: 54,
                      child: _HeroContentCard(
                        heroTag: heroTag,
                        imageUrl: posterUrl,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '$requester · $mediaTypeLabel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            // The whole phrase, and the same one the row
                            // announces. It was a bare uppercase "PENDING":
                            // pending *what* was left to the two buttons beside
                            // it, and the row's spoken value already had to say
                            // "Pending approval" to make sense — a visible label
                            // that needs its own audible translation is a label
                            // that was too short.
                            'Pending approval',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: onTint,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Not excluded: these are the point of the row.
            _RequestDecisionButton.approve(
              title: title,
              onPressed: () => ActivityActions.approveRequest(
                context,
                ref,
                requestId: request.id,
                title: title,
              ),
            ),
            _RequestDecisionButton.decline(
              title: title,
              onPressed: () => ActivityActions.declineRequest(
                context,
                ref,
                requestId: request.id,
                title: title,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the two inline decisions on a pending request.
///
/// Both are icon-only, so both carry the media title in their name: five pending
/// rows would otherwise offer five identical "Approve" buttons with no way to
/// tell which request each belongs to.
class _RequestDecisionButton extends StatelessWidget {
  const _RequestDecisionButton._({
    required this.icon,
    required this.verb,
    required this.tone,
    required this.title,
    required this.onPressed,
  });

  const _RequestDecisionButton.approve({
    required String title,
    required VoidCallback onPressed,
  }) : this._(
         icon: Icons.check_rounded,
         verb: 'Approve',
         tone: StatusTone.success,
         title: title,
         onPressed: onPressed,
       );

  const _RequestDecisionButton.decline({
    required String title,
    required VoidCallback onPressed,
  }) : this._(
         icon: Icons.close_rounded,
         verb: 'Decline',
         tone: StatusTone.error,
         title: title,
         onPressed: onPressed,
       );

  final IconData icon;
  final String verb;
  final StatusTone tone;
  final String title;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      // The tooltip is already this button's accessible name and three test
      // files assert on `find.byTooltip`, so it stays; the explicit label is
      // added rather than traded for it.
      tooltip: '$verb $title',
      color: ServiceTheme.onTint(
        statusToneColor(colorScheme, tone),
        surface: colorScheme.surfaceContainer,
        tintAlpha: 0,
      ),
      // Material's default 48x48 clears both the 44pt iOS and 48dp Android
      // floors; stated so a later density tweak cannot quietly drop under them.
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      padding: EdgeInsets.zero,
    );
  }
}

/// Skeleton placeholder for a single [_RequestRow] while data is loading.
class _RequestRowSkeleton extends StatelessWidget {
  const _RequestRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard.surfaceOutlined(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            ShimmerPlaceholder(
              width: 38,
              height: 54,
              borderRadius: BorderRadius.circular(6),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerPlaceholder.text(width: 140),
                  const SizedBox(height: AppSpacing.xs),
                  ShimmerPlaceholder.text(width: 90),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            ShimmerPlaceholder(
              width: 110,
              height: 26,
              borderRadius: AppRadius.borderRadiusSm,
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadRow extends StatelessWidget {
  final ServiceQueueItem item;

  const _DownloadRow(this.item);

  @override
  Widget build(BuildContext context) {
    final percent = item.progress == null
        ? null
        : (item.progress! * 100).round();
    // Brand primary, not the source service's accent, for both the figure and
    // the bar. Two reasons and either one is sufficient. Contrast: SABnzbd's
    // gold measures about 1.9:1 as `labelSmall` on the light card and NZBGet's
    // green about 2.9:1, well under AA, and a 3pt progress bar in the same hue
    // misses the 3:1 floor for a graphical object. Identity: DESIGN.md's Room
    // Light Rule confines service accents on this screen to the matrix's
    // identity tile, and seven download sources putting their own hue on a
    // percentage is the rainbow that rule exists to prevent. The row already
    // names its client in the leading glyph and in the subtitle.
    final accent = Theme.of(context).colorScheme.primary;
    final trailing = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (item.warning != null) ...[
          _SmallStatusPill(label: 'Warning', color: AppColors.error),
          const SizedBox(height: AppSpacing.xs),
        ],
        // Nothing at all when the client reports no progress. It used to print
        // "DL", an abbreviation that says nothing, in the slot where every other
        // row shows a number — so it read as a value rather than as its absence.
        // `downloadRowValue` already drops it from speech for the same reason.
        if (percent != null)
          Text(
            '$percent%',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: _CompactListRow(
        icon: item.service.icon,
        title: item.title,
        subtitle: item.subtitle,
        trailing: trailing,
        semanticValue: downloadRowValue(
          subtitle: item.subtitle,
          percent: percent,
          warning: item.warning,
        ),
        progressValue: item.progress,
        progressColor: item.progress == null ? null : accent,
        onTap: () => context.go('/activity'),
      ),
    );
  }
}

class _CompactListRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final String? heroTag;
  final Widget trailing;
  final double? progressValue;
  final Color? progressColor;
  final VoidCallback onTap;

  /// Everything announced after [title].
  ///
  /// Composed by the caller because [trailing] is an opaque widget and only the
  /// caller knows what is in it — the status pill, the percentage. It also folds
  /// in the progress bar, which publishes nothing of its own and whose "75%"
  /// label lives in a sibling subtree on screen.
  final String semanticValue;

  const _CompactListRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.semanticValue,
    required this.onTap,
    this.imageUrl,
    this.heroTag,
    this.progressValue,
    this.progressColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppCard.surfaceOutlined(
      onTap: onTap,
      semanticLabel: title,
      semanticValue: semanticValue,
      // Nothing in this row is interactive on its own. Note the deliberate
      // absence of LinearProgressIndicator.semanticsLabel: it would add a second
      // focus stop *inside* a button, which is worse than the bar being silent.
      excludeChildSemantics: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            height: 54,
            child: imageUrl == null || imageUrl!.isEmpty
                ? Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      icon,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  )
                : _HeroContentCard(heroTag: heroTag, imageUrl: imageUrl!),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (progressColor != null) ...[
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progressValue,
                      minHeight: 3,
                      color: progressColor,
                      backgroundColor: colorScheme.outlineVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          trailing,
        ],
      ),
    );
  }
}

/// A tone-coloured pill. Deliberately carries no semantics of its own: both call
/// sites sit inside a row that silences its children and folds this label into
/// the row's spoken value, so a node here would be either dead or a duplicate
/// stop.
class _SmallStatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _SmallStatusPill({required this.label, required this.color});

  /// Widest the pill may get before its label elides.
  ///
  /// [label] is service-derived — a Seerr `displayStatus` or an arr status
  /// message — so its length is not this app's to promise. Unbounded, it sits in
  /// a `Row` beside an `Expanded` title and a long value pushes the row into a
  /// `RenderFlex` overflow rather than shortening itself.
  static const double _maxWidth = 132;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // The label *is* the tone colour, painted over a 14% wash of that same tone,
    // and the raw accent is not legible there: measured over its own tint on the
    // light card, the warning amber lands near 1.8:1 and the success green near
    // 1.9:1, against a 4.5:1 floor. `onTint` walks the lightness until it clears
    // AA while keeping the hue, so the pill still reads as amber or green. Dark
    // theme passes untouched, which is exactly why the check has to be run on
    // both — `_PendingCountBadge` a few classes up already does this.
    final onTint = ServiceTheme.onTint(
      color,
      surface: colorScheme.surfaceContainer,
      tintAlpha: 0.14,
    );

    return Container(
      constraints: const BoxConstraints(maxWidth: _maxWidth),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: AppRadius.borderRadiusSm,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: onTint,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _SectionAction extends StatelessWidget {
  final String label;
  final Color color;

  const _SectionAction({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label →',
      // One line, always. The arrow belongs to the words before it, so a wrap
      // that stranded it on its own line would read as a second control.
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// The "nothing here" state for a dashboard section.
///
/// Distinguishes an empty library from sources that did not answer. Browse calls
/// degrade to `[]` on failure by convention, so both arrive here as the same
/// empty list — and before this the merged regions could only ever print the
/// empty copy, sending the user to look for missing media when the answer was a
/// missing connection.
///
/// The old shape allowed exactly one service to be blamed, which is why the
/// cross-service regions declared none and stayed silent. Taking the *list* of
/// sources removes that trade: the state names the ones that are actually dark,
/// so a merged rail can be as specific as a single-service one without ever
/// blaming a source that is fine.
///
/// The statuses come from [serviceSummaryProvider], already resolved for the
/// matrix at the top of the same screen, so this costs no extra request.
class _SectionEmptyState extends ConsumerWidget {
  final String label;

  /// The configured services feeding the section. Any that are not answering are
  /// named in place of [label].
  final List<ServiceKey> sources;
  final VoidCallback? onRetry;

  const _SectionEmptyState({
    required this.label,
    required this.sources,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final offline = sources
        .where(
          // Strictly `false`, not `!= true`: a summary still loading is neither
          // online nor a fault, and blaming it during the first second of a cold
          // open is the same wolf-crying `ServicesAlertBand` avoids.
          (service) =>
              ref
                  .watch(serviceSummaryProvider(service))
                  .asData
                  ?.value
                  .isOnline ==
              false,
        )
        .toList(growable: false);
    final titles = offline
        .map((service) => service.title)
        .toList(growable: false);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            offline.isEmpty ? label : servicesSectionOfflineMessage(titles),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (offline.isNotEmpty && onRetry != null) ...[
            const SizedBox(height: AppSpacing.xs),
            TextButton(
              // Re-check the connections as well: refreshing only the list would
              // leave this state insisting the services are down.
              onPressed: () {
                for (final service in offline) {
                  ref.invalidate(serviceSummaryProvider(service));
                }
                onRetry!();
              },
              style: TextButton.styleFrom(
                // Brand primary, never a source's accent. `/services` confines
                // service accents to the matrix's identity tiles, and this button
                // sat outside that confinement painting Radarr amber — which on a
                // "did not answer" state also made hue carry health.
                foregroundColor: theme.colorScheme.primary,
                minimumSize: const Size(44, 44),
              ),
              // Up to five sections can be offline at once, each producing an
              // identically-named "Retry". `semanticsLabel` renames the button
              // without a wrapper and without losing its tap semantics.
              child: Text(
                'Retry',
                semanticsLabel: 'Retry ${titles.join(', ')}',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Color _requestStatusColor(SeerrRequestDisplayKind kind) {
  switch (kind) {
    case SeerrRequestDisplayKind.pending:
      return AppColors.warning;
    case SeerrRequestDisplayKind.approved:
    case SeerrRequestDisplayKind.processing:
      return AppColors.info;
    case SeerrRequestDisplayKind.available:
    case SeerrRequestDisplayKind.partiallyAvailable:
    case SeerrRequestDisplayKind.completed:
      return AppColors.success;
    case SeerrRequestDisplayKind.declined:
    case SeerrRequestDisplayKind.failed:
    case SeerrRequestDisplayKind.deleted:
      return AppColors.error;
    case SeerrRequestDisplayKind.unknown:
      return AppColors.info;
  }
}

/// Whether a section has resolved to nothing to show.
///
/// Only for a settled [AsyncValue]: loading and error are the skeleton's and
/// [AsyncValueWidget]'s to render, and treating either as empty would show
/// "nothing added yet" over a request that has not come back.
bool _isEmpty<T>(AsyncValue<List<T>> value) =>
    value is AsyncData<List<T>> && value.value.isEmpty;

String _requestHeroTag(SeerrRequest request) =>
    'services_request_${request.id}';
